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
import 'package:es_manager/tools/label_designer_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_utils.dart';
import 'dart:typed_data';

class LanLabelsScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const LanLabelsScreen({super.key, this.initialData});

  @override
  State<LanLabelsScreen> createState() => _LanLabelsScreenState();
}

class _LanLabelsScreenState extends State<LanLabelsScreen> {
  List<dynamic> _savedProjects = [];
  List<String> _orderNames = [];
  bool _isLoading = true;
  final Color primaryColor = const Color(0xFF00796B);

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

    final String? data = prefs.getString('saved_lan_labels_v1');
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
    await prefs.setString('saved_lan_labels_v1', AppUtils.safeJsonEncode(_savedProjects));
    try {
      await CloudSyncService().uploadLanLabels();
    } catch (e) {
      debugPrint("LAN sync failed: $e");
    }
  }

  void _deleteProject(int index) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('USUŃ PROJEKT?'),
        content: const Text('Czy na pewno chcesz usunąć ten opis patch panelu?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
          TextButton(
            onPressed: () async {
              final id = _savedProjects[index]['id'].toString();
              setState(() => _savedProjects.removeAt(index));
              await _saveProjects();
              try {
                await FirebaseFirestore.instance.collection('lan_labels').doc(id).delete();
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
        builder: (c) => LanLabelsEditor(
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
        title: const Text('ARCHIWUM LAN'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync), 
            onPressed: () async {
              setState(() => _isLoading = true);
              await CloudSyncService().downloadLanLabels();
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
                      Icon(Icons.lan_outlined, size: 64, color: colorScheme.onSurface.withOpacity(0.1)),
                      const SizedBox(height: 16),
                      Text('Brak zapisanych opisów LAN', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5))),
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
                          child: Icon(Icons.lan, color: primaryColor, size: 20),
                        ),
                        title: Text(p['pp_name'] ?? 'Patch Panel', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Budowa: ${p['const_name'] ?? '-'}\nData: ${p['date_short'] ?? ''}', style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withOpacity(0.6))),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteProject(index),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: Colors.blue[800],
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('NOWY OPIS LAN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class LanLabelsEditor extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final List<String> orderNames;
  final Function(Map<String, dynamic>) onSave;

  const LanLabelsEditor({super.key, this.initialData, required this.orderNames, required this.onSave});

  @override
  State<LanLabelsEditor> createState() => _LanLabelsEditorState();
}

class _LanLabelsEditorState extends State<LanLabelsEditor> {
  final _constController = TextEditingController();
  final _ppNameController = TextEditingController();
  List<Map<String, dynamic>> _labels = [];
  bool _showLabels = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _constController.text = widget.initialData!['const_name'] ?? "";
      _ppNameController.text = widget.initialData!['pp_name'] ?? "";
      _labels = List<Map<String, dynamic>>.from(widget.initialData!['items'] ?? []);
      _showLabels = true;
    } else {
      _labels = [ {'port': '1', 'lan': '', 'desc': ''} ];
    }
  }

  void _addLabel() {
    _showAddPortDialog();
  }

  void _showAddPortDialog({int? insertIndex}) {
    final portController = TextEditingController(text: insertIndex != null ? (insertIndex + 2).toString() : (_labels.length + 1).toString());
    final lanController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('DODAJ PORT LAN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: portController,
              decoration: const InputDecoration(labelText: 'Numer Portu', hintText: 'np. 1'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: lanController,
              decoration: const InputDecoration(labelText: 'Oznaczenie LAN', hintText: 'np. L-01'),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'Opis / Lokalizacja', hintText: 'np. Salon TV'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
          ElevatedButton(
            onPressed: () {
              if (portController.text.isNotEmpty) {
                setState(() {
                  final newItem = {
                    'port': portController.text,
                    'lan': lanController.text,
                    'desc': descController.text,
                    'u_id': DateTime.now().microsecondsSinceEpoch.toString()
                  };
                  if (insertIndex != null) {
                    _labels.insert(insertIndex + 1, newItem);
                  } else {
                    _labels.add(newItem);
                  }
                  
                  // Renumeracja portów jeśli chcemy zachować ciągłość
                  for (int i = 0; i < _labels.length; i++) {
                    _labels[i]['port'] = (i + 1).toString();
                  }
                });
                Navigator.pop(context);
              }
            },
            child: const Text('ZAPISZ'),
          ),
        ],
      ),
    );
  }

  void _exportToExcel() async {
    String csvData = "Port;LAN;Opis\n";
    for (var l in _labels) {
      csvData += "${l['port']};${l['lan']};${l['desc']}\n";
    }

    if (kIsWeb) {
      final bytes = utf8.encode(csvData);
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: "LAN_${_ppNameController.text}.csv");
    } else {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/LAN_${_ppNameController.text}.csv');
      await file.writeAsString(csvData);
      await Share.shareXFiles([XFile(file.path)], text: 'Export LAN CSV');
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
    final String qrUrl = "https://es-manager-crm.web.app/#/lan_view?id=$projectId";

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 25, vertical: 20),
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      build: (context) => pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (logoImage != null) pw.Container(height: 45, child: pw.Image(logoImage)),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('PATCH PANEL', style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey700)),
                  pw.Text(_ppNameController.text.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                ]
              )
            ]
          ),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
            headerHeight: 25,
            cellHeight: 22,
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headers: ['Port', 'LAN', 'Opis przeznaczenia / Lokalizacja'],
            columnWidths: {
              0: const pw.FixedColumnWidth(40),
              1: const pw.FixedColumnWidth(80),
              2: const pw.FlexColumnWidth(),
            },
            data: _labels.map((l) => [
              (l['port'] ?? '').toString(),
              (l['lan'] ?? '').toString(),
              (l['desc'] ?? '').toString(),
            ]).toList(),
          ),
          pw.SizedBox(height: 15),
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
                    width: 60, height: 60,
                    child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: qrUrl, drawText: false),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text('SKANUJ OPIS', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                ]
              )
            ]
          ),
        ],
      ),
    ));

    return pdf;
  }

  Future<void> _saveAsPdf() async {
    try {
      final pdf = await _generatePdfDoc();
      final bytes = await pdf.save();
      await Printing.sharePdf(bytes: bytes, filename: "LAN_${_ppNameController.text}.pdf");
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
          appBar: AppBar(title: const Text('PODGLĄD WYDRUKU LAN'), backgroundColor: const Color(0xFF00796B), foregroundColor: Colors.white),
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
            pdfFileName: 'LAN_${_ppNameController.text}.pdf',
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
        title: Text(_showLabels ? 'EDYTOR LAN' : 'NOWY PATCH PANEL'),
        backgroundColor: const Color(0xFF00796B),
        foregroundColor: Colors.white,
        actions: [
          if (_showLabels) IconButton(
            icon: const Icon(Icons.print_outlined), 
            onPressed: () {
              final labels = _labels.map((l) => "${l['lan'] ?? ''} ${l['desc'] ?? ''}".trim()).toList();
              Navigator.push(context, MaterialPageRoute(builder: (c) => LabelDesignerScreen(initialLabels: labels)));
            },
            tooltip: 'Drukuj Etykiety',
          ),
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
                'pp_name': _ppNameController.text,
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
    final String url = "https://es-manager-crm.web.app/#/lan_view?id=$projectId";
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('KOD QR LAN', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Zapisz lub wydrukuj ten kod i naklej na Patch Panelu. Każdy kto go zeskanuje, zobaczy opisy portów.', 
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
          const Text('PODAJ DANE PATCH PANELU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
            controller: _ppNameController,
            decoration: InputDecoration(
              labelText: 'Nazwa Patch Panelu (np. Szafa Rack 1, PP Główny)',
              prefixIcon: const Icon(Icons.lan),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () {
                if (_constController.text.isNotEmpty && _ppNameController.text.isNotEmpty) {
                  setState(() => _showLabels = true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uzupełnij dane!')));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00796B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text('PRZEJDŹ DO OPISÓW PORTÓW'),
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
              Expanded(child: Text('${_constController.text} / ${_ppNameController.text}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.edit, size: 16), onPressed: () => setState(() => _showLabels = false)),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Przytrzymaj i przesuń port, aby zmienić jego kolejność. Numeracja zaktualizuje się automatycznie.', style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
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
                
                for (int i = 0; i < _labels.length; i++) {
                  _labels[i]['port'] = (i + 1).toString();
                }
              });
            },
            itemBuilder: (context, index) {
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
                      CircleAvatar(radius: 15, child: Text(_labels[index]['port'] ?? '', style: const TextStyle(fontSize: 10))),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: InkWell(
                          onTap: () => _showEditItemDialog(index),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('LAN: ${_labels[index]['lan'] ?? '-'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal)),
                              Text(_labels[index]['desc'] ?? 'Brak opisu', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
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
                          onPressed: () => _showAddPortDialog(insertIndex: index),
                          tooltip: 'Wstaw wiersz poniżej',
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                          onPressed: () => setState(() {
                            _labels.removeAt(index);
                            for (int i = 0; i < _labels.length; i++) {
                              _labels[i]['port'] = (i + 1).toString();
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
            label: const Text('DODAJ KOLEJNY PORT'),
          ),
        ),
        const SizedBox(height: 70),
      ],
    );
  }

  void _showEditItemDialog(int index) {
    final portController = TextEditingController(text: _labels[index]['port']);
    final lanController = TextEditingController(text: _labels[index]['lan']);
    final descController = TextEditingController(text: _labels[index]['desc']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('EDYTUJ PORT LAN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: portController,
              decoration: const InputDecoration(labelText: 'Port'),
              readOnly: true,
            ),
            TextField(
              controller: lanController,
              decoration: const InputDecoration(labelText: 'LAN (Oznaczenie)'),
              autofocus: true,
            ),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'Opis Lokalizacji'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _labels[index]['lan'] = lanController.text;
                _labels[index]['desc'] = descController.text;
              });
              Navigator.pop(context);
            },
            child: const Text('ZAPISZ'),
          ),
        ],
      ),
    );
  }
}
