import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // 1. Poproś o pozwolenie (wymagane na iOS i nowszych Androidach)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      if (kDebugMode) print('Użytkownik wyraził zgodę na powiadomienia');
    }

    // 2. Inicjalizacja dla powiadomień gdy aplikacja jest otwarta (Android)
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _localNotificationsPlugin.initialize(initializationSettings);

    // Stworzenie kanału o wysokim priorytecie (wymusza dźwięk)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', 
      'Ważne Powiadomienia',
      description: 'Ten kanał służy do pilnych powiadomień o budowach.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 3. Obsługa wiadomości gdy apka jest na wierzchu (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null && !kIsWeb) {
        _localNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'Ważne Powiadomienia',
              channelDescription: 'Ten kanał służy do pilnych powiadomień o budowach.',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
              playSound: true,
              enableVibration: true,
              styleInformation: BigTextStyleInformation(''), // Pozwala na dłuższe teksty
            ),
          ),
        );
      }
    });
  }

  // 4. Pobieranie tokenu (unikalny adres telefonu) i zapis do bazy
  Future<void> updateTokenInFirestore(String email) async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(email.trim().toLowerCase())
            .update({'fcmToken': token});
        if (kDebugMode) print('Token PUSH zaktualizowany dla: $email');
      }
    } catch (e) {
      if (kDebugMode) print('Błąd aktualizacji tokenu: $e');
    }
  }

  // 5. Metoda wysyłająca polecenie PUSH do Firestore
  // W systemie bez backendu (Node.js), najbezpieczniej jest zapisać "zlecenie wysyłki" w Firestore
  // a Google Cloud Function to podchwyci i wyśle realny sygnał.
  Future<void> sendPushRequest({
    required String targetEmail,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Pobierz token adresata
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(targetEmail.trim().toLowerCase())
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        String? token = (userDoc.data() as Map<String, dynamic>)['fcmToken'];
        
        if (token != null) {
          // Zapisujemy "prośbę o wysłanie PUSH" - system Firestore Trigger ją wyśle
          await FirebaseFirestore.instance.collection('push_requests').add({
            'to': token,
            'title': title,
            'body': body,
            'data': data ?? {},
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print('Błąd wysyłania PUSH request: $e');
    }
  }
}
