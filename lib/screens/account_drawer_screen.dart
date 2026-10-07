import 'package:darb/screens/purchase_history_screen.dart';
import 'package:flutter/material.dart';

import 'package:darb/constants/colors.dart';
import 'package:darb/widgets/drawer_tile.dart';
import 'package:darb/utils/logout_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/language_constants.dart';
import '../services/metro_train_marker_preferences.dart';
import '../services/onboard_display_preferences.dart';

import 'chat_bot_screen.dart';
import 'language_screen.dart';
import 'personal_info_screen.dart';
import 'travel_history_screen.dart';
import '../main.dart';

class AccountDrawerScreen extends StatelessWidget {
  final String displayName;
  final String appVersion;

  const AccountDrawerScreen({
    super.key,
    required this.displayName,
    this.appVersion = "1.2.1",
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: back + logo + greeting
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    height: 28,
                    width: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.kPrimaryColor.withOpacity(.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Image.asset('assets/logo/darb_logo.jpeg'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${getTranslated(context, 'drawer.hi')} $displayName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PersonalInfoScreen(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    side: BorderSide(color: cs.outline),
                    backgroundColor:
                        theme.inputDecorationTheme.fillColor ?? cs.surface,
                    foregroundColor: cs.onSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: Text(getTranslated(context, 'drawer.manageAccount')),
                ),
              ),

              const SizedBox(height: 14),

              // -------- Your account --------
              _sectionTitle(context, 'drawer.section.account'),
              const SizedBox(height: 6),
              DrawerTile(
                icon: Icons.access_time_rounded,
                title: getTranslated(context, 'drawer.reminders'),
                onTap: () {},
              ),
              DrawerTile(
                icon: Icons.directions_bus_filled_rounded,
                title: getTranslated(context, 'drawer.busOnDemand'),
                onTap: () {},
              ),
              DrawerTile(
                icon: Icons.route_rounded,
                title: getTranslated(context, 'drawer.travelHistory'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const TravelHistoryScreen()),
                  );
                },
              ),
              DrawerTile(
                icon: Icons.receipt_long_rounded,
                title: getTranslated(context, 'drawer.purchaseHistory'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PurchaseHistoryScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 14),

              // -------- Benefits --------
              _sectionTitle(context, 'drawer.section.benefits'),
              const SizedBox(height: 6),
              DrawerTile(
                icon: Icons.campaign_rounded,
                title: getTranslated(context, 'drawer.whatsNew'),
                onTap: () {},
              ),

              const SizedBox(height: 14),

              // -------- Support / About --------
              _sectionTitle(context, 'drawer.section.support'),
              const SizedBox(height: 6),
              DrawerTile(
                icon: Icons.privacy_tip_rounded,
                title: getTranslated(context, 'drawer.privacy'),
                trailing: Icon(Icons.open_in_new_rounded,
                    color: cs.onSurface.withOpacity(0.45)),
                onTap: () {},
              ),
              DrawerTile(
                icon: Icons.smart_toy_rounded,
                title:
                    getTranslated(context, 'drawer.darbBot') == 'drawer.darbBot'
                        ? 'Darb Bot'
                        : getTranslated(context, 'drawer.darbBot'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChatBotScreen()),
                  );
                },
              ),
              DrawerTile(
                icon: Icons.info_outline_rounded,
                title: getTranslated(context, 'drawer.about'),
                trailing: Icon(Icons.open_in_new_rounded,
                    color: cs.onSurface.withOpacity(0.45)),
                onTap: () {},
              ),
              DrawerTile(
                icon: Icons.description_outlined,
                title: getTranslated(context, 'drawer.terms'),
                trailing: Icon(Icons.open_in_new_rounded,
                    color: cs.onSurface.withOpacity(0.45)),
                onTap: () {},
              ),
              DrawerTile(
                icon: Icons.help_outline_rounded,
                title: getTranslated(context, 'drawer.help'),
                onTap: () {},
              ),
              DrawerTile(
                icon: Icons.map_rounded,
                title: getTranslated(context, 'drawer.suggestRoute'),
                onTap: () {},
              ),

              const SizedBox(height: 14),

              // -------- Other --------
              _sectionTitle(context, 'drawer.section.other'),
              const SizedBox(height: 6),

