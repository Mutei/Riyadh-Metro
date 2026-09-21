import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'local_notifications.dart';

enum BusOnDemandDirection { stationToLocation, locationToStation }

class BusOnDemandPass {
  final String id;
  final String title;
  final String description;
  final int priceSar;
  final Duration validity;
  final bool includesMetro;

  const BusOnDemandPass({
    required this.id,
    required this.title,
    required this.description,
    required this.priceSar,
    required this.validity,
    required this.includesMetro,
  });
}

const busOnDemandPasses = <BusOnDemandPass>[
  BusOnDemandPass(
    id: 'bod_30m',
    title: 'Bus on Demand Pass',
    description:
        'One Bus on Demand ride. A separate ticket is required for Bus/Metro.',
    priceSar: 2,
    validity: Duration(minutes: 30),
    includesMetro: false,
  ),
  BusOnDemandPass(
    id: 'bod_combined_3h',
    title: 'Combined Bus on Demand Pass',
    description:
        'One Bus on Demand ride plus unlimited Bus/Metro rides for 3 hours.',
    priceSar: 6,
    validity: Duration(hours: 3),
    includesMetro: true,
  ),
];

class BusOnDemandBookingData {
  final BusOnDemandPass pass;
  final BusOnDemandDirection direction;
  final String stationName;
  final double stationLat;
  final double stationLng;
  final String locationLabel;
  final double locationLat;
  final double locationLng;
  final DateTime scheduledPickup;

  const BusOnDemandBookingData({
    required this.pass,
    required this.direction,
    required this.stationName,
    required this.stationLat,
    required this.stationLng,
    required this.locationLabel,
    required this.locationLat,
    required this.locationLng,
    required this.scheduledPickup,
  });
}

class BusOnDemandDuplicateBookingException implements Exception {
  const BusOnDemandDuplicateBookingException();
}

/// Owns only Bus on Demand records. Metro tickets and trip records are untouched.
class BusOnDemandService {
  static final FirebaseDatabase _database = FirebaseDatabase.instance;

  static DatabaseReference _bookings(String uid) =>
      _database.ref('App/BusOnDemandBookings/$uid');

  static DatabaseReference _tickets(String uid) =>
      _database.ref('App/Tickets/$uid');

  static String _directionValue(BusOnDemandDirection direction) =>
      direction == BusOnDemandDirection.stationToLocation
          ? 'stationToLocation'
          : 'locationToStation';

  static String _bookingId(BusOnDemandBookingData booking) {
    final location =
        '${booking.locationLat.toStringAsFixed(5)},${booking.locationLng.toStringAsFixed(5)}';
    final source = [
      booking.pass.id,
      _directionValue(booking.direction),
      booking.stationName.trim().toLowerCase(),
      location,
      booking.scheduledPickup.millisecondsSinceEpoch ~/ 60000,
    ].join('|');
    var hash = 2166136261;
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 'bod_$hash';
  }

  static Future<String> createBooking({
    required String uid,
    required BusOnDemandBookingData booking,
  }) async {
    final bookingId = _bookingId(booking);
    final ticketId = _tickets(uid).push().key;
    if (ticketId == null) throw StateError('Could not create a ticket ID.');

    final now = DateTime.now();
    final direction = _directionValue(booking.direction);
    final common = <String, Object?>{
      'bookingId': bookingId,
      'ticketId': ticketId,
      'productId': booking.pass.id,
      'title': booking.pass.title,
      'priceSar': booking.pass.priceSar,
      'direction': direction,
      'stationName': booking.stationName,
      'stationLat': booking.stationLat,
      'stationLng': booking.stationLng,
      'locationLabel': booking.locationLabel,
      'locationLat': booking.locationLat,
      'locationLng': booking.locationLng,
      'scheduledPickupMillis': booking.scheduledPickup.millisecondsSinceEpoch,
      'createdAtMillis': now.millisecondsSinceEpoch,
      'status': 'scheduled',
      'metroIncluded': booking.pass.includesMetro,
    };

    final result = await _bookings(uid).child(bookingId).runTransaction(
          (current) => current == null
              ? Transaction.success(common)
              : Transaction.abort(),
          applyLocally: false,
        );
    if (!result.committed) throw const BusOnDemandDuplicateBookingException();

    try {
      await _tickets(uid).child(ticketId).set({
        'productId': booking.pass.id,
        'class': 'regular',
        'kind': 'busOnDemand',
        'title': booking.pass.title,
        'priceSar': booking.pass.priceSar,
        'purchasedAt': '${now.month}/${now.day}/${now.year}',
        'purchasedAtMillis': now.millisecondsSinceEpoch,
        'activated': false,
        'activatedAt': null,
        'expiresAt': null,
        'expired': false,
        'bookingId': bookingId,
        'busBookingStatus': 'scheduled',
        'busDirection': direction,
        'stationName': booking.stationName,
        'locationLabel': booking.locationLabel,
        'scheduledPickupMillis': booking.scheduledPickup.millisecondsSinceEpoch,
        'metroIncluded': booking.pass.includesMetro,
      });
    } catch (_) {
      await _bookings(uid).child(bookingId).remove();
      rethrow;
    }

    // A denied notification permission must not undo a completed booking, but
    // its state is retained for support and for the booking status UI.
    try {
      final scheduled = await BusOnDemandNotifications.schedule(
        bookingId: bookingId,
        scheduledPickup: booking.scheduledPickup,
        pickupLabel: booking.direction == BusOnDemandDirection.stationToLocation
            ? booking.stationName
            : booking.locationLabel,
        requestPermissions: true,
      );
      await _bookings(uid).child(bookingId).update({
        'notificationScheduleStatus': scheduled ? 'scheduled' : 'unavailable',
        'notificationScheduleUpdatedAtMillis':
            DateTime.now().millisecondsSinceEpoch,
      });
    } catch (error) {
      await _bookings(uid).child(bookingId).update({
        'notificationScheduleStatus': 'failed',
        'notificationScheduleError': error.toString(),
        'notificationScheduleUpdatedAtMillis':
            DateTime.now().millisecondsSinceEpoch,
      });
    }
    return bookingId;
  }

