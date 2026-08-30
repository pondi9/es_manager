import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../core/app_utils.dart';

class CloudSyncService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> deleteEmployee(String email) async {
    String ce = email.trim().toLowerCase();
    await _db.collection('employees').doc(ce).delete();
    await _db.collection('attendance').doc(ce).delete();
  }
  Future<void> deleteOrder(String id) async { await _db.collection('orders').doc(id).delete(); }

  Future<void> uploadEmployees() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('user_permissions');
    if (data == null) return;
    List<dynamic> emps = json.decode(data);
    for (var e in emps) { await _db.collection('employees').doc(e['email'].toString().trim().toLowerCase()).set(e); }
  }
  Future<void> downloadEmployees() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('employees').get();
      List<Map<String, dynamic>> emps = s.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
      await prefs.setString('user_permissions', AppUtils.safeJsonEncode(emps));
    } catch (_) {}
  }

  Future<void> uploadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('company_notifications_v2');
    if (data == null) return;
    List<dynamic> notes = json.decode(data);
    for (var n in notes.take(100)) {
      String timeId = n['timestamp']?.toString().replaceAll(RegExp(r'[^0-9]'), "") ?? 
                      n['date'].toString().replaceAll(RegExp(r'[^0-9]'), "");
      String id = n['id'] ?? "${n['author']}_$timeId";
      await _db.collection('notifications').doc(id).set(n);
    }
  }

  Future<void> markAllNotificationsAsRead(String userEmail) async {
    try {
      final String email = userEmail.trim().toLowerCase();
      QuerySnapshot s = await _db.collection('notifications')
          .where('isRead', isEqualTo: false)
          .get();

      WriteBatch batch = _db.batch();
      bool hasUpdates = false;

      for (var doc in s.docs) {
        Map<String, dynamic> n = doc.data() as Map<String, dynamic>;
        String target = (n['target'] ?? "").toString().toLowerCase();
        
        if (target == 'all' || target == email || (email == 'admin' && target == 'admin')) {
          batch.update(doc.reference, {'isRead': true});
          hasUpdates = true;
        }
      }
      if (hasUpdates) await batch.commit();
    } catch (_) {}
  }

  Future<void> clearChatNotifications(String userEmail) async {
    try {
      final String email = userEmail.trim().toLowerCase();
      QuerySnapshot s = await _db.collection('notifications')
          .where('title', isEqualTo: 'NOWA WIADOMOŚĆ')
          .where('isRead', isEqualTo: false)
          .get();

      WriteBatch batch = _db.batch();
      bool hasUpdates = false;

      for (var doc in s.docs) {
        Map<String, dynamic> n = doc.data() as Map<String, dynamic>;
        String target = (n['target'] ?? "").toString().toLowerCase();
        
        if (target == 'all' || target == email || (email == 'admin' && target == 'admin')) {
          batch.update(doc.reference, {'isRead': true});
          hasUpdates = true;
        }
      }
      if (hasUpdates) await batch.commit();
    } catch (_) {}
  }

  Future<void> uploadAssignments(List<Map<String, dynamic>> assignments) async {
    for (var a in assignments) {
      await _db.collection('assignments').doc(a['id']).set(a);
    }
  }

  Future<void> downloadAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('assignments').get();
      List<Map<String, dynamic>> items = s.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      await prefs.setString('company_assignments_v1', AppUtils.safeJsonEncode(items));
    } catch (_) {}
  }
  
  Future<void> deleteNotification(Map<String, dynamic> n) async {
    try { String id = "${n['author']}_${n['date']}".replaceAll(" ", "_").replaceAll(".", "").replaceAll(":", ""); await _db.collection('notifications').doc(id).delete(); } catch (_) {}
  }

  Future<void> downloadNotifications(String email, bool isAdmin, String group) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('notifications').orderBy('date', descending: true).limit(40).get();
      List<dynamic> notes = s.docs.map((doc) => doc.data()).toList();
      await prefs.setString('company_notifications_v2', AppUtils.safeJsonEncode(notes));
    } catch (_) {}
  }

  Future<void> downloadWarehouseOrders() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('warehouse').get();
      List<Map<String, dynamic>> orders = s.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // ENSURE ID IS PRESENT
        return data;
      }).toList();
      await prefs.setString('warehouse_orders_v1', AppUtils.safeJsonEncode(orders));
    } catch (_) {}
  }

  Future<void> uploadWarehouseOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('warehouse_orders_v1');
    if (data == null) return;
    List<dynamic> orders = json.decode(data);
    for (var o in orders) {
      String id = o['id'] ?? "${o['author']}_${o['date']}".replaceAll(" ", "_").replaceAll(".", "").replaceAll(":", "");
      o['id'] = id; // ENSURE ID IS IN DATA
      await _db.collection('warehouse').doc(id).set(o);
    }
  }

  Future<void> deleteWarehouseOrder(Map<String, dynamic> o) async {
    try {
      String id = o['id'] ?? "${o['author']}_${o['date']}".replaceAll(" ", "_").replaceAll(".", "").replaceAll(":", "");
      await _db.collection('warehouse').doc(id).delete();
    } catch (_) {}
  }

  Future<void> deleteVehicleFromCloud(String plate, bool isPrivate, String ownerEmail) async {
    try {
      if (isPrivate) {
        await _db.collection('private_fleet').doc("${ownerEmail.trim().toLowerCase()}_$plate").delete();
      } else {
        await _db.collection('fleet').doc(plate.toString().toUpperCase()).delete();
      }
    } catch (_) {}
  }

  Future<void> deleteExpense(String id) async { await _db.collection('expenses').doc(id).delete(); }
  Future<void> deleteClient(String id) async { await _db.collection('clients').doc(id).delete(); }
  Future<void> deleteTool(String id) async { await _db.collection('tools').doc(id).delete(); }
  Future<void> deleteProtocol(String id) async { await _db.collection('protocols').doc(id).delete(); }

  Future<void> downloadKnowledgeBase() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      DocumentSnapshot d = await _db.collection('settings').doc('knowledge_base').get();
      if (d.exists) { await prefs.setString('knowledge_base_data_v1', AppUtils.safeJsonEncode((d.data() as Map<String, dynamic>)['data'])); }
    } catch (_) {}
  }

  Future<void> uploadKnowledgeBase() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('knowledge_base_data_v1');
    if (data == null) return;
    await _db.collection('settings').doc('knowledge_base').set({'data': json.decode(data)});
  }

  Future<void> uploadDbLabels() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('saved_db_labels_v2');
    if (data == null) return;
    List<dynamic> projects = json.decode(data);
    for (var p in projects) { await _db.collection('switchboards').doc(p['id'].toString()).set(p); }
  }

  Future<void> downloadDbLabels() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('switchboards').get();
      List<Map<String, dynamic>> prots = s.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      await prefs.setString('saved_db_labels_v2', AppUtils.safeJsonEncode(prots));
    } catch (_) {}
  }

  Future<void> uploadLanLabels() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('saved_lan_labels_v1');
    if (data == null) return;
    List<dynamic> projects = json.decode(data);
    for (var p in projects) { await _db.collection('lan_labels').doc(p['id'].toString()).set(p); }
  }

  Future<void> downloadLanLabels() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('lan_labels').get();
      List<Map<String, dynamic>> prots = s.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      await prefs.setString('saved_lan_labels_v1', AppUtils.safeJsonEncode(prots));
    } catch (_) {}
  }

  Future<void> uploadOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('company_orders_v2');
    if (data == null) return;
    List<dynamic> orders = json.decode(data);
    for (var o in orders) { 
      int photoCount = 0;
      if (o['stages'] != null) {
        for (var s in (o['stages'] as List)) {
          if (s['photos'] != null) photoCount += (s['photos'] as List).length;
        }
      }
      debugPrint("DIAGNOSTYKA: UPLOAD ORDER TO FIRESTORE ID: ${o['id']}");
      debugPrint("DIAGNOSTYKA: PHOTOS SENT TO FIRESTORE: $photoCount");
      await _db.collection('orders').doc(o['id'].toString()).set(o); 
    }
  }
  Future<void> downloadOrders() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('orders').get();
      List<Map<String, dynamic>> orders = s.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
      await prefs.setString('company_orders_v2', AppUtils.safeJsonEncode(orders));
    } catch (_) {}
  }

  Future<void> uploadTools() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('company_tools_v1');
    if (data == null) return;
    List<dynamic> tools = json.decode(data);
    for (var t in tools) { await _db.collection('tools').doc(t['id'].toString()).set(t); }
  }

  Future<void> downloadTools() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('tools').get();
      List<Map<String, dynamic>> tools = s.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
      await prefs.setString('company_tools_v1', AppUtils.safeJsonEncode(tools));
    } catch (_) {}
  }

  Future<void> uploadClients() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('company_clients');
    if (data == null) return;
    List<dynamic> clients = json.decode(data);
    for (var c in clients) { await _db.collection('clients').doc(c['id'] ?? c['name']).set(c); }
  }

  Future<void> uploadProtocols() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('company_protocols_v1');
    if (data == null) return;
    List<dynamic> prots = json.decode(data);
    for (var p in prots) { await _db.collection('protocols').doc(p['id'].toString()).set(p); }
  }

  Future<void> uploadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('company_expenses_v1');
    if (data == null) return;
    List<dynamic> exps = json.decode(data);
    for (var e in exps) {
      String id = e['id'] ?? "${e['author']}_${e['date']}".replaceAll(" ", "_");
      await _db.collection('expenses').doc(id).set(e);
    }
  }

  Future<void> downloadClients() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('clients').get();
      List<Map<String, dynamic>> clients = s.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
      await prefs.setString('company_clients', AppUtils.safeJsonEncode(clients));
    } catch (_) {}
  }

  Future<void> downloadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('expenses').get();
      List<Map<String, dynamic>> exps = s.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
      await prefs.setString('company_expenses_v1', AppUtils.safeJsonEncode(exps));
    } catch (_) {}
  }

  Future<void> downloadProtocols() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('protocols').get();
      List<Map<String, dynamic>> prots = s.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
      await prefs.setString('company_protocols_v1', AppUtils.safeJsonEncode(prots));
    } catch (_) {}
  }

  Future<void> downloadFleet(String email, bool isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot cs = await _db.collection('fleet').get();
      List<Map<String, dynamic>> av = cs.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      
      QuerySnapshot ps;
      if (isAdmin) {
        // Admin sees all private vehicles too
        ps = await _db.collection('private_fleet').get();
      } else {
        ps = await _db.collection('private_fleet').where('owner', isEqualTo: email.trim().toLowerCase()).get();
      }
      av.addAll(ps.docs.map((doc) => doc.data() as Map<String, dynamic>));

      if (av.isNotEmpty) {
        await prefs.setString('company_fleet_v1', AppUtils.safeJsonEncode(av));
      }
    } catch (_) {}
  }

  Future<void> uploadFleet(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('company_fleet_v1');
    if (data == null) return;
    List<dynamic> fleet = json.decode(data);
    String ce = email.trim().toLowerCase();
    for (var v in fleet) {
      if (v['isPrivate'] == true) { await _db.collection('private_fleet').doc("${ce}_${v['plate']}").set(v); }
      else { await _db.collection('fleet').doc(v['plate'].toString().toUpperCase()).set(v); }
    }
  }

  Future<void> downloadSchematics() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      QuerySnapshot s = await _db.collection('schematics').get();
      List<Map<String, dynamic>> items = s.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      await prefs.setString('saved_schematics_v2', AppUtils.safeJsonEncode(items));
    } catch (_) {}
  }

  // --- NEW: Dashboard Persistent Settings ---
  Future<void> uploadDashboardSettings(String email, {List<String>? tileOrder, Map<String, bool>? visibility, List<dynamic>? folders}) async {
    try {
      final String ce = email.trim().toLowerCase();
      final Map<String, dynamic> settings = {};
      if (tileOrder != null) settings['tileOrder'] = tileOrder;
      if (visibility != null) settings['visibility'] = visibility;
      if (folders != null) settings['customFolders'] = folders;
      
      await _db.collection('employees').doc(ce).set({
        'dashboard_settings': settings
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Failed to upload dashboard settings: $e");
    }
  }

  Future<void> downloadDashboardSettings(String email) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final String ce = email.trim().toLowerCase();
      DocumentSnapshot doc = await _db.collection('employees').doc(ce).get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        final settings = data['dashboard_settings'] as Map<String, dynamic>?;
        
        if (settings != null) {
          if (settings['tileOrder'] != null) {
            await prefs.setStringList('tile_order_$ce', List<String>.from(settings['tileOrder']));
          }
          if (settings['visibility'] != null) {
            final Map<String, dynamic> vis = Map<String, dynamic>.from(settings['visibility']);
            vis.forEach((id, val) async {
              await prefs.setBool('tile_visible_${id}_$ce', val as bool);
            });
          }
          if (settings['customFolders'] != null) {
            await prefs.setString('custom_folders_$ce', AppUtils.safeJsonEncode(settings['customFolders']));
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to download dashboard settings: $e");
    }
  }

  Future<void> updateMaterialOrderStatus(String orderId, String materialOrderId, String newStatus) async {
    try {
      final docRef = _db.collection('orders').doc(orderId);
      final doc = await docRef.get();
      if (doc.exists) {
        List materials = List.from(doc.data()?['material_orders'] ?? []);
        int idx = materials.indexWhere((m) => m['id'] == materialOrderId);
        if (idx != -1) {
          materials[idx]['status'] = newStatus;
          await docRef.update({'material_orders': materials});
        }
      }
    } catch (e) {
      debugPrint("Error updating material status in cloud: $e");
    }
  }

  Future<void> updateMaterialOrderItems(String orderId, String materialOrderId, String itemsText, List itemsStructured) async {
    try {
      final docRef = _db.collection('orders').doc(orderId);
      final doc = await docRef.get();
      if (doc.exists) {
        List materials = List.from(doc.data()?['material_orders'] ?? []);
        int idx = materials.indexWhere((m) => m['id'] == materialOrderId);
        if (idx != -1) {
          materials[idx]['items'] = itemsText;
          materials[idx]['items_structured'] = itemsStructured;
          await docRef.update({'material_orders': materials});
        }
      }
    } catch (e) {
      debugPrint("Error updating material items in cloud: $e");
    }
  }

  // --- NEW: App Update Checker ---
  Future<Map<String, dynamic>?> checkLatestVersion() async {
    try {
      DocumentSnapshot doc = await _db.collection('settings').doc('app_version').get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<void> updateRemoteVersion(String version, String downloadUrl) async {
    try {
      await _db.collection('settings').doc('app_version').set({
        'version': version,
        'downloadUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // --- NEW: Global Company & SMTP Settings ---
  Future<void> uploadCompanySettings(Map<String, dynamic> data) async {
    try {
      await _db.collection('settings').doc('company_info').set(data);
    } catch (e) {
      debugPrint("Error uploading company settings: $e");
    }
  }

  Future<Map<String, dynamic>?> downloadCompanySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      DocumentSnapshot doc = await _db.collection('settings').doc('company_info').get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        // Save to local prefs for offline/immediate use
        if (data['name'] != null) await prefs.setString('comp_name', data['name']);
        if (data['nip'] != null) await prefs.setString('comp_nip', data['nip']);
        if (data['address'] != null) await prefs.setString('comp_address', data['address']);
        if (data['bank'] != null) await prefs.setString('comp_bank', data['bank']);
        if (data['smtp'] != null) await prefs.setString('smtp_settings', AppUtils.safeJsonEncode(data['smtp']));
        return data;
      }
    } catch (e) {
      debugPrint("Error downloading company settings: $e");
    }
    return null;
  }
}