              DrawerTile(
                icon: Icons.language_rounded,
                title: getTranslated(context, 'drawer.language'),
                subtitle: getTranslated(context, 'drawer.languageSubtitle'),
                onTap: () async {
                  final picked = await Navigator.of(context).push<Locale>(
                    MaterialPageRoute(builder: (_) => const LanguageScreen()),
                  );
                  if (picked != null) {}
                },
              ),

              DrawerTile(
                icon: Icons.brightness_6_rounded,
                title: getTranslated(context, 'drawer.themeSettings') ==
                        'drawer.themeSettings'
                    ? 'Theme Settings'
                    : getTranslated(context, 'drawer.themeSettings'),
                subtitle: getTranslated(context, 'drawer.themeSubtitle') ==
                        'drawer.themeSubtitle'
                    ? 'Light, Dark, or follow System'
                    : getTranslated(context, 'drawer.themeSubtitle'),
                onTap: () => _showThemeBottomSheet(context),
              ),
              DrawerTile(
                icon: Icons.train_rounded,
                title: 'Metro train marker',
                subtitle: 'Choose classic or line-specific trains',
                onTap: () => _showMetroTrainMarkerBottomSheet(context),
              ),
              DrawerTile(
                icon: Icons.view_carousel_rounded,
                title: 'Route display style',
                subtitle: 'Preview and choose an onboard journey layout',
                onTap: () => _showOnboardDisplayBottomSheet(context),
              ),

              DrawerTile(
                icon: Icons.my_location_rounded,
                title: getTranslated(context, 'drawer.defaultLocation'),
                subtitle:
                    getTranslated(context, 'drawer.defaultLocationSubtitle'),
                onTap: () {},
              ),
              DrawerTile(
                icon: Icons.logout_rounded,
                title: getTranslated(context, 'drawer.logout'),
                onTap: () => confirmAndLogout(context),
                foreground: Colors.red,
              ),

              const SizedBox(height: 18),

              // -------- Registration badge --------
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                decoration: BoxDecoration(
                  color: theme.inputDecorationTheme.fillColor ?? cs.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outline),
                ),
                child: Column(
                  children: [
                    Text(
                      getTranslated(context, 'drawer.registeredDGA'),
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.65),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '20241208431',
                        style: text.labelLarge?.copyWith(color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Center(
                child: Text(
                  '${getTranslated(context, 'drawer.version')} $appVersion',
                  style: text.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.55),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helpers ---
  Widget _sectionTitle(BuildContext context, String key) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text(
          getTranslated(context, key),
          style: TextStyle(
            color: cs.onSurface.withOpacity(0.60),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  void _showThemeBottomSheet(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.inputDecorationTheme.fillColor ?? cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ThemePickerSheet(),
    );
  }

  void _showMetroTrainMarkerBottomSheet(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: theme.inputDecorationTheme.fillColor ?? cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _MetroTrainMarkerPickerSheet(),
    );
  }

  void _showOnboardDisplayBottomSheet(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: theme.inputDecorationTheme.fillColor ?? cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const FractionallySizedBox(
        heightFactor: .9,
        child: _OnboardDisplayPickerSheet(),
      ),
    );
  }
}

class _OnboardDisplayPickerSheet extends StatefulWidget {
  const _OnboardDisplayPickerSheet();

  @override
  State<_OnboardDisplayPickerSheet> createState() =>
      _OnboardDisplayPickerSheetState();
}

class _OnboardDisplayPickerSheetState
    extends State<_OnboardDisplayPickerSheet> {
  OnboardDisplayStyle? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final style = await OnboardDisplayPreferences.load();
    if (mounted) setState(() => _selected = style);
  }

  Future<void> _apply(OnboardDisplayStyle style) async {
    await OnboardDisplayPreferences.save(style);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected ?? OnboardDisplayStyle.stationPulse;
    const options = <(OnboardDisplayStyle, String, String)>[
      (
        OnboardDisplayStyle.stationPulse,
        'Station Pulse',
        'Vertical route spine with a clear next-station focus.',
      ),
      (
        OnboardDisplayStyle.originalMotion,
        'Original Motion',
        'Horizontal route with a moving train and transfer context.',
      ),
      (
        OnboardDisplayStyle.trackFocus,
        'Track Focus',
        'Precise station timing with the train placed on the track.',
      ),
      (
        OnboardDisplayStyle.liveCarriage,
        'Live Carriage',
        'Full side-view carriage moving between station platforms.',
      ),
    ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(
            'Route display style',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Preview and select the route layout shown during your metro trip.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .68),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Preview colors are illustrative. The selected design follows your active metro line color.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .52),
            ),
          ),
          const SizedBox(height: 16),
          for (final option in options)
            _OnboardDesignOptionCard(
              style: option.$1,
              title: option.$2,
              subtitle: option.$3,
              selected: selected == option.$1,
              onTap: () => _apply(option.$1),
            ),
        ],
      ),
    );
  }
}

