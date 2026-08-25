import 'package:firebase_database/firebase_database.dart';

/// Reads REAL metro travel times directly from Firebase Realtime Database.
///
/// Database structure expected:
///
/// App
///   TravelHistory
///     {userId}
///       {tripId}
///         metroSegments
///           {segmentId}
///             fromStation: "KAFD"
///             toStation: "Al Murooj"
///             lineKey: "blue"
///             seconds: 174
///             startedAt: ...
///             finishedAt: ...
///
/// Example:
///
/// KAFD -> Al Murooj       = 174 sec
/// Al Murooj -> King Fahad = 120 sec
/// King Fahad -> STC       = 135 sec
///
/// Asking:
/// KAFD -> STC
///
/// Result:
/// 174 + 120 + 135 = 429 seconds
class TripAnalyticsService {
  TripAnalyticsService({
    FirebaseDatabase? database,
  }) : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  Future<TripTimeEstimate?> estimateMetroTrip({
    required String fromStation,
    required String toStation,
  }) async {
    final expectedFrom = _normalize(fromStation);
    final expectedTo = _normalize(toStation);

    if (expectedFrom.isEmpty ||
        expectedTo.isEmpty ||
        expectedFrom == expectedTo) {
      return null;
    }

    dynamic raw;

    try {
      raw = (await _database.ref('App/TravelHistory').get()).value;
    } catch (e) {
      return null;
    }

    if (raw is! Map) {
      return null;
    }

    final travelHistory = Map<Object?, Object?>.from(raw);

    final samples = <_TripSample>[];

    // ---------------------------------------------------------
    // TravelHistory
    //   userId
    //     tripId
    //       metroSegments
    // ---------------------------------------------------------
    for (final userEntry in travelHistory.entries) {
      final userData = userEntry.value;

      if (userData is! Map) {
        continue;
      }

      final trips = Map<Object?, Object?>.from(userData);

      for (final tripEntry in trips.entries) {
        final rawTrip = tripEntry.value;

        if (rawTrip is! Map) {
          continue;
        }

        final trip = Map<Object?, Object?>.from(rawTrip);

        // If mode exists and isn't metro, ignore it.
        final mode = trip['mode']?.toString().trim().toLowerCase();

        if (mode != null && mode.isNotEmpty && mode != 'metro') {
          continue;
        }

        final segments = _segmentsFor(
          trip['metroSegments'],
        );

        if (segments.isEmpty) {
          continue;
        }

        // One saved trip may contain the requested route
        // somewhere inside its metroSegments.
        final sample = _findRouteInsideTrip(
          segments,
          fromStation: expectedFrom,
          toStation: expectedTo,
        );

        if (sample != null && sample.durationSeconds > 0) {
          samples.add(sample);
        }
      }
    }

    if (samples.isEmpty) {
      return null;
    }

    return _estimateFromSamples(samples);
  }

  /// Finds a route inside ONE recorded trip.
  ///
  /// For example:
  ///
  /// segment 1:
  /// KAFD -> Al Murooj = 174
  ///
  /// segment 2:
  /// Al Murooj -> King Fahad = 120
  ///
  /// segment 3:
  /// King Fahad -> STC = 135
  ///
  /// Searching KAFD -> STC:
  ///
  /// 174 + 120 + 135
  /// = 429 seconds
  _TripSample? _findRouteInsideTrip(
    List<_MetroSegment> segments, {
    required String fromStation,
    required String toStation,
  }) {
    // Search every possible starting segment.
    for (var startIndex = 0; startIndex < segments.length; startIndex++) {
      final startingSegment = segments[startIndex];

      final startingFrom = _normalize(startingSegment.fromStation);

      if (startingFrom != fromStation) {
        continue;
      }

      var totalSeconds = 0;

      final lines = <String>[];

      String? previousDestination;

      // Starting from the requested origin,
      // keep adding segments until destination is found.
      for (var index = startIndex; index < segments.length; index++) {
        final segment = segments[index];

        final segmentFrom = _normalize(segment.fromStation);

        final segmentTo = _normalize(segment.toStation);

        // ----------------------------------------------------
        // Make sure the segments form one continuous journey.
        //
        // Example:
        //
        // KAFD -> Al Murooj
        // Al Murooj -> STC
        //
        // Valid because the previous destination equals the
        // next segment's origin.
        // ----------------------------------------------------
        if (previousDestination != null && segmentFrom != previousDestination) {
          break;
        }

        if (segment.seconds <= 0) {
          break;
        }

        totalSeconds += segment.seconds;

        if (segment.lineKey.trim().isNotEmpty) {
          lines.add(segment.lineKey.trim());
        }

        // Destination reached.
        if (segmentTo == toStation) {
          return _TripSample(
            durationSeconds: totalSeconds,
            lines: lines,
          );
        }

        previousDestination = segmentTo;
      }
    }

    return null;
  }

