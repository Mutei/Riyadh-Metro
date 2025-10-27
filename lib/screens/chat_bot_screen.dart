// lib/screens/chat_bot_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:intl/intl.dart';

import 'package:darb/constants/colors.dart';
import 'package:darb/localization/language_constants.dart';
import 'package:darb/latlon/latlong_stations.dart' as metro;
import 'package:darb/services/app_bus.dart';

class ChatBotScreen extends StatefulWidget {
  const ChatBotScreen({super.key});
  @override
  State<ChatBotScreen> createState() => _ChatBotScreenState();
}

enum _Lang { en, ar }

enum _WhichTarget { origin, destination }

class _ChatBotScreenState extends State<ChatBotScreen> {
  final _ctrl = TextEditingController();
  final List<_Msg> _messages = <_Msg>[];
  bool _busy = false;

  // Track last user language so bot can mirror it
  _Lang? _lastUserLang;

  // ===== Autocomplete overlay =====
  OverlayEntry? _suggestionsOverlay;
  bool _suggestForOrigin = true; // which endpoint we’re suggesting for
  final _inputFocus = FocusNode();

  bool get _localeIsArabic => Localizations.localeOf(context)
      .languageCode
      .toLowerCase()
      .startsWith('ar');

  // Flattened station list once, reused
  List<Map<String, dynamic>> get _allStations => [
        ...metro.blueStations,
        ...metro.redStations,
        ...metro.yellowStations,
        ...metro.purpleStations,
        ...metro.orangeStations,
        ...metro.greenStations,
      ];

  // We add the greeting after dependencies are available
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(() {
      if (!_inputFocus.hasFocus) _hideSuggestions();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_booted) return;
    _booted = true;

    final useAr = _localeIsArabic;
    _messages.add(_Msg.bot(
      'Hi! I can help with Darb. Try “Nearest station”, “Metro hours”, or “from KAFD to Qasr Al Hokm”.',
      'مرحباً! أستطيع مساعدتك في درب. جرّب "أقرب محطة"، "ساعات المترو"، أو "من المركز المالي إلى قصر الحكم".',
      lang: useAr ? _Lang.ar : _Lang.en,
    ));
    setState(() {});
  }

  @override
  void dispose() {
    _hideSuggestions();
    _ctrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: bubbleColor,
                            borderRadius: radius,
                            border:
                                Border.all(color: cs.outline.withOpacity(.35)),
                          ),
                          child: Text(
                            showText,
                            textAlign: TextAlign.start,
                            style: t.bodyMedium?.copyWith(color: cs.onSurface),
                          ),
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

          // Quick chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
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

          // Input
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _inputFocus,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      onChanged: (val) => _handleChanged(val),
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
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(),
                          )
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

  // ---------- Quick helper (chip) ----------
  Widget _chip(
      {required IconData icon, required String label, VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: cs.onSurface),
      label: Text(label),
      onPressed: onTap,
      shape: StadiumBorder(side: BorderSide(color: cs.outline)),
      backgroundColor:
          Theme.of(context).inputDecorationTheme.fillColor ?? cs.surface,
    );
  }

  // ---------- Language helpers ----------
  bool _containsArabic(String s) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(s); // Arabic Unicode block

  _Lang _replyLang() {
    // Prefer last user language; fallback to current locale
    return _lastUserLang ?? (_localeIsArabic ? _Lang.ar : _Lang.en);
  }

  // ---------- Input router ----------
  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    _hideSuggestions();

    // detect user language per message
    final userLang = _containsArabic(text) ? _Lang.ar : _Lang.en;
    _lastUserLang = userLang;

    _addUserText(text, text, lang: userLang);

    if (_looksLikeNearest(text)) {
      _handleNearestStation();
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
      'For now, try: “Nearest station”, “Metro hours”, or “from KAFD to Qasr Al Hokm”.',
      'جرّب الآن: "أقرب محطة"، "ساعات المترو"، أو "من المركز المالي إلى قصر الحكم".',
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

  // ---------- Metro hours logic (Sat–Thu 5:30 AM–12:00 PM, Fri 10:00 AM–12:00 AM) ----------
  (DateTime open, DateTime close) _todayWindow(DateTime now) {
    final d = DateTime(now.year, now.month, now.day);
    if (now.weekday == DateTime.friday) {
      final open = DateTime(d.year, d.month, d.day, 10, 0);
      final close =
          DateTime(d.year, d.month, d.day).add(const Duration(days: 1));
      return (open, close);
    } else {
      final open = DateTime(d.year, d.month, d.day, 5, 30);
      final close = DateTime(d.year, d.month, d.day, 12, 0);
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
        'Hours: Sat–Thu 5:30 AM — 12:00 PM • Fri 10:00 AM — 12:00 AM';
    final summaryAr =
        'المواعيد: السبت–الخميس 5:30 ص — 12:00 م • الجمعة 10:00 ص — 12:00 ص';

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
    final all = _allStations;
    final n = _norm(q);
    Map<String, dynamic>? best;
    int bestScore = -1;
    for (final s in all) {
      final en = _norm((s['name'] ?? '').toString());
      final ar = _norm((s['nameAr'] ?? '').toString());
      final score = _score(n, en, ar);
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return bestScore <= 0 ? null : best;
  }

  String _norm(String x) => x.toLowerCase().trim();
  int _score(String q, String en, String ar) {
    if (en.startsWith(q) || ar.startsWith(q)) return 3;
    if (en.contains(q) || ar.contains(q)) return 2;
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
    final trimmed = val.trim();
    if (trimmed.length < 2) {
      _hideSuggestions();
      return;
    }

    final _WhichTarget? target = _whichTarget(trimmed);
    if (target == null) {
      _hideSuggestions();
      return;
    }

    _suggestForOrigin = (target == _WhichTarget.origin);
    final frag = _currentFragmentForTarget(trimmed, target);
    if (frag.isEmpty) {
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

  void _showSuggestions(BuildContext ctx, List<Map<String, dynamic>> results,
      _WhichTarget target) {
    _hideSuggestions();
    if (!_inputFocus.hasFocus) return;

    final overlayState = Overlay.of(ctx);
    if (overlayState == null) return;

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
    overlayState.insert(_suggestionsOverlay!);
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
  }

  // ===================== Chips helpers =====================

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
      _ctrl.text = text +
          ' ' +
          (_replyLang() == _Lang.ar ? 'إلى ' : 'to ') +
          toName.toString();
    } else {
      _ctrl.text =
          (_replyLang() == _Lang.ar ? 'إلى ' : 'to ') + toName.toString();
    }
    _ctrl.selection =
        TextSelection.fromPosition(TextPosition(offset: _ctrl.text.length));
    _inputFocus.requestFocus();
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
  }
}

// ===== models =====
class _Msg {
  final String textEn;
  final String textAr;
  final bool isMe;
  final _MsgAction? action;
  final _Lang lang; // per-message language

  const _Msg._(this.textEn, this.textAr, this.isMe, this.action, this.lang);

  factory _Msg.user(String en, String ar, {required _Lang lang}) =>
      _Msg._(en, ar, true, null, lang);

  // Make `action` optional (nullable) — not required
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
