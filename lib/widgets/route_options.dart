// lib/widgets/route_options_sheet.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../classes/route_option.dart';
import '../localization/language_constants.dart';
import '../constants/colors.dart'; // <-- NEW: for AppColors.kDarkBackgroundColor
import 'all_metro_lines.dart';

class RouteOptionsSheet extends StatelessWidget {
  final List<RouteOption> options;
  final String destLabel;
  final String Function(String key) cap;
  final void Function(RouteOption r) onPick;

  const RouteOptionsSheet({
    super.key,
    required this.options,
    required this.destLabel,
    required this.cap,
    required this.onPick,
  });

  String _fmtDur(double s) {
    final d = Duration(seconds: s.round());
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  double _distMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLng = _deg2rad(b.longitude - a.longitude);
    final la1 = _deg2rad(a.latitude);
    final la2 = _deg2rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  int _desiredCountByDistanceMeters(double meters) {
    if (meters < 4000) return 3;
    if (meters < 9000) return 4;
    return 5;
  }

  Widget _lineChip(BuildContext context, String key) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = metroLineColors[key] ?? cs.secondary;
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(isDark ? .22 : .15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_subway_filled, size: 16, color: c),
          const SizedBox(width: 4),
          Text(
            getTranslated(context, key),
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    final onSurface = cs.onSurface;
    final onSurfaceSubtle = onSurface.withOpacity(0.65);
    final outline = cs.outline;
    final outlineVariant = cs.outlineVariant;

    // ✅ Use your custom dark background; keep Material surface in light mode
    final bgColor = isDark ? AppColors.kDarkBackgroundColor : cs.surface;

    if (options.isEmpty) {
      return SafeArea(
        child: Container(
          color: bgColor,
          padding: const EdgeInsets.all(16),
          child: Text(
            getTranslated(context, 'No routes found'),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    final origin = options.first.originLL;
    final dest = options.first.destLL;
    final meters = _distMeters(origin, dest);
    final desired = _desiredCountByDistanceMeters(meters);
    final visible = options.take(desired).toList();

    return SafeArea(
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: onSurface.withOpacity(0.24),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${getTranslated(context, 'Routes to')} $destLabel',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: visible.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: outlineVariant),
                itemBuilder: (_, i) {
                  final r = visible[i];
                  final eta = DateTime.now().add(
                    Duration(seconds: r.totalSeconds.round()),
                  );

                  return ListTile(
                    tileColor: Colors.transparent, // keep sheet bg visible
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(isDark ? .22 : .12),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: cs.primary.withOpacity(.35)),
                          ),
                          child: Text(
                            _fmtDur(r.totalSeconds),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• ${getTranslated(context, 'ETA')} '
                          '${TimeOfDay.fromDateTime(eta).format(context)}',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: onSurfaceSubtle),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  isDark ? Colors.white10 : cs.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: outline),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.directions_walk,
                                    size: 16, color: onSurface),
                                const SizedBox(width: 4),
                                Text(
                                  '${r.walkMeters.toStringAsFixed(0)} '
                                  '${getTranslated(context, 'm')} '
                                  '${getTranslated(context, 'walk')}',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: onSurface),
                                ),
                              ],
                            ),
                          ),
                          ...r.lineSequence.map((k) => _lineChip(context, k)),
                          if (r.transfers > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    isDark ? Colors.white10 : cs.surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: outline),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.swap_horiz_rounded,
                                      size: 16, color: onSurface),
                                  const SizedBox(width: 4),
                                  Text(
                                    r.transfers == 1
                                        ? '1 ${getTranslated(context, 'transfer')}'
                                        : '${r.transfers} ${getTranslated(context, 'transfers')}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: onSurface),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    onTap: () => onPick(r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
