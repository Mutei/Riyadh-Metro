import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../localization/language_constants.dart'; // Add this line

class BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const BottomNav({
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: index,
      onTap: onChanged,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.kPrimaryColor,
      unselectedItemColor: Colors.black54,
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
