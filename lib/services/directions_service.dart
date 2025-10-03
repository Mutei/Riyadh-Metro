import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../private.dart';

/// Keep your original enum
enum TravelMode { walk, drive }

/// ===== Existing model you already had =====
class LegPath {
  final List<LatLng> points;
  final int durationSec;
  final int distanceMeters;
  final TravelMode mode;
  LegPath(this.points, this.durationSec, this.distanceMeters, this.mode);
}

/// ===== Traffic-aware driving (Routes API v2) =====
class DriveRoute {
  final List<LatLng> points;
  final int distanceMeters;
  final int durationSeconds; // live, traffic-aware ETA
  final int staticDurationSeconds; // no-traffic baseline (NEW)
  final bool fuelEfficient; // route label from API
  final List<_SpeedSegment> traffic; // congestion segments (may be empty)
  final List<_StepInfo> steps; // maneuvers for banner

  DriveRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.staticDurationSeconds,
    required this.fuelEfficient,
    required this.traffic,
    required this.steps,
  });
}

class _SpeedSegment {
  final int startIndex;
  final int endIndex; // exclusive
  final String speed; // NORMAL | SLOW | TRAFFIC_JAM | FREE_FLOW
  _SpeedSegment(this.startIndex, this.endIndex, this.speed);
}

class _StepInfo {
  final String? maneuver; // e.g. TURN_RIGHT
  final String? instruction; // localized like "toward Arafat Branch Rd"
  final List<LatLng> poly;
  _StepInfo(this.maneuver, this.instruction, this.poly);
}

class DirectionsService {
  static const double walkDriveSwitchMeters = 1000;

  // ---------- First/last mile helpers ----------

  Future<LegPath?> bestFirstLastMile(LatLng from, LatLng to) async {
    final meters = _metersBetween(from, to);
    final mode =
        meters >= walkDriveSwitchMeters ? TravelMode.drive : TravelMode.walk;
    return routeViaRoads(from, to, mode: mode);
  }

  /// Legacy Directions API v3 (kept for walking and simple fallback)
  Future<LegPath?> routeViaRoads(
    LatLng a,
    LatLng b, {
    required TravelMode mode,
  }) async {
    final m = mode == TravelMode.walk ? 'walking' : 'driving';
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${a.latitude},${a.longitude}'
      '&destination=${b.latitude},${b.longitude}'
      '&mode=$m'
      '&alternatives=false'
      '&units=metric'
      '&key=$kDirectionsApiKey',
    );

    try {
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data['status'] != 'OK') return null;