  static Future<void> activateBoarding({
    required String uid,
    required String ticketId,
    required String bookingId,
    required Duration validity,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(validity);
    final bookingRef = _bookings(uid).child(bookingId);
    final snapshot = await bookingRef.get();
    final raw = snapshot.value;
    if (raw is! Map) throw StateError('This booking is no longer available.');
    final status = raw['status']?.toString();
    if (status == 'noShow' || status == 'cancelled') {
      throw StateError('This booking is no longer available for boarding.');
    }

    final updates = <String, Object?>{
      'App/BusOnDemandBookings/$uid/$bookingId/status': 'boarded',
      'App/BusOnDemandBookings/$uid/$bookingId/boardedAtMillis':
          now.millisecondsSinceEpoch,
      'App/BusOnDemandBookings/$uid/$bookingId/activatedAtMillis':
          now.millisecondsSinceEpoch,
      'App/BusOnDemandBookings/$uid/$bookingId/expiresAtMillis':
          expiresAt.millisecondsSinceEpoch,
      'App/Tickets/$uid/$ticketId/activated': true,
      'App/Tickets/$uid/$ticketId/activatedAt':
          '${now.month}/${now.day}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'App/Tickets/$uid/$ticketId/expiresAt':
          '${expiresAt.month}/${expiresAt.day}/${expiresAt.year} ${expiresAt.hour.toString().padLeft(2, '0')}:${expiresAt.minute.toString().padLeft(2, '0')}',
      'App/Tickets/$uid/$ticketId/expired': false,
      'App/Tickets/$uid/$ticketId/busBookingStatus': 'boarded',
    };
    await _database.ref().update(updates);
    await BusOnDemandNotifications.cancel(bookingId);
    await AppLocalNotifications.show(
      title: 'Bus on Demand',
      body: 'You have successfully boarded the bus.',
    );
  }

  /// Reconciles missed boarding windows whenever the user's tickets are opened.
  /// A backend worker should also run this for users who never reopen the app.
  static Future<void> reconcileNoShows(String uid) async {
    final snap = await _bookings(uid).get();
    if (snap.value is! Map) return;
    final now = DateTime.now();
    final updates = <String, Object?>{};
    for (final entry in Map<dynamic, dynamic>.from(snap.value as Map).entries) {
      if (entry.value is! Map) continue;
      final data = Map<dynamic, dynamic>.from(entry.value as Map);
      final pickupMillis = (data['scheduledPickupMillis'] as num?)?.toInt();
      final status = data['status']?.toString();
      final ticketId = data['ticketId']?.toString();
      if (pickupMillis == null || ticketId == null) continue;
      final closing = DateTime.fromMillisecondsSinceEpoch(pickupMillis)
          .add(const Duration(minutes: 10));
      final id = entry.key.toString();
      if (status == 'scheduled' &&
          !now.isBefore(DateTime.fromMillisecondsSinceEpoch(pickupMillis)) &&
          now.isBefore(closing)) {
        updates['App/BusOnDemandBookings/$uid/$id/status'] = 'driverArrived';
        updates['App/Tickets/$uid/$ticketId/busBookingStatus'] =
            'driverArrived';
      } else if ((status == 'scheduled' || status == 'driverArrived') &&
          !now.isBefore(closing)) {
        updates['App/BusOnDemandBookings/$uid/$id/status'] = 'noShow';
        updates['App/BusOnDemandBookings/$uid/$id/noShowAtMillis'] =
            now.millisecondsSinceEpoch;
        updates['App/Tickets/$uid/$ticketId/busBookingStatus'] = 'noShow';
      } else if (status == 'noShow' &&
          !now.isBefore(closing.add(const Duration(minutes: 30)))) {
        updates['App/BusOnDemandBookings/$uid/$id/hiddenAtMillis'] =
            now.millisecondsSinceEpoch;
        updates['App/Tickets/$uid/$ticketId/busHidden'] = true;
      }
    }
    if (updates.isNotEmpty) await _database.ref().update(updates);
  }
}

class BusOnDemandNotifications {
  static bool _timezoneReady = false;

