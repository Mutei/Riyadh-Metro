import 'package:flutter/material.dart';
import 'leading_circle_icon.dart';

class DrawerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? foreground;
  final Widget? trailing;

  const DrawerTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.foreground,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      leading: LeadingCircleIcon(icon: icon, foreground: foreground),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: foreground ?? Colors.black,
        ),
      ),
      subtitle: (subtitle == null)
          ? null
          : Text(subtitle!, style: const TextStyle(color: Colors.black54)),
      trailing: trailing ??
          const Icon(Icons.chevron_right_rounded, color: Colors.black38),
    );
  }
}
