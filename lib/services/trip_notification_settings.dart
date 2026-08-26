import 'package:shared_preferences/shared_preferences.dart';

enum TripNotificationDetail { minimal, standard, detailed }

/// Persisted preferences for guidance generated while a trip is active.
class TripNotificationSettings {
  static const _detailKey = 'trip_notifications.detail';
  static const _destinationKey = 'trip_notifications.destination';
  static const _transferKey = 'trip_notifications.transfer';
  static const _progressKey = 'trip_notifications.progress';
  static const _serviceKey = 'trip_notifications.service';

  final TripNotificationDetail detail;
  final bool destinationAlerts;
  final bool transferAlerts;
  final bool progressAlerts;
  final bool serviceAlerts;

  const TripNotificationSettings({
    this.detail = TripNotificationDetail.standard,
    this.destinationAlerts = true,
    this.transferAlerts = true,
    this.progressAlerts = true,
    this.serviceAlerts = true,
  });

  bool get allowsProgress =>
      progressAlerts && detail != TripNotificationDetail.minimal;

  TripNotificationSettings copyWith({
    TripNotificationDetail? detail,
    bool? destinationAlerts,
    bool? transferAlerts,
    bool? progressAlerts,
    bool? serviceAlerts,
  }) {
    return TripNotificationSettings(
      detail: detail ?? this.detail,
      destinationAlerts: destinationAlerts ?? this.destinationAlerts,
      transferAlerts: transferAlerts ?? this.transferAlerts,
      progressAlerts: progressAlerts ?? this.progressAlerts,
      serviceAlerts: serviceAlerts ?? this.serviceAlerts,
    );
  }

  static Future<TripNotificationSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDetail = prefs.getString(_detailKey);
    final detail = TripNotificationDetail.values.firstWhere(
      (value) => value.name == savedDetail,
      orElse: () => TripNotificationDetail.standard,
    );
    return TripNotificationSettings(
      detail: detail,
      destinationAlerts: prefs.getBool(_destinationKey) ?? true,
      transferAlerts: prefs.getBool(_transferKey) ?? true,
      progressAlerts: prefs.getBool(_progressKey) ?? true,
      serviceAlerts: prefs.getBool(_serviceKey) ?? true,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_detailKey, detail.name);
    await prefs.setBool(_destinationKey, destinationAlerts);
    await prefs.setBool(_transferKey, transferAlerts);
    await prefs.setBool(_progressKey, progressAlerts);
    await prefs.setBool(_serviceKey, serviceAlerts);
  }
}
