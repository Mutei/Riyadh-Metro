import 'package:darb/services/trip_analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<Object?, Object?> _segment({
  required String from,
  required String to,
  required String line,
  required int startedAt,
  required int finishedAt,
}) =>
    <Object?, Object?>{
      'fromStation': from,
      'toStation': to,
      'lineKey': line,
      'startedAt': startedAt,
      'finishedAt': finishedAt,
      // This deliberately differs from the timestamps to prove it is ignored.
      'seconds': 1,
    };

Map<Object?, Object?> _completedTrip(Map<Object?, Object?> segments) =>
    <Object?, Object?>{
      'mode': 'metro',
      'startedAt': 1000,
      'finishedAt': 100000,
      'metroSegments': segments,
    };

void main() {
  test('uses intermediate station timestamps and includes a transfer wait', () {
    final trip = _completedTrip(<Object?, Object?>{
      'a': _segment(
        from: 'KAFD',
        to: 'STC',
        line: 'blue',
        startedAt: 1000,
        finishedAt: 5000,
      ),
      'b': _segment(
        from: 'STC',
        to: 'Al Wurud 2',
        line: 'red',
        startedAt: 8000,
        finishedAt: 13000,
      ),
    });

    final estimate = TripAnalyticsService.estimateFromRecordedTrips(
      trips: [trip],
      fromStation: 'STC',
      toStation: 'Al Wurud 2',
    );

    expect(estimate, isNotNull);
    expect(estimate!.averageSeconds, 8);
    expect(estimate.minimumSeconds, 8);
    expect(estimate.maximumSeconds, 8);
    expect(estimate.sampleCount, 1);
    expect(estimate.commonLines, ['red']);
  });

  test('aggregates valid actual observations and rejects reverse direction', () {
    final first = _completedTrip(<Object?, Object?>{
      'a': _segment(
        from: 'STC',
        to: 'Al Wurud 2',
        line: 'blue',
        startedAt: 1000,
        finishedAt: 5000,
      ),
    });
    final second = _completedTrip(<Object?, Object?>{
      'a': _segment(
        from: 'STC',
        to: 'Al Wurud 2',
        line: 'blue',
        startedAt: 2000,
        finishedAt: 8000,
      ),
    });

    final estimate = TripAnalyticsService.estimateFromRecordedTrips(
      trips: [first, second],
      fromStation: 'STC',
      toStation: 'Al Wurud 2',
    );
    final reverse = TripAnalyticsService.estimateFromRecordedTrips(
      trips: [first, second],
      fromStation: 'Al Wurud 2',
      toStation: 'STC',
    );

    expect(estimate, isNotNull);
    expect(estimate!.averageSeconds, 5);
    expect(estimate.minimumSeconds, 4);
    expect(estimate.maximumSeconds, 6);
    expect(estimate.sampleCount, 2);
    expect(reverse, isNull);
  });

  test('rejects incomplete trips and segments without both timestamps', () {
    final incompleteTrip = <Object?, Object?>{
      'mode': 'metro',
      'startedAt': 1000,
      'finishedAt': null,
      'metroSegments': <Object?, Object?>{
        'a': _segment(
          from: 'KAFD',
          to: 'STC',
          line: 'blue',
          startedAt: 1000,
          finishedAt: 5000,
        ),
      },
    };
    final noTimestampTrip = _completedTrip(<Object?, Object?>{
      'a': <Object?, Object?>{
        'fromStation': 'KAFD',
        'toStation': 'STC',
        'lineKey': 'blue',
        'seconds': 400,
      },
    });

    final estimate = TripAnalyticsService.estimateFromRecordedTrips(
      trips: [incompleteTrip, noTimestampTrip],
      fromStation: 'KAFD',
      toStation: 'STC',
    );

    expect(estimate, isNull);
  });

  test('keeps reliable station boundaries when an unrelated segment is malformed',
      () {
    final first = _completedTrip(<Object?, Object?>{
      'a': _segment(
        from: 'SABIC',
        to: 'An Naseem',
        line: 'purple',
        startedAt: 1000,
        finishedAt: 43000,
      ),
      'broken': <Object?, Object?>{
        'fromStation': 'Harun Al Rashid Road',
        'toStation': 'Al Rajhi Grand Mosque',
        'lineKey': 'orange',
        'startedAt': 50000,
      },
      'z': _segment(
        from: 'Al Hilla',
        to: 'Qasr Al Hokm',
        line: 'orange',
        startedAt: 68000,
        finishedAt: 70000,
      ),
    });
    final second = _completedTrip(<Object?, Object?>{
      'a': _segment(
        from: 'An Naseem',
        to: 'Harun Al Rashid Road',
        line: 'orange',
        startedAt: 47000,
        finishedAt: 50000,
      ),
      'z': _segment(
        from: 'Al Hilla',
        to: 'Qasr Al Hokm',
        line: 'orange',
        startedAt: 68000,
        finishedAt: 70000,
      ),
    });

    final estimate = TripAnalyticsService.estimateFromRecordedTrips(
      trips: [first, second],
      fromStation: 'An Naseem',
      toStation: 'Qasr Al Hokm',
    );

    expect(estimate, isNotNull);
    expect(estimate!.sampleCount, 2);
    expect(estimate.averageSeconds, 25);
    expect(estimate.minimumSeconds, 23);
    expect(estimate.maximumSeconds, 27);
  });
}
