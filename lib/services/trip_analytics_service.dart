import 'package:firebase_database/firebase_database.dart';

/// Reads anonymized, server-generated statistics for completed metro trips.
///
/// Individual histories remain private at `App/TravelHistory/<uid>`. A Cloud
/// Function writes aggregate-only data at `App/RouteAnalytics/metro/<route>`.
class TripAnalyticsService {
  TripAnalyticsService({FirebaseDatabase? database})
      : _database = database ?? FirebaseDatabase.instance;

  static const int minimumReliableSamples = 2;

  final FirebaseDatabase _database;

  Future<TripTimeEstimate?> estimateMetroTrip({
    required String fromStation,
    required String toStation,
  }) async {
    final routeKey = routeKeyFor(fromStation, toStation);
    if (routeKey.isEmpty) return null;

    final raw =
        (await _database.ref('App/RouteAnalytics/metro/$routeKey').get()).value;
    if (raw is! Map) return null;
    final stats = Map<Object?, Object?>.from(raw);

    final sampleCount = _asInt(stats['sampleCount']);
    final totalSeconds = _asInt(stats['totalDurationSeconds']);
    if (sampleCount < minimumReliableSamples || totalSeconds <= 0) return null;

    return TripTimeEstimate(
      averageSeconds: (totalSeconds / sampleCount).round(),
      minimumSeconds: _asInt(stats['minimumDurationSeconds']),
      maximumSeconds: _asInt(stats['maximumDurationSeconds']),
      sampleCount: sampleCount,
      commonLines: _readLineCounts(stats['lineCounts']),
      averageTransfers: (_asInt(stats['transferTotal']) / sampleCount).round(),
    );
  }

  /// Must stay aligned with `functions/index.js` so app reads use the same
  /// aggregate key written by the trusted server-side trigger.
  static String routeKeyFor(String fromStation, String toStation) {
    final from = _normalize(fromStation);
    final to = _normalize(toStation);
    return from.isEmpty || to.isEmpty ? '' : '${from}__${to}';
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\b(station|metro)\b'), '')
      .replaceAll('محطة', '')
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  int _asInt(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<String> _readLineCounts(dynamic value) {
    if (value is! Map) return const [];
    final counts = value.entries
        .map((entry) => MapEntry(entry.key.toString(), _asInt(entry.value)))
        .where((entry) => entry.key.isNotEmpty && entry.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return counts.take(3).map((entry) => entry.key).toList();
  }
}

class TripTimeEstimate {
  final int averageSeconds;
  final int minimumSeconds;
  final int maximumSeconds;
  final int sampleCount;
  final List<String> commonLines;
  final int averageTransfers;

  const TripTimeEstimate({
    required this.averageSeconds,
    required this.minimumSeconds,
    required this.maximumSeconds,
    required this.sampleCount,
    required this.commonLines,
    required this.averageTransfers,
  });
}
