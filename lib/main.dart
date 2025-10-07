import 'dart:async';

import 'package:darb/screens/login_screen.dart';
import 'package:darb/screens/main_screen.dart';
import 'package:darb/screens/sign_up_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart'; // Realtime DB
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart'; // persist

import 'localization/demo_localization.dart';
import 'localization/language_constants.dart';
import 'screens/welcome_screen.dart';
import 'constants/colors.dart';

/// App-level theme choices, including the new "smart" mode.
enum AppThemeMode { light, dark, system, smart }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  final startLocale = await getLocale();

  final user = FirebaseAuth.instance.currentUser;
  final startOnMain = user != null;

  runApp(MyApp(startLocale: startLocale, startOnMain: startOnMain));
}

class MyApp extends StatefulWidget {
  final Locale startLocale;
  final bool startOnMain;

  const MyApp({
    super.key,
    required this.startLocale,
    required this.startOnMain,
  });

  /// Update UI language instantly.
  static void setLocale(BuildContext context, Locale newLocale) {
    final _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.setLocale(newLocale);
  }

  /// Backward-compatible setter for the classic 3 ThemeMode values.
  static void setThemeMode(BuildContext context, ThemeMode mode) {
    final _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    if (state == null) return;
    switch (mode) {
      case ThemeMode.light:
        state.setAppThemeMode(AppThemeMode.light);
        break;
      case ThemeMode.dark:
        state.setAppThemeMode(AppThemeMode.dark);
        break;
      case ThemeMode.system:
        state.setAppThemeMode(AppThemeMode.system);
        break;
    }
  }

  /// New: set the 4-option app theme mode (includes SMART).
  static void setAppThemeMode(BuildContext context, AppThemeMode mode) {
    final _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.setAppThemeMode(mode);
  }

