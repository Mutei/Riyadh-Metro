import 'package:darb/services/metro_trip_time_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('route comparison respects each route priority', () {
    final comparison = MetroTripTimeService().compare(
      fromStation: 'KAFD',
      toStation: 'STC',
    );

    expect(comparison, isNotNull);
    expect(comparison!.fastest.seconds, greaterThan(0));
    expect(
      comparison.fewestTransfers.transfers,
      lessThanOrEqualTo(comparison.fastest.transfers),
    );
    expect(
      comparison.leastWalking.walkingMeters,
      lessThanOrEqualTo(comparison.fastest.walkingMeters),
    );
  });
}
