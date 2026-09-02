import 'package:firebase_database/firebase_database.dart';

/// Calculates metro travel statistics from actual, completed trip records.
///
/// A valid observation uses the timestamps stored at the two requested station
/// boundaries. Segment `seconds` is deliberately not used: elapsed time from
/// the origin segment's `startedAt` to the destination segment's `finishedAt`
/// includes real waiting and transfer time.
class TripAnalyticsService {
  TripAnalyticsService({FirebaseDatabase? database})
      : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  Future<TripTimeEstimate?> estimateMetroTrip({
    required String fromStation,
    required String toStation,
  }) async {
    dynamic raw;
    try {
      raw = (await _database.ref('App/TravelHistory').get()).value;
    } catch (_) {
      return null;
    }
    if (raw is! Map) return null;

    final trips = <Map<Object?, Object?>>[];
    for (final userData in Map<Object?, Object?>.from(raw).values) {
      if (userData is! Map) continue;
      for (final rawTrip in Map<Object?, Object?>.from(userData).values) {
        if (rawTrip is Map) trips.add(Map<Object?, Object?>.from(rawTrip));
      }
    }

    return estimateFromRecordedTrips(
      trips: trips,
      fromStation: fromStation,
      toStation: toStation,
    );
  }

  /// Pure calculation entry point for regression tests. Every map has the same
  /// shape as a Firebase `TravelHistory/<uid>/<tripId>` record.
  static TripTimeEstimate? estimateFromRecordedTrips({
    required Iterable<Map<Object?, Object?>> trips,
    required String fromStation,
    required String toStation,
  }) {
    final expectedFrom = _normalize(fromStation);
    final expectedTo = _normalize(toStation);
    if (expectedFrom.isEmpty ||
        expectedTo.isEmpty ||
        expectedFrom == expectedTo) {
      return null;
    }

    final samples = <_TripSample>[];
    for (final trip in trips) {
      if (!_isCompletedMetroTrip(trip)) continue;
      final sample = _findRouteInsideTrip(
        _segmentsFor(trip['metroSegments']),
        fromStation: expectedFrom,
        toStation: expectedTo,
      );
      if (sample != null) samples.add(sample);
    }
    return samples.isEmpty ? null : _estimateFromSamples(samples);
  }

  static bool _isCompletedMetroTrip(Map<Object?, Object?> trip) {
    final mode = trip['mode']?.toString().trim().toLowerCase();
    if (mode != null && mode.isNotEmpty && mode != 'metro') return false;
    final startedAt = _asInt(trip['startedAt']);
    final finishedAt = _asInt(trip['finishedAt']);
    return startedAt > 0 && finishedAt > startedAt;
  }

  /// The source station must occur before the destination station. The result
  /// is measured from actual station timestamps, never generated timings.
  static _TripSample? _findRouteInsideTrip(
    List<_MetroSegment> segments, {
    required String fromStation,
    required String toStation,
  }) {
    final originTimes = <int>[];
    final destinationTimes = <int>[];
    for (final segment in segments) {
      final segmentFrom = _normalize(segment.fromStation);
      final segmentTo = _normalize(segment.toStation);
      if (segmentFrom == fromStation) originTimes.add(segment.startedAt);
      if (segmentTo == fromStation) originTimes.add(segment.finishedAt);
      if (segmentTo == toStation) destinationTimes.add(segment.finishedAt);
    }
    originTimes.sort();
    destinationTimes.sort();

    for (final startedAt in originTimes) {
      int? finishedAt;
      for (final timestamp in destinationTimes) {
        if (timestamp > startedAt) {
          finishedAt = timestamp;
          break;
        }
      }
      if (finishedAt == null) continue;

      final lines = segments
          .where((segment) =>
              segment.startedAt >= startedAt &&
              segment.finishedAt <= finishedAt!)
          .map((segment) => segment.lineKey)
          .where((line) => line.isNotEmpty)
          .toList();
      final durationSeconds = ((finishedAt - startedAt) / 1000).round();
      if (durationSeconds > 0) {
        return _TripSample(durationSeconds: durationSeconds, lines: lines);
      }
    }
    return null;
  }

