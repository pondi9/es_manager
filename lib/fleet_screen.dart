import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'core/app_utils.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'services/cloud_sync_service.dart';

class FleetScreen extends StatefulWidget {
  final bool isAdmin;
  final String currentUserEmail;
  const FleetScreen({super.key, required this.isAdmin, required this.currentUserEmail});

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  final _picker = ImagePicker();
  
  bool _isTracking = false;
  double _tripDistance = 0;
  Position? _lastPos;
  int? _trackingVehicleIndex;
  StreamSubscription<Position>? _positionStream;

  final Color primaryColor = const Color(0xFF263238);
  final Color accentColor = const Color(0xFF455A64);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    try { 
      await CloudSyncService().downloadFleet(widget.currentUserEmail, widget.isAdmin).timeout(const Duration(seconds: 8)); 
    } catch (_) {}

    // FRESH LOAD of employees to ensure names are available on mobile
    try {
      final empSnap = await FirebaseFirestore.instance.collection('employees').get();
      if (empSnap.docs.isNotEmpty) {
        _employees = empSnap.docs.map((d) {
          var data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();
      }
    } catch (e) {
      debugPrint("Fleet name mapping error: $e");
      // Fallback to local
      final String? empData = prefs.getString('user_permissions');
      if (empData != null) {
        try {
          List<dynamic> decoded = json.decode(empData);
          _employees = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {}
      }
    }

    final String? fleetData = prefs.getString('company_fleet_v1');
    if (fleetData != null && fleetData.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(fleetData);
        _vehicles = decoded.map((v) => Map<String, dynamic>.from(v)).toList();
      } catch (_) {}
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
      _checkExpirations();
    }
  }

  Future<void> _checkExpirations() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final String? noteData = prefs.getString('company_notifications_v2');
    List<Map<String, dynamic>> notes = noteData != null ? List<Map<String, dynamic>>.from(json.decode(noteData)) : [];
    bool changed = false;

    for (var v in _vehicles) {
      final plate = v['plate'] ?? '';
      final owner = v['owner'] ?? 'admin';
      
      // Check Insurance
      if (v['insuranceDate'] != null && v['insuranceDate'].toString().isNotEmpty) {
        try {
          DateTime d = DateFormat('dd.MM.yyyy').parse(v['insuranceDate']);
          int days = d.difference(now).inDays;
          if (days <= 7 && days >= -1) {
            String title = "KOŃCZY SIĘ OC: $plate";
            if (!notes.any((n) => n['title'] == title && n['date'].toString().startsWith(DateFormat('dd.MM').format(now)))) {
              notes.insert(0, {
                'title': title,
                'content': 'Ubezpieczenie pojazdu ${v['brand']} ($plate) wygasa za $days dni (${v['insuranceDate']}).',
                'date': DateFormat('dd.MM HH:mm').format(now),
                'target': 'admin',
                'isRead': false, 'isArchived': false, 'author': 'System Flota'
              });
              changed = true;
            }
          }
        } catch (_) {}
      }

      // Check Inspection
      if (v['inspectionDate'] != null && v['inspectionDate'].toString().isNotEmpty) {
        try {
          DateTime d = DateFormat('dd.MM.yyyy').parse(v['inspectionDate']);
          int days = d.difference(now).inDays;
          if (days <= 7 && days >= -1) {
            String title = "KOŃCZY SIĘ PRZEGLĄD: $plate";
            if (!notes.any((n) => n['title'] == title && n['date'].toString().startsWith(DateFormat('dd.MM').format(now)))) {
              notes.insert(0, {
                'title': title,
                'content': 'Przegląd techniczny pojazdu ${v['brand']} ($plate) wygasa za $days dni (${v['inspectionDate']}).',
                'date': DateFormat('dd.MM HH:mm').format(now),
                'target': 'admin',
                'isRead': false, 'isArchived': false, 'author': 'System Flota'
              });
              changed = true;
            }
          }
        } catch (_) {}
      }
    }

    if (changed) {
      await prefs.setString('company_notifications_v2', AppUtils.safeJsonEncode(notes));
      await CloudSyncService().uploadNotifications();
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_fleet_v1', AppUtils.safeJsonEncode(_vehicles));
    try { await CloudSyncService().uploadFleet(widget.currentUserEmail); } catch (_) {}
  }

  String _getName(String? email) {
    if (email == null || email.isEmpty || email == 'brak') return "-";
    final String sMail = email.trim().toLowerCase();
    if (sMail == 'admin') return "Marcin Kiczek";
    
    try {
      final emp = _employees.firstWhere(
        (e) => (e['email'] ?? '').toString().toLowerCase() == sMail || (e['id'] ?? '').toString().toLowerCase() == sMail, 
        orElse: () => {}
      );
      
      if (emp.isEmpty) return email;
      String fn = "${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}".trim();
      if (fn.isNotEmpty) return fn;
      if (emp['displayName'] != null && emp['displayName'].toString().isNotEmpty) return emp['displayName'];
      return email;
    } catch (_) { return email; }
  }

  void _toggleTrip(int index) async {
    if (_isTracking) {
      if (_trackingVehicleIndex != index) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zakończ najpierw trasę w innym aucie!')));
        return;
      }
      
      _positionStream?.cancel();
      double drivenKm = _tripDistance / 1000.0;
      final kmController = TextEditingController(text: drivenKm.toStringAsFixed(1));

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('ZAKOŃCZONO TRASĘ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Przejechany dystans (GPS): ${drivenKm.toStringAsFixed(2)} km'),
              const SizedBox(height: 15),
              TextField(
                controller: kmController,
                decoration: const InputDecoration(labelText: 'Skoryguj km (jeśli potrzeba)', suffixText: 'km'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () { setState(() { _isTracking = false; _tripDistance = 0; _lastPos = null; _trackingVehicleIndex = null; }); Navigator.pop(ctx); }, child: const Text('ANULUJ')),
            ElevatedButton(
              onPressed: () async {
                double finalKm = double.tryParse(kmController.text.replaceAll(',', '.')) ?? drivenKm;
                setState(() {
                  double currentMileage = _getVNum(_vehicles[index]['mileage']);
                  _vehicles[index]['mileage'] = currentMileage + finalKm;
                  if (_vehicles[index]['history'] == null) _vehicles[index]['history'] = [];
                  (_vehicles[index]['history'] as List).add({
                    'type': 'LICZNIK', 'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
                    'action': 'Trasa GPS: +${finalKm.toStringAsFixed(1)} km', 'cost': '0', 'km': (_vehicles[index]['mileage'] as double).round(),
                    'author': widget.currentUserEmail
                  });
                  _isTracking = false; _tripDistance = 0; _lastPos = null; _trackingVehicleIndex = null;
                });
                await _saveData();
                Navigator.pop(ctx);
              }, 
              child: const Text('DOPISZ DO LICZNIKA')
            ),
          ],
        )
      );
    } else {
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) { p = await Geolocator.requestPermission(); if (p == LocationPermission.denied) return; }
      if (p == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Brak uprawnień do lokalizacji! Włącz je w ustawieniach telefonu.')));
        return;
      }

      setState(() { _isTracking = true; _tripDistance = 0; _trackingVehicleIndex = index; });
      
      final androidSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "ES CRM rejestruje Twoją trasę w tle...",
          notificationTitle: "Pomiar trasy GPS",
          enableWakeLock: true,
        )
      );

      _positionStream = Geolocator.getPositionStream(locationSettings: androidSettings).listen((pos) {
        if (_lastPos != null) {
          double dist = Geolocator.distanceBetween(_lastPos!.latitude, _lastPos!.longitude, pos.latitude, pos.longitude);
          // Only add distance if movement is significant (avoids GPS "drift" when standing still)
          if (dist > 3.0) setState(() => _tripDistance += dist);
        }
        _lastPos = pos;
      });
    }
  }

  double _getVNum(dynamic val) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  void _updateMileage(int index) {
    double current = _getVNum(_vehicles[index]['mileage']);
    final mc = TextEditingController(text: current.round().toString());
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('STAN LICZNIKA'), 
      content: TextField(controller: mc, decoration: const InputDecoration(labelText: 'km'), keyboardType: TextInputType.number), 
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ANULUJ')),
        ElevatedButton(onPressed: () async {
          double? nm = double.tryParse(mc.text);
          if (nm != null) {
            setState(() {
              _vehicles[index]['mileage'] = nm;
              if (_vehicles[index]['history'] == null) _vehicles[index]['history'] = [];
              (_vehicles[index]['history'] as List).add({'type': 'LICZNIK', 'date': DateFormat('dd.MM HH:mm').format(DateTime.now()), 'action': 'Aktualizacja ręczna', 'cost': '0', 'km': nm.round()});
            });
            await _saveData();
          }
          Navigator.pop(ctx);
        }, child: const Text('ZAPISZ'))
      ]
    ));
  }

  Future<void> _exportFleetPdf({Map<String, dynamic>? singleVehicle}) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final vList = singleVehicle != null ? [singleVehicle] : _vehicles;
    for (var v in vList) {
      List h = List.from(v['history'] ?? []);
      pdf.addPage(pw.MultiPage(theme: pw.ThemeData.withFont(base: font, bold: fontBold), build: (ctx) => [
        pw.Header(level: 0, child: pw.Text('${v['brand'] ?? ''} ${v['model'] ?? ''} (${v['plate'] ?? ''})', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
        pw.TableHelper.fromTextArray(
          headers: ['Data', 'Typ', 'Opis', 'KM', 'Koszt'], 
          data: h.reversed.map((e) {
            String desc = (e['action'] ?? '').toString();
            // Fix legacy typos
            desc = desc.replaceAll("wystaMiea", "wystawienia");
            desc = desc.replaceAll("fakliry", "faktury");
            
            return [e['date'] ?? '', e['type'] ?? '', desc, '${e['km'] ?? ''}', '${e['cost'] ?? ''}'];
          }).toList()
        )
      ]));
    }
    Navigator.push(context, MaterialPageRoute(builder: (c) => Scaffold(appBar: AppBar(title: const Text('RAPORT PDF')), body: PdfPreview(build: (f) => pdf.save()))));
  }

  void _showVehicleDialog({Map<String, dynamic>? vehicle, int? index}) {
    final bc = TextEditingController(text: vehicle?['brand'] ?? ''); final mc = TextEditingController(text: vehicle?['model'] ?? '');
    final pc = TextEditingController(text: vehicle?['plate'] ?? ''); final mic = TextEditingController(text: _getVNum(vehicle?['mileage']).round().toString());
    final icDate = TextEditingController(text: vehicle?['insuranceDate'] ?? '');
    final insDate = TextEditingController(text: vehicle?['inspectionDate'] ?? '');
    
    String? so = vehicle?['owner'] ?? (widget.isAdmin ? 'brak' : widget.currentUserEmail);
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDS) => AlertDialog(title: Text(vehicle == null ? 'DODAJ POJAZD' : 'EDYTUJ'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: bc, decoration: const InputDecoration(labelText: 'Marka')), TextField(controller: mc, decoration: const InputDecoration(labelText: 'Model')),
      TextField(controller: pc, decoration: const InputDecoration(labelText: 'Tablice')),
      TextField(controller: mic, decoration: const InputDecoration(labelText: 'Przebieg'), keyboardType: TextInputType.number),
      
      const SizedBox(height: 10),
      TextField(
        controller: icDate, 
        decoration: const InputDecoration(labelText: 'Ważność ubezpieczenia', suffixIcon: Icon(Icons.calendar_today, size: 16)), 
        readOnly: true,
        onTap: () async {
          DateTime? p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
          if (p != null) setDS(() => icDate.text = DateFormat('dd.MM.yyyy').format(p));
        },
      ),
      TextField(
        controller: insDate, 
        decoration: const InputDecoration(labelText: 'Ważność przeglądu', suffixIcon: Icon(Icons.calendar_today, size: 16)), 
        readOnly: true,
        onTap: () async {
          DateTime? p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
          if (p != null) setDS(() => insDate.text = DateFormat('dd.MM.yyyy').format(p));
        },
      ),

      if (widget.isAdmin) DropdownButtonFormField<String>(value: so, items: [ const DropdownMenuItem(value: 'brak', child: Text('MAGAZYN')), ..._employees.map((e) => DropdownMenuItem(value: e['email'], child: Text(e['firstName'] ?? e['email']))) ], onChanged: (v) => so = v),
    ])), actions: [
      if (vehicle != null) TextButton(onPressed: () { setState(() => _vehicles.removeAt(index!)); _saveData(); Navigator.pop(ctx); }, child: const Text('USUŃ', style: TextStyle(color: Colors.red))),
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ANULUJ')),
      ElevatedButton(onPressed: () {
        final d = Map<String, dynamic>.from(vehicle ?? {});
        d['brand'] = bc.text; d['model'] = mc.text; d['plate'] = pc.text.toUpperCase(); d['mileage'] = double.tryParse(mic.text) ?? 0.0; 
        d['owner'] = so;
        d['insuranceDate'] = icDate.text;
        d['inspectionDate'] = insDate.text;
        setState(() { if (index == null) _vehicles.add(d); else _vehicles[index] = d; });
        _saveData(); Navigator.pop(ctx);
      }, child: const Text('ZAPISZ'))
    ])));
  }

  void _showHistoryDialog(int vIndex) {
    final v = _vehicles[vIndex];
    bool isMine = v['owner']?.toString().toLowerCase() == widget.currentUserEmail.toLowerCase() || v['isPrivate'] == true;
    String sf = 'WSZYSTKO';
    
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDS) {
      List hList = List.from(v['history'] ?? []);
      if (sf != 'WSZYSTKO') hList = hList.where((h) => h['type'] == sf).toList();
      
      return AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text('HISTORIA: ${v['plate']}', overflow: TextOverflow.ellipsis)),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
              onPressed: () => _exportFleetPdf(singleVehicle: v),
              tooltip: 'Drukuj historię pojazdu',
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.isAdmin || isMine) Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: () => _addHistoryEntry(vIndex, onAdded: (_) => setDS((){})), icon: const Icon(Icons.add), label: const Text('WPIS'))),
            const SizedBox(width: 8),
            ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], foregroundColor: Colors.white), onPressed: () => _addDamageEntry(vIndex, onAdded: (_) => setDS((){})), icon: const Icon(Icons.warning_amber), label: const Text('SZKODA')),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.speed, color: Colors.blue), onPressed: () { Navigator.pop(context); _updateMileage(vIndex); })
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: sf, 
            decoration: const InputDecoration(labelText: 'Filtr', border: OutlineInputBorder()),
            items: ['WSZYSTKO', 'NAPRAWY', 'SERWIS', 'TANKOWANIE', 'OLEJ', 'SZKODA', 'LICZNIK'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(), 
            onChanged: (val) => setDS(() => sf = val!)
          ),
          const Divider(),
          Expanded(child: hList.isEmpty 
            ? const Center(child: Text('Brak wpisów.')) 
            : ListView.builder(itemCount: hList.length, itemBuilder: (context, i) {
                final h = hList[hList.length - 1 - i];
                
                List<String> phs = [];
                try {
                  dynamic raw = h['photoUrls'] ?? h['photoUrl'] ?? h['photos'] ?? [];
                  if (raw is List) phs = raw.map((u) => u.toString()).where((u) => u.startsWith('http')).toList();
                  else if (raw is String && raw.startsWith('http')) phs = [raw];
                } catch(_) {}

                IconData ic = Icons.build_outlined; Color clr = Colors.grey;
                if (h['type'] == 'TANKOWANIE') { ic = Icons.local_gas_station; clr = Colors.green; } 
                else if (h['type'] == 'OLEJ') { ic = Icons.oil_barrel; clr = Colors.orange; } 
                else if (h['type'] == 'PRZEGLĄD') { ic = Icons.fact_check; clr = Colors.blue; } 
                else if (h['type'] == 'LICZNIK') { ic = Icons.speed; clr = Colors.indigo; }
                else if (h['type'] == 'SZKODA') { ic = Icons.gavel_rounded; clr = Colors.red[900]!; }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0, color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        leading: Icon(ic, color: clr, size: 22),
                        title: Text(h['action'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${h['date']} | ${h['km']} km | ${h['cost']} zł${h['liters'] != null && h['liters'].toString().isNotEmpty ? ' | ${h['liters']} L' : ''}', 
                          style: const TextStyle(fontSize: 10)
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.isAdmin || isMine) IconButton(
                              icon: const Icon(Icons.edit_note, color: Colors.blueGrey, size: 20), 
                              onPressed: () => _addHistoryEntry(vIndex, existingEntry: h, onAdded: (_) => setDS(() {}))
                            ),
                            if (widget.isAdmin || isMine) IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18), 
                              onPressed: () => _deleteHistoryEntry(vIndex, h, () => setDS(() {}))
                            ),
                          ],
                        ),
                        onTap: () => _showEntryDetails(h),
                      ),
                      if (phs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Wrap(
                            spacing: 8, runSpacing: 8,
                            children: phs.map((url) {
                              final String displayUrl = kIsWeb ? 'https://images.weserv.nl/?url=${Uri.encodeComponent(url)}&w=200' : url;
                              return GestureDetector(
                                onTap: () => _showPhotoPreview(url),
                                child: Container(
                                  width: 80, height: 60,
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!), color: Colors.grey[50]),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: Image.network(
                                      displayUrl, fit: BoxFit.cover,
                                      loadingBuilder: (c, child, p) => p == null ? child : const Center(child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))),
                                      errorBuilder: (c,e,s) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        const Icon(Icons.broken_image, size: 16, color: Colors.grey),
                                        TextButton(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), child: const Text('OTWÓRZ', style: TextStyle(fontSize: 7)))
                                      ]),
                                    )
                                  )
                                )
                              );
                            }).toList(),
                          ),
                        )
                    ],
                  ),
                );
              })
          )
        ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ZAMKNIJ'))]);
    }));
  }

  void _showEntryDetails(Map<String, dynamic> h) {
    List<String> phs = [];
    try {
      dynamic raw = h['photoUrls'] ?? h['photoUrl'] ?? h['photos'] ?? [];
      if (raw is List) phs = raw.map((u) => u.toString()).where((u) => u.startsWith('http')).toList();
      else if (raw is String && raw.startsWith('http')) phs = [raw];
    } catch(_) {}

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(h['type'] ?? 'WPIS'), 
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Opis: ${h['action']}', style: const TextStyle(fontWeight: FontWeight.bold)), 
        Text('Data: ${h['date']}'), 
        Text('Koszt: ${h['cost']} zł'),
        Text('Przebieg: ${h['km']} km'),
        if (h['liters'] != null && h['liters'].toString().isNotEmpty) Text('Ilość paliwa: ${h['liters']} L'),
        if (h['fault'] != null) Text('Wina: ${h['fault']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        if (h['repairInfo'] != null && h['repairInfo'].toString().isNotEmpty) Text('Naprawa: ${h['repairInfo']}'),
        if (phs.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 15), child: Wrap(spacing: 8, runSpacing: 8, children: phs.map((u) {
          final String displayUrl = kIsWeb ? 'https://images.weserv.nl/?url=${Uri.encodeComponent(u)}&w=400' : u;
          return GestureDetector(onTap: () => _showPhotoPreview(u), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(displayUrl, height: 100, width: 100, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.broken_image))));
        }).toList()))
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
  }

  void _addHistoryEntry(int vIndex, {Map<String, dynamic>? existingEntry, required Function(List) onAdded}) {
    final actc = TextEditingController(text: existingEntry?['action'] ?? ''); 
    final coc = TextEditingController(text: existingEntry?['cost']?.toString() ?? '');
    final kmc = TextEditingController(text: existingEntry?['km']?.toString() ?? _getVNum(_vehicles[vIndex]['mileage']).round().toString());
    final litc = TextEditingController(text: existingEntry?['liters']?.toString() ?? '');
    String type = existingEntry?['type'] ?? 'SERWIS';
    List<String> phs = List<String>.from(existingEntry?['photoUrls'] ?? []);
    bool isUpl = false;

    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDS) => AlertDialog(title: const Text('NOWY WPIS'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(value: type, items: ['SERWIS', 'NAPRAWY', 'TANKOWANIE', 'OLEJ', 'PRZEGLĄD'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (v) => setDS(() => type = v!), decoration: const InputDecoration(labelText: 'Kategoria')),
      TextField(controller: actc, decoration: const InputDecoration(labelText: 'Opis')),
      TextField(controller: coc, decoration: const InputDecoration(labelText: 'Koszt (zł)'), keyboardType: TextInputType.number),
      TextField(controller: kmc, decoration: const InputDecoration(labelText: 'Licznik (km)'), keyboardType: TextInputType.number),
      if (type == 'TANKOWANIE') TextField(controller: litc, decoration: const InputDecoration(labelText: 'Ilość litrów (l)', suffixText: 'L'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 10),
      if (type == 'TANKOWANIE' && phs.isEmpty) ...[
        ElevatedButton.icon(
          onPressed: () async {
            final XFile? img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);
            if (img != null) {
              setDS(() => isUpl = true);
              try {
                final inputImage = InputImage.fromFilePath(img.path);
                final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
                final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
                String fullText = recognizedText.text;
                
                // Smart extraction
                RegExp costRegex = RegExp(r'(TOTAL|SUMA|PLN|RAZEM|TOTAL\s*PLN)[:\s]*(\d+[\.,]\d{2})', caseSensitive: false);
                RegExp dateRegex = RegExp(r'(\d{4}-\d{2}-\d{2})|(\d{2}\.\d{2}\.\d{4})');
                RegExp litersRegex = RegExp(r'(\d+[\.,]\d{2,3})\s*(L|litr|litrów|ltr)', caseSensitive: false);
                
                var costMatch = costRegex.firstMatch(fullText);
                var dateMatch = dateRegex.firstMatch(fullText);
                var litersMatch = litersRegex.firstMatch(fullText);
                
                if (costMatch != null) coc.text = costMatch.group(2)!.replaceAll(',', '.');
                if (litersMatch != null) litc.text = litersMatch.group(1)!.replaceAll(',', '.');

                String detectedDate = dateMatch != null ? dateMatch.group(0)! : DateFormat('dd.MM.yyyy').format(DateTime.now());
                actc.text = "Data wystawienia faktury: $detectedDate";

                final fn = 'fuel_${DateTime.now().millisecondsSinceEpoch}.jpg';
                final ref = FirebaseStorage.instance.ref().child('fleet/$fn');
                if (kIsWeb) await ref.putData(await img.readAsBytes()); else await ref.putFile(File(img.path));
                final url = await ref.getDownloadURL();
                setDS(() { phs.add(url); });
                textRecognizer.close();
              } catch (e) { print("OCR Error: $e"); }
              setDS(() => isUpl = false);
            }
          }, 
          icon: const Icon(Icons.document_scanner), 
          label: const Text("SKANUJ PARAGON"),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[700], foregroundColor: Colors.white),
        ),
        const SizedBox(height: 10),
      ],
      Row(children: [ 
        const Text('ZDJĘCIA:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), const Spacer(), 
        IconButton(icon: const Icon(Icons.add_a_photo, size: 20), onPressed: () async {
          final src = await showDialog<ImageSource>(context: context, builder: (ctx) => AlertDialog(title: const Text('ŹRÓDŁO'), actions: [ TextButton(onPressed: () => Navigator.pop(ctx, ImageSource.gallery), child: const Text('GALERIA')), TextButton(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: const Text('APARAT')) ]));
          if (src != null) { final img = await _picker.pickImage(source: src, imageQuality: 40); if (img != null) { setDS(() => isUpl = true); final fn = 'fleet_${DateTime.now().millisecondsSinceEpoch}.jpg'; final ref = FirebaseStorage.instance.ref().child('fleet/$fn'); if (kIsWeb) await ref.putData(await img.readAsBytes()); else await ref.putFile(File(img.path)); final url = await ref.getDownloadURL(); setDS(() { phs.add(url); isUpl = false; }); } }
        }) 
      ]),
      if (isUpl) const CircularProgressIndicator() else Wrap(spacing: 4, children: phs.map((url) => Stack(children: [ Image.network(url, height: 45, width: 45, fit: BoxFit.cover), Positioned(right: 0, top: 0, child: GestureDetector(onTap: () => setDS(() => phs.remove(url)), child: Container(color: Colors.black54, child: const Icon(Icons.close, size: 12, color: Colors.white)))) ])).toList())
    ])), actions: [ TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')), ElevatedButton(onPressed: isUpl ? null : () {
      if (actc.text.isNotEmpty || type == 'TANKOWANIE') {
        final en = { 
          'type': type, 
          'date': existingEntry?['date'] ?? DateFormat('dd.MM.yyyy').format(DateTime.now()), 
          'action': actc.text.isEmpty && type == 'TANKOWANIE' ? "Tankowanie" : actc.text, 
          'cost': coc.text, 
          'km': int.tryParse(kmc.text) ?? 0, 
          'liters': litc.text.replaceAll(',', '.'),
          'photoUrls': phs,
          'author': widget.currentUserEmail
        };
        setState(() {
          if (_vehicles[vIndex]['history'] == null) _vehicles[vIndex]['history'] = [];
          List h = _vehicles[vIndex]['history'] as List;
          if (existingEntry != null) { 
            // Znajdź wpis po dacie i km (unikalność) lub po prostu podmień jeśli to ten sam obiekt
            int idx = h.indexWhere((item) => item == existingEntry);
            if (idx != -1) h[idx] = en; else h.add(en);
          } else {
            h.add(en);
          }
          
          double newKm = _getVNum(kmc.text);
          if (newKm > _getVNum(_vehicles[vIndex]['mileage'])) {
            _vehicles[vIndex]['mileage'] = newKm;
          }
        });
        _saveData(); onAdded([]); Navigator.pop(context);
      }
    }, child: const Text('ZAPISZ')) ])));
  }

  void _addDamageEntry(int vIndex, {Map<String, dynamic>? existingEntry, required Function(List) onAdded}) {
    final descC = TextEditingController(text: existingEntry?['action'] ?? '');
    final costC = TextEditingController(text: existingEntry?['cost']?.toString() ?? '');
    final kmc = TextEditingController(text: existingEntry?['km']?.toString() ?? _getVNum(_vehicles[vIndex]['mileage']).round().toString());
    final faultC = TextEditingController(text: existingEntry?['fault'] ?? '');
    final repairC = TextEditingController(text: existingEntry?['repairInfo'] ?? '');
    List<String> phs = List<String>.from(existingEntry?['photoUrls'] ?? []);
    bool isUpl = false;

    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDS) => AlertDialog(
      title: const Text('ZGŁOŚ SZKODĘ'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: descC, decoration: const InputDecoration(labelText: 'Opis uszkodzeń')),
        TextField(controller: faultC, decoration: const InputDecoration(labelText: 'Z czyjej winy?')),
        TextField(controller: costC, decoration: const InputDecoration(labelText: 'Wycena / Naprawa'), keyboardType: TextInputType.number),
        TextField(controller: kmc, decoration: const InputDecoration(labelText: 'Licznik (km)'), keyboardType: TextInputType.number),
        TextField(controller: repairC, decoration: const InputDecoration(labelText: 'Info o naprawie')),
        const SizedBox(height: 15),
        IconButton(icon: const Icon(Icons.add_a_photo), onPressed: () async {
          final src = await showDialog<ImageSource>(context: context, builder: (ctx) => AlertDialog(title: const Text('ŹRÓDŁO'), actions: [ TextButton(onPressed: () => Navigator.pop(ctx, ImageSource.gallery), child: const Text('GALERIA')), TextButton(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: const Text('APARAT')) ]));
          if (src != null) { final img = await _picker.pickImage(source: src, imageQuality: 30); if (img != null) { setDS(() => isUpl = true); final fn = 'damage_${DateTime.now().millisecondsSinceEpoch}.jpg'; final ref = FirebaseStorage.instance.ref().child('fleet/damages/$fn'); if (kIsWeb) await ref.putData(await img.readAsBytes()); else await ref.putFile(File(img.path)); final url = await ref.getDownloadURL(); setDS(() { phs.add(url); isUpl = false; }); } }
        }),
        if (isUpl) const CircularProgressIndicator() else Wrap(spacing: 4, children: phs.map((u) => Image.network(u, height: 40, width: 40, fit: BoxFit.cover)).toList())
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
        ElevatedButton(onPressed: isUpl ? null : () {
          if (descC.text.isNotEmpty) {
            final en = { 'type': 'SZKODA', 'date': DateFormat('dd.MM.yyyy').format(DateTime.now()), 'action': descC.text, 'cost': costC.text, 'km': int.tryParse(kmc.text) ?? 0, 'fault': faultC.text, 'repairInfo': repairC.text, 'photoUrls': phs, 'author': widget.currentUserEmail };
            setState(() {
              if (_vehicles[vIndex]['history'] == null) _vehicles[vIndex]['history'] = [];
              if (existingEntry != null) { int idx = (_vehicles[vIndex]['history'] as List).indexOf(existingEntry); (_vehicles[vIndex]['history'] as List)[idx] = en; } else { (_vehicles[vIndex]['history'] as List).add(en); }
            });
            _saveData(); Navigator.pop(context);
          }
        }, child: const Text('ZAPISZ'))
      ]
    )));
  }

  void _deleteHistoryEntry(int vIndex, dynamic entry, VoidCallback onDeleted) async {
    final bool? confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('USUNĄĆ?'), content: const Text('Trwale usunąć ten wpis?'), actions: [ TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ANULUJ')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('USUŃ', style: TextStyle(color: Colors.white))) ]));
    if (confirm == true) { setState(() { (_vehicles[vIndex]['history'] as List).remove(entry); }); await _saveData(); onDeleted(); }
  }

  void _showPhotoPreview(String url) { 
    final String displayUrl = kIsWeb ? 'https://images.weserv.nl/?url=${Uri.encodeComponent(url)}&w=1200' : url;
    showDialog(context: context, builder: (c) => Dialog(backgroundColor: Colors.transparent, child: Stack(children: [ Image.network(displayUrl, fit: BoxFit.contain, errorBuilder: (c,e,s) => const Center(child: Text("Błąd ładowania zdjęcia podglądu", style: TextStyle(color: Colors.white)))), Positioned(top: 10, right: 10, child: CircleAvatar(backgroundColor: Colors.black45, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(c)))) ]))); 
  }

  Widget _buildOilBadge(Map<String, dynamic> v) {
    List history = v['history'] as List? ?? [];
    double currentKm = _getVNum(v['mileage']);
    
    // Szukaj ostatniego wpisu typu OLEJ
    var oilEntries = history.where((e) => e['type'] == 'OLEJ').toList();
    if (oilEntries.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
        child: const Text('OLEJ: BRAK DANYCH', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
      );
    }

    // Sortuj po dacie (najnowszy na końcu)
    oilEntries.sort((a, b) => (a['km'] ?? 0).compareTo(b['km'] ?? 0));
    var lastOil = oilEntries.last;
    double lastOilKm = _getVNum(lastOil['km']);
    double nextOilKm = lastOilKm + 15000; // Zakładamy 15 tyś km
    double remaining = nextOilKm - currentKm;

    Color badgeColor = Colors.green;
    if (remaining < 2000) badgeColor = Colors.orange;
    if (remaining < 500) badgeColor = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: badgeColor.withOpacity(0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NASTĘPNY OLEJ: ${nextOilKm.round()} km', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeColor)),
          Text('Zostało: ${remaining.round()} km', style: TextStyle(fontSize: 8, color: badgeColor.withOpacity(0.8))),
        ],
      ),
    );
  }

  Widget _buildConsumptionBadge(Map<String, dynamic> v) {
    List history = v['history'] as List? ?? [];
    // Filtrujemy tylko tankowania z podaną ilością litrów
    var fuelEntries = history.where((e) => 
      e['type'] == 'TANKOWANIE' && 
      e['liters'] != null && 
      e['liters'].toString().isNotEmpty &&
      _getVNum(e['liters']) > 0
    ).toList();

    if (fuelEntries.length < 2) {
      // Jeśli mamy tylko jedno tankowanie z litrami, nie da się obliczyć spalania (potrzebny dystans między dwoma punktami)
      return const SizedBox(); 
    }

    // Sortujemy chronologicznie według przebiegu
    fuelEntries.sort((a, b) => _getVNum(a['km']).compareTo(_getVNum(b['km'])));
    
    double firstKm = _getVNum(fuelEntries.first['km']);
    double lastKm = _getVNum(fuelEntries.last['km']);
    double totalKm = lastKm - firstKm;

    if (totalKm <= 0) return const SizedBox();

    double totalLiters = 0;
    // Sumujemy wszystkie litry OPRÓCZ pierwszego tankowania (zakładamy tankowanie do pełna)
    // Bo pierwsze tankowanie wyznacza moment startowy przebiegu, a spalanie mierzymy litrami dodanymi później
    for (int i = 1; i < fuelEntries.length; i++) {
        totalLiters += _getVNum(fuelEntries[i]['liters']);
    }
    
    if (totalLiters <= 0) return const SizedBox();
    
    double avg = (totalLiters / totalKm) * 100;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1), 
        borderRadius: BorderRadius.circular(8), 
        border: Border.all(color: Colors.green.withOpacity(0.5))
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed, size: 10, color: Colors.green),
          const SizedBox(width: 4),
          Text(
            'ŚR. SPALANIE: ${avg.toStringAsFixed(1)} l/100km', 
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green)
          ),
        ],
      ),
    );
  }

  Widget _buildDateBadge(String label, String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return const SizedBox();
    try {
      DateTime d = DateFormat('dd.MM.yyyy').parse(dateStr);
      int days = d.difference(DateTime.now()).inDays;
      Color c = days < 0 ? Colors.red : (days < 7 ? Colors.orange : Colors.blueGrey);
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: c.withOpacity(0.3))),
        child: Text('$label: $dateStr ${days < 0 ? "(PO TERMINIE)" : ""}', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: c)),
      );
    } catch (_) { return const SizedBox(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], 
      appBar: AppBar(
        title: const Text('FLOTA / POJAZDY'), 
        backgroundColor: primaryColor, 
        foregroundColor: Colors.white, 
        actions: [ 
          IconButton(
            icon: const Icon(Icons.sync), 
            onPressed: () async {
              setState(() => _isLoading = true);
              await CloudSyncService().downloadFleet(widget.currentUserEmail, widget.isAdmin);
              await _loadData();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dane floty zsynchronizowane!')));
            },
            tooltip: 'Synchronizuj z chmurą',
          ),
          if (widget.isAdmin) IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: () => _exportFleetPdf()) 
        ]
      ),
      body: Column(
        children: [
          if (_isTracking)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.orange[800],
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white, size: 24),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TRWA POMIAR TRASY GPS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                        Text('Pojazd: ${_vehicles[_trackingVehicleIndex!]['brand']} | Dystans: ${(_tripDistance / 1000).toStringAsFixed(2)} km', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _toggleTrip(_trackingVehicleIndex!),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red[900]),
                    child: const Text('ZAKOŃCZ', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator()) 
              : ListView.builder(
                  itemCount: _vehicles.length, 
                  itemBuilder: (ctx, i) {
                    final v = _vehicles[i];
                    double currentMileage = _getVNum(v['mileage']);
                    bool isThisTracking = _isTracking && _trackingVehicleIndex == i;
                    bool isMine = v['owner']?.toString().toLowerCase() == widget.currentUserEmail.toLowerCase() || v['isPrivate'] == true;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), 
                      child: Column(
                        children: [
                          ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.directions_car)),
                            title: Text('${v['brand']} ${v['model']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${v['plate']} | ${currentMileage.round()} km | Opiekun: ${_getName(v['owner'])}'),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    _buildOilBadge(v),
                                    _buildConsumptionBadge(v),
                                  ],
                                ),
                                Row(
                                  children: [
                                    _buildDateBadge("OC", v['insuranceDate']),
                                    const SizedBox(width: 8),
                                    _buildDateBadge("PRZEGLĄD", v['inspectionDate']),
                                  ],
                                ),
                              ],
                            ),
                            onTap: () => _showHistoryDialog(i),
                            trailing: widget.isAdmin ? IconButton(icon: const Icon(Icons.settings), onPressed: () => _showVehicleDialog(vehicle: v, index: i)) : null,
                          ),
                          if (isMine || widget.isAdmin)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _toggleTrip(i),
                                      icon: Icon(isThisTracking ? Icons.stop : Icons.play_arrow),
                                      label: Text(isThisTracking ? 'STOP GPS' : 'START TRASA GPS'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isThisTracking ? Colors.red[900] : Colors.blue[800],
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () => _showHistoryDialog(i),
                                    icon: const Icon(Icons.history, color: Colors.blueGrey),
                                    tooltip: 'Historia',
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    );
                  }
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showVehicleDialog(), child: const Icon(Icons.add)),
    );
  }
}
