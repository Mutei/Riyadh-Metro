// lib/screens/language_screen.dart
import 'package:flutter/material.dart';
import 'package:darb/constants/colors.dart';
import 'package:darb/localization/language_constants.dart'; // getTranslated / getLocale / setLocale
import 'package:darb/main.dart' show MyApp; // 👈 import MyApp to call setLocale

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  Locale? _current; // loaded from prefs
  late Locale _selected;

  @override
  void initState() {
    super.initState();
    // load current locale from SharedPreferences
    getLocale().then((loc) {
      _current = loc;
      _selected = loc;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    // while loading current locale
    if (_current == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final options = <_LangOption>[
      const _LangOption(
        title: 'English',
        subtitle: 'English (United States)',
        locale: Locale('en', 'US'),
      ),
      const _LangOption(
        title: 'عربي',
        subtitle: 'Saudi Arabia',
        locale: Locale('ar', 'SA'),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.kBackGroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.kBackGroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          getTranslated(context, 'Language'),
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final horizontalPad = c.maxWidth >= 600 ? 32.0 : 16.0;
          final bottomPad = c.maxHeight >= 800 ? 16.0 : 8.0;

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontalPad, 8, horizontalPad, 0),
              child: Column(
                children: [
                  _Card(
                    child: Column(
                      children: [
                        for (int i = 0; i < options.length; i++) ...[
                          _LanguageTile(
                            option: options[i],
                            selected: _selected,
                            onTap: () =>
                                setState(() => _selected = options[i].locale),
                          ),
                          if (i != options.length - 1)
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Colors.black12.withOpacity(.06),
                              indent: 16,
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 20, color: Colors.black54),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              getTranslated(context,
                                  'Change app language. Some pages may still appear in their original language.'),
                              style: text.bodyMedium?.copyWith(
                                color: Colors.black54,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  SafeArea(
                    top: false,
                    minimum: EdgeInsets.only(
                        left: horizontalPad,
                        right: horizontalPad,
                        bottom: bottomPad),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.kPrimaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          // 1) Persist selection
                          await setLocale(_selected.languageCode);

                          if (!mounted) return;

                          // 2) Rebuild app NOW with the new locale (no restart)
                          MyApp.setLocale(context, _selected);

                          // 3) Close this screen
                          Navigator.of(context).pop<Locale>(_selected);
                        },
                        child: Text(
                          getTranslated(context, 'Apply'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LangOption {
  final String title;
  final String subtitle;
  final Locale locale;
  const _LangOption({
    required this.title,
    required this.subtitle,
    required this.locale,
  });
}

class _LanguageTile extends StatelessWidget {
  final _LangOption option;
  final Locale selected;
  final VoidCallback onTap;
  const _LanguageTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  bool _equals(Locale a, Locale b) =>
      a.languageCode == b.languageCode &&
      (a.countryCode ?? '') == (b.countryCode ?? '');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final bool isSelected = _equals(option.locale, selected);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: .1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
            _RadioBadge(selected: isSelected),
          ],
        ),
      ),
    );
  }
}

class _RadioBadge extends StatelessWidget {
  final bool selected;
  const _RadioBadge({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.kPrimaryColor : Colors.black26,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: selected ? 12 : 0,
        height: selected ? 12 : 0,
        decoration: BoxDecoration(
          color: AppColors.kPrimaryColor,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