  static Future<void> _ensureReady() async {
    await AppLocalNotifications.init();
    if (!_timezoneReady) {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
      _timezoneReady = true;
    }
    const channel = AndroidNotificationChannel(
      'bus_on_demand',
      'Bus on Demand',
      description: 'Bus pickup reminders and boarding updates',
      importance: Importance.high,
    );
    await AppLocalNotifications.plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static int _id(String bookingId, int event) {
    var hash = 17;
    for (final unit in bookingId.codeUnits) {
      hash = 37 * hash + unit;
    }
    return 1200000 + ((hash & 0x3fffffff) % 400000) * 10 + event;
  }

  static Future<bool> schedule({
    required String bookingId,
    required DateTime scheduledPickup,
    required String pickupLabel,
    bool requestPermissions = false,
  }) async {
    await _ensureReady();
    final notificationsEnabled = requestPermissions
        ? await AppLocalNotifications.prepareScheduledNotifications()
        : await AppLocalNotifications.scheduledNotificationsEnabled();
    if (!notificationsEnabled) return false;
    final now = DateTime.now();
    var scheduledAny = false;
    for (var lead = 30; lead >= 5; lead -= 5) {
      final when = scheduledPickup.subtract(Duration(minutes: lead));
      if (!when.isAfter(now)) continue;
      await _schedule(
        id: _id(bookingId, lead),
        when: when,
        title: 'Bus on Demand is approaching',
        body: 'Your pickup at $pickupLabel is in $lead minutes.',
      );
      scheduledAny = true;
    }
    if (scheduledPickup.isAfter(now)) {
      await _schedule(
        id: _id(bookingId, 1),
        when: scheduledPickup,
        title: 'Your driver is here',
        body:
            'Your Bus on Demand vehicle is at $pickupLabel. You have up to 10 minutes to board.',
      );
      scheduledAny = true;
    }
    final noShowAt = scheduledPickup.add(const Duration(minutes: 10));
    if (noShowAt.isAfter(now)) {
      await _schedule(
        id: _id(bookingId, 2),
        when: noShowAt,
        title: 'Bus on Demand boarding window ended',
        body:
            'The bus has left $pickupLabel because the card was not activated.',
      );
      scheduledAny = true;
    }
    return scheduledAny;
  }

  /// Replaces the stable notification IDs for outstanding bookings after an
  /// app restart or an app update. The Android boot receiver handles reboots.
  static Future<void> reschedulePendingBookings(String uid) async {
    final snapshot = await FirebaseDatabase.instance
        .ref('App/BusOnDemandBookings/$uid')
        .get();
    if (snapshot.value is! Map) return;
    final now = DateTime.now();
    for (final entry
        in Map<dynamic, dynamic>.from(snapshot.value as Map).entries) {
      if (entry.value is! Map) continue;
      final data = Map<dynamic, dynamic>.from(entry.value as Map);
      final pickupMillis = (data['scheduledPickupMillis'] as num?)?.toInt();
      final status = data['status']?.toString();
      if (pickupMillis == null ||
          (status != 'scheduled' && status != 'driverArrived')) {
        continue;
      }
      final pickup = DateTime.fromMillisecondsSinceEpoch(pickupMillis);
      if (!pickup.add(const Duration(minutes: 10)).isAfter(now)) continue;
      await schedule(
        bookingId: entry.key.toString(),
        scheduledPickup: pickup,
        pickupLabel: data['direction'] == 'stationToLocation'
            ? data['stationName']?.toString() ?? 'metro station'
            : data['locationLabel']?.toString() ?? 'pickup location',
      );
    }
  }

  static Future<void> cancel(String bookingId) async {
    await _ensureReady();
    await Future.wait([
      for (var lead = 30; lead >= 5; lead -= 5)
        AppLocalNotifications.plugin.cancel(_id(bookingId, lead)),
      AppLocalNotifications.plugin.cancel(_id(bookingId, 1)),
      AppLocalNotifications.plugin.cancel(_id(bookingId, 2)),
    ]);
  }

  static Future<void> _schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) {
    const android = AndroidNotificationDetails(
      'bus_on_demand',
      'Bus on Demand',
      channelDescription: 'Bus pickup reminders and boarding updates',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: false,
    );
    return AppLocalNotifications.plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(android: android, iOS: ios),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode:
          AppLocalNotifications.scheduledNotificationsCanBeExact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
