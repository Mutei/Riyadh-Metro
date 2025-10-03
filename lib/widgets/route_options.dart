import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../classes/route_option.dart';
import '../localization/language_constants.dart';
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

  // -------- helpers --------
  String _fmtDur(double s) {
    final d = Duration(seconds: s.round());
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  // Haversine great-circle distance (meters)
  double _distMeters(LatLng a, LatLng b) {
    const R = 6371000.0; // meters
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
    // Tune thresholds as you like
    if (meters < 4000) return 3; // < 4 km → 3 routes
    if (meters < 9000) return 4; // 4–9 km → 4 routes
    return 5; // >= 9 km → 5 routes
  }

  Widget _lineChip(BuildContext context, String key) {
    final c = metroLineColors[key] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(.35)),
      ),
      child: Row(children: [
        const Icon(Icons.directions_subway_filled, size: 16),
        const SizedBox(width: 4),
        // Text('${cap(key)} ${getTranslated(context, 'line')}',
        //     style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(
          '${getTranslated(context, key)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Guard: no options
    if (options.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(getTranslated(context, 'No routes found'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
    }

    // Use the origin/dest common to all options to decide how many to show
    final origin = options.first.originLL;
    final dest = options.first.destLL;
    final meters = _distMeters(origin, dest);
    final desired = _desiredCountByDistanceMeters(meters);
    final visible = options.take(desired).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: visible.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = visible[i];
                  final eta = DateTime.now()
                      .add(Duration(seconds: r.totalSeconds.round()));
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(_fmtDur(r.totalSeconds),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• ${getTranslated(context, 'ETA')} ${TimeOfDay.fromDateTime(eta).format(context)}',
                          style: const TextStyle(color: Colors.black54),
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
                              color: Colors.black.withOpacity(.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(children: [
                              const Icon(Icons.directions_walk, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${r.walkMeters.toStringAsFixed(0)} ${getTranslated(context, 'm')} ${getTranslated(context, 'walk')}',
                              ),
                            ]),
                          ),
                          ...r.lineSequence.map((k) => _lineChip(context, k)),
                          if (r.transfers > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(children: [
                                const Icon(Icons.swap_horiz_rounded, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  r.transfers == 1
                                      ? '1 ${getTranslated(context, 'transfer')}'
                                      : '${r.transfers} ${getTranslated(context, 'transfers')}',
                                ),
                              ]),
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