class _OnboardDesignOptionCard extends StatelessWidget {
  final OnboardDisplayStyle style;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _OnboardDesignOptionCard({
    required this.style,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final borderColor =
        selected ? cs.primary : cs.outlineVariant.withValues(alpha: .72);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: selected
            ? cs.primary.withValues(alpha: .07)
            : cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2.65,
                  child: CustomPaint(
                    painter: _OnboardDesignPreviewPainter(style),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: .66),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? cs.primary : cs.outline,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: selected ? 14 : 0,
                        height: selected ? 14 : 0,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardDesignPreviewPainter extends CustomPainter {
  final OnboardDisplayStyle style;

  const _OnboardDesignPreviewPainter(this.style);

  static const _background = Color(0xFF0B111B);
  static const _panel = Color(0xFF152235);
  static const _muted = Color(0xFF8090A9);
  static const _white = Color(0xFFF3F7FF);

  Color get _accent => switch (style) {
        OnboardDisplayStyle.stationPulse => const Color(0xFF3698FF),
        OnboardDisplayStyle.originalMotion => const Color(0xFFEC4A4A),
        OnboardDisplayStyle.trackFocus => const Color(0xFF9D5CFF),
        OnboardDisplayStyle.liveCarriage => const Color(0xFFF3A32D),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height * .11);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = _background,
    );

    final accentGlow = Paint()
      ..color = _accent.withValues(alpha: .22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawCircle(
      Offset(size.width * .78, size.height * .32),
      size.height * .28,
      accentGlow,
    );

    switch (style) {
      case OnboardDisplayStyle.stationPulse:
        _paintStationPulse(canvas, size);
      case OnboardDisplayStyle.originalMotion:
        _paintOriginalMotion(canvas, size);
      case OnboardDisplayStyle.trackFocus:
        _paintTrackFocus(canvas, size);
      case OnboardDisplayStyle.liveCarriage:
        _paintLiveCarriage(canvas, size);
    }
  }

  void _paintStationPulse(Canvas canvas, Size size) {
    final x = size.width * .12;
    _label(canvas, 'LINE BLUE', Offset(size.width * .07, size.height * .09),
        size.height * .105, _white, FontWeight.w800);
    _pill(
        canvas,
        Rect.fromLTWH(size.width * .75, size.height * .07, size.width * .18,
            size.height * .22),
        '4 min');

    canvas.drawLine(
      Offset(x, size.height * .34),
      Offset(x, size.height * .86),
      Paint()
        ..color = _accent
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    final stations = <(double, String)>[
      (.37, 'KAFD'),
      (.54, 'Riyadh Exhibition Center'),
      (.70, 'An Nuzhah'),
      (.85, 'Ministry of Education'),
    ];
    for (var index = 0; index < stations.length; index++) {
      final station = stations[index];
      final isCurrent = index == 1;
      _node(canvas, Offset(x, size.height * station.$1),
          active: isCurrent, completed: index == 0);
      if (isCurrent) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * .18, size.height * (station.$1 - .08),
                size.width * .72, size.height * .16),
            const Radius.circular(9),
          ),
          Paint()..color = _panel,
        );
      }
      _label(
        canvas,
        station.$2,
        Offset(size.width * .22, size.height * (station.$1 - .035)),
        size.height * .085,
        isCurrent ? _white : _muted,
        isCurrent ? FontWeight.w700 : FontWeight.w500,
      );
    }
  }

  void _paintOriginalMotion(Canvas canvas, Size size) {
    _lineBadge(canvas, size, 'RED LINE');
    _pill(
        canvas,
        Rect.fromLTWH(size.width * .75, size.height * .08, size.width * .18,
            size.height * .22),
        '8 min');
    final y = size.height * .62;
    canvas.drawLine(
      Offset(size.width * .08, y),
      Offset(size.width * .92, y),
      Paint()
        ..color = _accent.withValues(alpha: .62)
        ..strokeWidth = 3,
    );
    for (final x in [.15, .5, .86]) {
      _node(canvas, Offset(size.width * x, y), active: x == .5);
    }
    _train(canvas, Offset(size.width * .43, y), size.width * .18,
        size.height * .17);
    _label(
        canvas,
        'Exhibition Center',
        Offset(size.width * .07, size.height * .75),
        size.height * .075,
        _muted);
    _label(
        canvas,
        'Khalid Ibn Waleed',
        Offset(size.width * .37, size.height * .75),
        size.height * .075,
        _white,
        FontWeight.w700);
    _label(canvas, 'Hamra', Offset(size.width * .82, size.height * .75),
        size.height * .075, _muted);
  }

  void _paintTrackFocus(Canvas canvas, Size size) {
    _lineBadge(canvas, size, 'PURPLE LINE');
    final panelRect = Rect.fromLTWH(size.width * .05, size.height * .34,
        size.width * .9, size.height * .52);
    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, const Radius.circular(10)),
      Paint()..color = _panel.withValues(alpha: .88),
    );
    final y = size.height * .61;
    canvas.drawLine(
      Offset(size.width * .12, y),
      Offset(size.width * .88, y),
      Paint()
        ..color = _accent
        ..strokeWidth = 4,
    );
    const positions = [.18, .5, .82];
    const names = ['KAFD', 'King Abdullah Rd', 'Financial District'];
    const times = ['2 min', '5 min', '9 min'];
    for (var index = 0; index < positions.length; index++) {
      final x = size.width * positions[index];
      _node(canvas, Offset(x, y), active: index == 1);
      _label(
          canvas,
          names[index],
          Offset(x - size.width * .075, size.height * .4),
          size.height * .065,
          index == 1 ? _white : _muted,
          index == 1 ? FontWeight.w700 : FontWeight.w500);
      _label(
          canvas,
          times[index],
          Offset(x - size.width * .04, size.height * .72),
          size.height * .07,
          _muted);
    }
    _train(canvas, Offset(size.width * .43, y), size.width * .17,
        size.height * .16);
  }

  void _paintLiveCarriage(Canvas canvas, Size size) {
    _lineBadge(canvas, size, 'ORANGE LINE');
    _label(canvas, '55 km/h', Offset(size.width * .57, size.height * .13),
        size.height * .08, _muted, FontWeight.w700);
    _pill(
        canvas,
        Rect.fromLTWH(size.width * .78, size.height * .08, size.width * .16,
            size.height * .22),
        '6 min');
    final railY = size.height * .73;
    canvas.drawLine(
      Offset.zero.translate(0, railY),
      Offset(size.width, railY),
      Paint()
        ..color = _accent
        ..strokeWidth = 4,
    );
    for (final x in [.13, .5, .87]) {
      _platform(canvas, Offset(size.width * x, railY), size);
    }
    _carriage(canvas, Offset(size.width * .27, size.height * .46),
        size.width * .46, size.height * .25);
    _label(
        canvas,
        'Exhibition Center',
        Offset(size.width * .04, size.height * .82),
        size.height * .068,
        _muted);
    _label(
        canvas,
        'Khalid Ibn Waleed',
        Offset(size.width * .38, size.height * .82),
        size.height * .068,
        _white,
        FontWeight.w700);
    _label(canvas, 'Hamra', Offset(size.width * .82, size.height * .82),
        size.height * .068, _muted);
  }

  void _lineBadge(Canvas canvas, Size size, String text) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .055, size.height * .07, size.width * .34,
            size.height * .23),
        const Radius.circular(8),
      ),
      Paint()..color = _accent.withValues(alpha: .20),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            size.width * .07, size.height * .11, 5, size.height * .15),
        const Radius.circular(4),
      ),
      Paint()..color = _accent,
    );
    _label(canvas, text, Offset(size.width * .11, size.height * .125),
        size.height * .09, _white, FontWeight.w800);
  }

  void _pill(Canvas canvas, Rect rect, String text) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(9)),
      Paint()..color = _panel,
    );
    _label(
        canvas,
        text,
        Offset(rect.left + rect.width * .2, rect.top + rect.height * .28),
        rect.height * .36,
        _white,
        FontWeight.w700);
  }

  void _node(
    Canvas canvas,
    Offset center, {
    bool active = false,
    bool completed = false,
  }) {
    if (active) {
      canvas.drawCircle(
        center,
        13,
        Paint()
          ..color = _accent.withValues(alpha: .28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawCircle(
      center,
      active ? 7 : 5,
      Paint()..color = active || completed ? _accent : _background,
    );
    canvas.drawCircle(
      center,
      active ? 7 : 5,
      Paint()
        ..color = active ? _white : (completed ? _accent : _muted)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _train(Canvas canvas, Offset center, double width, double height) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(height * .45),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFFE9EDF3));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(center.dx - width * .28, center.dy - height * .25,
            width * .38, height * .5),
        Radius.circular(height * .12),
      ),
      Paint()..color = const Color(0xFF263343),
    );
    canvas.drawCircle(
      Offset(center.dx + width * .29, center.dy),
      height * .22,
      Paint()..color = _accent,
    );
  }

  void _carriage(Canvas canvas, Offset origin, double width, double height) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.dx, origin.dy, width, height),
      Radius.circular(height * .28),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFFE4E8EE));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx + width * .68, origin.dy, width * .32, height),
        Radius.circular(height * .27),
      ),
      Paint()..color = _accent,
    );
    for (var index = 0; index < 4; index++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(origin.dx + width * (.08 + index * .15),
              origin.dy + height * .22, width * .11, height * .38),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFF202B38),
      );
    }
  }

  void _platform(Canvas canvas, Offset center, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            center.dx - 3, size.height * .42, 6, center.dy - size.height * .42),
        const Radius.circular(3),
      ),
      Paint()..color = _accent.withValues(alpha: .72),
    );
    _node(canvas, center);
  }

  void _label(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize,
    Color color, [
    FontWeight weight = FontWeight.w500,
  ]) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          height: 1,
        ),
      ),
      maxLines: 1,
      ellipsis: '\u2026',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 150);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _OnboardDesignPreviewPainter oldDelegate) =>
      oldDelegate.style != style;
}

