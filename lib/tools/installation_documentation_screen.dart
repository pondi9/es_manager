import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../core/app_utils.dart';

class InstallationDocumentationScreen extends StatefulWidget {
  final String? initialOrderId;
  const InstallationDocumentationScreen({super.key, this.initialOrderId});

  @override
  State<InstallationDocumentationScreen> createState() => _InstallationDocumentationScreenState();
}

class _InstallationDocumentationScreenState extends State<InstallationDocumentationScreen> {
  List<dynamic> _projects = [];
  bool _isLoading = true;
  final Color primaryColor = const Color(0xFF00796B);
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Pobierz z chmury
    try {
      QuerySnapshot snap = await FirebaseFirestore.instance.collection('installation_docs').get().timeout(const Duration(seconds: 5));
      _projects = snap.docs.map((doc) => doc.data()).toList();
      await prefs.setString('saved_installation_docs_v1', AppUtils.safeJsonEncode(_projects));
    } catch (_) {
      final String? localData = prefs.getString('saved_installation_docs_v1');
      if (localData != null) _projects = json.decode(localData);
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_installation_docs_v1', AppUtils.safeJsonEncode(_projects));
    
    // Synchronizacja z chmurą
    for (var p in _projects) {
      await FirebaseFirestore.instance.collection('installation_docs').doc(p['id'].toString()).set(p);
    }
  }

