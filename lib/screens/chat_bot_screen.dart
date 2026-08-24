// lib/screens/chat_bot_screen.dart
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

  // Persistence keys
  static const _kDraftKey = 'chatbot_draft_v1';
  static const _kRecentRoutesKey =
      'chatbot_recent_routes_v1'; // List<String> like "from||to"

  // Recent routes in memory
  List<(String from, String to)> _recentRoutes = [];

  // Initial greeting control
  bool _booted = false;

  bool get _localeIsArabic => Localizations.localeOf(context)
      .languageCode
      .toLowerCase()
      .startsWith('ar');

  // Flattened station list (reuse)
  List<Map<String, dynamic>> get _allStations => [
        ...metro.blueStations,
        ...metro.redStations,
        ...metro.yellowStations,
        ...metro.purpleStations,
        ...metro.orangeStations,
        ...metro.greenStations,
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
    _messages.add(_Msg.bot(
      'Hi! I can help with Darb. Try “Nearest station”, “Metro hours”, or “How long does it take from KAFD to STC?”.',
      'مرحباً! أستطيع مساعدتك في درب. جرّب "أقرب محطة"، "ساعات المترو"، أو "كم تستغرق الرحلة من المركز المالي إلى STC؟".',
      lang: _localeIsArabic ? _Lang.ar : _Lang.en,
    ));
    setState(() {}); // show greeting
  }

  @override
  void dispose() {
    _hideSuggestions();
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
    if (mounted) setState(() {});
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _localeIsArabic ? 'درب بوت' : 'Darb Bot',
          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              reverse: true,
              itemCount: _messages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final msg = _messages[_messages.length - 1 - i];
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
                        _MsgBubble(
                          lang: msg.lang,
                          bubbleColor: bubbleColor,
                          radius: radius,
                          text: showText,
                          textStyle:
                              t.bodyMedium?.copyWith(color: cs.onSurface),
                        ),
                        if (msg.action != null) ...[
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            icon: Icon(msg.action!.icon, size: 18),
                            label: Text(actionLabel!),
                            onPressed: msg.action!.onTap,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // -------- Quick chips (core) --------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_recentRoutes.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    const _DividerDot(),
                    const SizedBox(width: 12),
                    ..._recentRoutes
                        .map((r) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _chip(
                                icon: Icons.history_rounded,
                                label: _localeIsArabic
                                    ? 'من ${_short(r.$1)} → ${_short(r.$2)}'
                                    : 'From ${_short(r.$1)} → ${_short(r.$2)}',
                                onTap: _busy
                                    ? null
                                    : () => _handleRouteRequest(r.$1, r.$2),
                              ),
                            ))
                        .toList(),
                  ],
                  _chip(
                    icon: Icons.location_searching_rounded,
                    label: _localeIsArabic ? 'أقرب محطة' : 'Nearest station',
                    onTap: _busy ? null : _handleNearestStation,
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    icon: Icons.route_rounded,
                    label: _localeIsArabic ? 'من / إلى' : 'From / To',
                    onTap: () {
                      _addBotText(
                        'Type: from <start> to <end>',
                        'اكتب: من <البداية> إلى <الوجهة>',
                        lang: _replyLang(),
                      );
                      _ctrl.text = _replyLang() == _Lang.ar ? 'من ' : 'from ';
                      _ctrl.selection = TextSelection.fromPosition(
                        TextPosition(offset: _ctrl.text.length),
                      );
                      _inputFocus.requestFocus();
                    },
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    icon: Icons.info_rounded,
                    label: _localeIsArabic ? 'ساعات المترو' : 'Metro hours',
                    onTap: _busy ? null : _handleHours,
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    icon: Icons.schedule_rounded,
                    label: _localeIsArabic ? 'وقت الرحلة' : 'Trip time',
                    onTap: _busy
                        ? null
                        : () => _insertQuestionSuggestion(
                              _localeIsArabic
                                  ? 'كم تستغرق الرحلة من '
                                  : 'How long does it take from ',
                            ),
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    icon: Icons.my_location_rounded,
                    label: _localeIsArabic
                        ? 'اجعل موقعي البداية'
                        : 'Use my location (from)',
                    onTap: _busy ? null : _useMyLocationAsOrigin,
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    icon: Icons.flag_circle_rounded,
                    label: _localeIsArabic
                        ? 'اجعل موقعي الوجهة'
                        : 'Use my location (to)',
                    onTap: _busy ? null : _useMyLocationAsDestination,
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    icon: Icons.swap_vert_rounded,
                    label: _localeIsArabic ? 'تبديل من/إلى' : 'Swap From/To',
                    onTap: _swapFromTo,
                  ),
                ],
              ),
            ),
          ),

          if (timeSuggestions.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: timeSuggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) => ActionChip(
                  avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(
                    timeSuggestions[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _busy
                      ? null
                      : () => _insertQuestionSuggestion(timeSuggestions[index]),
                ),
              ),
            ),

          // -------- Input --------
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                      decoration: InputDecoration(
                        hintText:
                            getTranslated(context, 'bot.typeYourMessage') ==
                                    'bot.typeYourMessage'
                                ? (_localeIsArabic
                                    ? 'اكتب رسالتك'
                                    : 'Type your message')
                                : getTranslated(context, 'bot.typeYourMessage'),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send
                  IconButton.filled(
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
        ],
      ),
    );
  }

  // ---------- UI helpers ----------
  Widget _chip(
      {required IconData icon, required String label, VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: cs.onSurface),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      onPressed: onTap,
      shape: StadiumBorder(side: BorderSide(color: cs.outline)),
      backgroundColor:
          Theme.of(context).inputDecorationTheme.fillColor ?? cs.surface,
    );
  }

  static String _short(String name) {
    // Keep chips compact
    const max = 18;
    return name.length <= max ? name : '${name.substring(0, max - 1)}…';
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
      _handleTripTimeRequest(timeRoute.$1, timeRoute.$2);
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
        query.contains('time from') ||
        query.contains('metro trip') ||
        query.contains('take me') ||
        query.contains('كم يستغرق') ||
        query.contains('كم تستغرق') ||
        query.contains('كم ياخذ') ||
        query.contains('مدة الرحلة') ||
        query.contains('متوسط وقت') ||
        query.contains('وقت الرحلة');
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

    final arFromTo =
        RegExp(r'من\s+(.+?)\s+إ?لى\s+(.+?)(?:[؟?.!]|$)').firstMatch(raw);
    if (arFromTo != null) {
      return (
        _cleanStationQuery(arFromTo.group(1)!),
        _cleanStationQuery(arFromTo.group(2)!),
      );
    }
    return null;
  }

  String _cleanStationQuery(String value) => value
      .replaceAll(RegExp(r'\b(station|metro)\b', caseSensitive: false), '')
      .replaceAll('محطة', '')
      .trim();

  Future<void> _handleTripTimeRequest(String fromTxt, String toTxt) async {
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
      final transferText = estimate.averageTransfers == 0
          ? ''
          : ' Typical transfers: ${estimate.averageTransfers}.';
      final transferTextAr = estimate.averageTransfers == 0
          ? ''
          : ' التحويلات المعتادة: ${estimate.averageTransfers}.';
      _addBotText(
        'Based on ${estimate.sampleCount} completed metro trips, travel from $fromEn to $toEn takes about $average min on average. Typical range: $minimum-$maximum min.$lines$transferText',
        'استنادًا إلى ${estimate.sampleCount} رحلة مترو مكتملة، تستغرق الرحلة من $fromAr إلى $toAr حوالي $average دقيقة في المتوسط. المدى المعتاد: $minimum-$maximum دقيقة.$linesAr$transferTextAr',
        lang: _replyLang(),
      );
    } catch (_) {
      _addBotText(
        'I could not read your trip history right now. Please try again.',
        'تعذر قراءة سجل رحلاتك الآن. حاول مرة أخرى.',
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
  void _addUserText(String en, String ar, {required _Lang lang}) =>
      setState(() => _messages.add(_Msg.user(en, ar, lang: lang)));

  void _addBotText(String en, String ar, {required _Lang lang}) =>
      setState(() => _messages.add(_Msg.bot(en, ar, lang: lang)));

  void _addBotAction({
    required String textEn,
    required String textAr,
    required _MsgAction action,
    required _Lang lang,
  }) {
    setState(() =>
        _messages.add(_Msg.bot(textEn, textAr, action: action, lang: lang)));
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

    _showSuggestions(context, results, target);
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
          RegExp(r'\bfrom\s*([^t]+?)(?:\s+to\s+.*)?$', caseSensitive: false);
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
    return _allStations
        .map((s) => {
              'en': (s['name'] ?? '').toString(),
              'ar': (s['nameAr'] ?? '').toString(),
              'lat': s['lat'],
              'lng': s['lng'],
            })
        .where((s) {
          final en = _norm(s['en'] as String);
          final ar = _norm(s['ar'] as String);
          return en.contains(n) || ar.contains(n);
        })
        .take(8)
        .toList();
  }

  List<String> _tripTimeSuggestions(String input) {
    final normalized = _norm(input);
    final timeLike = normalized.contains('how') ||
        normalized.contains('long') ||
        normalized.contains('time') ||
        normalized.contains('average') ||
        normalized.contains('كم') ||
        normalized.contains('وقت') ||
        normalized.contains('مدة');
    final isArabic = _replyLang() == _Lang.ar;
    final catalog = isArabic
        ? <String>[
            'كم تستغرق الرحلة من المركز المالي إلى STC؟',
            'ما متوسط وقت الرحلة من المركز المالي إلى STC؟',
            'كم تستغرق رحلة المترو من المركز المالي إلى قصر الحكم؟',
          ]
        : <String>[
            'How long does it take from KAFD to STC?',
            'What is the average travel time from KAFD to STC?',
            'How long is the metro trip from KAFD to Qasr Al Hokm?',
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

  void _showSuggestions(BuildContext ctx, List<Map<String, dynamic>> results,
      _WhichTarget target) {
    _hideSuggestions();
    if (!_inputFocus.hasFocus) return;

    final overlay = Overlay.of(ctx);
    if (overlay == null) return;

    _suggestionsOverlay = OverlayEntry(
      builder: (_) {
        return Positioned(
          left: 12,
          right: 12,
          bottom: 84, // above input row
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = results[i];
                  final title =
                      _replyLang() == _Lang.ar && (s['ar'] as String).isNotEmpty
                          ? s['ar'] as String
                          : s['en'] as String;
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.train_rounded),
                    title: Text(title),
                    onTap: () => _onPickSuggestion(title, target),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_suggestionsOverlay!);
  }

  void _hideSuggestions() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
  }

  void _onPickSuggestion(String pickedName, _WhichTarget target) {
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
                RegExp(r'\bfrom\s+(.+?)(\s+to\b|$)', caseSensitive: false),
                'from $pickedName')
            .replaceAll(RegExp(r'\bمن\s+(.+?)(\s+إ?لى\b|$)'), 'من $pickedName');

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
    _handleChanged(_ctrl.text);
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
  final _Lang lang;

  const _Msg._(this.textEn, this.textAr, this.isMe, this.action, this.lang);

  factory _Msg.user(String en, String ar, {required _Lang lang}) =>
      _Msg._(en, ar, true, null, lang);

  factory _Msg.bot(String en, String ar,
          {_MsgAction? action, required _Lang lang}) =>
      _Msg._(en, ar, false, action, lang);
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

class _DividerDot extends StatelessWidget {
  const _DividerDot({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
          color: cs.outlineVariant, borderRadius: BorderRadius.circular(3)),
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
