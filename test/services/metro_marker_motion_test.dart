import 'package:darb/services/metro_marker_motion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('MetroMarkerMotion', () {
    test('interpolates position without moving the navigation target', () {
      final motion = MetroMarkerMotion();
      final start = DateTime(2026, 1, 1, 12);
      const first = LatLng(24.7, 46.6);
      const target = LatLng(24.8, 46.8);

      motion.retarget(
        position: first,
        heading: 90,
        at: start,
        duration: const Duration(seconds: 1),
      );
      motion.retarget(
        position: target,
        heading: 90,
        at: start,
        duration: const Duration(seconds: 1),
      );

      final halfway =
          motion.frameAt(start.add(const Duration(milliseconds: 500)))!;
      expect(halfway.position.latitude, inInclusiveRange(24.7, 24.8));
      expect(halfway.position.longitude, inInclusiveRange(46.6, 46.8));
      expect(halfway.position, isNot(target));
      expect(halfway.complete, isFalse);
      expect(
        motion.frameAt(start.add(const Duration(seconds: 1)))!.position,
        target,
      );
    });

    test('turns through the shortest heading path', () {
      final motion = MetroMarkerMotion();
      final start = DateTime(2026, 1, 1, 12);
      const position = LatLng(24.7, 46.6);

      motion.retarget(
        position: position,
        heading: 350,
        at: start,
        duration: const Duration(seconds: 1),
      );
      motion.retarget(
        position: position,
        heading: 10,
        at: start,
        duration: const Duration(seconds: 1),
      );

      final halfway =
          motion.frameAt(start.add(const Duration(milliseconds: 500)))!;
      expect(halfway.heading < 20 || halfway.heading > 340, isTrue);
    });

    test('retargeting continues from the current visual frame', () {
      final motion = MetroMarkerMotion();
      final start = DateTime(2026, 1, 1, 12);
      const first = LatLng(24.7, 46.6);
      const second = LatLng(24.8, 46.7);
      const third = LatLng(24.9, 46.8);

      motion.retarget(
        position: first,
        heading: 0,
        at: start,
        duration: const Duration(seconds: 1),
      );
      motion.retarget(
        position: second,
        heading: 45,
        at: start,
        duration: const Duration(seconds: 1),
      );
      final retargetAt = start.add(const Duration(milliseconds: 400));
      final beforeRetarget = motion.frameAt(retargetAt)!;

      motion.retarget(
        position: third,
        heading: 90,
        at: retargetAt,
        duration: const Duration(seconds: 1),
      );
      final afterRetarget = motion.frameAt(retargetAt)!;

      expect(afterRetarget.position, beforeRetarget.position);
      expect(afterRetarget.heading, beforeRetarget.heading);
    });
  });
}
