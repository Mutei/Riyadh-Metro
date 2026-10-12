import 'dart:math' as math;

import '../latlon/latlong_stations.dart' as metro;

class MetroRouteDistance {
  const MetroRouteDistance._();

  static const double _earthRadiusMeters = 6371000;

  static int? betweenStations({
    required String lineKey,
    required String fromStation,
    required String toStation,
  }) {
    final stations = _stationsForLine(lineKey);
    if (stations == null) return null;

    final fromIndex = _stationIndex(stations, fromStation);
    final toIndex = _stationIndex(stations, toStation);
    if (fromIndex < 0 || toIndex < 0) return null;
    if (fromIndex == toIndex) return 0;

    final first = math.min(fromIndex, toIndex);
    final last = math.max(fromIndex, toIndex);
    var distance = 0.0;
    for (var index = first; index < last; index++) {
      final current = stations[index];
      final next = stations[index + 1];
      distance += _distanceBetween(
        (current['lat'] as num).toDouble(),
        (current['lng'] as num).toDouble(),
        (next['lat'] as num).toDouble(),
        (next['lng'] as num).toDouble(),
      );
    }
    return distance.round();
  }

  static List<Map<String, dynamic>>? _stationsForLine(String lineKey) {
    switch (lineKey.trim().toLowerCase()) {
      case 'blue':
        return metro.blueStations;
      case 'red':
        return metro.redStations;
      case 'green':
        return metro.greenStations;
      case 'yellow':
        return metro.yellowStations;
      case 'orange':
        return metro.orangeStations;
      case 'purple':
        return metro.purpleStations;
      default:
        return null;
    }
  }

  static int _stationIndex(
    List<Map<String, dynamic>> stations,
    String stationName,
  ) {
    final target = _normalizeStation(stationName);
    if (target.isEmpty) return -1;
    return stations.indexWhere((station) {
      final english = _normalizeStation(station['name']?.toString() ?? '');
      final arabic = _normalizeStation(station['nameAr']?.toString() ?? '');
      return target == english || target == arabic;
    });
  }

  static String _normalizeStation(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\b(station|metro)\b'), '')
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), '');

  static double _distanceBetween(
    double firstLat,
    double firstLng,
    double secondLat,
    double secondLng,
  ) {
    final firstLatRadians = _radians(firstLat);
    final secondLatRadians = _radians(secondLat);
    final latitudeDelta = _radians(secondLat - firstLat);
    final longitudeDelta = _radians(secondLng - firstLng);
    final sinLatitude = math.sin(latitudeDelta / 2);
    final sinLongitude = math.sin(longitudeDelta / 2);
    final haversine = sinLatitude * sinLatitude +
        math.cos(firstLatRadians) *
            math.cos(secondLatRadians) *
            sinLongitude *
            sinLongitude;
    return 2 *
        _earthRadiusMeters *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
