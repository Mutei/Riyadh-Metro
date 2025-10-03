import 'package:flutter/material.dart';

class LeadingCircleIcon extends StatelessWidget {
  final IconData icon;
  final Color? foreground;

  const LeadingCircleIcon({
    super.key,
    required this.icon,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: (foreground ?? Colors.black).withOpacity(.06),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: foreground ?? Colors.black87),
    );
  }
}
