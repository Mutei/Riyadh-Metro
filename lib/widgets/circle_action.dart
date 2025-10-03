import 'package:flutter/material.dart';

class CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const CircleAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Icon(icon, size: 24, color: Colors.black87),
        ),
      ),
    );
  }
}
