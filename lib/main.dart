// lib/main.dart
import 'package:darb/screens/login_screen.dart';
import 'package:darb/screens/main_screen.dart';
import 'package:darb/screens/sign_up_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart'; // Realtime DB
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'localization/demo_localization.dart';
import 'localization/language_constants.dart';
import 'screens/welcome_screen.dart'; // keep if you use it elsewhere
import 'constants/colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Firebase Init

  final startLocale = await getLocale(); // load saved locale before runApp

  // Persisted session check (user stays signed in after restart)
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

  /// Call this from anywhere (e.g., your Language screen) to update the UI language instantly.
  static void setLocale(BuildContext context, Locale newLocale) {
    final _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.setLocale(newLocale);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Locale _locale;

  @override
  void initState() {
    super.initState();
    _locale = widget.startLocale;
  }

  void setLocale(Locale newLocale) {
    if (_locale == newLocale) return; // avoid redundant rebuilds
    setState(() {
      _locale = newLocale;
    });
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
  /// Falls back to displayName/email if not found.
  Future<String> _getFirstName(User? user) async {
    if (user == null) return 'Friend';
    try {
      final path = 'App/User/${user.uid}/FirstName';
      final snap = await FirebaseDatabase.instance.ref(path).get();
      if (snap.exists && snap.value != null) {
        final value = snap.value.toString().trim();
        if (value.isNotEmpty) return value;
      }
    } catch (_) {
      // Ignore and fall back gracefully
    }
    return _fallbackFirstName(user);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      scaffoldBackgroundColor: AppColors.kBackGroundColor,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.kPrimaryColor),
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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Darb Demo',
      theme: theme,

      // 👇 Runtime language switch: this is updated by MyApp.setLocale(context, newLocale)
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

      // No need for localeResolutionCallback since we explicitly control `locale`.
      // Flutter will rebuild and reload strings whenever `_locale` changes.

      // Decide first screen based on whether a user session exists
      initialRoute: widget.startOnMain ? '/mainScreen' : '/login',

      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const SignUpScreen(),

        // ---- Build MainScreen with first name fetched from DB ----
        '/mainScreen': (_) {
          final user = FirebaseAuth.instance.currentUser;
          final emailVerified = user?.emailVerified ?? false;

          // Use FutureBuilder to fetch first name from Realtime DB
          return FutureBuilder<String>(
            future: _getFirstName(user),
            builder: (context, snapshot) {
              final firstName =
                  snapshot.data ?? _fallbackFirstName(user); // safe fallback

              // While loading, you can show a lightweight splash
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  backgroundColor: AppColors.kBackGroundColor,
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
