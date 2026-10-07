import 'package:shared_preferences/shared_preferences.dart';

enum OnboardDisplayStyle {
  stationPulse,
  originalMotion,
  trackFocus,
  liveCarriage,
}

class OnboardDisplayPreferences {
  OnboardDisplayPreferences._();

  static const _key = 'onboard_display_style';

  static Future<OnboardDisplayStyle> load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_key);
    return OnboardDisplayStyle.values.firstWhere(
      (style) => style.name == saved,
      orElse: () => OnboardDisplayStyle.stationPulse,
    );
  }

  static Future<void> save(OnboardDisplayStyle style) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, style.name);
  }
}
