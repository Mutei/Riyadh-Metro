// lib/screens/chat_bot_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui show TextDirection;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:darb/constants/colors.dart';
import 'package:darb/localization/language_constants.dart';
import 'package:darb/latlon/latlong_stations.dart' as metro;
import 'package:darb/widgets/all_metro_lines.dart';
import 'package:darb/services/app_bus.dart';
import 'package:darb/services/trip_analytics_service.dart';
import 'package:darb/services/metro_trip_time_service.dart';

class ChatBotScreen extends StatefulWidget {
  const ChatBotScreen({super.key});
  @override
  State<ChatBotScreen> createState() => _ChatBotScreenState();
}

enum _Lang { en, ar }

enum _WhichTarget { origin, destination }

enum _TripStatistic { average, fastest, slowest }

class _ChatBotScreenState extends State<ChatBotScreen> {
  // ---------------- State ----------------
  final _ctrl = TextEditingController();
  final List<_Msg> _messages = <_Msg>[];
  bool _busy = false;
  final _tripAnalytics = TripAnalyticsService();
  final _metroTripTime = MetroTripTimeService();

  // STT (Speech-to-Text)
  late final stt.SpeechToText _stt;
  bool _sttAvailable = false;
  bool _listening = false;
  bool _holdToTalk = false; // UI state while pressing mic
  bool _autoSendAfterSpeech = true; // send message when final result comes
  String? _lastSttLocaleId;

  // Language tracking (mirror user language in bot replies)
  _Lang? _lastUserLang;

  // Autocomplete overlay
  OverlayEntry? _suggestionsOverlay;
  bool _suggestForOrigin = true;
  final _inputFocus = FocusNode();
  List<Map<String, dynamic>> _stationSuggestions = const [];
  _WhichTarget? _stationSuggestionTarget;

  // Persistence keys
  static const _kDraftKey = 'chatbot_draft_v1';
  static const _kRecentRoutesKey =
      'chatbot_recent_routes_v1'; // List<String> like "from||to"
  static const _kConversationKey = 'chatbot_conversation_v1';
  static const _kConversationExpiresAtKey =
      'chatbot_conversation_expires_at_v1';

  // Recent routes in memory
  List<(String from, String to)> _recentRoutes = [];

  // Initial greeting control
  bool _booted = false;
  bool _conversationRestored = false;
  Timer? _conversationExpiryTimer;

  bool get _localeIsArabic => Localizations.localeOf(context)
      .languageCode
      .toLowerCase()
      .startsWith('ar');

  // Flattened station list (reuse)
  List<Map<String, dynamic>> get _allStations => [
        for (final station in metro.blueStations)
          <String, dynamic>{...station, 'lineKey': 'blue'},
        for (final station in metro.redStations)
          <String, dynamic>{...station, 'lineKey': 'red'},
        for (final station in metro.yellowStations)
          <String, dynamic>{...station, 'lineKey': 'yellow'},
        for (final station in metro.purpleStations)
          <String, dynamic>{...station, 'lineKey': 'purple'},
        for (final station in metro.orangeStations)
          <String, dynamic>{...station, 'lineKey': 'orange'},
        for (final station in metro.greenStations)
          <String, dynamic>{...station, 'lineKey': 'green'},
      ];

  // -------------- Lifecycle --------------
  @override
  void initState() {
    super.initState();
    _stt = stt.SpeechToText();
    _initStt();

    _inputFocus.addListener(() {
      if (!_inputFocus.hasFocus) _hideSuggestions();
    });
    _restoreDraftAndHistory(); // safe (no context usage)
  }

