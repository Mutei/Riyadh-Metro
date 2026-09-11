// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
//
// class AppLocalNotifications {
//   static final FlutterLocalNotificationsPlugin _plugin =
//       FlutterLocalNotificationsPlugin();
//   static bool _inited = false;
//
//   static Future<void> init() async {
//     if (_inited) return;
//     const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
//     const iosInit = DarwinInitializationSettings(
//       requestAlertPermission: true,
//       requestBadgePermission: false,
//       requestSoundPermission: true,
//     );
//     await _plugin.initialize(
//       const InitializationSettings(android: androidInit, iOS: iosInit),
//     );
//
//     // Create Android channel (id must match below).
//     const channel = AndroidNotificationChannel(
//       'nav_alerts',
//       'Navigation alerts',
//       description: 'Metro/drive guidance, transfers and arrivals',
//       importance: Importance.high,
//     );
//     await _plugin
//         .resolvePlatformSpecificImplementation<
//             AndroidFlutterLocalNotificationsPlugin>()
//         ?.createNotificationChannel(channel);
//
//     _inited = true;
//   }
//
//   static Future<void> show({
//     String? title,
//     required String body,
//   }) async {
//     await init();
//     const android = AndroidNotificationDetails(
//       'nav_alerts',
//       'Navigation alerts',
//       channelDescription: 'Metro/drive guidance, transfers and arrivals',
//       importance: Importance.high,
//       priority: Priority.high,
//       category: AndroidNotificationCategory.navigation,
//       ticker: 'nav',
//       playSound: true,
//     );
//     const ios = DarwinNotificationDetails(
//       presentAlert: true,
//       presentSound: true,
//       presentBadge: false,
//     );
//     await _plugin.show(
//       DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique id
//       title ?? 'Metro guidance',
//       body,
//       const NotificationDetails(android: android, iOS: ios),
//     );
//   }
// }
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum TripNotificationPriority { progress, important, critical }

class AppLocalNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static final Set<int> _activeTripNotificationIds = <int>{};
  static const int _ongoingTripStatusNotificationId = 900001;

  static Future<void> init() async {
    if (_inited) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Create Android channel (id must match below).
    const channel = AndroidNotificationChannel(
      'nav_alerts',
      'Navigation alerts',
      description: 'Metro/drive guidance, transfers and arrivals',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const progressChannel = AndroidNotificationChannel(
      'trip_progress',
      'Trip progress',
      description: 'Quiet updates while a metro trip is active',
      importance: Importance.defaultImportance,
      playSound: false,
    );
    const guidanceChannel = AndroidNotificationChannel(
      'trip_guidance',
      'Trip guidance',
      description: 'Important metro transfer and arrival instructions',
      importance: Importance.high,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(progressChannel);
    await android?.createNotificationChannel(guidanceChannel);

    _inited = true;
  }

  static Future<void> show({
    String? title,
    required String body,
  }) async {
    await init();
    const android = AndroidNotificationDetails(
      'nav_alerts',
      'Navigation alerts',
      channelDescription: 'Metro/drive guidance, transfers and arrivals',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.navigation,
      ticker: 'nav',
      playSound: true,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: false,
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique id
      title ?? 'Metro guidance',
      body,
      const NotificationDetails(android: android, iOS: ios),
    );
  }

  /// Shows a trip-scoped event with a stable ID so guidance can be replaced
  /// and cleared when the trip finishes without touching scheduled alerts.
  static Future<void> showTripEvent({
    required String eventKey,
    required String title,
    required String body,
    required TripNotificationPriority priority,
    Color? accentColor,
  }) async {
    await init();
    final isProgress = priority == TripNotificationPriority.progress;
    final android = AndroidNotificationDetails(
      isProgress ? 'trip_progress' : 'trip_guidance',
      isProgress ? 'Trip progress' : 'Trip guidance',
      channelDescription: isProgress
          ? 'Quiet updates while a metro trip is active'
          : 'Important metro transfer and arrival instructions',
      importance: isProgress ? Importance.defaultImportance : Importance.high,
      priority: isProgress ? Priority.defaultPriority : Priority.high,
      category: AndroidNotificationCategory.navigation,
      playSound: !isProgress,
      enableVibration: !isProgress,
      color: accentColor,
    );
    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: !isProgress,
      presentBadge: false,
    );
    final id = _tripNotificationId(eventKey);
    _activeTripNotificationIds.add(id);
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: android, iOS: ios),
    );
  }

  /// Replaces one non-dismissible status notification while a trip is active.
  /// This is deliberately separate from event alerts so it remains visible in
  /// Android's notification shade without creating a notification per update.
  static Future<void> showOngoingTripStatus({
    required String title,
    required String body,
    Color? accentColor,
    int? progress,
  }) async {
    await init();
    final normalizedProgress = progress?.clamp(0, 100).toInt();
    final android = AndroidNotificationDetails(
      'trip_progress',
      'Trip progress',
      channelDescription: 'Active metro navigation status',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      category: AndroidNotificationCategory.navigation,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      color: accentColor,
      showProgress: normalizedProgress != null,
      maxProgress: 100,
      progress: normalizedProgress ?? 0,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'Darb active trip',
      ),
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: false,
      presentBadge: false,
    );
    await _plugin.show(
      _ongoingTripStatusNotificationId,
      title,
      body,
      NotificationDetails(android: android, iOS: ios),
    );
  }

  static Future<void> clearOngoingTripStatus() async {
    await init();
    await _plugin.cancel(_ongoingTripStatusNotificationId);
  }

  static Future<void> clearTripEvents() async {
    await init();
    await Future.wait(_activeTripNotificationIds.map(_plugin.cancel));
    _activeTripNotificationIds.clear();
  }

  static int _tripNotificationId(String key) {
    var hash = 17;
    for (final unit in key.codeUnits) {
      hash = 37 * hash + unit;
    }
    return 100000 + (hash & 0x7fffffff) % 800000;
  }

  /// Expose the plugin so other services (scheduler) can schedule alarms.
  static FlutterLocalNotificationsPlugin get plugin => _plugin;
}
