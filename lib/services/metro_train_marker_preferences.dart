import 'package:shared_preferences/shared_preferences.dart';

enum MetroTrainMarkerStyle { classic, lineSpecific }

class MetroTrainMarkerPreferences {
  MetroTrainMarkerPreferences._();

  static const _key = 'metro_train_marker_style';

  static Future<MetroTrainMarkerStyle> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key) == 'line_specific'
        ? MetroTrainMarkerStyle.lineSpecific
        : MetroTrainMarkerStyle.classic;
  }

  static Future<void> save(MetroTrainMarkerStyle style) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      style == MetroTrainMarkerStyle.lineSpecific ? 'line_specific' : 'classic',
    );
  }
}
