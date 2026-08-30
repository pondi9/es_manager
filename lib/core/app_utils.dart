import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AppUtils {
  /// Bezpieczne kodowanie do JSON obsługujące Timestamp i DateTime
  static String safeJsonEncode(dynamic data) {
    try {
      return json.encode(data, toEncodable: (item) {
        if (item is Timestamp) {
          return item.toDate().toIso8601String();
        }
        if (item is DateTime) {
          return item.toIso8601String();
        }
        return item.toString();
      });
    } catch (e) {
      return json.encode(data.toString());
    }
  }

  /// Wysyła powiadomienie do Firestore
  static Future<void> sendNotification({
    required String title,
    required String content,
    required String target,
    required String author,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'title': title,
      'content': content,
      'target': target,
      'author': author,
      'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'isArchived': false,
    });
  }
}