  void _createNewProject() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('NOWA DOKUMENTACJA'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nazwa budowy / Inwestycji'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                final newProj = {
                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                  'name': nameController.text,
                  'date': DateFormat('dd.MM.yyyy').format(DateTime.now()),
                  'rooms': [],
                };
                setState(() => _projects.insert(0, newProj));
                _saveData();
                Navigator.pop(context);
                _openProject(newProj);
              }
            },
            child: const Text('STWÓRZ'),
          ),
        ],
      ),
    );
  }

  void _openProject(Map<String, dynamic> project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => ProjectDetailScreen(
          project: project,
          onUpdate: (updated) {
            int idx = _projects.indexWhere((p) => p['id'] == updated['id']);
            if (idx != -1) {
              setState(() => _projects[idx] = updated);
              _saveData();
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('DOKUMENTACJA PODTYNKOWA'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _projects.isEmpty 
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.camera_outlined, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text('Brak dokumentacji. Kliknij +, aby dodać.', style: TextStyle(color: Colors.grey)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _projects.length,
              itemBuilder: (context, index) {
                final p = _projects[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    onTap: () => _openProject(p),
                    leading: CircleAvatar(backgroundColor: primaryColor.withOpacity(0.1), child: Icon(Icons.home_work, color: primaryColor)),
                    title: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Data: ${p['date']} | Pomieszczeń: ${(p['rooms'] as List).length}'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewProject,
        backgroundColor: primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class ProjectDetailScreen extends StatefulWidget {
  final Map<String, dynamic> project;
  final Function(Map<String, dynamic>) onUpdate;

  const ProjectDetailScreen({super.key, required this.project, required this.onUpdate});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  Map<String, dynamic> _localProject = {};
  final String _proxy = "https://weserv.nl/?url=";

  @override
  void initState() {
    super.initState();
    _localProject = Map<String, dynamic>.from(widget.project);
  }

  void _addRoom() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DODAJ POMIESZCZENIE'),
        content: TextField(controller: c, decoration: const InputDecoration(hintText: 'np. Salon, Kuchnia, Garaż')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
          ElevatedButton(onPressed: () {
            if (c.text.isNotEmpty) {
              setState(() {
                _localProject['rooms'].add({'name': c.text, 'photos': []});
              });
              widget.onUpdate(_localProject);
              Navigator.pop(context);
            }
          }, child: const Text('DODAJ')),
        ],
      ),
    );
  }

  Future<void> _addPhoto(int roomIdx) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 40);
    
    if (image != null) {
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
      try {
        final fileName = 'doc_${_localProject['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final storageRef = FirebaseStorage.instance.ref().child('installation_docs/$fileName');
        if (kIsWeb) {
          await storageRef.putData(await image.readAsBytes());
        } else {
          await storageRef.putFile(File(image.path));
        }
        final url = await storageRef.getDownloadURL();
        
        setState(() {
          _localProject['rooms'][roomIdx]['photos'].add({
            'url': url,
            'desc': '',
            'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
          });
        });
        widget.onUpdate(_localProject);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd: $e')));
      }
    }
  }

  Future<void> _generatePdf() async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.white), SizedBox(height: 10), Text('Pobieranie zdjęć do raportu...', style: TextStyle(color: Colors.white))])));

    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.notoSansRegular();
      final fontBold = await PdfGoogleFonts.notoSansBold();

      // Pobieranie obrazów do pamięci
      Map<String, pw.MemoryImage> imageCache = {};
      for (var room in _localProject['rooms']) {
        for (var photo in room['photos']) {
          String url = photo['url'];
          if (!imageCache.containsKey(url)) {
            try {
              final String finalUrl = kIsWeb ? '$_proxy${Uri.encodeComponent(url)}' : url;
              final response = await http.get(Uri.parse(finalUrl)).timeout(const Duration(seconds: 10));
              if (response.statusCode == 200) {
                imageCache[url] = pw.MemoryImage(response.bodyBytes);
              }
            } catch (e) {
              debugPrint("Błąd pobierania zdjęcia do PDF: $e");
            }
          }
        }
      }

      if (mounted) Navigator.pop(context); // Zamknij loading

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(bottom: 15),
          child: pw.Text('RAPORT PRZEBIEGU INSTALACJI - ${_localProject['name']}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ),
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('DOKUMENTACJA PODTYNKOWA: ${_localProject['name'].toUpperCase()}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
          pw.Text('Data wygenerowania: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 20),
          
          ...(_localProject['rooms'] as List).map((room) {
            final List photos = room['photos'] ?? [];
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  width: double.infinity,
                  decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                  child: pw.Text(room['name'].toUpperCase(), style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12)),
                ),
                pw.SizedBox(height: 10),
                if (photos.isEmpty)
                  pw.Padding(padding: const pw.EdgeInsets.only(bottom: 20), child: pw.Text('Brak zdjęć.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)))
                else
                  pw.Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: photos.map((photo) {
                      final img = imageCache[photo['url']];
                      return pw.Container(
                        width: 250, // Dwa zdjęcia w rzędzie
                        padding: const pw.EdgeInsets.all(5),
                        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300, width: 0.5), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5))),
                        child: pw.Column(
                          children: [
                            if (img != null) 
                              pw.Container(height: 180, child: pw.Image(img, fit: pw.BoxFit.contain))
                            else
                              pw.Container(height: 100, child: pw.Center(child: pw.Text('Błąd ładowania zdjęcia', style: const pw.TextStyle(fontSize: 8)))),
                            pw.SizedBox(height: 5),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('Data: ${photo['date']}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                                if (photo['desc'].toString().isNotEmpty) 
                                  pw.Text(photo['desc'], style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)),
                              ]
                            )
                          ]
                        )
                      );
                    }).toList(),
                  ),
                pw.SizedBox(height: 20),
              ]
            );
          }).toList(),
        ],
        footer: (context) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Strona ${context.pageNumber} | Wygenerowano z ES CRM', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600))),
      ));

      await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Dokumentacja_${_localProject['name']}.pdf');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd generowania PDF: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_localProject['name']),
        backgroundColor: const Color(0xFF00796B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _generatePdf),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: (_localProject['rooms'] as List).length,
        itemBuilder: (context, rIdx) {
          final room = _localProject['rooms'][rIdx];
          return Card(
            margin: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  tileColor: Colors.teal.withOpacity(0.05),
                  title: Text(room['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: IconButton(icon: const Icon(Icons.add_a_photo, color: Colors.teal), onPressed: () => _addPhoto(rIdx)),
                ),
                if (room['photos'].isEmpty)
                  const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Brak zdjęć w tym pomieszczeniu.', style: TextStyle(fontSize: 11, color: Colors.grey))))
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(10),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                    itemCount: room['photos'].length,
                    itemBuilder: (context, pIdx) {
                      final photo = room['photos'][pIdx];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              kIsWeb ? 'https://images.weserv.nl/?url=${Uri.encodeComponent(photo['url'])}&w=300&h=300&fit=cover' : photo['url'],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              loadingBuilder: (c, w, p) => p == null ? w : const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                              errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                          Positioned(
                            right: 0, top: 0,
                            child: IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                              onPressed: () {
                                setState(() {
                                  _localProject['rooms'][rIdx]['photos'].removeAt(pIdx);
                                });
                                widget.onUpdate(_localProject);
                              },
                            ),
                          )
                        ],
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRoom,
        backgroundColor: Colors.teal[800],
        icon: const Icon(Icons.add_home, color: Colors.white),
        label: const Text('DODAJ POMIESZCZENIE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
