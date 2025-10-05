// lib/widgets/nav_hint.dart
import 'package:flutter/material.dart';

enum NavHintType { walk, board, transfer, alight }

class NavHint {
  final NavHintType type;
  final String text;
  final Duration duration;
  NavHint({
    required this.type,
    required this.text,
    this.duration = const Duration(seconds: 4),
  });
}

class NavHints extends StatefulWidget {
  final Widget child;
  const NavHints({super.key, required this.child});

  static _NavHintsState of(BuildContext context) =>
      context.findAncestorStateOfType<_NavHintsState>()!;

  @override
  State<NavHints> createState() => _NavHintsState();
}

class _NavHintsState extends State<NavHints> with TickerProviderStateMixin {
  final _queue = <NavHint>[];
  OverlayEntry? _entry;
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, 0.15), end: Offset.zero)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  void show(NavHint hint) {
    _queue
      ..clear()
      ..add(hint); // keep the latest only
    _present();
  }

  Color _bg(NavHintType t) {
    switch (t) {
      case NavHintType.walk:
        return const Color(0xFF263238);
      case NavHintType.board:
        return const Color(0xFF1B5E20);
      case NavHintType.transfer:
        return const Color(0xFFFB8C00);
      case NavHintType.alight:
        return const Color(0xFFE53935);
    }
  }

  IconData _icon(NavHintType t) {
    switch (t) {
      case NavHintType.walk:
        return Icons.directions_walk_rounded;
      case NavHintType.board:
        return Icons.directions_subway_filled;
      case NavHintType.transfer:
        return Icons.swap_horiz_rounded;
      case NavHintType.alight:
        return Icons.flag_rounded;
    }
  }

  Future<void> _present() async {
    if (_queue.isEmpty) return;

    // Create overlay once
    _entry ??= OverlayEntry(builder: (ctx) {
      final hint = _queue.last;
      return Positioned(
        left: 12,
        right: 12,
        bottom: 96, // sits above FABs / bottom nav
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: SafeArea(
              top: false,
              child: _HintCard(
                color: _bg(hint.type),
                icon: _icon(hint.type),
                text: hint.text,
                onClose: _hide,
              ),
            ),
          ),
        ),
      );
    });

    Overlay.of(context, rootOverlay: true).insert(_entry!);
    await _ctrl.forward();
    await Future.delayed(_queue.last.duration);
    _hide();
  }

  Future<void> _hide() async {
    if (_entry == null) return;
    await _ctrl.reverse();
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _HintCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final VoidCallback onClose;
  const _HintCard(
      {required this.color,
      required this.icon,
      required this.text,
      required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                blurRadius: 12, color: Colors.black26, offset: Offset(0, 6))
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white70, size: 20),
              splashRadius: 18,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}