  /// New: let any screen tell the app we’re “underground / in a tunnel”.
  /// While in SMART mode, this forces dark theme to reduce glare.
  static void setUnderground(BuildContext context, bool value) {
    final _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?._setUnderground(value);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Locale _locale;

  // ------------------ THEME STATE ------------------
  static const _kThemeModeKey = 'theme_mode'; // 'light'|'dark'|'system'|'smart'
  AppThemeMode _appThemeMode = AppThemeMode.system;

  // For SMART mode we compute an effective ThemeMode to pass to MaterialApp
  ThemeMode _smartEffective = ThemeMode.light;
  Timer? _smartTimer;
  bool _underground = false; // externally toggled while in tunnels/metro, etc.

  // Persist
  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kThemeModeKey) ?? 'system';
    setState(() {
      _appThemeMode = _decodeAppThemeMode(s);
    });
    // ensure smart calculation starts if needed
    _startOrStopSmartTimer();
    _recomputeSmartEffective(); // compute once initially
  }

  Future<void> _saveThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, _encodeAppThemeMode(mode));
  }

  static String _encodeAppThemeMode(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.light:
        return 'light';
      case AppThemeMode.dark:
        return 'dark';
      case AppThemeMode.system:
        return 'system';
      case AppThemeMode.smart:
        return 'smart';
    }
  }

  static AppThemeMode _decodeAppThemeMode(String s) {
    switch (s) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      case 'smart':
        return AppThemeMode.smart;
      case 'system':
      default:
        return AppThemeMode.system;
    }
  }
  // -------------------------------------------------

  @override
  void initState() {
    super.initState();
    _locale = widget.startLocale;
    _initPushNotifications();
    _loadThemeMode();
  }

  @override
  void dispose() {
    _smartTimer?.cancel();
    super.dispose();
  }

  Future<void> _initPushNotifications() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );
      debugPrint('Notification authorization: ${settings.authorizationStatus}');
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onMessage.listen((RemoteMessage m) {
        debugPrint(
            'Foreground message: ${m.notification?.title} | ${m.notification?.body}');
      });
    } catch (e) {
      debugPrint('Push init failed: $e');
    }
  }

  void setLocale(Locale newLocale) {
    if (_locale == newLocale) return;
    setState(() => _locale = newLocale);
  }

  void setAppThemeMode(AppThemeMode mode) {
    if (_appThemeMode == mode) return;
    setState(() => _appThemeMode = mode);
    _saveThemeMode(mode);
    _startOrStopSmartTimer();
    _recomputeSmartEffective();
  }

  void _setUnderground(bool v) {
    if (_underground == v) return;
    _underground = v;
    if (_appThemeMode == AppThemeMode.smart) {
      _recomputeSmartEffective();
    }
  }

  void _startOrStopSmartTimer() {
    _smartTimer?.cancel();
    if (_appThemeMode == AppThemeMode.smart) {
      // check often enough to feel responsive; light-weight computation
      _smartTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _recomputeSmartEffective();
      });
    }
  }

  /// Simple heuristic:
  /// - If "underground" is true → force dark
  /// - Else light between 06:00–18:00, dark otherwise
  void _recomputeSmartEffective() {
    ThemeMode newMode;
    if (_underground) {
      newMode = ThemeMode.dark;
    } else {
      final hour = DateTime.now().hour;
      newMode = (hour >= 6 && hour < 18) ? ThemeMode.light : ThemeMode.dark;
    }
    if (newMode != _smartEffective) {
      setState(() => _smartEffective = newMode);
    } else {
      // still request a rebuild if appThemeMode==smart and we just switched to it
      if (_appThemeMode == AppThemeMode.smart) {
        setState(() {});
      }
    }
  }

  // ---- Helpers to get a friendly first name ----
  String _fallbackFirstName(User? user) {
    final dn = user?.displayName?.trim();
    if (dn != null && dn.isNotEmpty) {
      final parts = dn.split(RegExp(r'\s+'));
      if (parts.isNotEmpty && parts.first.isNotEmpty) return parts.first;
    }
    final local = user?.email?.split('@').first;
    return (local != null && local.isNotEmpty) ? local : 'Friend';
  }

  /// Attempts to read: App/User/<uid>/FirstName from Realtime Database.
  Future<String> _getFirstName(User? user) async {
    if (user == null) return 'Friend';
    try {
      final path = 'App/User/${user.uid}/FirstName';
      final snap = await FirebaseDatabase.instance.ref(path).get();
      if (snap.exists && snap.value != null) {
        final value = snap.value.toString().trim();
        if (value.isNotEmpty) return value;
      }
    } catch (_) {}
    return _fallbackFirstName(user);
  }

  @override
  Widget build(BuildContext context) {
    // LIGHT THEME
    final lightTheme = ThemeData(
      scaffoldBackgroundColor: AppColors.kBackGroundColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.kPrimaryColor,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.interTextTheme(),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );

    // DARK THEME
    final darkTheme = ThemeData(
      scaffoldBackgroundColor: AppColors.kDarkBackgroundColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.kPrimaryColor,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );

    // Effective mode for MaterialApp (smart collapses to a real ThemeMode).
    final effectiveMode = () {
      switch (_appThemeMode) {
        case AppThemeMode.light:
          return ThemeMode.light;
        case AppThemeMode.dark:
          return ThemeMode.dark;
        case AppThemeMode.system:
          return ThemeMode.system;
        case AppThemeMode.smart:
          return _smartEffective;
      }
    }();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Darb Demo',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: effectiveMode,

      // Language
      locale: _locale,
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('ar', 'SA'),
      ],
      localizationsDelegates: const [
        DemoLocalization.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // First screen based on session
      initialRoute: widget.startOnMain ? '/mainScreen' : '/login',

      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const SignUpScreen(),
        '/mainScreen': (_) {
          final user = FirebaseAuth.instance.currentUser;
          final emailVerified = user?.emailVerified ?? false;

          return FutureBuilder<String>(
            future: _getFirstName(user),
            builder: (context, snapshot) {
              final firstName = snapshot.data ?? _fallbackFirstName(user);

              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  body: const Center(child: CircularProgressIndicator()),
                );
              }

              return MainScreen(
                firstName: firstName,
                emailVerified: emailVerified,
              );
            },
          );
        },
      },
    );
  }
}