  /// Converts Firebase metroSegments into a chronological list.
  List<_MetroSegment> _segmentsFor(dynamic value) {
    if (value is! Map) {
      return const [];
    }

    final segments = <_MetroSegment>[];

    value.forEach((key, rawSegment) {
      if (rawSegment is! Map) {
        return;
      }

      final segment = Map<Object?, Object?>.from(rawSegment);

      final fromStation = _nonEmpty(
        segment['fromStation'] ?? segment['from'],
      );

      final toStation = _nonEmpty(
        segment['toStation'] ?? segment['to'],
      );

      if (fromStation == null || toStation == null) {
        return;
      }

      var seconds = _asInt(
        segment['seconds'],
      );

      final startedAt = _asInt(
        segment['startedAt'],
      );

      final finishedAt = _asInt(
        segment['finishedAt'],
      );

      // If seconds was not saved correctly,
      // calculate it from timestamps.
      if (seconds <= 0 && startedAt > 0 && finishedAt > startedAt) {
        seconds = ((finishedAt - startedAt) / 1000).round();
      }

      if (seconds <= 0) {
        return;
      }

      final lineKey = segment['lineKey']?.toString().trim() ?? '';

      segments.add(
        _MetroSegment(
          id: key.toString(),
          fromStation: fromStation,
          toStation: toStation,
          lineKey: lineKey,
          seconds: seconds,
          startedAt: startedAt,
          finishedAt: finishedAt,
        ),
      );
    });

    // --------------------------------------------------------
    // IMPORTANT
    //
    // Firebase push IDs should NOT decide trip order.
    // startedAt determines the actual segment order.
    // --------------------------------------------------------
    segments.sort((a, b) {
      if (a.startedAt == b.startedAt) {
        return a.id.compareTo(b.id);
      }

      return a.startedAt.compareTo(
        b.startedAt,
      );
    });

    return segments;
  }

  TripTimeEstimate _estimateFromSamples(
    List<_TripSample> samples,
  ) {
    var totalSeconds = 0;

    var minimumSeconds = samples.first.durationSeconds;

    var maximumSeconds = samples.first.durationSeconds;

    final lineCounts = <String, int>{};

    var transferTotal = 0;

    for (final sample in samples) {
      totalSeconds += sample.durationSeconds;

      if (sample.durationSeconds < minimumSeconds) {
        minimumSeconds = sample.durationSeconds;
      }

      if (sample.durationSeconds > maximumSeconds) {
        maximumSeconds = sample.durationSeconds;
      }

      // Remove duplicate consecutive line names.
      final uniqueLines = <String>[];

      for (final line in sample.lines) {
        if (line.trim().isEmpty) {
          continue;
        }

        if (uniqueLines.isEmpty || uniqueLines.last != line) {
          uniqueLines.add(line);
        }
      }

      if (uniqueLines.length > 1) {
        transferTotal += uniqueLines.length - 1;
      }

      for (final line in uniqueLines.toSet()) {
        lineCounts[line] = (lineCounts[line] ?? 0) + 1;
      }
    }

    final commonLineEntries = lineCounts.entries.toList()
      ..sort(
        (a, b) => b.value.compareTo(a.value),
      );

    return TripTimeEstimate(
      averageSeconds: (totalSeconds / samples.length).round(),
      minimumSeconds: minimumSeconds,
      maximumSeconds: maximumSeconds,
      sampleCount: samples.length,
      commonLines: commonLineEntries.take(3).map((entry) => entry.key).toList(),
      averageTransfers:
          samples.isEmpty ? 0 : (transferTotal / samples.length).round(),

      // These samples came from actual recorded
      // TravelHistory data.
      isCommunityAggregate: true,
    );
  }

  String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim() ?? '';

    if (text.isEmpty || text == '—' || text == '-') {
      return null;
    }

    return text;
  }

  static String _normalize(
    String value,
  ) {
    return value
        .toLowerCase()
        .trim()

        // Remove common words.
        .replaceAll(
          RegExp(
            r'\b(station|metro)\b',
          ),
          '',
        )
        .replaceAll(
          'محطة',
          '',
        )

        // Remove Arabic diacritics.
        .replaceAll(
          RegExp(
            r'[\u064B-\u065F\u0670]',
          ),
          '',
        )

        // Normalize non-alphanumeric characters.
        .replaceAll(
          RegExp(
            r'[^a-z0-9\u0621-\u064A]+',
          ),
          ' ',
        )

        // Remove duplicate spaces.
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }
}

class TripTimeEstimate {
  final int averageSeconds;

  final int minimumSeconds;

  final int maximumSeconds;

  final int sampleCount;

  final List<String> commonLines;

  final int averageTransfers;

  final bool isCommunityAggregate;

  const TripTimeEstimate({
    required this.averageSeconds,
    required this.minimumSeconds,
    required this.maximumSeconds,
    required this.sampleCount,
    required this.commonLines,
    required this.averageTransfers,
    required this.isCommunityAggregate,
  });
}

class _TripSample {
  final int durationSeconds;

  final List<String> lines;

  const _TripSample({
    required this.durationSeconds,
    required this.lines,
  });
}

class _MetroSegment {
  final String id;

  final String fromStation;

  final String toStation;

  final String lineKey;

  final int seconds;

  final int startedAt;

  final int finishedAt;

  const _MetroSegment({
    required this.id,
    required this.fromStation,
    required this.toStation,
    required this.lineKey,
    required this.seconds,
    required this.startedAt,
    required this.finishedAt,
  });
}
