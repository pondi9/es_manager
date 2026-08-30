import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB5XcaI7irXPcqVLMR52lihP-9iaJWTOwI',
    appId: '1:898105514236:web:87543533c9be02da05df79',
    messagingSenderId: '898105514236',
    projectId: 'es-manager-crm',
    authDomain: 'es-manager-crm.firebaseapp.com',
    storageBucket: 'es-manager-crm.firebasestorage.app',
    measurementId: 'G-RQ3HKVHGVX',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB5XcaI7irXPcqVLMR52lihP-9iaJWTOwI',
    appId: '1:898105514236:android:ce9e6587c69992d905df79', // Wygenerowane na podstawie nazwy paczki
    messagingSenderId: '898105514236',
    projectId: 'es-manager-crm',
    storageBucket: 'es-manager-crm.firebasestorage.app',
  );
}
