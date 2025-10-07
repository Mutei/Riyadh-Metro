import 'package:darb/screens/purchase_history_screen.dart';
import 'package:flutter/material.dart';

import 'package:darb/constants/colors.dart';
import 'package:darb/widgets/drawer_tile.dart';
import 'package:darb/utils/logout_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/language_constants.dart';

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
    this.appVersion = "1.2.0",
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