  // Move greeting here (fixes Localizations access before initState finished)
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_booted) return;
    _booted = true;
    if (_conversationRestored && _messages.isEmpty) {
      _addGreeting();
      setState(() {});
    }
  }

  void _addGreeting() {
    _messages.add(_Msg.bot(
      'Hi! I can help with Darb. Try “Nearest station”, “Metro hours”, or “How long does it take from KAFD to STC?”.',
      'مرحباً! أستطيع مساعدتك في درب. جرّب "أقرب محطة"، "ساعات المترو"، أو "كم تستغرق الرحلة من المركز المالي إلى STC؟".',
      lang: _localeIsArabic ? _Lang.ar : _Lang.en,
    ));
    _persistConversation();
  }

  @override
  void dispose() {
    _hideSuggestions(rebuild: false);
    _conversationExpiryTimer?.cancel();
    _persistDraft(); // store last typed text
    _ctrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // -------------- STT --------------
  Future<void> _initStt() async {
    final available = await _stt.initialize(
      onError: (e) {
        setState(() {
          _listening = false;
          _holdToTalk = false;
        });
      },
      onStatus: (status) {
        if (status.toLowerCase().contains('notListening'.toLowerCase())) {
          setState(() => _listening = false);
        }
      },
    );
    setState(() {
      _sttAvailable = available;
    });
  }

  Future<void> _startMic() async {
    if (!_sttAvailable || _listening) return;

    final localeId = _replyLang() == _Lang.ar ? 'ar_SA' : 'en_US';
    _lastSttLocaleId = localeId;

    setState(() => _holdToTalk = true);

    final ok = await _stt.listen(
      localeId: localeId,
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      onResult: (result) {
        final text = result.recognizedWords.trim();
        if (text.isNotEmpty) {
          _ctrl.text = text;
          _ctrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _ctrl.text.length),
          );
        }
        if (result.finalResult && _autoSendAfterSpeech) {
          Future.delayed(const Duration(milliseconds: 60), () {
            _send();
          });
        }
      },
      cancelOnError: true,
    );

    setState(() => _listening = ok);
    if (!ok) setState(() => _holdToTalk = false);
  }

  Future<void> _stopMic({bool sendOnStop = false}) async {
    if (_listening) {
      await _stt.stop();
    }
    setState(() {
      _listening = false;
      _holdToTalk = false;
    });

    if (sendOnStop && _ctrl.text.trim().isNotEmpty) {
      _send();
    }
  }

  // -------------- Persistence --------------
  Future<void> _restoreDraftAndHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString(_kDraftKey);
    if (draft != null && draft.isNotEmpty) {
      _ctrl.text = draft;
      _ctrl.selection =
          TextSelection.fromPosition(TextPosition(offset: _ctrl.text.length));
    }

    final list = prefs.getStringList(_kRecentRoutesKey) ?? const [];
    _recentRoutes = list
        .map((s) {
          final parts = s.split('||');
          if (parts.length == 2) return (parts[0], parts[1]);
          return null;
        })
        .whereType<(String, String)>()
        .toList();

    final expiresAt = prefs.getInt(_kConversationExpiresAtKey);
    final now = DateTime.now();
    if (expiresAt != null && now.millisecondsSinceEpoch < expiresAt) {
      final rawConversation = prefs.getString(_kConversationKey);
      if (rawConversation != null) {
        try {
          final decoded = jsonDecode(rawConversation);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is! Map) continue;
              final en = item['en']?.toString() ?? '';
              final ar = item['ar']?.toString() ?? en;
              if (en.isEmpty && ar.isEmpty) continue;
              final lang = item['lang'] == 'ar' ? _Lang.ar : _Lang.en;
              _messages.add(_restoreMessage(item, en, ar, lang));
            }
          }
        } catch (_) {
          await _clearExpiredConversation(prefs);
        }
      }
    } else {
      await _clearExpiredConversation(prefs);
    }

    _conversationRestored = true;
    if (_booted && _messages.isEmpty) _addGreeting();
    _scheduleConversationExpiry();
    if (mounted) setState(() {});
  }

  DateTime _nextMidnight() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  void _scheduleConversationExpiry() {
    _conversationExpiryTimer?.cancel();
    _conversationExpiryTimer =
        Timer(_nextMidnight().difference(DateTime.now()), () async {
      final prefs = await SharedPreferences.getInstance();
      await _clearExpiredConversation(prefs);
      if (!mounted) return;
      setState(() => _messages.clear());
    });
  }

  Future<void> _clearExpiredConversation(SharedPreferences prefs) async {
    await prefs.remove(_kConversationKey);
    await prefs.remove(_kConversationExpiresAtKey);
  }

  Future<void> _persistConversation() async {
    if (!_conversationRestored) return;
    final prefs = await SharedPreferences.getInstance();
    final payload = _messages.map((message) {
      final serialized = <String, dynamic>{
        'en': message.textEn,
        'ar': message.textAr,
        'isMe': message.isMe,
        'lang': message.lang == _Lang.ar ? 'ar' : 'en',
      };
      final analytics = _analyticsPayload(message);
      if (analytics != null) serialized['analytics'] = analytics;
      return serialized;
    }).toList(growable: false);
    await prefs.setString(_kConversationKey, jsonEncode(payload));
    await prefs.setInt(
      _kConversationExpiresAtKey,
      _nextMidnight().millisecondsSinceEpoch,
    );
    _scheduleConversationExpiry();
  }

  _Msg _restoreMessage(
    Map item,
    String en,
    String ar,
    _Lang lang,
  ) {
    if (item['isMe'] == true) return _Msg.user(en, ar, lang: lang);

    final rawAnalytics = item['analytics'];
    if (rawAnalytics is! Map) return _Msg.bot(en, ar, lang: lang);

    final analytics = Map<Object?, Object?>.from(rawAnalytics);
    final fromEn = analytics['fromEn']?.toString().trim() ?? '';
    final toEn = analytics['toEn']?.toString().trim() ?? '';
    final fromAr = analytics['fromAr']?.toString().trim() ?? '';
    final toAr = analytics['toAr']?.toString().trim() ?? '';
    final statistic = _tripStatisticFromKey(analytics['statistic']?.toString());
    final average = _savedInt(analytics['averageSeconds']);
    final minimum = _savedInt(analytics['minimumSeconds']);
    final maximum = _savedInt(analytics['maximumSeconds']);
    final sampleCount = _savedInt(analytics['sampleCount']);

    if (fromEn.isEmpty ||
        toEn.isEmpty ||
        fromAr.isEmpty ||
        toAr.isEmpty ||
        statistic == null ||
        average < 0 ||
        minimum < 0 ||
        maximum < 0 ||
        sampleCount <= 0) {
      return _Msg.bot(en, ar, lang: lang);
    }

    final rawLines = analytics['commonLines'];
    final lines = rawLines is List
        ? rawLines
            .map((line) => line.toString())
            .where((line) => line.isNotEmpty)
            .toList()
        : const <String>[];

    return _Msg.analytics(
      textEn: en,
      textAr: ar,
      estimate: TripTimeEstimate(
        averageSeconds: average,
        minimumSeconds: minimum,
        maximumSeconds: maximum,
        sampleCount: sampleCount,
        commonLines: lines,
        fastestLines: _savedLines(analytics['fastestLines']),
        slowestLines: _savedLines(analytics['slowestLines']),
        averageTransfers: _savedInt(analytics['averageTransfers']),
        isCommunityAggregate: analytics['isCommunityAggregate'] == true,
      ),
      fromEn: fromEn,
      toEn: toEn,
      fromAr: fromAr,
      toAr: toAr,
      statistic: statistic,
      lang: lang,
    );
  }

  Map<String, dynamic>? _analyticsPayload(_Msg message) {
    final estimate = message.estimate;
    final statistic = message.statistic;
    if (estimate == null ||
        statistic == null ||
        message.fromEn == null ||
        message.toEn == null ||
        message.fromAr == null ||
        message.toAr == null) {
      return null;
    }

    return <String, dynamic>{
      'averageSeconds': estimate.averageSeconds,
      'minimumSeconds': estimate.minimumSeconds,
      'maximumSeconds': estimate.maximumSeconds,
      'sampleCount': estimate.sampleCount,
      'commonLines': estimate.commonLines,
      'fastestLines': estimate.fastestLines,
      'slowestLines': estimate.slowestLines,
      'averageTransfers': estimate.averageTransfers,
      'isCommunityAggregate': estimate.isCommunityAggregate,
      'fromEn': message.fromEn,
      'toEn': message.toEn,
      'fromAr': message.fromAr,
      'toAr': message.toAr,
      'statistic': _tripStatisticKey(statistic),
    };
  }

  int _savedInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? -1;

  List<String> _savedLines(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((line) => line.toString().trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String _tripStatisticKey(_TripStatistic statistic) {
    return switch (statistic) {
      _TripStatistic.average => 'average',
      _TripStatistic.fastest => 'fastest',
      _TripStatistic.slowest => 'slowest',
    };
  }

  _TripStatistic? _tripStatisticFromKey(String? value) {
    return switch (value) {
      'average' => _TripStatistic.average,
      'fastest' => _TripStatistic.fastest,
      'slowest' => _TripStatistic.slowest,
      _ => null,
    };
  }

  Future<void> _persistDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDraftKey, _ctrl.text.trim());
  }

  Future<void> _addRecentRoute(String from, String to) async {
    final prefs = await SharedPreferences.getInstance();
    // De-dup by same pair; newest first
    _recentRoutes.removeWhere((e) =>
        e.$1.toLowerCase() == from.toLowerCase() &&
        e.$2.toLowerCase() == to.toLowerCase());
    _recentRoutes.insert(0, (from, to));
    if (_recentRoutes.length > 5) {
      _recentRoutes = _recentRoutes.sublist(0, 5);
    }
    final payload =
        _recentRoutes.map((e) => '${e.$1}||${e.$2}').toList(growable: false);
    await prefs.setStringList(_kRecentRoutesKey, payload);
    if (mounted) setState(() {});
  }

  // -------------- Build --------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final timeSuggestions = _tripTimeSuggestions(_ctrl.text);
    final availableHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final stationPickerHeight =
        math.min(280.0, math.max(170.0, availableHeight * .36));

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withOpacity(.22),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(Icons.subway_rounded, color: cs.onPrimary),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localeIsArabic ? 'درب بوت' : 'Darb Bot',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _localeIsArabic
                        ? 'مساعدك الذكي للمترو'
                        : 'Your Riyadh Metro assistant',
                    style: t.labelSmall?.copyWith(
                      color: cs.onSurface.withOpacity(.62),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _localeIsArabic ? 'أدوات سريعة' : 'Quick tools',
            onPressed: _showToolsSheet,
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              reverse: true,
              itemCount: _messages.length + (_busy ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                if (_busy && i == 0) {
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _TypingIndicator(isArabic: _replyLang() == _Lang.ar),
                  );
                }
                final messageIndex = _messages.length - 1 - (_busy ? i - 1 : i);
                final msg = _messages[messageIndex];
                final bubbleColor = msg.isMe
                    ? (AppColors.kPrimaryColor.withOpacity(.10))
                    : (Theme.of(context).inputDecorationTheme.fillColor ??
                        cs.surfaceVariant);
                final align =
                    msg.isMe ? Alignment.centerRight : Alignment.centerLeft;
                final radius = msg.isMe
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        topRight: Radius.circular(6),
                        bottomRight: Radius.circular(16),
                      )
                    : const BorderRadius.only(
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                        topLeft: Radius.circular(6),
                        bottomLeft: Radius.circular(16),
                      );

                final showText =
                    (msg.lang == _Lang.ar) ? msg.textAr : msg.textEn;
                final actionLabel = (msg.lang == _Lang.ar)
                    ? msg.action?.labelAr
                    : msg.action?.labelEn;

                return Align(
                  alignment: align,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: msg.isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (!msg.isMe) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.subway_rounded,
                                  color: cs.onPrimary,
                                  size: 14,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _localeIsArabic ? 'درب' : 'Darb',
                                style: t.labelSmall?.copyWith(
                                  color: cs.onSurface.withOpacity(.58),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                        ],
                        _MsgBubble(
                          lang: msg.lang,
                          bubbleColor: bubbleColor,
                          radius: radius,
                          text: showText,
                          textStyle:
                              t.bodyMedium?.copyWith(color: cs.onSurface),
                        ),
                        if (msg.estimate != null) ...[
                          const SizedBox(height: 8),
                          _TripAnalyticsCard(
                            estimate: msg.estimate!,
                            from: msg.lang == _Lang.ar
                                ? msg.fromAr!
                                : msg.fromEn!,
                            to: msg.lang == _Lang.ar ? msg.toAr! : msg.toEn!,
                            statistic: msg.statistic!,
                            isArabic: msg.lang == _Lang.ar,
                          ),
                        ],
                        if (msg.action != null) ...[
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            icon: Icon(msg.action!.icon, size: 18),
                            label: Text(actionLabel!),
                            onPressed: msg.action!.onTap,
                          ),
                        ],
                        if (_messages.length == 1 && messageIndex == 0) ...[
                          const SizedBox(height: 12),
                          _WelcomePanel(
                            isArabic: _localeIsArabic,
                            onPrompt: _insertQuestionSuggestion,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          if (timeSuggestions.isNotEmpty && _stationSuggestions.isEmpty)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Padding(
                key: ValueKey(timeSuggestions.join()),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 16, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(
                          _localeIsArabic
                              ? 'اقتراحات ذكية'
                              : 'Smart suggestions',
                          style: t.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _showToolsSheet,
                          child: Text(_localeIsArabic ? 'أدوات' : 'Tools'),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: timeSuggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) => _SuggestionCard(
                          label: timeSuggestions[index],
                          icon: _suggestionIcon(timeSuggestions[index]),
                          onTap: _busy
                              ? null
                              : () => _insertQuestionSuggestion(
                                    timeSuggestions[index],
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_stationSuggestions.isNotEmpty &&
              _stationSuggestionTarget != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SizedBox(
                height: stationPickerHeight,
                child: _StationSuggestionPanel(
                  results: _stationSuggestions,
                  target: _stationSuggestionTarget!,
                  isArabic: _replyLang() == _Lang.ar,
                  onPick: _onPickSuggestion,
                ),
              ),
            ),

          // -------- Input --------
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(.62),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: cs.outline.withOpacity(.28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        Theme.of(context).brightness == Brightness.dark
                            ? .12
                            : .05,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Mic (press & hold)
                    GestureDetector(
                      onLongPressStart: (_) {
                        if (_sttAvailable) _startMic();
                      },
                      onLongPressEnd: (_) {
                        _stopMic(sendOnStop: true);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _holdToTalk
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.18)
                              : Colors.transparent,
                          border: Border.all(
                            color: _listening
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        child: IconButton(
                          tooltip: _localeIsArabic ? 'تحدث' : 'Speak',
                          onPressed: _sttAvailable
                              ? () async {
                                  if (_listening) {
                                    await _stopMic(sendOnStop: true);
                                  } else {
                                    await _startMic();
                                  }
                                }
                              : null,
                          icon: Icon(
                            _listening
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Text box
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _inputFocus,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        onChanged: (val) {
                          _handleChanged(val);
                          _persistDraft(); // live-persist draft as they type
                        },
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: getTranslated(
                                      context, 'bot.typeYourMessage') ==
                                  'bot.typeYourMessage'
                              ? (_localeIsArabic
                                  ? 'اكتب رسالتك'
                                  : 'Type your message')
                              : getTranslated(context, 'bot.typeYourMessage'),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide:
                                BorderSide(color: cs.primary.withOpacity(.5)),
                          ),
                          fillColor: cs.surface,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Send
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                      ),
                      onPressed: _busy ? null : _send,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator())
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Language helpers ----------
  bool _containsArabic(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

  _Lang _replyLang() {
    // Prefer last user language; fallback to current locale
    return _lastUserLang ?? (_localeIsArabic ? _Lang.ar : _Lang.en);
  }

  // ---------- Input router ----------
  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    _hideSuggestions();
    _persistDraft(); // ensure saved
    _ctrl.clear();

    // Detect user language per message
    final userLang = _containsArabic(text) ? _Lang.ar : _Lang.en;
    _lastUserLang = userLang;

    _addUserText(text, text, lang: userLang);

    if (_looksLikeNearest(text)) {
      _handleNearestStation();
      return;
    }

    final timeRoute = _extractTripTimeRoute(text);
    if (_isTripTimeIntent(text) && timeRoute != null) {
      _handleTripTimeRequest(
        timeRoute.$1,
        timeRoute.$2,
        statistic: _tripStatisticFor(text),
      );
      return;
    }

    final rt = _extractRoute(text);
    if (rt != null) {
      _handleRouteRequest(rt.$1, rt.$2);
      return;
    }

    if (_isHoursIntent(text)) {
      _handleHours();
      return;
    }

    _addBotText(
      'Try: “How long does it take from KAFD to STC?”, “Nearest station”, or “Metro hours”.',
      'جرّب: "كم تستغرق الرحلة من المركز المالي إلى STC؟"، أو "أقرب محطة"، أو "ساعات المترو".',
      lang: _replyLang(),
    );
  }

  bool _looksLikeNearest(String s) {
    final q = s.toLowerCase();
    return q.contains('nearest') ||
        q.contains('closest') ||
        q.contains('near me') ||
        q.contains('اقرب') ||
        q.contains('أقرب') ||
        q.contains('قريب');
  }

  bool _isHoursIntent(String s) {
    final q = s.toLowerCase().replaceAll('statis', 'status');
    return q.contains('status') ||
        q.contains('hour') ||
        q.contains('hours') ||
        q.contains('open') ||
        q.contains('close') ||
        q.contains('closing') ||
        q.contains('time') ||
        q.contains('حالة') ||
        q.contains('الحالة') ||
        q.contains('ساعات') ||
        q.contains('العمل') ||
        q.contains('مفتوح') ||
        q.contains('مغل');
  }

  // ---------- Metro hours (FIXED to midnight close) ----------
  // Sat–Thu: 05:30 → 24:00 (midnight = next day 00:00)
  // Fri:     10:00 → 24:00 (midnight = next day 00:00)
  (DateTime open, DateTime close) _todayWindow(DateTime now) {
    final d = DateTime(now.year, now.month, now.day);
    if (now.weekday == DateTime.friday) {
      final open = DateTime(d.year, d.month, d.day, 10, 0);
      final close = d.add(const Duration(days: 1)); // 00:00 next day
      return (open, close);
    } else {
      final open = DateTime(d.year, d.month, d.day, 5, 30);
      final close = d.add(const Duration(days: 1)); // 00:00 next day
      return (open, close);
    }
  }

  bool _isOpenNow(DateTime now) {
    final w = _todayWindow(now);
    return now.isAfter(w.$1) && now.isBefore(w.$2);
  }

  DateTime _nextOpening(DateTime now) {
    final w = _todayWindow(now);
    if (now.isBefore(w.$1)) return w.$1;
    final tomorrow = now.add(const Duration(days: 1));
    return _todayWindow(tomorrow).$1;
  }

  void _handleHours() {
    final now = DateTime.now();
    final df = DateFormat('h:mm a');
    final summaryEn =
        'Hours: Sat–Thu 5:30 AM — 12:00 AM • Fri 10:00 AM — 12:00 AM';
    final summaryAr =
        'المواعيد: السبت–الخميس 5:30 ص — 12:00 ص • الجمعة 10:00 ص — 12:00 ص';

    if (_isOpenNow(now)) {
      final close = _todayWindow(now).$2;
      _addBotText(
        'Metro is OPEN now. Closes at ${df.format(close)}.\n$summaryEn',
        'المترو مفتوح الآن. يغلق عند ${df.format(close)}.\n$summaryAr',
        lang: _replyLang(),
      );
    } else {
      final next = _nextOpening(now);
      _addBotText(
        'Metro stations are CLOSED now. Next opening: ${df.format(next)}.\n$summaryEn',
        'محطات المترو مغلقة الآن. الافتتاح التالي: ${df.format(next)}.\n$summaryAr',
        lang: _replyLang(),
      );
    }
  }

  // ---------- Nearest station ----------
  Future<void> _handleNearestStation() async {
    setState(() => _busy = true);
    try {
      final hasPerm = await _ensureLocationPermission();
      if (!hasPerm) {
        _addBotText(
          'Location permission denied. Enable it to find your nearest station.',
          'تم رفض إذن الموقع. فعّله للعثور على أقرب محطة.',
          lang: _replyLang(),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final user = LatLng(pos.latitude, pos.longitude);
      final nearest = _computeNearest(user);

      if (nearest == null) {
        _addBotText('No stations data found.', 'لا توجد بيانات محطات.',
            lang: _replyLang());
        return;
      }

      final distM = nearest.distanceMeters.round();
      final nameEn = nearest.station['name'] as String? ?? 'Unknown';
      final nameAr = nearest.station['nameAr'] as String? ?? nameEn;

      _addBotAction(
        textEn: 'Nearest station is $nameEn, about ${distM} m away.',
        textAr: 'أقرب محطة هي $nameAr، تبعد تقريبًا ${distM} متر.',
        action: _MsgAction(
          icon: Icons.map_rounded,
          labelEn: 'Show on Map',
          labelAr: 'عرض على الخريطة',
          onTap: () {
            AppBus.I.emit(FocusStationEvent(
              LatLng(nearest.station['lat'] as double,
                  nearest.station['lng'] as double),
              zoom: 16.5,
              pulse: true,
            ));
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
        lang: _replyLang(),
      );
    } catch (_) {
      _addBotText(
        'Sorry, I couldn’t get your location.',
        'عذرًا، تعذّر الحصول على موقعك.',
        lang: _replyLang(),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final service = await Geolocator.isLocationServiceEnabled();
    if (!service) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  _Nearest? _computeNearest(LatLng user) {
    final all = _allStations;
    if (all.isEmpty) return null;
    _Nearest? best;
    for (final s in all) {
      final lat = (s['lat'] as num?)?.toDouble();
      final lng = (s['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final d = _haversineMeters(user.latitude, user.longitude, lat, lng);
      if (best == null || d < best.distanceMeters) {
        best = _Nearest(station: s, distanceMeters: d);
      }
    }
    return best;
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // meters
    double toRad(double d) => d * math.pi / 180.0;
    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  // ---------- From ... To ----------
  (String, String)? _extractRoute(String raw) {
    final s = raw.trim();
    final en = RegExp(r'^\s*from\s+(.+?)\s+to\s+(.+)$', caseSensitive: false);
    final ar = RegExp(r'^\s*من\s+(.+?)\s+إ?لى\s+(.+)$');
    final m1 = en.firstMatch(s);
    if (m1 != null) return (m1.group(1)!.trim(), m1.group(2)!.trim());
    final m2 = ar.firstMatch(s);
    if (m2 != null) return (m2.group(1)!.trim(), m2.group(2)!.trim());
    return null;
  }

  bool _isTripTimeIntent(String raw) {
    final query = _norm(raw);
    return query.contains('how long') ||
        query.contains('how much time') ||
        query.contains('average travel time') ||
        query.contains('average trip time') ||
        query.contains('fastest') ||
        query.contains('quickest') ||
        query.contains('shortest trip') ||
        query.contains('minimum recorded') ||
        query.contains('slowest') ||
        query.contains('longest trip') ||
        query.contains('maximum recorded') ||
        query.contains('time from') ||
        query.contains('metro trip') ||
        query.contains('take me') ||
        query.contains('كم يستغرق') ||
        query.contains('كم تستغرق') ||
        query.contains('كم ياخذ') ||
        query.contains('مدة الرحلة') ||
        query.contains('متوسط وقت') ||
        query.contains('وقت الرحلة') ||
        query.contains('اسرع') ||
        query.contains('أسرع') ||
        query.contains('اقصر') ||
        query.contains('أقصر') ||
        query.contains('ابطي') ||
        query.contains('أبطأ') ||
        query.contains('اطول') ||
        query.contains('أطول');
  }

  IconData _suggestionIcon(String suggestion) {
    final text = _norm(suggestion);
    if (text.contains('fastest') ||
        text.contains('quickest') ||
        text.contains('اسرع') ||
        text.contains('أسرع')) {
      return Icons.bolt_rounded;
    }
    if (text.contains('slowest') ||
        text.contains('longest') ||
        text.contains('ابطي') ||
        text.contains('أبطأ')) {
      return Icons.hourglass_bottom_rounded;
    }
    return Icons.schedule_rounded;
  }

  void _showToolsSheet() {
    final isArabic = _localeIsArabic;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Wrap(
            runSpacing: 4,
            children: [
              Text(isArabic ? 'أدوات سريعة' : 'Quick tools',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      )),
              const SizedBox(height: 10),
              _toolTile(
                sheetContext,
                icon: Icons.my_location_rounded,
                label: isArabic
                    ? 'استخدم موقعي كنقطة بداية'
                    : 'Use my location as origin',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _useMyLocationAsOrigin();
                },
              ),
              _toolTile(
                sheetContext,
                icon: Icons.flag_circle_rounded,
                label: isArabic
                    ? 'استخدم موقعي كوجهة'
                    : 'Use my location as destination',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _useMyLocationAsDestination();
                },
              ),
              _toolTile(
                sheetContext,
                icon: Icons.swap_vert_rounded,
                label: isArabic
                    ? 'تبديل البداية والوجهة'
                    : 'Swap origin and destination',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _swapFromTo();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child:
            Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  _TripStatistic _tripStatisticFor(String raw) {
    final query = _norm(raw);
    if (query.contains('fastest') ||
        query.contains('quickest') ||
        query.contains('shortest') ||
        query.contains('minimum') ||
        query.contains('اسرع') ||
        query.contains('أسرع') ||
        query.contains('اقصر') ||
        query.contains('أقصر')) {
      return _TripStatistic.fastest;
    }
    if (query.contains('slowest') ||
        query.contains('longest') ||
        query.contains('maximum') ||
        query.contains('ابطي') ||
        query.contains('أبطأ') ||
        query.contains('اطول') ||
        query.contains('أطول')) {
      return _TripStatistic.slowest;
    }
    return _TripStatistic.average;
  }

  (String, String)? _extractTripTimeRoute(String raw) {
    final direct = _extractRoute(raw);
    if (direct != null)
      return (_cleanStationQuery(direct.$1), _cleanStationQuery(direct.$2));

    final enFromTo = RegExp(
      r'\bfrom\s+(.+?)\s+to\s+(.+?)(?:[?!.]|$)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (enFromTo != null) {
      return (
        _cleanStationQuery(enFromTo.group(1)!),
        _cleanStationQuery(enFromTo.group(2)!),
      );
    }

    final enToFrom = RegExp(
      r'\bto\s+(.+?)\s+from\s+(.+?)(?:[?!.]|$)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (enToFrom != null) {
      return (
        _cleanStationQuery(enToFrom.group(2)!),
        _cleanStationQuery(enToFrom.group(1)!),
      );
    }

    final enReachFrom = RegExp(
      r'\b(?:reach|get\s+to)\s+(.+?)\s+from\s+(.+?)(?:[?!.]|$)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (enReachFrom != null) {
      return (
        _cleanStationQuery(enReachFrom.group(2)!),
        _cleanStationQuery(enReachFrom.group(1)!),
      );
    }

    final enBetween = RegExp(
      r'\bbetween\s+(.+?)\s+and\s+(.+?)(?:[?!.]|$)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (enBetween != null) {
      return (
        _cleanStationQuery(enBetween.group(1)!),
        _cleanStationQuery(enBetween.group(2)!),
      );
    }

    final arFromTo =
        RegExp(r'من\s+(.+?)\s+إ?لى\s+(.+?)(?:[؟?.!]|$)').firstMatch(raw);
    if (arFromTo != null) {
      return (
        _cleanStationQuery(arFromTo.group(1)!),
        _cleanStationQuery(arFromTo.group(2)!),
      );
    }
    final arBetween =
        RegExp(r'بين\s+(.+?)\s+و\s+(.+?)(?:[؟?.!]|$)').firstMatch(raw);
    if (arBetween != null) {
      return (
        _cleanStationQuery(arBetween.group(1)!),
        _cleanStationQuery(arBetween.group(2)!),
      );
    }
    return null;
  }

  String _cleanStationQuery(String value) => value
      .replaceAll(RegExp(r'\b(station|metro)\b', caseSensitive: false), '')
      .replaceAll('محطة', '')
      .trim();

  Future<void> _handleTripTimeRequest(
    String fromTxt,
    String toTxt, {
    _TripStatistic statistic = _TripStatistic.average,
  }) async {
    final fromMatches = _stationMatches(fromTxt);
    final toMatches = _stationMatches(toTxt);
    if (fromMatches.isEmpty || toMatches.isEmpty) {
      _addBotText(
        'I couldn’t match one of the stations. Try a station name such as KAFD or Qasr Al Hokm.',
        'تعذر مطابقة إحدى المحطتين. جرّب اسم محطة مثل المركز المالي أو قصر الحكم.',
        lang: _replyLang(),
      );
      return;
    }
    if (fromMatches.length > 1 || toMatches.length > 1) {
      final options = (fromMatches.length > 1 ? fromMatches : toMatches)
          .take(3)
          .map((station) => _replyLang() == _Lang.ar
              ? (station['nameAr'] ?? station['name']).toString()
              : station['name'].toString())
          .join(', ');
      _addBotText(
        'I found more than one possible station. Please use a more specific name: $options.',
        'وجدت أكثر من محطة محتملة. يرجى استخدام اسم أكثر تحديدًا: $options.',
        lang: _replyLang(),
      );
      return;
    }

    final from = fromMatches.first;
    final to = toMatches.first;
    setState(() => _busy = true);
    try {
      final estimate = await _tripAnalytics.estimateMetroTrip(
        fromStation: from['name'].toString(),
        toStation: to['name'].toString(),
      );
      final fromEn = from['name'].toString();
      final toEn = to['name'].toString();
      final fromAr = (from['nameAr'] ?? fromEn).toString();
      final toAr = (to['nameAr'] ?? toEn).toString();
      if (estimate == null) {
        if (statistic != _TripStatistic.average) {
          final metric = statistic == _TripStatistic.fastest
              ? 'fastest recorded trip'
              : 'slowest recorded trip';
          final metricAr = statistic == _TripStatistic.fastest
              ? 'أسرع رحلة مسجلة'
              : 'أبطأ رحلة مسجلة';
          _addBotText(
            'There are not enough completed community trips yet to provide the $metric from $fromEn to $toEn.',
            'لا توجد رحلات مكتملة كافية من المستخدمين بعد لتقديم $metricAr من $fromAr إلى $toAr.',
            lang: _replyLang(),
          );
          return;
        }
        final planned = _metroTripTime.estimate(
          fromStation: fromEn,
          toStation: toEn,
        );
        if (planned != null) {
          final minutes = _minutes(planned.seconds);
          final lines = planned.lines.isEmpty
              ? ''
              : ' Lines: ${planned.lines.join(', ')}.';
          final linesAr = planned.lines.isEmpty
              ? ''
              : ' الخطوط: ${planned.lines.join('، ')}.';
          final transferText =
              planned.transfers == 0 ? '' : ' Transfers: ${planned.transfers}.';
          final transferTextAr =
              planned.transfers == 0 ? '' : ' التحويلات: ${planned.transfers}.';
          _addBotText(
            'The current route-planning estimate is about $minutes min. It will be replaced by an anonymous community average once enough completed trips are recorded.$lines$transferText',
            '. تقدير مخطط المسار الحالي هو حوالي $minutes دقيقة. سيُستبدل بمتوسط مجهول من رحلات المستخدمين عند توفر عدد كافٍ من الرحلات المكتملة.$linesAr$transferTextAr',
            lang: _replyLang(),
          );
          return;
        }
        _addBotText(
          'There are not enough completed community trips yet to provide a reliable average from $fromEn to $toEn.',
          'لا توجد رحلات مكتملة كافية من المستخدمين بعد لتقديم متوسط موثوق من $fromAr إلى $toAr.',
          lang: _replyLang(),
        );
        return;
      }

      final average = _minutes(estimate.averageSeconds);
      final minimum = _minutes(estimate.minimumSeconds);
      final maximum = _minutes(estimate.maximumSeconds);
      final lines = estimate.commonLines.isEmpty
          ? ''
          : ' Common lines: ${estimate.commonLines.join(', ')}.';
      final linesAr = estimate.commonLines.isEmpty
          ? ''
          : ' الخطوط الشائعة: ${estimate.commonLines.join('، ')}.';
      final fastestLines = estimate.fastestLines.isEmpty
          ? lines
          : ' Lines on the fastest recorded trip: ${estimate.fastestLines.join(', ')}.';
      final fastestLinesAr = estimate.fastestLines.isEmpty
          ? linesAr
          : ' الخطوط المستخدمة في أسرع رحلة مسجلة: ${estimate.fastestLines.join('، ')}.';
      final slowestLines = estimate.slowestLines.isEmpty
          ? lines
          : ' Lines on the longest recorded trip: ${estimate.slowestLines.join(', ')}.';
      final slowestLinesAr = estimate.slowestLines.isEmpty
          ? linesAr
          : ' الخطوط المستخدمة في أطول رحلة مسجلة: ${estimate.slowestLines.join('، ')}.';
      final transferText = estimate.averageTransfers == 0
          ? ''
          : ' Typical transfers: ${estimate.averageTransfers}.';
      final transferTextAr = estimate.averageTransfers == 0
          ? ''
          : ' التحويلات المعتادة: ${estimate.averageTransfers}.';
      final limitedDataEn = estimate.sampleCount <= 3
          ? ' This result is based on a limited number of completed trips.'
          : '';
      final limitedDataAr = estimate.sampleCount <= 3
          ? ' هذه النتيجة مبنية على عدد محدود من الرحلات المكتملة.'
          : '';
      final averageSourceEn = estimate.isCommunityAggregate
          ? 'recorded community'
          : 'your recorded';
      final samplePhraseEn = estimate.isCommunityAggregate
          ? '${estimate.sampleCount} completed community trips with recorded station timestamps'
          : '${estimate.sampleCount} of your completed saved trips';
      final sourceAr = estimate.isCommunityAggregate
          ? 'رحلات المستخدمين المسجلة بتوقيتات المحطات'
          : 'رحلاتك المسجلة';
      final responseEn = switch (statistic) {
        _TripStatistic.fastest =>
          'The fastest recorded trip from $fromEn to $toEn is $minimum min.$fastestLines$limitedDataEn',
        _TripStatistic.slowest =>
          'The longest recorded trip from $fromEn to $toEn is $maximum min.$slowestLines$limitedDataEn',
        _TripStatistic.average =>
          'From $fromEn to $toEn, the $averageSourceEn average is $average min across $samplePhraseEn. Typical range: $minimum-$maximum min.$lines$transferText$limitedDataEn',
      };
      final responseAr = switch (statistic) {
        _TripStatistic.fastest =>
          'أسرع رحلة مسجلة من $fromAr إلى $toAr هي $minimum دقيقة.$fastestLinesAr$limitedDataAr',
        _TripStatistic.slowest =>
          'أطول رحلة مسجلة من $fromAr إلى $toAr هي $maximum دقيقة.$slowestLinesAr$limitedDataAr',
        _TripStatistic.average =>
          'متوسط وقت الرحلة من $fromAr إلى $toAr في $sourceAr هو $average دقيقة عبر ${estimate.sampleCount} رحلة مكتملة. المدى المعتاد: $minimum-$maximum دقيقة.$linesAr$transferTextAr$limitedDataAr',
      };
      _addAnalyticsMessage(
        textEn: responseEn,
        textAr: responseAr,
        estimate: estimate,
        fromEn: fromEn,
        toEn: toEn,
        fromAr: fromAr,
        toAr: toAr,
        statistic: statistic,
        lang: _replyLang(),
      );
    } catch (_) {
      _addBotAction(
        textEn: 'I could not read the community trip data right now.',
        textAr: 'تعذر قراءة بيانات رحلات المستخدمين الآن.',
        action: _MsgAction(
          icon: Icons.refresh_rounded,
          labelEn: 'Retry',
          labelAr: 'إعادة المحاولة',
          onTap: () => _handleTripTimeRequest(
            fromTxt,
            toTxt,
            statistic: statistic,
          ),
        ),
        lang: _replyLang(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _minutes(int seconds) => (seconds / 60).round();

  Future<void> _handleRouteRequest(String fromTxt, String toTxt) async {
    final sFrom = _findStationByName(fromTxt);
    final sTo = _findStationByName(toTxt);

    if (sFrom == null || sTo == null) {
      _addBotText(
        'I couldn’t match one of the stations. Try exact names (e.g., “KAFD”, “Qasr Al Hokm”).',
        'تعذّر مطابقة إحدى المحطّتين. حاول أسماء دقيقة (مثل "المركز المالي"، "قصر الحكم").',
        lang: _replyLang(),
      );
      return;
    }

    final en = 'Planning from ${sFrom['name']} to ${sTo['name']}...';
    final ar =
        'تخطيط من ${sFrom['nameAr'] ?? sFrom['name']} إلى ${sTo['nameAr'] ?? sTo['name']}...';

    // Save in Recent Routes (note: stored as display labels; chips mirror app locale)
    await _addRecentRoute(
      (sFrom['nameAr'] ?? sFrom['name']).toString(),
      (sTo['nameAr'] ?? sTo['name']).toString(),
    );

    _addBotAction(
      textEn: en,
      textAr: ar,
      action: _MsgAction(
        icon: Icons.directions_transit_rounded,
        labelEn: 'Open on Map',
        labelAr: 'فتح على الخريطة',
        onTap: () {
          final a = LatLng(sFrom['lat'] as double, sFrom['lng'] as double);
          final b = LatLng(sTo['lat'] as double, sTo['lng'] as double);
          AppBus.I.emit(RouteRequestEvent(from: a, to: b));
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
      lang: _replyLang(),
    );
  }

  Map<String, dynamic>? _findStationByName(String q) {
    final matches = _stationMatches(q);
    return matches.isEmpty ? null : matches.first;
  }

  List<Map<String, dynamic>> _stationMatches(String q) {
    final normalized = _norm(_cleanStationQuery(q));
    if (normalized.isEmpty) return const [];
    final scored = <(Map<String, dynamic> station, int score)>[];
    for (final s in _allStations) {
      final en = _norm((s['name'] ?? '').toString());
      final ar = _norm((s['nameAr'] ?? '').toString());
      final score = _score(normalized, en, ar);
      if (score > 0) scored.add((s, score));
    }
    if (scored.isEmpty) return const [];
    final highest = scored.map((item) => item.$2).reduce(math.max);
    final unique = <String, Map<String, dynamic>>{};
    for (final item in scored.where((item) => item.$2 == highest)) {
      final key = _norm((item.$1['name'] ?? '').toString());
      unique.putIfAbsent(key, () => item.$1);
    }
    return unique.values.toList();
  }

  String _norm(String x) => x
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]+'), ' ')
      .trim();
  int _score(String q, String en, String ar) {
    if (en == q || ar == q) return 5;
    if (en.startsWith(q) || ar.startsWith(q)) return 4;
    if (en.contains(q) || ar.contains(q)) return 3;
    for (final tok in q.split(' ')) {
      if (tok.isEmpty) continue;
      if (en.contains(tok) || ar.contains(tok)) return 1;
    }
    return 0;
  }

  // ---------- message helpers ----------
  void _addUserText(String en, String ar, {required _Lang lang}) {
    setState(() => _messages.add(_Msg.user(en, ar, lang: lang)));
    _persistConversation();
  }

  void _addBotText(String en, String ar, {required _Lang lang}) {
    setState(() => _messages.add(_Msg.bot(en, ar, lang: lang)));
    _persistConversation();
  }

  void _addBotAction({
    required String textEn,
    required String textAr,
    required _MsgAction action,
    required _Lang lang,
  }) {
    setState(() =>
        _messages.add(_Msg.bot(textEn, textAr, action: action, lang: lang)));
    _persistConversation();
  }

  void _addAnalyticsMessage({
    required String textEn,
    required String textAr,
    required TripTimeEstimate estimate,
    required String fromEn,
    required String toEn,
    required String fromAr,
    required String toAr,
    required _TripStatistic statistic,
    required _Lang lang,
  }) {
    setState(() {
      _messages.add(
        _Msg.analytics(
          textEn: textEn,
          textAr: textAr,
          estimate: estimate,
          fromEn: fromEn,
          toEn: toEn,
          fromAr: fromAr,
          toAr: toAr,
          statistic: statistic,
          lang: lang,
        ),
      );
    });
    _persistConversation();
  }

  // ===================== Autocomplete logic =====================
  void _handleChanged(String val) {
    if (mounted) setState(() {});
    final trimmed = val.trim();
    if (trimmed.length < 2) {
      _hideSuggestions();
      return;
    }

    final _WhichTarget? target = _whichTarget(trimmed);
    if (target == null) {
      final prompts = _tripTimeSuggestions(trimmed);
      if (prompts.isEmpty) {
        _hideSuggestions();
      } else {
        _showQuestionSuggestions(context, prompts);
      }
      return;
    }

    _suggestForOrigin = (target == _WhichTarget.origin);
    final frag = _currentFragmentForTarget(trimmed, target);
    if (frag.isEmpty && target == _WhichTarget.origin) {
      _hideSuggestions();
      return;
    }
    final results = _filterStations(frag);
    if (results.isEmpty) {
      _hideSuggestions();
      return;
    }

    _showSuggestions(results, target);
  }

  _WhichTarget? _whichTarget(String s) {
    final enFrom = RegExp(r'(^|\s)from\s+', caseSensitive: false);
    final enTo = RegExp(r'\s+to\s*$', caseSensitive: false);
    final enToAny = RegExp(r'\s+to\s+', caseSensitive: false);

    final arFrom = RegExp(r'(^|\s)من\s+');
    final arToEnd = RegExp(r'\s+إ?لى\s*$');
    final arToAny = RegExp(r'\s+إ?لى\s+');

    final hasEnFrom = enFrom.hasMatch(s);
    final hasArFrom = arFrom.hasMatch(s);
    final hasFrom = hasEnFrom || hasArFrom;

    if (!hasFrom) return null;

    if (enTo.hasMatch(s) || arToEnd.hasMatch(s)) {
      return _WhichTarget.destination;
    }

    if (enToAny.hasMatch(s) || arToAny.hasMatch(s)) {
      return _WhichTarget.destination;
    }

    return _WhichTarget.origin;
  }

  String _currentFragmentForTarget(String s, _WhichTarget target) {
    if (target == _WhichTarget.destination) {
      final en = RegExp(r'\bto\s*(.*)$', caseSensitive: false);
      final ar = RegExp(r'إ?لى\s*(.*)$');
      final m1 = en.firstMatch(s);
      if (m1 != null) return m1.group(1)!.trim();
      final m2 = ar.firstMatch(s);
      if (m2 != null) return m2.group(1)!.trim();
      return '';
    } else {
      final en =
          RegExp(r'\bfrom\s*(.*?)(?:\s+to\s+.*)?$', caseSensitive: false);
      final ar = RegExp(r'\bمن\s*(.+?)(?:\s+إ?لى\s+.*)?$');
      final m1 = en.firstMatch(s);
      if (m1 != null) return m1.group(1)!.trim();
      final m2 = ar.firstMatch(s);
      if (m2 != null) return m2.group(1)!.trim();
      return '';
    }
  }

  List<Map<String, dynamic>> _filterStations(String q) {
    final n = _norm(q);
    if (n.isEmpty) return const [];
    final merged = <String, (Map<String, dynamic> station, int score)>{};

    for (final station in _allStations) {
      final en = (station['name'] ?? '').toString();
      final ar = (station['nameAr'] ?? '').toString();
      final score = _score(n, _norm(en), _norm(ar));
      if (score <= 0) continue;

      // Interchange stations are present once per served line. Keep one clear
      // result and expose every applicable line rather than repeated rows.
      final stationKey = '${_norm(en)}|${_norm(ar)}';
      final lineKey = (station['lineKey'] ?? '').toString();
      final current = merged[stationKey];
      if (current == null) {
        merged[stationKey] = (
          <String, dynamic>{
            'en': en,
            'ar': ar,
            'lat': station['lat'],
            'lng': station['lng'],
            'lineKeys': <String>[lineKey],
          },
          score,
        );
        continue;
      }

      final lineKeys = List<String>.from(current.$1['lineKeys'] as List);
      if (lineKey.isNotEmpty && !lineKeys.contains(lineKey)) {
        lineKeys.add(lineKey);
      }
      current.$1['lineKeys'] = lineKeys;
      merged[stationKey] = (current.$1, math.max(current.$2, score));
    }

    final results = merged.values.toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return results.take(6).map((item) => item.$1).toList();
  }

  List<String> _tripTimeSuggestions(String input) {
    final normalized = _norm(input);
    final timeLike = normalized.contains('how') ||
        normalized.contains('long') ||
        normalized.contains('time') ||
        normalized.contains('average') ||
        normalized.contains('fastest') ||
        normalized.contains('quickest') ||
        normalized.contains('shortest') ||
        normalized.contains('slowest') ||
        normalized.contains('maximum') ||
        normalized.contains('minimum') ||
        normalized.contains('كم') ||
        normalized.contains('وقت') ||
        normalized.contains('مدة') ||
        normalized.contains('اسرع') ||
        normalized.contains('أسرع') ||
        normalized.contains('ابطي') ||
        normalized.contains('أبطأ');
    final isArabic = _replyLang() == _Lang.ar;
    final catalog = isArabic
        ? <String>[
            'كم تستغرق الرحلة من المركز المالي إلى STC؟',
            'ما أسرع رحلة من المركز المالي إلى STC؟',
            'ما أطول رحلة من المركز المالي إلى STC؟',
          ]
        : <String>[
            'How long does it take from KAFD to STC?',
            'What is the fastest trip from KAFD to STC?',
            'What is the longest trip from KAFD to STC?',
          ];
    for (final route in _recentRoutes) {
      catalog.add(isArabic
          ? 'كم تستغرق الرحلة من ${route.$1} إلى ${route.$2}؟'
          : 'How long does it take from ${route.$1} to ${route.$2}?');
    }

    if (normalized.isEmpty) return catalog.take(3).toList();
    if (!timeLike) return const [];

    final tokens = normalized.split(' ').where((token) => token.length > 1);
    final scored = catalog
        .toSet()
        .map((prompt) {
          final promptNormalized = _norm(prompt);
          var score = promptNormalized.contains(normalized) ? 10 : 0;
          for (final token in tokens) {
            if (promptNormalized.contains(token)) score += 3;
          }
          return (prompt, score);
        })
        .where((item) => item.$2 > 0)
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(4).map((item) => item.$1).toList();
  }

  void _showQuestionSuggestions(BuildContext ctx, List<String> prompts) {
    _hideSuggestions();
    if (!_inputFocus.hasFocus) return;
    final overlay = Overlay.of(ctx);
    if (overlay == null) return;
    _suggestionsOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: 12,
        right: 12,
        bottom: 84,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shrinkWrap: true,
            itemCount: prompts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) => ListTile(
              dense: true,
              leading: const Icon(Icons.schedule_rounded),
              title: Text(prompts[index]),
              onTap: () => _insertQuestionSuggestion(prompts[index]),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_suggestionsOverlay!);
  }

  void _insertQuestionSuggestion(String prompt) {
    _ctrl.text = prompt;
    _ctrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _ctrl.text.length),
    );
    _hideSuggestions();
    _inputFocus.requestFocus();
    _persistDraft();
  }

  void _showSuggestions(
      List<Map<String, dynamic>> results, _WhichTarget target) {
    if (!_inputFocus.hasFocus) return;
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
    setState(() {
      _stationSuggestions = results;
      _stationSuggestionTarget = target;
    });
  }

  void _hideSuggestions({bool rebuild = true}) {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
    if (_stationSuggestions.isEmpty && _stationSuggestionTarget == null) {
      return;
    }
    _stationSuggestions = const [];
    _stationSuggestionTarget = null;
    if (rebuild && mounted) setState(() {});
  }

  void _onPickSuggestion(String pickedName, _WhichTarget target) {
    // A station tap is a completed selection. Keep the keyboard available for
    // the next field, but do not immediately reopen the picker with the same
    // exact station name.
    _hideSuggestions();
    final text = _ctrl.text;

    if (target == _WhichTarget.origin) {
      final hasFromEn =
          RegExp(r'\bfrom\b', caseSensitive: false).hasMatch(text);
      final hasFromAr = text.contains('من');
      final hasToEn = RegExp(r'\bto\b', caseSensitive: false).hasMatch(text);
      final hasToAr = text.contains('إلى');

      if (!hasFromEn && !hasFromAr) {
        _ctrl.text = _replyLang() == _Lang.ar
            ? 'من $pickedName إلى '
            : 'from $pickedName to ';
      } else {
        String newText = text;
        newText = newText
            .replaceAll(
                RegExp(r'\bfrom\s+.*?(?=\s+to\b|$)', caseSensitive: false),
                'from $pickedName')
            .replaceAll(
              RegExp(r'\bمن\s+.*?(?=\s+إ?لى\b|$)'),
              'من $pickedName',
            );

        if (!hasToEn && !hasToAr) {
          newText += _replyLang() == _Lang.ar ? ' إلى ' : ' to ';
        }
        _ctrl.text = newText;
      }
    } else {
      final hasToEn = RegExp(r'\bto\b', caseSensitive: false).hasMatch(text);
      final hasToAr = text.contains('إلى');

      if (!hasToEn && !hasToAr) {
        if (RegExp(r'\bfrom\b', caseSensitive: false).hasMatch(text) ||
            text.contains('من')) {
          _ctrl.text = text.trim() +
              ' ' +
              (_replyLang() == _Lang.ar ? 'إلى ' : 'to ') +
              pickedName;
        } else {
          _ctrl.text = (_replyLang() == _Lang.ar ? 'إلى ' : 'to ') + pickedName;
        }
      } else {
        String newText = text;
        newText = newText
            .replaceAll(
                RegExp(r'\bto\s*(.*)$', caseSensitive: false), 'to $pickedName')
            .replaceAll(RegExp(r'إ?لى\s*(.*)$'), 'إلى $pickedName');
        _ctrl.text = newText;
      }
    }

    _ctrl.selection =
        TextSelection.fromPosition(TextPosition(offset: _ctrl.text.length));
    _inputFocus.requestFocus();
    if (mounted) setState(() {});
    _persistDraft();
  }

  // ---------- Chips helpers ----------
  Future<void> _useMyLocationAsOrigin() async {
    if (_busy) return;
    final hasPerm = await _ensureLocationPermission();
    if (!hasPerm) {
      _addBotText('Location permission denied.', 'تم رفض إذن الموقع.',
          lang: _replyLang());
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final nearest = _computeNearest(LatLng(pos.latitude, pos.longitude));
    if (nearest == null) return;
    final fromName = _replyLang() == _Lang.ar
        ? (nearest.station['nameAr'] ?? nearest.station['name'])
        : (nearest.station['name'] ?? 'Nearest');
    _ctrl.text = (_replyLang() == _Lang.ar ? 'من ' : 'from ') +
        fromName.toString() +
        (_replyLang() == _Lang.ar ? ' إلى ' : ' to ');
    _ctrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _ctrl.text.length),
    );
    _inputFocus.requestFocus();
    _persistDraft();
  }

  Future<void> _useMyLocationAsDestination() async {
    if (_busy) return;
    final hasPerm = await _ensureLocationPermission();
    if (!hasPerm) {
      _addBotText('Location permission denied.', 'تم رفض إذن الموقع.',
          lang: _replyLang());
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final nearest = _computeNearest(LatLng(pos.latitude, pos.longitude));
    if (nearest == null) return;
    final toName = _replyLang() == _Lang.ar
        ? (nearest.station['nameAr'] ?? nearest.station['name'])
        : (nearest.station['name'] ?? 'Nearest');

    final text = _ctrl.text.trim();
    if (RegExp(r'\bfrom\b', caseSensitive: false).hasMatch(text) ||
        text.contains('من')) {
      _ctrl.text =
          '$text ${_replyLang() == _Lang.ar ? 'إلى ' : 'to '}${toName.toString()}';
    } else {
      _ctrl.text =
          (_replyLang() == _Lang.ar ? 'إلى ' : 'to ') + toName.toString();
    }
    _ctrl.selection =
        TextSelection.fromPosition(TextPosition(offset: _ctrl.text.length));
    _inputFocus.requestFocus();
    _persistDraft();
  }

  void _swapFromTo() {
    final rt = _extractRoute(_ctrl.text);
    if (rt == null) {
      _addBotText(
        'Type: from <start> to <end> first.',
        'اكتب: من <البداية> إلى <الوجهة> أولاً.',
        lang: _replyLang(),
      );
      return;
    }
    final swapped = _replyLang() == _Lang.ar
        ? 'من ${rt.$2} إلى ${rt.$1}'
        : 'from ${rt.$2} to ${rt.$1}';
    _ctrl.text = swapped;
    _ctrl.selection =
        TextSelection.fromPosition(TextPosition(offset: _ctrl.text.length));
    _inputFocus.requestFocus();
    _persistDraft();
  }
}

// ===== models =====
class _Msg {
  final String textEn;
  final String textAr;
  final bool isMe;
  final _MsgAction? action;
  final TripTimeEstimate? estimate;
  final String? fromEn;
  final String? toEn;
  final String? fromAr;
  final String? toAr;
  final _TripStatistic? statistic;
  final _Lang lang;

  const _Msg._(
    this.textEn,
    this.textAr,
    this.isMe,
    this.action,
    this.estimate,
    this.fromEn,
    this.toEn,
    this.fromAr,
    this.toAr,
    this.statistic,
    this.lang,
  );

  factory _Msg.user(String en, String ar, {required _Lang lang}) =>
      _Msg._(en, ar, true, null, null, null, null, null, null, null, lang);

  factory _Msg.bot(String en, String ar,
          {_MsgAction? action, required _Lang lang}) =>
      _Msg._(
        en,
        ar,
        false,
        action,
        null,
        null,
        null,
        null,
        null,
        null,
        lang,
      );

  factory _Msg.analytics({
    required String textEn,
    required String textAr,
    required TripTimeEstimate estimate,
    required String fromEn,
    required String toEn,
    required String fromAr,
    required String toAr,
    required _TripStatistic statistic,
    required _Lang lang,
  }) =>
      _Msg._(
        textEn,
        textAr,
        false,
        null,
        estimate,
        fromEn,
        toEn,
        fromAr,
        toAr,
        statistic,
        lang,
      );
}

class _MsgAction {
  final IconData icon;
  final String labelEn;
  final String labelAr;
  final VoidCallback onTap;
  const _MsgAction({
    required this.icon,
    required this.labelEn,
    required this.labelAr,
    required this.onTap,
  });
}

class _Nearest {
  final Map<String, dynamic> station;
  final double distanceMeters;
  const _Nearest({required this.station, required this.distanceMeters});
}

class _SuggestionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _SuggestionCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer.withOpacity(.52),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 228,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.primary.withOpacity(.18)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationSuggestionPanel extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final _WhichTarget target;
  final bool isArabic;
  final void Function(String name, _WhichTarget target) onPick;

  const _StationSuggestionPanel({
    required this.results,
    required this.target,
    required this.isArabic,
    required this.onPick,
  });

  String _lineLabel(String key) {
    final names = isArabic
        ? <String, String>{
            'blue': 'الخط الأزرق',
            'red': 'الخط الأحمر',
            'green': 'الخط الأخضر',
            'orange': 'الخط البرتقالي',
            'purple': 'الخط البنفسجي',
            'yellow': 'الخط الأصفر',
          }
        : <String, String>{
            'blue': 'Blue Line',
            'red': 'Red Line',
            'green': 'Green Line',
            'orange': 'Orange Line',
            'purple': 'Purple Line',
            'yellow': 'Yellow Line',
          };
    return names[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = target == _WhichTarget.origin
        ? (isArabic ? 'محطة الانطلاق' : 'From station')
        : (isArabic ? 'محطة الوصول' : 'To station');

    return Directionality(
      textDirection: isArabic ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Material(
        color: cs.surface,
        elevation: 12,
        shadowColor: Colors.black.withOpacity(.22),
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                color: cs.primaryContainer.withOpacity(.5),
                child: Row(
                  children: [
                    Icon(
                      target == _WhichTarget.origin
                          ? Icons.trip_origin_rounded
                          : Icons.location_on_rounded,
                      size: 18,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            isArabic
                                ? 'اختر محطة مترو'
                                : 'Select a metro station',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: cs.onSurface.withOpacity(.62),
                                ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${results.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 68,
                    color: cs.outlineVariant.withOpacity(.55),
                  ),
                  itemBuilder: (_, index) {
                    final station = results[index];
                    final stationName =
                        isArabic && (station['ar'] as String).isNotEmpty
                            ? station['ar'] as String
                            : station['en'] as String;
                    final lineKeys = List<String>.from(
                      station['lineKeys'] as List,
                    );
                    final primaryColor =
                        metroLineColors[lineKeys.first] ?? cs.primary;

                    return ListTile(
                      dense: true,
                      minVerticalPadding: 9,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.subway_rounded,
                          size: 21,
                          color: primaryColor,
                        ),
                      ),
                      title: Text(
                        stationName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      subtitle: Text(
                        lineKeys.map(_lineLabel).join('  |  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: cs.onSurface.withOpacity(.62),
                                ),
                      ),
                      trailing: SizedBox(
                        width: 24.0 * lineKeys.length,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            for (final key in lineKeys)
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsetsDirectional.only(
                                  start: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: metroLineColors[key] ?? cs.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                      onTap: () => onPick(stationName, target),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  final bool isArabic;
  final ValueChanged<String> onPrompt;

  const _WelcomePanel({required this.isArabic, required this.onPrompt});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tripTimePrompt = isArabic
        ? 'كم تستغرق الرحلة من المركز المالي إلى STC؟'
        : 'How long does it take from KAFD to STC?';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withOpacity(.82),
            cs.secondaryContainer.withOpacity(.5),
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withOpacity(.16)),
      ),
      child: Directionality(
        textDirection: isArabic ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic
                  ? 'ابدأ رحلتك بذكاء'
                  : 'Plan your journey with confidence',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              isArabic
                  ? 'اسأل عن المسارات، أقرب محطة، أو أوقات الرحلات الفعلية.'
                  : 'Ask about routes, nearby stations, or real trip times.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(.72),
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.schedule_rounded, size: 16),
                  label: Text(isArabic ? 'وقت الرحلة' : 'Trip time'),
                  onPressed: () => onPrompt(tripTimePrompt),
                ),
                ActionChip(
                  avatar:
                      const Icon(Icons.location_searching_rounded, size: 16),
                  label: Text(isArabic ? 'أقرب محطة' : 'Nearest station'),
                  onPressed: () =>
                      onPrompt(isArabic ? 'أقرب محطة' : 'Nearest station'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  final bool isArabic;

  const _TypingIndicator({required this.isArabic});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 700),
      tween: Tween(begin: .45, end: 1),
      curve: Curves.easeInOut,
      builder: (context, opacity, _) => Opacity(
        opacity: opacity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withOpacity(.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.subway_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 7),
              Text(
                isArabic ? 'درب يكتب...' : 'Darb is thinking...',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.onSurface.withOpacity(.72),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 8),
              ...List.generate(
                3,
                (index) => Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(.45 + index * .16),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripAnalyticsCard extends StatelessWidget {
  final TripTimeEstimate estimate;
  final String from;
  final String to;
  final _TripStatistic statistic;
  final bool isArabic;

  const _TripAnalyticsCard({
    required this.estimate,
    required this.from,
    required this.to,
    required this.statistic,
    required this.isArabic,
  });

  int _minutes(int seconds) => (seconds / 60).round();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = estimate.commonLines
        .map((line) => line.trim().toLowerCase())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final specificLines = switch (statistic) {
      _TripStatistic.average => lines,
      _TripStatistic.fastest => estimate.fastestLines
          .map((line) => line.trim().toLowerCase())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
      _TripStatistic.slowest => estimate.slowestLines
          .map((line) => line.trim().toLowerCase())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
    };
    final linesTitle = switch (statistic) {
      _TripStatistic.average =>
        isArabic ? 'الخطوط الأكثر استخدامًا' : 'Common community lines',
      _TripStatistic.fastest =>
        isArabic ? 'خطوط أسرع رحلة مسجلة' : 'Lines on the fastest trip',
      _TripStatistic.slowest =>
        isArabic ? 'خطوط أطول رحلة مسجلة' : 'Lines on the longest trip',
    };
    final average = _minutes(estimate.averageSeconds);
    final fastest = _minutes(estimate.minimumSeconds);
    final slowest = _minutes(estimate.maximumSeconds);
    final focus = switch (statistic) {
      _TripStatistic.average => average,
      _TripStatistic.fastest => fastest,
      _TripStatistic.slowest => slowest,
    };
    final focusLabel = switch (statistic) {
      _TripStatistic.average => isArabic ? 'المتوسط' : 'Average',
      _TripStatistic.fastest => isArabic ? 'الأسرع' : 'Fastest',
      _TripStatistic.slowest => isArabic ? 'الأبطأ' : 'Slowest',
    };

    return Directionality(
      textDirection: isArabic ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(.56),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.primary.withOpacity(.24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '$from  →  $to',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    focusLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: cs.onPrimary.withOpacity(.82),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '$focus ${isArabic ? 'دقيقة' : 'min'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (statistic == _TripStatistic.average)
              Row(
                children: [
                  Expanded(
                      child: _metric(
                          context, isArabic ? 'المتوسط' : 'Average', average)),
                  Expanded(
                      child: _metric(
                          context, isArabic ? 'الأسرع' : 'Fastest', fastest)),
                  Expanded(
                      child: _metric(
                          context, isArabic ? 'الأبطأ' : 'Slowest', slowest)),
                ],
              ),
            if (specificLines.isNotEmpty) ...[
              const SizedBox(height: 12),
              _CommunityLinesPanel(
                lines: specificLines,
                title: linesTitle,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'استنادًا إلى ${estimate.sampleCount} رحلة مكتملة'
                  : 'Based on ${estimate.sampleCount} completed trips',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withOpacity(.62),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, int value) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurface.withOpacity(.62),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          '$value ${isArabic ? 'د' : 'm'}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

/// Shows aggregate line usage without implying that it is one exact route.
class _CommunityLinesPanel extends StatelessWidget {
  final List<String> lines;
  final String title;

  const _CommunityLinesPanel({required this.lines, required this.title});

  Color _colorFor(String line, Color fallback) {
    return metroLineColors[line.toLowerCase()] ?? fallback;
  }

  String _labelFor(String line) {
    if (line.isEmpty) return 'Metro line';
    final english = '${line[0].toUpperCase()}${line.substring(1)}';
    return '$english Line';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = lines.map((line) => _colorFor(line, cs.primary)).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(.64),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 17, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _LineUsageStrip(colors: colors, accent: cs.primary),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (var index = 0; index < lines.length; index++)
                _CommunityLineBadge(
                  label: _labelFor(lines[index]),
                  color: colors[index],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineUsageStrip extends StatelessWidget {
  final List<Color> colors;
  final Color accent;

  const _LineUsageStrip({required this.colors, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.trip_origin_rounded, size: 15, color: accent),
        const SizedBox(width: 6),
        for (var index = 0; index < colors.length; index++) ...[
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: colors[index],
                borderRadius: BorderRadius.horizontal(
                  left: index == 0 ? const Radius.circular(99) : Radius.zero,
                  right: index == colors.length - 1
                      ? const Radius.circular(99)
                      : Radius.zero,
                ),
              ),
            ),
          ),
          if (index != colors.length - 1)
            Container(
                width: 3,
                height: 5,
                color: Theme.of(context).colorScheme.surface),
        ],
        const SizedBox(width: 6),
        Icon(Icons.location_on_rounded, size: 16, color: accent),
      ],
    );
  }
}

class _CommunityLineBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CommunityLineBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.13),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

// ===== Animated Bubble =====
class _MsgBubble extends StatelessWidget {
  final _Lang lang;
  final Color bubbleColor;
  final BorderRadius radius;
  final String text;
  final TextStyle? textStyle;

  const _MsgBubble({
    required this.lang,
    required this.bubbleColor,
    required this.radius,
    required this.text,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0.8, end: 1.0),
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - value) * 12),
            child: child,
          ),
        );
      },
      child: Directionality(
        textDirection:
            (lang == _Lang.ar) ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: radius,
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(.35),
            ),
          ),
          child: Text(
            text,
            textAlign: TextAlign.start,
            style: textStyle,
          ),
        ),
      ),
    );
  }
}
