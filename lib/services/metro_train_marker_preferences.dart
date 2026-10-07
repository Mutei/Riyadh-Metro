import 'package:shared_preferences/shared_preferences.dart';

enum MetroTrainMarkerStyle { classic, lineSpecific, directional3d }

class MetroTrainMarkerPreferences {
  MetroTrainMarkerPreferences._();

  static const _key = 'metro_train_marker_style';

  static Future<MetroTrainMarkerStyle> load() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(_key)) {
      'line_specific' => MetroTrainMarkerStyle.lineSpecific,
      'directional_3d' => MetroTrainMarkerStyle.directional3d,
      _ => MetroTrainMarkerStyle.classic,
    };
  }

  static Future<void> save(MetroTrainMarkerStyle style) async {
    final preferences = await SharedPreferences.getInstance();
    final value = switch (style) {
      MetroTrainMarkerStyle.classic => 'classic',
      MetroTrainMarkerStyle.lineSpecific => 'line_specific',
      MetroTrainMarkerStyle.directional3d => 'directional_3d',
    };
    await preferences.setString(_key, value);
  }
}