class _MetroTrainMarkerPickerSheet extends StatefulWidget {
  const _MetroTrainMarkerPickerSheet();

  @override
  State<_MetroTrainMarkerPickerSheet> createState() =>
      _MetroTrainMarkerPickerSheetState();
}

class _MetroTrainMarkerPickerSheetState
    extends State<_MetroTrainMarkerPickerSheet> {
  MetroTrainMarkerStyle? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final style = await MetroTrainMarkerPreferences.load();
    if (mounted) setState(() => _selected = style);
  }

  Future<void> _apply(MetroTrainMarkerStyle style) async {
    await MetroTrainMarkerPreferences.save(style);
    if (!mounted) return;
    setState(() => _selected = style);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _selected ?? MetroTrainMarkerStyle.classic;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Metro train marker',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose how your position appears during a metro trip.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(.68),
              ),
            ),
            const SizedBox(height: 12),
            _option(
              context,
              value: MetroTrainMarkerStyle.classic,
              groupValue: selected,
              asset: 'assets/markers/metro_train_topdown.png',
              title: 'Classic train pin',
              subtitle: 'Use the original train marker for every line.',
            ),
            _option(
              context,
              value: MetroTrainMarkerStyle.lineSpecific,
              groupValue: selected,
              asset: 'assets/markers/metro_train_blue.png',
              title: 'Line-specific trains',
              subtitle: 'Use the Riyadh Metro vehicle for the active line.',
            ),
            _option(
              context,
              value: MetroTrainMarkerStyle.directional3d,
              groupValue: selected,
              asset: 'assets/markers/directional/metro_train_3d_blue_se.png',
              title: 'Directional 3D trains',
              subtitle:
                  'Match the active line and the train\'s direction of travel.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required MetroTrainMarkerStyle value,
    required MetroTrainMarkerStyle groupValue,
    required String asset,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _apply(value),
      leading: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Image.asset(asset, fit: BoxFit.contain),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: Radio<MetroTrainMarkerStyle>(
        value: value,
        groupValue: groupValue,
        onChanged: (_) => _apply(value),
      ),
    );
  }
}