      final route = (data['routes'] as List).first;
      final leg = route['legs'][0];
      final dist = (leg['distance']['value'] as num).toInt();
      final dur = (leg['duration']['value'] as num).toInt();
      final encoded = route['overview_polyline']['points'] as String;
      final pts = _decodePolyline(encoded);
      if (pts.length < 2) return null;
      return LegPath(pts, dur, dist, mode);
    } catch (_) {
      return null;
    }
  }

  /// ===== Google Routes API v2 (traffic-aware + alternatives) =====
  ///
  /// Call this ONLY for car mode to get:
  /// - multiple routes (sorted fastest first)
  /// - live-traffic ETA (duration)
  /// - no-traffic ETA (staticDuration)  ⟵ NEW parsed
  /// - congestion segments (speedReadingIntervals)
  /// - step maneuvers/instructions (for the banner)
  Future<List<DriveRoute>> computeDriveAlternatives(
    LatLng origin,
    LatLng dest, {
    String languageCode = 'en',
  }) async {
    final url = Uri.parse(
      'https://routes.googleapis.com/directions/v2:computeRoutes',
    );

    // Make the departure time slightly in the future to avoid clock skew issues
    final depIso = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 2))
        .toIso8601String();

    final body = {
      "origin": {
        "location": {
          "latLng": {"latitude": origin.latitude, "longitude": origin.longitude}
        }
      },
      "destination": {
        "location": {
          "latLng": {"latitude": dest.latitude, "longitude": dest.longitude}
        }
      },
      "travelMode": "DRIVE",
      "routingPreference": "TRAFFIC_AWARE_OPTIMAL",
      "computeAlternativeRoutes": true,
      "polylineQuality": "HIGH_QUALITY",
      "polylineEncoding": "ENCODED_POLYLINE",
      "languageCode": languageCode,

      // >>> THIS is the missing piece <<<
      "extraComputations": ["TRAFFIC_ON_POLYLINE"],

      // Traffic ETA settings
      "departureTime": depIso,
      "trafficModel": "BEST_GUESS",
    };

    // Keep speedReadingIntervals in the field mask
    final fieldMask = "routes.distanceMeters,"
        "routes.duration,"
        "routes.staticDuration,"
        "routes.polyline.encodedPolyline,"
        "routes.travelAdvisory.speedReadingIntervals,"
        "routes.legs.steps.navigationInstruction.maneuver,"
        "routes.legs.steps.navigationInstruction.instructions,"
        "routes.legs.steps.polyline.encodedPolyline,"
        "routes.routeLabels";

    final res = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": kDirectionsApiKey,
        "X-Goog-FieldMask": fieldMask,
      },
      body: jsonEncode(body),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('Routes API HTTP ${res.statusCode}\n${res.body}');
      return [];
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final List routes = (data["routes"] as List?) ?? const [];

    int _secs(dynamic iso) {
      if (iso is String && iso.endsWith('s')) {
        final n = int.tryParse(iso.substring(0, iso.length - 1));
        return n ?? 0;
      }
      return 0;
    }

    final out = <DriveRoute>[];
    for (final r in routes) {
      final enc = r["polyline"]?["encodedPolyline"] as String?;
      if (enc == null) continue;

      final pts = _decodePolyline(enc);
      if (pts.length < 2) continue;

      final labels = (r["routeLabels"] as List?)?.cast<String>() ?? const [];
      final sri =
          (r["travelAdvisory"]?["speedReadingIntervals"] as List?) ?? const [];

      final traffic = <_SpeedSegment>[
        for (final s in sri)
          _SpeedSegment(
            (s["startPolylinePointIndex"] as num?)?.toInt() ?? 0,
            (s["endPolylinePointIndex"] as num?)?.toInt() ?? 0,
            (s["speed"] as String?) ?? "SPEED_NORMAL",
          )
      ];

      final steps = <_StepInfo>[];
      final legs = (r["legs"] as List?) ?? const [];
      if (legs.isNotEmpty) {
        final ls = (legs.first["steps"] as List?) ?? const [];
        for (final s in ls) {
          steps.add(_StepInfo(
            s["navigationInstruction"]?["maneuver"] as String?,
            s["navigationInstruction"]?["instructions"] as String?,
            _decodePolyline(
              (s["polyline"]?["encodedPolyline"] as String?) ?? "",
            ),
          ));
        }
      }

      out.add(DriveRoute(
        points: pts,
        distanceMeters: (r["distanceMeters"] as num?)?.toInt() ?? 0,
        durationSeconds: _secs(r["duration"]),
        staticDurationSeconds: _secs(r["staticDuration"]),
        fuelEfficient: labels.contains("FUEL_EFFICIENT"),
        traffic: traffic,
        steps: steps,
      ));
    }

    out.sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));

    debugPrint('alts=${out.length} '
        'trafficCounts=${out.map((r) => r.traffic.length).toList()} '
        'speeds=${out.expand((r) => r.traffic.map((s) => s.speed)).take(10).toList()}');

    return out;
  }

  // ---------- helpers ----------
  List<LatLng> _decodePolyline(String poly) {
    if (poly.isEmpty) return const [];
    final pts = <LatLng>[];
    int index = 0, lat = 0, lng = 0;

    while (index < poly.length) {
      int b, shift = 0, result = 0;
      do {
        b = poly.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = poly.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      pts.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return pts;
  }

  double _metersBetween(LatLng a, LatLng b) {
    const R = 6371000.0;
    double deg2rad(double d) => d * pi / 180.0;
    final dLat = deg2rad(b.latitude - a.latitude);
    final dLon = deg2rad(b.longitude - a.longitude);
    final la1 = deg2rad(a.latitude);
    final la2 = deg2rad(b.latitude);
    final h = (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2));
    return R * 2 * atan2(sqrt(h), sqrt(1 - h));
  }
}
