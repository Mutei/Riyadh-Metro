import 'package:darb/services/metro_route_distance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MetroRouteDistance', () {
    test('sums consecutive stations along a line in either direction', () {
      final forward = MetroRouteDistance.betweenStations(
        lineKey: 'red',
        fromStation: 'King Saud University',
        toStation: 'KACST',
      );
      final reverse = MetroRouteDistance.betweenStations(
        lineKey: 'red',
        fromStation: 'KACST',
        toStation: 'King Saud University',
      );

      expect(forward, isNotNull);
      expect(forward, greaterThan(0));
      expect(reverse, forward);
    });

    test('matches Arabic station names', () {
      final english = MetroRouteDistance.betweenStations(
        lineKey: 'red',
        fromStation: 'King Saud University',
        toStation: 'King Salman Oasis',
      );
      final arabic = MetroRouteDistance.betweenStations(
        lineKey: 'red',
        fromStation: 'جامعة الملك سعود',
        toStation: 'واحة الملك سلمان',
      );

      expect(arabic, english);
    });

    test('returns zero for the same station and null for unknown data', () {
      expect(
        MetroRouteDistance.betweenStations(
          lineKey: 'purple',
          fromStation: 'Al Andalus',
          toStation: 'Al Andalus',
        ),
        0,
      );
      expect(
        MetroRouteDistance.betweenStations(
          lineKey: 'not-a-line',
          fromStation: 'A',
          toStation: 'B',
        ),
        isNull,
      );
    });
  });
}
