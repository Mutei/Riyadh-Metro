import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

String fmtMeters(double m) => m < 1000
    ? '${m.toStringAsFixed(0)} m'
    : '${(m / 1000).toStringAsFixed(1)} km';

double dist2(LatLng a, LatLng b) {
  final dx = a.latitude - b.latitude;
  final dy = a.longitude - b.longitude;
  return dx * dx + dy * dy;
}
