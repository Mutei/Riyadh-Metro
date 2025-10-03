import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AppLocalNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

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
}
