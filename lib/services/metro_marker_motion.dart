import 'package:google_maps_flutter/google_maps_flutter.dart';

class MetroMarkerMotionFrame {
  final LatLng position;
  final double heading;
  final bool complete;

  const MetroMarkerMotionFrame({
    required this.position,
    required this.heading,
    required this.complete,
  });
}

/// Interpolates only the visual state of a metro marker.
///
/// Navigation, route matching, trip timing, and distance calculations should
/// continue using their original location updates rather than these frames.
class MetroMarkerMotion {
  LatLng? _fromPosition;
  LatLng? _targetPosition;
  double _fromHeading = 0;
  double _targetHeading = 0;
  DateTime? _startedAt;
  Duration _duration = Duration.zero;

  bool get hasFrame => _targetPosition != null;

  void retarget({
    required LatLng position,
    required double heading,
    required DateTime at,
    required Duration duration,
  }) {
    final current = frameAt(at);
    final normalizedHeading = _normalizeHeading(heading);
    if (current == null) {
      _fromPosition = position;
      _targetPosition = position;
      _fromHeading = normalizedHeading;
      _targetHeading = normalizedHeading;
      _startedAt = at;
      _duration = Duration.zero;
      return;
    }

    _fromPosition = current.position;
    _targetPosition = position;
    _fromHeading = current.heading;
    _targetHeading = normalizedHeading;
    _startedAt = at;
    _duration = duration;
  }

  MetroMarkerMotionFrame? frameAt(DateTime at) {
    final from = _fromPosition;
    final target = _targetPosition;
    final startedAt = _startedAt;
    if (from == null || target == null || startedAt == null) return null;

    final durationMicros = _duration.inMicroseconds;
    final rawProgress = durationMicros <= 0
        ? 1.0
        : at.difference(startedAt).inMicroseconds / durationMicros;
    final progress = rawProgress.clamp(0.0, 1.0).toDouble();
    final eased = 1 - _cube(1 - progress);
    final headingDelta = ((_targetHeading - _fromHeading + 540) % 360) - 180;

    return MetroMarkerMotionFrame(
      position: LatLng(
        _lerp(from.latitude, target.latitude, eased),
        _lerp(from.longitude, target.longitude, eased),
      ),
      heading: _normalizeHeading(_fromHeading + headingDelta * eased),
      complete: progress >= 1,
    );
  }

  void reset() {
    _fromPosition = null;
    _targetPosition = null;
    _fromHeading = 0;
    _targetHeading = 0;
    _startedAt = null;
    _duration = Duration.zero;
  }

  static double _lerp(double start, double end, double progress) =>
      start + (end - start) * progress;

  static double _cube(double value) => value * value * value;

  static double _normalizeHeading(double value) => ((value % 360) + 360) % 360;
}
