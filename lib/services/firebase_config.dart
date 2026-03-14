import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';

/// Firebase configuration for Dudh Passbook
/// Matches website Firebase config for sync compatibility
class DefaultFirebaseConfig {
  /// Get platform-specific Firebase options
  static FirebaseOptions get platformOptions {
    if (kIsWeb) {
      return _webOptions;
    }
    
    // Android platform options
    if (!kIsWeb && Platform.isAndroid) {
      return _androidOptions;
    }
    
    // Fallback to web options
    return _webOptions;
  }

  /// Android platform options (from google-services.json)
  static const FirebaseOptions _androidOptions = FirebaseOptions(
    apiKey: "AIzaSyBQm8P73_XrH1wfHA2ChUJ0GSnrWH1xNQI",
    appId: "1:21967386098:android:eec16eb0e4446b55f8676b",
    messagingSenderId: "21967386098",
    projectId: "my-diray-83de8",
    storageBucket: "my-diray-83de8.firebasestorage.app",
  );

  /// Web platform options
  static const FirebaseOptions _webOptions = FirebaseOptions(
    apiKey: "AIzaSyD1W2CAr3Wr4EB2PAFjkr5sTmCtshoVsRs",
    authDomain: "my-diray-83de8.firebaseapp.com",
    projectId: "my-diray-83de8",
    storageBucket: "my-diray-83de8.firebasestorage.app",
    messagingSenderId: "21967386098",
    appId: "1:21967386098:web:367463a16fcd237bf8676b",
    measurementId: "G-27TDW0XF71",
  );

  /// Initialize Firebase
  static Future<void> initialize() async {
    await Firebase.initializeApp(options: platformOptions);
  }
}
