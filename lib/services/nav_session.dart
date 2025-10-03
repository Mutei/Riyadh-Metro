import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart'; // PlatformException
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class NavUpdate {
  final LatLng here;
  final double speedMps;
  final double headingDeg;
  final bool predicted;
  final DateTime at;
  NavUpdate({
    required this.here,
    required this.speedMps,
    required this.headingDeg,
    required this.predicted,
    required this.at,
  });
}

class NavSession {
  NavSession._();
  static final NavSession instance = NavSession._();

  // ---- Public stream for UI ----
  final StreamController<NavUpdate> _ctrl = StreamController.broadcast();
  Stream<NavUpdate> get updates => _ctrl.stream;

  // ---- Durable state ----
  LatLng? _dest;
  StreamSubscription<Position>? _sub;
  Timer? _pred;

  // last true fix (GPS)
  LatLng? _lastFixLL;
  double _lastFixSpeed = 0; // m/s
  double _lastFixHeading = 0; // deg (0..360)
  DateTime _lastFixAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRealFixAt =
      DateTime.fromMillisecondsSinceEpoch(0); // <- when we last got REAL GPS

  bool get isActive => _dest != null;
  LatLng? get currentDestination => _dest; // used by MainScreen

  // Some Android devices throw when cancelling a non-existent platform stream.
  Future<void> _safeCancelSubscription() async {
    if (_sub == null) return;
    try {
      await _sub!.cancel();
    } on PlatformException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      if (!msg.contains('no active stream to cancel')) rethrow;
    } catch (_) {
      // ignore
    } finally {
      _sub = null;
    }
  }

  // Foreground, high-frequency settings
  LocationSettings _hiFreq() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: Duration(seconds: 1),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Darb is navigating',
          notificationText: 'Turn-by-turn is active',
          enableWakeLock: true, // requires android.permission.WAKE_LOCK
          setOngoing: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: false,
      );
    } else {
      return const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      );
    }
  }

  double _bearing(LatLng a, LatLng b) {
    final dLon = (b.longitude - a.longitude) * (math.pi / 180);
    final lat1 = a.latitude * (math.pi / 180);
    final lat2 = b.latitude * (math.pi / 180);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Future<void> start({required LatLng dest}) async {
    // If already navigating to the same place, just keep going.
    if (_dest != null && _dest == dest && _sub != null) return;
    _dest = dest;

    // Seed last fix (ignore failures silently; stream will provide updates)
    try {
      final p0 = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best);
      _lastFixLL = LatLng(p0.latitude, p0.longitude);
      _lastFixSpeed = p0.speed.isFinite ? p0.speed : 0;
      _lastFixHeading = p0.heading.isFinite ? p0.heading : 0;
      _lastFixAt = DateTime.now();
      _lastRealFixAt = _lastFixAt;

      _ctrl.add(NavUpdate(
        here: _lastFixLL!,
        speedMps: _lastFixSpeed,
        headingDeg: _lastFixHeading,
        predicted: false,
        at: _lastFixAt,
      ));
    } catch (_) {}

    // Ensure any previous subscription is cleanly stopped.
    await _safeCancelSubscription();

    // Live GPS stream (keeps running in BG due to _hiFreq settings)
    _sub = Geolocator.getPositionStream(locationSettings: _hiFreq()).listen(
      (p) {
        final here = LatLng(p.latitude, p.longitude);

        bool outlier() {
          if ((p.latitude.abs() < 0.0001 && p.longitude.abs() < 0.0001))
            return true;
          if (p.accuracy.isFinite && p.accuracy > 80) return true;
          if (_lastFixLL != null) {
            final dt =
                DateTime.now().difference(_lastFixAt).inMilliseconds / 1000.0;
            if (dt > 0) {
              final d = Geolocator.distanceBetween(
                _lastFixLL!.latitude,
                _lastFixLL!.longitude,
                here.latitude,
                here.longitude,
              );
              if (d / dt > 70) return true; // >252 km/h
            }
          }
          return false;
        }

        if (outlier()) return;

        _lastFixLL = here;
        _lastFixSpeed =
            (p.speed.isFinite && p.speed >= 0) ? p.speed : _lastFixSpeed;
        _lastFixHeading = (p.heading.isFinite && p.heading >= 0)
            ? p.heading
            : _lastFixHeading;
        _lastFixAt = DateTime.now();
        _lastRealFixAt = _lastFixAt; // mark that we have a fresh REAL fix

        _ctrl.add(NavUpdate(
          here: here,
          speedMps: _lastFixSpeed,
          headingDeg: _lastFixHeading,
          predicted: false,
          at: _lastFixAt,
        ));
      },
      onError: (e, _) {
        if (e is PlatformException) {
          final msg = (e.message ?? '').toLowerCase();
          if (msg.contains('no active stream to cancel')) return;
        }
      },
      cancelOnError: false,
    );

    // Dead-reckoner (ONLY when recently moving, for a short window)
    _pred?.cancel();
    _pred = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_dest == null || _lastFixLL == null) return;

      final now = DateTime.now();
      final sinceReal = now.difference(_lastRealFixAt);

      // Only predict if: no fresh GPS for >2s, but <12s (short tunnel), AND we were moving.
      const minGap = Duration(seconds: 2);
      const maxGap = Duration(seconds: 12);
      const minMovingSpeed =
          2.2; // m/s ~ 8 km/h: below this we treat as stationary

      if (sinceReal <= minGap || sinceReal > maxGap) return;
      if (!_lastFixSpeed.isFinite || _lastFixSpeed < minMovingSpeed) return;

      // Advance along last heading at last known speed
      const dt = 0.2;
      final v =
          _lastFixSpeed; // <- NO fallback speed; if slow, we already returned
      final d = v * dt;

      final rad = _lastFixHeading * math.pi / 180.0;
      final dy = d * math.cos(rad);
      final dx = d * math.sin(rad);

      const mPerDegLat = 111320.0;
      final mPerDegLon =
          111320.0 * math.cos((_lastFixLL!.latitude * math.pi) / 180.0);

      final next = LatLng(
        _lastFixLL!.latitude + (dy / mPerDegLat),
        _lastFixLL!.longitude + (dx / mPerDegLon),
      );

      _lastFixLL = next; // keep internal state moving smoothly
      _lastFixAt = now; // for continuity in distance calc

      _ctrl.add(NavUpdate(
        here: next,
        speedMps: v,
        headingDeg: _lastFixHeading,
        predicted: true,
        at: now,
      ));
    });
  }

  Future<void> stop() async {
    _pred?.cancel();
    _pred = null;
    await _safeCancelSubscription();
    _dest = null;
  }
}
