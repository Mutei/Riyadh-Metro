// lib/firebase_options.dart
// Manually authored Firebase configs (web + mobile)
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios; // if you also run on macOS, duplicate or adjust as needed
      default:
        return web; // Fallback
    }
  }

  /// ---- WEB ----
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBablaLaSLIWeDFJEzRDSBtiXfSBjGI9iY',
    appId:
        '1:142282943904:web:31cd8f760717c3e4b548c5', // e.g. 1:1234567890:android:abc123def456
    projectId: 'darb-911fc',
    authDomain: "darb-911fc.firebaseapp.com",
    storageBucket: 'darb-911fc.firebasestorage.app',
    messagingSenderId: '142282943904',
    databaseURL: 'https://darb-911fc-default-rtdb.firebaseio.com/',
  );

  /// ---- ANDROID ----
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBablaLaSLIWeDFJEzRDSBtiXfSBjGI9iY',
    appId:
        '1:142282943904:web:31cd8f760717c3e4b548c5', // e.g. 1:1234567890:android:abc123def456
    projectId: 'darb-911fc',
    storageBucket: 'darb-911fc.firebasestorage.app',
    messagingSenderId: '142282943904',
    databaseURL: 'https://darb-911fc-default-rtdb.firebaseio.com/',
  );

  /// ---- iOS ----
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBablaLaSLIWeDFJEzRDSBtiXfSBjGI9iY',
    appId:
        '1:142282943904:web:31cd8f760717c3e4b548c5', // e.g. 1:1234567890:ios:abc123def456
    projectId: 'darb-911fc',
    storageBucket: 'darb-911fc.firebasestorage.app',
    messagingSenderId: '142282943904',
    // iosBundleId: 'com.your.bundleid', // match your iOS bundle id
    databaseURL: 'https://darb-911fc-default-rtdb.firebaseio.com/',
  );
}
