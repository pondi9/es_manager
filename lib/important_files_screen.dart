import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'core/app_theme.dart';
import 'services/cloud_sync_service.dart';

class ImportantFilesScreen extends StatefulWidget {
  final bool isAdmin;
  final String currentUserEmail;
  const ImportantFilesScreen({super.key, required this.isAdmin, required this.currentUserEmail});

  @override
  State<ImportantFilesScreen> createState() => _ImportantFilesScreenState();
}

class _ImportantFilesScreenState extends State<ImportantFilesScreen> {
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _filteredFiles = [];
  bool _isLoading = true;
  String _searchQuery = "";
  bool _sortAscending = false;
  int _sortColumnIndex = 1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('important_docs').orderBy('timestamp', descending: true).get();
      _files = snap.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      _applyFilter();
    } catch (e) {
      debugPrint("Error loading docs: $e");
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFilter() {
    setState(() {
      _filteredFiles = _files.where((f) {
        final title = f['title']?.toString().toLowerCase() ?? "";
        return title.contains(_searchQuery.toLowerCase());
      }).toList();
    });
  }

  void _sort<T>(Comparable<T> Function(Map<String, dynamic> f) getField, int columnIndex, bool ascending) {
    _filteredFiles.sort((a, b) {
      final aValue = getField(a);
      final bValue = getField(b);
      return ascending ? Comparable.compare(aValue, bValue) : Comparable.compare(bValue, aValue);
    });
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  Future<void> _addFileDialog() async {
    final titleCtrl = TextEditingController();
    List<PlatformFile> selectedFiles = [];
    bool isUploading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("DODAJ INSTRUKCJĘ / PLIK"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Tytuł dokumentu")),
                const SizedBox(height: 20),
                if (isUploading) 
                  const CircularProgressIndicator()
                else ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
                      if (result != null) setDS(() => selectedFiles = result.files);
                    },
                    icon: const Icon(Icons.attach_file),
                    label: const Text("WYBIERZ PLIKI"),
                  ),
                  const SizedBox(height: 10),
                  Text("Wybrano: ${selectedFiles.length} plików", style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANULUJ")),
            ElevatedButton(
              onPressed: (selectedFiles.isEmpty || titleCtrl.text.isEmpty || isUploading) ? null : () async {
                setDS(() => isUploading = true);
                List<Map<String, String>> uploadedFiles = [];
                
                for (var file in selectedFiles) {
                  final ref = FirebaseStorage.instance.ref().child("important_docs/${DateTime.now().millisecondsSinceEpoch}_${file.name}");
                  if (kIsWeb) await ref.putData(file.bytes!); else await ref.putFile(File(file.path!));
                  final url = await ref.getDownloadURL();
                  uploadedFiles.add({'name': file.name, 'url': url});
                }

                await FirebaseFirestore.instance.collection('important_docs').add({
                  'title': titleCtrl.text,
                  'files': uploadedFiles,
                  'author': widget.currentUserEmail,
                  'date': DateFormat('dd.MM.yyyy').format(DateTime.now()),
                  'timestamp': FieldValue.serverTimestamp(),
                });

                Navigator.pop(ctx);
                _loadData();
              },
              child: const Text("WYŚLIJ"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDoc(Map<String, dynamic> doc) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("USUNĄĆ DOKUMENT?"),
        content: Text("Czy na pewno chcesz usunąć '${doc['title']}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("NIE")),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("TAK, USUŃ")),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await FirebaseFirestore.instance.collection('important_docs').doc(doc['id']).delete();
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("INSTRUKCJE I PLIKI", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)))
              : _filteredFiles.isEmpty 
                ? Center(child: Text("Brak dokumentów.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3))))
                : SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Theme(
                        data: theme.copyWith(
                          textTheme: theme.textTheme.copyWith(
                            bodyMedium: TextStyle(color: theme.colorScheme.onSurface)
                          )
                        ),
                        child: DataTable(
                          sortColumnIndex: _sortColumnIndex,
                          sortAscending: _sortAscending,
                          columnSpacing: 20,
                          headingTextStyle: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontSize: 12),
                          dataTextStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 13),
                          columns: [
                            const DataColumn(label: Text("PLIKI")),
                            DataColumn(
                              label: const Text("TYTUŁ"),
                              onSort: (idx, asc) => _sort((f) => f['title'] ?? "", idx, asc),
                            ),
                            DataColumn(
                              label: const Text("DATA"),
                              onSort: (idx, asc) => _sort((f) => f['date'] ?? "", idx, asc),
                            ),
                            if (widget.isAdmin) const DataColumn(label: Text("AKCJE")),
                          ],
                          rows: _filteredFiles.map((f) => DataRow(
                            cells: [
                              DataCell(Row(
                                children: (f['files'] as List? ?? []).map((file) => IconButton(
                                  icon: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
                                  onPressed: () => launchUrl(Uri.parse(file['url'])),
                                  tooltip: file['name'],
                                )).toList(),
                              )),
                              DataCell(Text(f['title'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text(f['date'] ?? "-")),
                              if (widget.isAdmin) DataCell(IconButton(
                                icon: Icon(Icons.delete_outline, color: theme.colorScheme.onSurface.withOpacity(0.3), size: 20),
                                onPressed: () => _deleteDoc(f),
                              )),
                            ],
                          )).toList(),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: widget.isAdmin 
        ? FloatingActionButton(
            onPressed: _addFileDialog,
            backgroundColor: Colors.orange,
            child: const Icon(Icons.add, color: Colors.white),
          )
        : null,
    );
  }

  Widget _buildSearchHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.cardTheme.color,
      child: TextField(
        onChanged: (v) {
          _searchQuery = v;
          _applyFilter();
        },
        style: TextStyle(color: theme.colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: "Szukaj instrukcji...",
          hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3)),
          prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurface.withOpacity(0.3)),
          filled: true,
          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }
}
