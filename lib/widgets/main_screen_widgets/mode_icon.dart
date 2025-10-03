import 'dart:ui';

import 'package:flutter/cupertino.dart';

class ModeIcon {
  final IconData icon;
  final String label;
  final Color? chipColor;
  const ModeIcon({
    required this.icon,
    required this.label,
    this.chipColor,
  });
}
