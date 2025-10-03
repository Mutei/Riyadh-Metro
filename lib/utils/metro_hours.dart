// lib/utils/metro_hours.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MetroHours {
  // Returns true if metro is open at `now` (local Riyadh time).
  static bool isOpen(DateTime nowLocal) {
    final wd = nowLocal.weekday; // Mon=1 ... Sun=7
    final minutes = nowLocal.hour * 60 + nowLocal.minute;

    // Close always at 24:00 -> treat as 1440
    const closeMins = 24 * 60;

    if (wd == DateTime.friday) {
      // 10:00 - 24:00
      return minutes >= (10 * 60) && minutes < closeMins;
    } else {
      // 05:30 - 24:00
      final open = (5 * 60) + 30;
      return minutes >= open && minutes < closeMins;
    }
  }

  // Returns the next opening DateTime (local) if currently closed.
  static DateTime nextOpen(DateTime nowLocal) {
    DateTime d = nowLocal;
    for (int i = 0; i < 8; i++) {
      final wd = d.weekday;
      final candidate = DateTime(d.year, d.month, d.day,
          wd == DateTime.friday ? 10 : 5, wd == DateTime.friday ? 0 : 30);
      // If still today and future today, use it; else go to next day
      if (candidate.isAfter(nowLocal)) return candidate;
      d = d.add(const Duration(days: 1));
    }
    return nowLocal; // fallback (never reached)
  }

  static String dayHoursString(int weekday) {
    if (weekday == DateTime.friday) return "10:00 AM — 12:00 AM";
    return "5:30 AM — 12:00 AM";
  }

  // “Next opens in 2h 15m” pretty string
  static String untilString(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h <= 0) return "$m min";
    return "$h h ${m.toString().padLeft(2, '0')} m";
  }
}
