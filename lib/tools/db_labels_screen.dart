import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:es_manager/services/cloud_sync_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_utils.dart';
import 'dart:typed_data';

class DbLabelsScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const DbLabelsScreen({super.key, this.initialData});

  @override
  State<DbLabelsScreen> createState() => _DbLabelsScreenState();
}

class _DbLabelsScreenState extends State<DbLabelsScreen> {
  List<dynamic> _savedProjects = [];
  List<String> _orderNames = [];
  bool _isLoading = true;
  final Color primaryColor = const Color(0xFF455A64);

  @override
  void initState() {
    super.initState();
    _loadProjects();
    if (widget.initialData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openEditor(project: widget.initialData);
      });
    }
  }

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Pobierz zlecenia do podpowiedzi
    try {
      final orderSnap = await FirebaseFirestore.instance.collection('orders').get();
      _orderNames = orderSnap.docs.map((d) => (d.data()['name'] ?? '').toString()).where((n) => n.isNotEmpty).toList();
    } catch (e) {
      debugPrint("Failed to fetch orders for autocomplete: $e");
    }

    final String? data = prefs.getString('saved_db_labels_v2');
    if (data != null) {
      setState(() {
        _savedProjects = json.decode(data);
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_db_labels_v2', AppUtils.safeJsonEncode(_savedProjects));
    try {
      await CloudSyncService().uploadDbLabels();
    } catch (e) {
      debugPrint("Switchboard sync failed: $e");
    }
  }

  void _deleteProject(int index) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('USUŃ PROJEKT?'),
        content: const Text('Czy na pewno chcesz usunąć ten opis rozdzielni?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
          TextButton(
            onPressed: () async {
              final id = _savedProjects[index]['id'].toString();
              setState(() => _savedProjects.removeAt(index));
              await _saveProjects();
              try {
                await FirebaseFirestore.instance.collection('switchboards').doc(id).delete();
              } catch (_) {}
              Navigator.pop(context);
            },
            child: const Text('USUŃ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openEditor({Map<String, dynamic>? project, int? index}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => DbLabelsEditor(
          initialData: project,
          orderNames: _orderNames,
          onSave: (newData) {
            setState(() {
              if (index != null) {
                _savedProjects[index] = newData;
              } else {
                _savedProjects.insert(0, newData);
              }
            });
            _saveProjects();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: const Text('ARCHIWUM ROZDZIELNI'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync), 
            onPressed: () async {
              setState(() => _isLoading = true);
              await CloudSyncService().downloadDbLabels();
              await _loadProjects();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zsynchronizowano z chmurą')));
            },
            tooltip: 'Synchronizuj z chmurą',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedProjects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: colorScheme.onSurface.withOpacity(0.1)),
                      const SizedBox(height: 16),
                      Text('Brak zapisanych rozdzielni', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5))),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _savedProjects.length,
                  itemBuilder: (context, index) {
                    final p = _savedProjects[index];
                    return Card(
                      elevation: 0,
                      color: colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        onTap: () => _openEditor(project: p, index: index),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                          child: Icon(Icons.electrical_services, color: primaryColor, size: 20),
                        ),
                        title: Text(p['db_name'] ?? 'Bez nazwy', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Budowa: ${p['const_name'] ?? '-'}\nData: ${p['date_short'] ?? ''}', style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withOpacity(0.6))),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blueGrey),
                              onPressed: () => _openEditor(project: p, index: index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteProject(index),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: Colors.amber[700],
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('NOWA ROZDZIELNIA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class DbLabelsEditor extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final List<String> orderNames;
  final Function(Map<String, dynamic>) onSave;

  const DbLabelsEditor({super.key, this.initialData, required this.orderNames, required this.onSave});

  @override
  State<DbLabelsEditor> createState() => _DbLabelsEditorState();
}

class _DbLabelsEditorState extends State<DbLabelsEditor> {
  final _constController = TextEditingController();
  final _dbNameController = TextEditingController();
  List<Map<String, dynamic>> _labels = [];
  bool _showLabels = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _constController.text = widget.initialData!['const_name'] ?? "";
      _dbNameController.text = widget.initialData!['db_name'] ?? "";
      _labels = List<Map<String, dynamic>>.from(widget.initialData!['items'] ?? []);
      _showLabels = true;
    } else {
      _labels = [ {'no': '1', 'desc': ''} ];
    }
  }

  void _addLabel() {
    setState(() {
      _labels.add({'no': (_labels.length + 1).toString(), 'desc': ''});
    });
  }

  void _exportToExcel() async {
    String csvData = "Lp.;Opis obwodu / Przeznaczenie\n";
    for (var l in _labels) {
      csvData += "${l['no']};${l['desc']}\n";
    }

    if (kIsWeb) {
      final bytes = utf8.encode(csvData);
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: "Opis_${_dbNameController.text}.csv");
    } else {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/Opis_${_dbNameController.text}.csv');
      await file.writeAsString(csvData);
      await Share.shareXFiles([XFile(file.path)], text: 'Export CSV');
    }
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plik CSV został przygotowany.')));
  }

  Future<pw.Document> _generatePdfDoc() async {
    final pdf = pw.Document();
    pw.Font font = pw.Font.helvetica();
    pw.Font fontBold = pw.Font.helveticaBold();
    try {
      font = await PdfGoogleFonts.notoSansRegular();
      fontBold = await PdfGoogleFonts.notoSansBold();
    } catch (_) {}

    pw.MemoryImage? logoImage;
    try {
      final ByteData bytes = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    final String projectId = widget.initialData?['id'] ?? "temp";
    final String qrUrl = "https://es-manager-crm.web.app/#/view?id=$projectId";

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 25, vertical: 30),
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      header: (context) => pw.Column(children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            if (logoImage != null) pw.Container(height: 40, child: pw.Image(logoImage)),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('OPIS ROZDZIELNI', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                pw.Text(_dbNameController.text.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ]
            )
          ]
        ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 10),
      ]),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text('Strona ${context.pageNumber} z ${context.pagesCount} | ES CRM', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
          headerHeight: 25,
          cellHeight: 22,
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headers: ['Lp.', 'Opis obwodu / Przeznaczenie'],
          columnWidths: {
            0: const pw.FixedColumnWidth(40),
            1: const pw.FlexColumnWidth(),
          },
          data: _labels.map((l) => [
            (l['no'] ?? '').toString(),
            (l['desc'] ?? '').toString(),
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                 pw.Text('Wygenerowano: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              ]
            ),
            pw.Column(
              children: [
                pw.Container(
                  width: 50, height: 50,
                  child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: qrUrl, drawText: false),
                ),
                pw.SizedBox(height: 2),
                pw.Text('SKANUJ OPIS', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
              ]
            )
          ]
        ),
      ],
    ));

    return pdf;
  }

  Future<void> _saveAsPdf() async {
    try {
      final pdf = await _generatePdfDoc();
      final bytes = await pdf.save();
      await Printing.sharePdf(bytes: bytes, filename: "Opis_${_dbNameController.text}.pdf");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plik PDF został przygotowany.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd zapisu PDF: $e'), backgroundColor: Colors.red));
    }
  }

  void _showPrintPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('PODGLĄD WYDRUKU'), backgroundColor: const Color(0xFF455A64), foregroundColor: Colors.white),
          body: PdfPreview(
            build: (format) async {
              try {
                final pdf = await _generatePdfDoc();
                return pdf.save();
              } catch (e) {
                return Uint8List(0);
              }
            },
            allowSharing: true, allowPrinting: true, initialPageFormat: PdfPageFormat.a4,
            pdfFileName: 'Opis_${_dbNameController.text}.pdf',
            onError: (context, error) => Center(child: Text('Błąd podglądu: $error')),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_showLabels ? 'EDYTOR OPISÓW' : 'NOWA ROZDZIELNIA'),
        backgroundColor: const Color(0xFF455A64),
        foregroundColor: Colors.white,
        actions: [
          if (_showLabels) IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _saveAsPdf, tooltip: 'Zapisz jako PDF'),
          if (_showLabels) IconButton(icon: const Icon(Icons.table_view), onPressed: _exportToExcel, tooltip: 'Eksportuj do Excel'),
          if (_showLabels) IconButton(icon: const Icon(Icons.qr_code_2), onPressed: _showQrCode, tooltip: 'Pobierz Kod QR'),
          if (_showLabels) IconButton(icon: const Icon(Icons.print), onPressed: _showPrintPreview, tooltip: 'Podgląd i Druk'),
        ],
      ),
      body: _showLabels ? _buildEditor() : _buildStep1(),
      floatingActionButton: _showLabels 
        ? FloatingActionButton(
            onPressed: () {
              widget.onSave({
                'id': widget.initialData?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
                'const_name': _constController.text,
                'db_name': _dbNameController.text,
                'items': _labels,
                'date_short': DateFormat('dd.MM.yyyy').format(DateTime.now()),
              });
              Navigator.pop(context);
            },
            backgroundColor: Colors.green,
            child: const Icon(Icons.save),
          )
        : null,
    );
  }

  void _showQrCode() {
    final String projectId = widget.initialData?['id'] ?? "temp";
    final String url = "https://es-manager-crm.web.app/#/view?id=$projectId";
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('KOD QR ROZDZIELNI', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Zapisz lub wydrukuj ten kod i naklej na rozdzielnicy. Każdy kto go zeskanuje, zobaczy opis bezpieczników.', 
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.white,
              child: Image.network(
                "https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${Uri.encodeComponent(url)}",
                height: 200, width: 200,
                loadingBuilder: (c, w, p) => p == null ? w : const CircularProgressIndicator(),
              ),
            ),
            const SizedBox(height: 10),
            Text('ID: $projectId', style: const TextStyle(fontSize: 9, color: Colors.blueGrey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ZAMKNIJ')),
          ElevatedButton.icon(
            onPressed: () => launchUrl(Uri.parse("https://api.qrserver.com/v1/create-qr-code/?size=1000x1000&data=${Uri.encodeComponent(url)}")), 
            icon: const Icon(Icons.download), 
            label: const Text('POBIERZ JPG')
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PODAJ DANE ROZDZIELNI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 24),
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<String>.empty();
              }
              return widget.orderNames.where((String option) {
                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
              });
            },
            onSelected: (String selection) {
              _constController.text = selection;
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              // Synchronizujemy kontroler Autocomplete z naszym _constController
              if (controller.text.isEmpty && _constController.text.isNotEmpty) {
                controller.text = _constController.text;
              }
              controller.addListener(() {
                _constController.text = controller.text;
              });
              
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: 'Nazwa budowy',
                  hintText: 'Szukaj lub wpisz nową...',
                  prefixIcon: const Icon(Icons.apartment),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onSubmitted: (val) => onFieldSubmitted(),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    width: MediaQuery.of(context).size.width - 48,
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final String option = options.elementAt(index);
                        return ListTile(
                          title: Text(option),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _dbNameController,
            decoration: InputDecoration(
              labelText: 'Nazwa rozdzielni (np. Parter, Główna)',
              prefixIcon: const Icon(Icons.electrical_services),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () {
                if (_constController.text.isNotEmpty && _dbNameController.text.isNotEmpty) {
                  setState(() => _showLabels = true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uzupełnij dane!')));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF455A64),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text('PRZEJDŹ DO OPISÓW ObWODÓW'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Expanded(child: Text('${_constController.text} / ${_dbNameController.text}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.edit, size: 16), onPressed: () => setState(() => _showLabels = false)),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Przytrzymaj i przesuń obwód, aby zmienić jego kolejność. Numeracja zaktualizuje się automatycznie.', style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _labels.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _labels.removeAt(oldIndex);
                _labels.insert(newIndex, item);
                
                // Automatyczna aktualizacja numeracji po przesunięciu
                for (int i = 0; i < _labels.length; i++) {
                  _labels[i]['no'] = (i + 1).toString();
                }
              });
            },
            itemBuilder: (context, index) {
              // Klucz musi być unikalny i stały dla danego elementu danych
              // Dodajemy unikalny identyfikator do mapy jeśli go nie ma
              if (_labels[index]['u_id'] == null) {
                _labels[index]['u_id'] = DateTime.now().microsecondsSinceEpoch.toString() + index.toString();
              }
              
              return Card(
                key: ValueKey(_labels[index]['u_id']),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.drag_indicator, color: Colors.grey),
                  title: Row(
                    children: [
                      CircleAvatar(radius: 15, child: Text(_labels[index]['no'] ?? '', style: const TextStyle(fontSize: 10))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(hintText: 'Opis...', border: InputBorder.none),
                          controller: TextEditingController(text: (_labels[index]['desc'] ?? '').toString())..selection = TextSelection.collapsed(offset: (_labels[index]['desc'] ?? '').toString().length),
                          onChanged: (v) => _labels[index]['desc'] = v,
                        ),
                      ),
                    ],
                  ),
                  trailing: SizedBox(
                    width: 100,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 20),
                          onPressed: () => setState(() {
                            _labels.insert(index + 1, {'no': '', 'desc': ''});
                            for (int i = 0; i < _labels.length; i++) {
                              _labels[i]['no'] = (i + 1).toString();
                            }
                          }),
                          tooltip: 'Wstaw wiersz poniżej',
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                          onPressed: () => setState(() {
                            _labels.removeAt(index);
                            for (int i = 0; i < _labels.length; i++) {
                              _labels[i]['no'] = (i + 1).toString();
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextButton.icon(
            onPressed: _addLabel, 
            icon: const Icon(Icons.add_circle_outline), 
            label: const Text('DODAJ KOLEJNY OBWÓD'),
          ),
        ),
        const SizedBox(height: 70),
      ],
    );
  }
}
