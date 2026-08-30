import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../core/app_utils.dart';

class AttendanceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _oldPrefix = 'attendance_data_';

  // We will stick to the LEGACY structure to ensure no data loss:
  // Firestore: collection('attendance').doc(email) -> { "email": "...", "data": { "2023-10-27": {...} } }
  // Local: prefs.getString('attendance_data_email') -> { "2023-10-27": {...} }

  Future<Map<String, dynamic>> getLocalData(String email) async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('$_oldPrefix$email');
    if (data == null) return {};
    try {
      return json.decode(data);
    } catch (e) {
      return {};
    }
  }

  Future<void> saveLocalData(String email, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_oldPrefix$email', AppUtils.safeJsonEncode(data));
  }

  Future<void> syncWithCloud(String email) async {
    try {
      final doc = await _db.collection('attendance').doc(email.trim().toLowerCase()).get();
      if (doc.exists) {
        Map<String, dynamic> cloudDoc = doc.data() as Map<String, dynamic>;
        Map<String, dynamic> cloudData = cloudDoc['data'] ?? {};
        
        // Merge strategy: Cloud wins for existing keys, local for new ones
        final localData = await getLocalData(email);
        Map<String, dynamic> merged = {...localData, ...cloudData};
        
        await saveLocalData(email, merged);
        await _db.collection('attendance').doc(email.trim().toLowerCase()).set({
          'email': email.trim().toLowerCase(),
          'data': merged
        }, SetOptions(merge: true));
      } else {
        // Upload local if cloud doesn't exist
        final localData = await getLocalData(email);
        if (localData.isNotEmpty) {
          await _db.collection('attendance').doc(email.trim().toLowerCase()).set({
            'email': email.trim().toLowerCase(),
            'data': localData
          });
        }
      }
    } catch (e) {
      print("Sync error: $e");
    }
  }

  Future<void> updateDay(String email, String dateKey, Map<String, dynamic> dayData) async {
    final data = await getLocalData(email);
    data[dateKey] = dayData;
    await saveLocalData(email, data);
    
    // Legacy compatible update
    await _db.collection('attendance').doc(email.trim().toLowerCase()).set({
      'data': { dateKey: dayData }
    }, SetOptions(merge: true));
  }

  double calculateHours(String? start, String? end) {
    if (start == null || end == null || start.isEmpty || end.isEmpty) return 0;
    try {
      final s = start.split(':');
      final e = end.split(':');
      final sMin = int.parse(s[0]) * 60 + int.parse(s[1]);
      final eMin = int.parse(e[0]) * 60 + int.parse(e[1]);
      return eMin > sMin ? (eMin - sMin) / 60.0 : 0;
    } catch (_) {
      return 0;
    }
  }
}
