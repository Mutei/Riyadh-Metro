// lib/services/metro_open_close_alerts.dart
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'local_notifications.dart' show AppLocalNotifications;

/// Schedules notifications for Riyadh Metro opening/closing.
/// Hours: Sat–Thu 05:30–24:00, Fri 10:00–24:00 (midnight).
class MetroOpenCloseAlerts {
  static bool _tzInited = false;

  // Stable IDs so they can be replaced each run.
  static const int _idOpen = 10001;
  static const int _idClose60 = 20001;
  static const int _idClose45 = 20002;
  static const int _idClose30 = 20003;
  static const int _idClose15 = 20004;

  static Future<void> _ensureInit() async {
    await AppLocalNotifications.init();
    if (_tzInited) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
    _tzInited = true;
  }

  /// Public: cancel any scheduled open/close alerts.
  static Future<void> cancelAll() async {
    await _ensureInit();
    final p = AppLocalNotifications.plugin;
    await Future.wait([
      p.cancel(_idOpen),
      p.cancel(_idClose60),
      p.cancel(_idClose45),
      p.cancel(_idClose30),
      p.cancel(_idClose15),
    ]);
  }

  /// Public: schedule the next open alert and the 4 closing alerts from [nowLocal].
  /// - Open alert: 10 minutes before opening (or at opening if late)
  /// - Close alerts: 60, 45, 30, and 15 minutes before close (skip any already passed)
  static Future<void> scheduleNextPair({DateTime? nowLocal}) async {
    await _ensureInit();
    nowLocal ??= DateTime.now();

    final nextOpen = _nextOpen(nowLocal);
    final nextClose = _nextClose(nowLocal);

    // -------- Opening (single) --------
    final openLead = const Duration(minutes: 10);
    final openWhen =
        _leadOrAtEventIfLate(nextOpen, openLead, nowLocal: nowLocal);
    await _zonedOneShot(
      id: _idOpen,
      when: openWhen,
      title: 'Metro reopens soon',
      body: 'Stations open at ${_fmtClock(nextOpen)}.',
      category: AndroidNotificationCategory.reminder,
    );

    // -------- Closing (four reminders) --------
    final closers = <int, Duration>{
      _idClose60: const Duration(minutes: 60),
      _idClose45: const Duration(minutes: 45),
      _idClose30: const Duration(minutes: 30),
      _idClose15: const Duration(minutes: 15),
    };

    for (final entry in closers.entries) {
      final id = entry.key;
      final lead = entry.value;
      final when = _leadOrNull(nextClose, lead, nowLocal: nowLocal);
      if (when == null) continue; // skip if already passed
      final mins = lead.inMinutes;
      await _zonedOneShot(
        id: id,
        when: when,
        title: 'Metro closing soon',
        body: 'Stations close in $mins minutes (at ${_fmtClock(nextClose)}).',
        category: AndroidNotificationCategory.reminder,
      );
    }
  }

  // ---------- Scheduling internals ----------

  static Future<void> _zonedOneShot({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    AndroidNotificationCategory category =
        AndroidNotificationCategory.navigation,
  }) async {
    const android = AndroidNotificationDetails(
      'nav_alerts',
      'Navigation alerts',
      channelDescription: 'Metro/drive guidance, transfers and arrivals',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      category: AndroidNotificationCategory.reminder,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: false,
    );

    await AppLocalNotifications.plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(android: android, iOS: ios),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
      // 👇 THIS AVOIDS THE EXACT-ALARM PERMISSION
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Returns (event - lead) if still in the future relative to [nowLocal], else null.
  static DateTime? _leadOrNull(DateTime event, Duration lead,
      {required DateTime nowLocal}) {
    final candidate = event.subtract(lead);
    return candidate.isAfter(nowLocal) ? candidate : null;
  }

  /// Returns (event - lead) if in future, else returns the event time itself.
  /// (Used for the single opening alert so user still gets a ping even if late.)
  static DateTime _leadOrAtEventIfLate(DateTime event, Duration lead,
      {required DateTime nowLocal}) {
    final candidate = event.subtract(lead);
    return candidate.isAfter(nowLocal) ? candidate : event;
  }

  static String _fmtClock(DateTime d) {
    final h12 = (d.hour % 12 == 0) ? 12 : (d.hour % 12);
    final mm = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $ampm';
  }

  // ---------- Riyadh hours logic (self-contained) ----------

  static bool _isFriday(DateTime d) => d.weekday == DateTime.friday;

  static DateTime _openAt(DateTime day) {
    final isFri = _isFriday(day);
    final h = isFri ? 10 : 5;
    final m = isFri ? 0 : 30;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  // Closing is always at 00:00 of the *next* day (midnight).
  static DateTime _closeAt(DateTime day) {
    final nextDay = day.add(const Duration(days: 1));
    return DateTime(nextDay.year, nextDay.month, nextDay.day, 0, 0);
  }

  /// next opening strictly after [now]
  static DateTime _nextOpen(DateTime now) {
    final openToday = _openAt(now);
    final closeToday = _closeAt(now);
    if (now.isBefore(openToday)) return openToday;
    if (now.isBefore(closeToday)) {
      // currently open → next open is tomorrow
      final tomorrow = now.add(const Duration(days: 1));
      return _openAt(tomorrow);
    }
    final tomorrow = now.add(const Duration(days: 1));
    return _openAt(tomorrow);
  }

  /// next closing strictly after [now]
  static DateTime _nextClose(DateTime now) {
    final closeToday = _closeAt(now);
    if (now.isBefore(closeToday)) return closeToday;
    final tomorrow = now.add(const Duration(days: 1));
    return _closeAt(tomorrow);
  }
}