// ————————————————— THEME PICKER SHEET (with SMART) —————————————————

class _ThemePickerSheet extends StatefulWidget {
  const _ThemePickerSheet();

  @override
  State<_ThemePickerSheet> createState() => _ThemePickerSheetState();
}

class _ThemePickerSheetState extends State<_ThemePickerSheet> {
  static const _kKey = 'theme_mode';
  AppThemeMode? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kKey) ?? 'system';
    setState(() => _selected = _decode(s));
  }

  AppThemeMode _decode(String s) {
    switch (s) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      case 'smart':
        return AppThemeMode.smart;
      default:
        return AppThemeMode.system;
    }
  }

  Future<void> _apply(BuildContext context, AppThemeMode mode) async {
    MyApp.setAppThemeMode(context, mode); // updates app immediately
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, _encode(mode));
    setState(() => _selected = mode);
  }

  String _encode(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.light:
        return 'light';
      case AppThemeMode.dark:
        return 'dark';
      case AppThemeMode.system:
        return 'system';
      case AppThemeMode.smart:
        return 'smart';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.color_lens_rounded),
            title: Text(
              getTranslated(context, 'drawer.themeSettings') ==
                      'drawer.themeSettings'
                  ? 'Theme Settings'
                  : getTranslated(context, 'drawer.themeSettings'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            subtitle: Text(
              // keep the same subtitle; SMART is self-explanatory below
              getTranslated(context, 'drawer.themeSubtitle') ==
                      'drawer.themeSubtitle'
                  ? 'Choose Light, Dark, or System default'
                  : getTranslated(context, 'drawer.themeSubtitle'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.65),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _optionTile(
            context,
            label: getTranslated(context, 'theme.light') == 'theme.light'
                ? 'Light'
                : getTranslated(context, 'theme.light'),
            value: AppThemeMode.light,
            icon: Icons.wb_sunny_rounded,
          ),
          _optionTile(
            context,
            label: getTranslated(context, 'theme.dark') == 'theme.dark'
                ? 'Dark'
                : getTranslated(context, 'theme.dark'),
            value: AppThemeMode.dark,
            icon: Icons.nightlight_round_rounded,
          ),
          _optionTile(
            context,
            label: getTranslated(context, 'theme.system') == 'theme.system'
                ? 'System'
                : getTranslated(context, 'theme.system'),
            value: AppThemeMode.system,
            icon: Icons.auto_mode_rounded,
          ),
          _optionTile(
            context,
            label: getTranslated(context, 'theme.smart') == 'theme.smart'
                ? 'Auto (Environment)'
                : getTranslated(context, 'theme.smart'),
            value: AppThemeMode.smart,
            icon: Icons.auto_awesome_rounded,
            subtitle: getTranslated(context, 'theme.smart.subtitle') ==
                    'theme.smart.subtitle'
                ? 'Daylight = Light, Night/Tunnel = Dark'
                : getTranslated(context, 'theme.smart.subtitle'),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _optionTile(
    BuildContext context, {
    required String label,
    required AppThemeMode value,
    required IconData icon,
    String? subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selected ?? AppThemeMode.system;

    return ListTile(
      onTap: () => _apply(context, value),
      leading: Icon(icon, color: cs.onSurface),
      title: Text(label, style: TextStyle(color: cs.onSurface)),
      subtitle: (subtitle == null || subtitle.isEmpty)
          ? null
          : Text(subtitle,
              style: TextStyle(color: cs.onSurface.withOpacity(.65))),
      trailing: Radio<AppThemeMode>(
        value: value,
        groupValue: selected,
        onChanged: (m) {
          if (m != null) _apply(context, m);
        },
      ),
    );
  }
}