  /// Reads only reliable station-to-station movement records. Transfers and
  /// unfinished/timestamp-less segments never become historical observations.
  static List<_MetroSegment> _segmentsFor(dynamic value) {
    if (value is! Map) return const [];

    final segments = <_MetroSegment>[];
    value.forEach((key, rawSegment) {
      if (rawSegment is! Map) return;
      final segment = Map<Object?, Object?>.from(rawSegment);
      final fromStation = _nonEmpty(segment['fromStation'] ?? segment['from']);
      final toStation = _nonEmpty(segment['toStation'] ?? segment['to']);
      final startedAt = _asInt(segment['startedAt']);
      final finishedAt = _asInt(segment['finishedAt']);

      if (fromStation == null ||
          toStation == null ||
          _normalize(fromStation) == _normalize(toStation) ||
          startedAt <= 0 ||
          finishedAt <= startedAt) {
        return;
      }

      segments.add(_MetroSegment(
        id: key.toString(),
        fromStation: fromStation,
        toStation: toStation,
        lineKey: segment['lineKey']?.toString().trim() ?? '',
        startedAt: startedAt,
        finishedAt: finishedAt,
      ));
    });

    segments.sort((a, b) {
      if (a.startedAt == b.startedAt) return a.id.compareTo(b.id);
      return a.startedAt.compareTo(b.startedAt);
    });
    return segments;
  }

  static TripTimeEstimate _estimateFromSamples(List<_TripSample> samples) {
    var totalSeconds = 0;
    var minimumSeconds = samples.first.durationSeconds;
    var maximumSeconds = samples.first.durationSeconds;
    var transferTotal = 0;

    for (final sample in samples) {
      totalSeconds += sample.durationSeconds;
      minimumSeconds = minimumSeconds > sample.durationSeconds
          ? sample.durationSeconds
          : minimumSeconds;
      maximumSeconds = maximumSeconds < sample.durationSeconds
          ? sample.durationSeconds
          : maximumSeconds;

      final uniqueLines = <String>[];
      for (final line in sample.lines) {
        if (line.isEmpty ||
            (uniqueLines.isNotEmpty && uniqueLines.last == line)) {
          continue;
        }
        uniqueLines.add(line);
      }
      if (uniqueLines.length > 1) transferTotal += uniqueLines.length - 1;
    }

    return TripTimeEstimate(
      averageSeconds: (totalSeconds / samples.length).round(),
      minimumSeconds: minimumSeconds,
      maximumSeconds: maximumSeconds,
      sampleCount: samples.length,
      commonLines: _rankedLines(samples).take(3).toList(),
      fastestLines: _rankedLines(
        samples.where((sample) => sample.durationSeconds == minimumSeconds),
      ),
      slowestLines: _rankedLines(
        samples.where((sample) => sample.durationSeconds == maximumSeconds),
      ),
      averageTransfers: (transferTotal / samples.length).round(),
      isCommunityAggregate: true,
    );
  }

  /// Lines are associated with the matching fastest/slowest samples, never
  /// borrowed from the overall community average. Tied samples are combined.
  static List<String> _rankedLines(Iterable<_TripSample> samples) {
    final counts = <String, int>{};
    for (final sample in samples) {
      for (final line in sample.lines.map((line) => line.trim()).toSet()) {
        if (line.isEmpty) continue;
        counts[line] = (counts[line] ?? 0) + 1;
      }
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return ranked.map((entry) => entry.key).toList(growable: false);
  }

  static String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == '—' || text == '-' ? null : text;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'\b(station|metro)\b'), '')
      .replaceAll('محطة', '')
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ـ', '')
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class TripTimeEstimate {
  final int averageSeconds;
  final int minimumSeconds;
  final int maximumSeconds;
  final int sampleCount;
  final List<String> commonLines;
  final List<String> fastestLines;
  final List<String> slowestLines;
  final int averageTransfers;
  final bool isCommunityAggregate;

  const TripTimeEstimate({
    required this.averageSeconds,
    required this.minimumSeconds,
    required this.maximumSeconds,
    required this.sampleCount,
    required this.commonLines,
    required this.fastestLines,
    required this.slowestLines,
    required this.averageTransfers,
    required this.isCommunityAggregate,
  });
}

class _TripSample {
  final int durationSeconds;
  final List<String> lines;

  const _TripSample({required this.durationSeconds, required this.lines});
}

class _MetroSegment {
  final String id;
  final String fromStation;
  final String toStation;
  final String lineKey;
  final int startedAt;
  final int finishedAt;

  const _MetroSegment({
    required this.id,
    required this.fromStation,
    required this.toStation,
    required this.lineKey,
    required this.startedAt,
    required this.finishedAt,
  });
}
