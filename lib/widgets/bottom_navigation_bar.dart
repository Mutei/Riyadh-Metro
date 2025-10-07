import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../localization/language_constants.dart';

class BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const BottomNav({
    super.key,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return BottomNavigationBar(
      currentIndex: index,
      onTap: onChanged,
      type: BottomNavigationBarType.fixed,

      selectedItemColor: AppColors.kPrimaryColor,
      unselectedItemColor: cs.onSurface.withOpacity(0.65), // ← Fix here

      selectedLabelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: AppColors.kPrimaryColor,
      ),
      unselectedLabelStyle: TextStyle(
        fontWeight: FontWeight.w500,
        color: cs.onSurface.withOpacity(0.65), // ← Fix here
      ),

      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.home_rounded),
          label: getTranslated(context, 'Home'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.tune_rounded),
          label: getTranslated(context, 'Lines'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.confirmation_number_outlined),
          label: getTranslated(context, 'Tickets'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.star_border_rounded),
          label: getTranslated(context, 'Favorites'),
        ),
      ],
    );
  }
}
