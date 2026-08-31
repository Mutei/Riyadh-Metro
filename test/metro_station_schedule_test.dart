import 'package:darb/latlon/metro_station_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MetroStationSchedule', () {
    test('returns the Friday timetable for the selected direction', () {
      final result = MetroStationSchedule.forJourney(
        lineKey: 'yellow',
        fromStation: 'KAFD',
        toStation: 'Airport T5',
        date: DateTime(2026, 8, 28),
      );

      expect(result, isNotNull);
      expect(result!.towardsStation, 'Airport T1-2');
      expect(result.firstTrain, '10:32');
      expect(result.lastTrain, '00:32');
    });

    test('resolves Arabic station names using existing station data', () {
      final result = MetroStationSchedule.forJourney(
        lineKey: 'green',
        fromStation: 'وزارة التعليم',
        toStation: 'المتحف الوطني',
        date: DateTime(2026, 8, 26),
      );

      expect(result, isNotNull);
      expect(result!.firstTrain, '05:30');
      expect(result.lastTrain, '00:00');
    });

    test('does not offer an outbound train beyond a terminal station', () {
      final result = MetroStationSchedule.forJourney(
        lineKey: 'yellow',
        fromStation: 'Airport T1-2',
        toStation: 'Airport T3-4',
        date: DateTime(2026, 8, 26),
      );

      expect(result, isNotNull);
      expect(result!.firstTrain, '05:30');
      expect(result.lastTrain, '00:00');
    });
  });
}
