import 'package:darb/screens/purchase_history_screen.dart';
import 'package:flutter/material.dart';

import 'package:darb/constants/colors.dart';
import 'package:darb/widgets/drawer_tile.dart';
import 'package:darb/utils/logout_dialog.dart';
import '../localization/language_constants.dart';

import 'language_screen.dart';
import 'personal_info_screen.dart';
import 'travel_history_screen.dart'; // ⬅️ NEW

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

    return Scaffold(
      backgroundColor: AppColors.kBackGroundColor,
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
                    side: BorderSide(color: Colors.black.withOpacity(.12)),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
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
                trailing: const Icon(Icons.open_in_new_rounded,
                    color: Colors.black45),
                onTap: () {}, // open external page
              ),
              DrawerTile(
                icon: Icons.info_outline_rounded,
                title: getTranslated(context, 'drawer.about'),
                trailing: const Icon(Icons.open_in_new_rounded,
                    color: Colors.black45),
                onTap: () {}, // open external page
              ),
              DrawerTile(
                icon: Icons.description_outlined,
                title: getTranslated(context, 'drawer.terms'),
                trailing: const Icon(Icons.open_in_new_rounded,
                    color: Colors.black45),
                onTap: () {}, // open external page
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
                  if (picked != null) {
                    // handled by app-level locale logic
                  }
                },
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  children: [
                    Text(
                      getTranslated(context, 'drawer.registeredDGA'),
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '20241208431',
                        style: text.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Center(
                child: Text(
                  '${getTranslated(context, 'drawer.version')} $appVersion',
                  style: text.bodySmall?.copyWith(color: Colors.black45),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text(
          getTranslated(context, key),
          style: const TextStyle(
            color: Colors.black54,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
