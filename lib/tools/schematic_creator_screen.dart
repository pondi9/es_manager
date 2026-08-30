import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../core/app_utils.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class SchematicCreatorScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const SchematicCreatorScreen({super.key, this.initialData});

  @override
  State<SchematicCreatorScreen> createState() => _SchematicCreatorScreenState();
}

class _SchematicCreatorScreenState extends State<SchematicCreatorScreen> {
  List<dynamic> _savedSchematics = [];
  bool _isLoading = true;
  final Color primaryColor = const Color(0xFF455A64);

  @override
  void initState() {
    super.initState();
    _loadSchematics();
  }

  Future<void> _loadSchematics() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('saved_schematics_v2');
    if (data != null) {
      setState(() { _savedSchematics = json.decode(data); _isLoading = false; });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSchematics() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_schematics_v2', AppUtils.safeJsonEncode(_savedSchematics));
  }

  void _openEditor({Map<String, dynamic>? schematic, int? index}) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => SchematicEditor(
      initialData: schematic,
      onSave: (newData) {
        setState(() {
          if (index != null) _savedSchematics[index] = newData;
          else _savedSchematics.insert(0, newData);
        });
        _saveSchematics();
      },
    )));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('KREATOR SCHEMATÓW PRO'), backgroundColor: primaryColor, foregroundColor: Colors.white),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _savedSchematics.length,
        itemBuilder: (context, index) {
          final s = _savedSchematics[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.schema, color: Colors.white, size: 18)),
              title: Text(s['name'] ?? 'Bez nazwy', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Data: ${s['date_short']} | Sekcji: ${(s['sections'] as List).length}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openEditor(schematic: s, index: index),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: Colors.indigo,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('NOWY SCHEMAT', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class SchematicEditor extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final Function(Map<String, dynamic>) onSave;
  const SchematicEditor({super.key, this.initialData, required this.onSave});

  @override
  State<SchematicEditor> createState() => _SchematicEditorState();
}

class _SchematicEditorState extends State<SchematicEditor> {
  final _nameController = TextEditingController();
  List<Map<String, dynamic>> _sections = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _nameController.text = widget.initialData!['name'] ?? "";
      _sections = List<Map<String, dynamic>>.from(widget.initialData!['sections'] ?? []);
    } else {
      _sections = [
        {
          'rcd_name': 'RCD 1', 'rcd_params': '40A 30mA 4P',
          'mcbs': [{'name': 'B16', 'desc': 'Gniazda Salon'}]
        }
      ];
    }
  }

  void _addSection() {
    setState(() {
      _sections.add({
        'rcd_name': 'RCD ${_sections.length + 1}', 'rcd_params': '40A 30mA 4P',
        'mcbs': []
      });
    });
  }

  void _addMcb(int sectionIdx) {
    setState(() {
      (_sections[sectionIdx]['mcbs'] as List).add({'name': 'B16', 'desc': 'Nowy obwód'});
    });
  }

  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      build: (pw.Context context) => [
        pw.Header(level: 0, child: pw.Text('SCHEMAT IDEOWY ROZDZIELNICY: ${_nameController.text.toUpperCase()}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 30),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: _sections.map((sec) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(right: 20),
              child: pw.Column(
                children: [
                  // Symbol RCD
                  pw.Container(
                    width: 60, height: 40,
                    decoration: pw.BoxDecoration(border: pw.Border.all()),
                    child: pw.Center(child: pw.Text('RCD\n${sec['rcd_params']}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8))),
                  ),
                  pw.Container(width: 1, height: 15, color: PdfColors.black),
                  // Linia pozioma (grzebień)
                  pw.Container(width: 100, height: 1, color: PdfColors.black),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: (sec['mcbs'] as List).map((mcb) {
                      return pw.Container(
                        width: 45,
                        child: pw.Column(
                          children: [
                            pw.Container(width: 1, height: 10, color: PdfColors.black),
                            // Symbol MCB
                            pw.Container(
                              width: 30, height: 35,
                              decoration: pw.BoxDecoration(border: pw.Border.all()),
                              child: pw.Center(child: pw.Text(mcb['name'], style: const pw.TextStyle(fontSize: 7))),
                            ),
                            pw.SizedBox(height: 5),
                            pw.Transform.rotate(angle: 1.57, child: pw.Text(mcb['desc'], style: const pw.TextStyle(fontSize: 6))),
                          ]
                        )
                      );
                    }).toList()
                  )
                ]
              )
            );
          }).toList()
        ),
      ]
    ));

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Schemat_${_nameController.text}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: const InputDecoration(hintText: 'Nazwa rozdzielnicy...', border: InputBorder.none, hintStyle: TextStyle(color: Colors.white70)),
        ),
        backgroundColor: const Color(0xFF455A64),
        actions: [IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _generatePdf)],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _sections.length,
        itemBuilder: (context, sIdx) => Card(
          margin: const EdgeInsets.only(bottom: 20),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: const BorderRadius.vertical(top: Radius.circular(15))),
              child: Row(children: [
                const Icon(Icons.shield_outlined, color: Colors.indigo),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  decoration: const InputDecoration(labelText: 'Parametry RCD', isDense: true),
                  controller: TextEditingController(text: _sections[sIdx]['rcd_params'])..selection = TextSelection.collapsed(offset: _sections[sIdx]['rcd_params'].length),
                  onChanged: (v) => _sections[sIdx]['rcd_params'] = v,
                )),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setState(() => _sections.removeAt(sIdx))),
              ]),
            ),
            ...List.generate((_sections[sIdx]['mcbs'] as List).length, (mIdx) {
              var mcb = _sections[sIdx]['mcbs'][mIdx];
              return ListTile(
                leading: const Icon(Icons.horizontal_rule, color: Colors.blueGrey),
                title: Row(children: [
                  SizedBox(width: 60, child: TextField(
                    decoration: const InputDecoration(hintText: 'B16'),
                    controller: TextEditingController(text: mcb['name'])..selection = TextSelection.collapsed(offset: mcb['name'].length),
                    onChanged: (v) => mcb['name'] = v,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    decoration: const InputDecoration(hintText: 'Opis obwodu'),
                    controller: TextEditingController(text: mcb['desc'])..selection = TextSelection.collapsed(offset: mcb['desc'].length),
                    onChanged: (v) => mcb['desc'] = v,
                  )),
                ]),
                trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, size: 18), onPressed: () => setState(() => (_sections[sIdx]['mcbs'] as List).removeAt(mIdx))),
              );
            }),
            TextButton.icon(onPressed: () => _addMcb(sIdx), icon: const Icon(Icons.add), label: const Text('DODAJ BEZPIECZNIK')),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          widget.onSave({
            'name': _nameController.text, 'sections': _sections,
            'date_short': DateFormat('dd.MM.yyyy').format(DateTime.now())
          });
          Navigator.pop(context);
        },
        label: const Text('ZAPISZ SCHEMAT'),
        icon: const Icon(Icons.save),
        backgroundColor: Colors.green[700],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ElevatedButton.icon(onPressed: _addSection, icon: const Icon(Icons.add_box), label: const Text('DODAJ NOWĄ RÓŻNICÓWKĘ (SEKCJĘ)')),
        ),
      ),
    );
  }
}
