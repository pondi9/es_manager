import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'tools/signature_pad.dart';
import 'services/cloud_sync_service.dart';
import 'core/app_utils.dart';

class ProtocolsScreen extends StatefulWidget {
  final bool isAdmin;
  final String currentUserEmail;
  const ProtocolsScreen({super.key, required this.isAdmin, required this.currentUserEmail});

  @override
  State<ProtocolsScreen> createState() => _ProtocolsScreenState();
}

class _ProtocolsScreenState extends State<ProtocolsScreen> {
  List<Map<String, dynamic>> _protocols = [];
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  final Color primaryColor = const Color(0xFF6A1B9A);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await CloudSyncService().downloadProtocols().timeout(const Duration(seconds: 5));
      await CloudSyncService().downloadOrders().timeout(const Duration(seconds: 5));
    } catch (e) {}

    final String? protData = prefs.getString('company_protocols_v1');
    if (protData != null) _protocols = List<Map<String, dynamic>>.from(json.decode(protData));

    final String? ordersData = prefs.getString('company_orders_v2');
    if (ordersData != null) _orders = List<Map<String, dynamic>>.from(json.decode(ordersData));

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveProtocols() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_protocols_v1', AppUtils.safeJsonEncode(_protocols));
    try { await CloudSyncService().uploadProtocols(); } catch (e) {}
  }

  void _addProtocolDialog({Map<String, dynamic>? protocol, int? index}) {
    final clientController = TextEditingController(text: protocol?['client'] ?? '');
    final deviceController = TextEditingController(text: protocol?['device'] ?? 'Miernik Sonel MPI-540');
    final tempController = TextEditingController(text: protocol?['temperature'] ?? '20°C');
    final humidityController = TextEditingController(text: protocol?['humidity'] ?? '45%');
    String? selectedOrderId = protocol?['orderId'];
    String? signatureB64 = protocol?['signatureB64'];
    List<Map<String, dynamic>> measurements = protocol != null 
        ? List<Map<String, dynamic>>.from(protocol['measurements'])
        : [{'circuit': 'L1 - Gniazda Salon', 'res': ' > 999 MΩ', 'rcd': '22ms / 24V', 'pe': '0.12 Ω', 'result': 'POZYTYWNY'}];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: Text(protocol == null ? 'NOWY PROTOKÓŁ' : 'EDYTUJ PROTOKÓŁ'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: selectedOrderId,
                    decoration: const InputDecoration(labelText: 'Wybierz budowę'),
                    items: _orders.map((o) => DropdownMenuItem(value: o['id'].toString(), child: Text(o['name']))).toList(),
                    onChanged: (val) => selectedOrderId = val,
                  ),
                  TextField(controller: clientController, decoration: const InputDecoration(labelText: 'Zleceniodawca / Klient')),
                  TextField(controller: deviceController, decoration: const InputDecoration(labelText: 'Użyty przyrząd pomiarowy')),
                  Row(children: [
                    Expanded(child: TextField(controller: tempController, decoration: const InputDecoration(labelText: 'Temp. otocz.'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: humidityController, decoration: const InputDecoration(labelText: 'Wilgotność'))),
                  ]),
                  const SizedBox(height: 20),
                  const Text('WYNIKI POMIARÓW:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const Divider(),
                  ...measurements.asMap().entries.map((entry) {
                    int i = entry.key;
                    return Card(
                      color: Colors.grey[50],
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(children: [
                          Row(children: [
                            Expanded(child: TextField(
                              decoration: const InputDecoration(labelText: 'Obwód / Punkt', isDense: true),
                              onChanged: (v) => measurements[i]['circuit'] = v,
                              controller: TextEditingController(text: measurements[i]['circuit']),
                            )),
                            IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => setDS(() => measurements.removeAt(i)))
                          ]),
                          Row(children: [
                            Expanded(child: TextField(
                              decoration: const InputDecoration(labelText: 'R. izolacji', isDense: true), 
                              onChanged: (v) => measurements[i]['res'] = v,
                              controller: TextEditingController(text: measurements[i]['res'] ?? ''),
                            )),
                            const SizedBox(width: 5),
                            Expanded(child: TextField(
                              decoration: const InputDecoration(labelText: 'Pętla / RCD', isDense: true), 
                              onChanged: (v) => measurements[i]['rcd'] = v,
                              controller: TextEditingController(text: measurements[i]['rcd'] ?? ''),
                            )),
                            const SizedBox(width: 5),
                            Expanded(child: TextField(
                              decoration: const InputDecoration(labelText: 'Ciągłość PE', isDense: true), 
                              onChanged: (v) => measurements[i]['pe'] = v,
                              controller: TextEditingController(text: measurements[i]['pe'] ?? ''),
                            )),
                          ]),
                        ]),
                      ),
                    );
                  }).toList(),
                  TextButton.icon(onPressed: () => setDS(() => measurements.add({'circuit': '', 'res': '', 'rcd': '', 'pe': '', 'result': 'POZYTYWNY'})), icon: const Icon(Icons.add), label: const Text('DODAJ WIERSZ')),
                  const Divider(),
                  if (signatureB64 != null) 
                    Column(children: [
                      const Text('PODPIS ZŁOŻONY', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
                      Image.memory(base64Decode(signatureB64!), height: 60),
                      TextButton(onPressed: () => setDS(() => signatureB64 = null), child: const Text('USUŃ PODPIS', style: TextStyle(color: Colors.red, fontSize: 10)))
                    ])
                  else
                    ElevatedButton.icon(
                      onPressed: () {
                        showDialog(context: context, builder: (c) => AlertDialog(
                          title: const Text('ZŁÓŻ PODPIS'),
                          content: SignaturePad(onSave: (bytes) {
                            if (bytes != null) {
                              setDS(() => signatureB64 = base64Encode(bytes));
                            }
                          }),
                        ));
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('DODAJ PODPIS ELEKTRYKA'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (protocol != null && widget.isAdmin)
              IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                _deleteProtocol(index!);
                Navigator.pop(context);
              }),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
            ElevatedButton(
              onPressed: () async {
                if (selectedOrderId != null) {
                  final data = {
                    'id': protocol?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
                    'orderId': selectedOrderId,
                    'orderName': _orders.firstWhere((o) => o['id'].toString() == selectedOrderId)['name'],
                    'client': clientController.text,
                    'device': deviceController.text,
                    'temperature': tempController.text,
                    'humidity': humidityController.text,
                    'date': protocol?['date'] ?? DateFormat('dd.MM.yyyy').format(DateTime.now()),
                    'author': protocol?['author'] ?? widget.currentUserEmail,
                    'measurements': measurements,
                    'signatureB64': signatureB64
                  };
                  setState(() {
                    if (index == null) _protocols.insert(0, data); else _protocols[index] = data;
                  });
                  await _saveProtocols();
                  Navigator.pop(context);
                  _generatePdf(data);
                }
              },
              child: const Text('ZAPISZ I GENERUJ'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteProtocol(int index) async {
    final prot = _protocols[index];
    setState(() => _protocols.removeAt(index));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_protocols_v1', AppUtils.safeJsonEncode(_protocols));
    try {
      await CloudSyncService().deleteProtocol(prot['id'].toString());
    } catch (e) {}
  }

  Future<void> _generatePdf(Map<String, dynamic> prot) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    
    final prefs = await SharedPreferences.getInstance();
    final compName = prefs.getString('comp_name') ?? 'ES CRM - USŁUGI ELEKTRYCZNE';

    pw.MemoryImage? signatureImage;
    if (prot['signatureB64'] != null) {
      try { signatureImage = pw.MemoryImage(base64Decode(prot['signatureB64'])); } catch (_) {}
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(compName, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.Text('Numer protokołu: ${prot['id'].toString().substring(prot['id'].toString().length - 6)}', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ]
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Strona ${context.pageNumber} z ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
            pw.Text('Wygenerowano: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8)),
          ]
        ),
        build: (pw.Context context) => [
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Column(children: [
              pw.Text('PROTOKÓŁ Z POMIARÓW PARAMETRÓW', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
              pw.Text('INSTALACJI ELEKTRYCZNEJ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
              pw.Text('Zgodnie z normą PN-HD 60364-6:2016-07', style: const pw.TextStyle(fontSize: 10)),
            ]),
          ),
          pw.SizedBox(height: 30),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('OBIEKT / ADRES:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey700)),
                    pw.Text('${prot['orderName']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 10),
                    pw.Text('ZLECENIODAWCA:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey700)),
                    pw.Text('${prot['client']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('WARUNKI POMIARÓW:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey700)),
                    pw.Text('Data pomiarów: ${prot['date']}'),
                    pw.Text('Temperatura: ${prot['temperature'] ?? '-'}'),
                    pw.Text('Wilgotność: ${prot['humidity'] ?? '-'}'),
                    pw.SizedBox(height: 10),
                    pw.Text('PRZYRZĄD POMIAROWY:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey700)),
                    pw.Text('${prot['device']}'),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headers: ['Lp.', 'Nazwa obwodu / Punktu', 'Rez. Izolacji [MΩ]', 'Pętla / RCD [ms/V]', 'Ciągłość PE [Ω]', 'Ocena'],
            data: List<List<String>>.generate(
              (prot['measurements'] as List).length,
              (index) {
                var m = prot['measurements'][index];
                return [
                  (index + 1).toString(),
                  m['circuit'] ?? '-',
                  m['res'] ?? '-',
                  m['rcd'] ?? '-',
                  m['pe'] ?? '-',
                  m['result'] ?? 'POZYTYWNA'
                ];
              }
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(25),
              1: const pw.FlexColumnWidth(),
              2: const pw.FixedColumnWidth(70),
              3: const pw.FixedColumnWidth(70),
              4: const pw.FixedColumnWidth(70),
              5: const pw.FixedColumnWidth(60),
            },
          ),
          pw.SizedBox(height: 30),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('ORZECZENIE / UWAGI:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.SizedBox(height: 5),
                pw.Text('Na podstawie przeprowadzonych pomiarów stwierdza się, że stan badanych obwodów oraz skuteczność ochrony przeciwporażeniowej odpowiadają wymogom przepisów i instalacja nadaje się do eksploatacji.', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          pw.SizedBox(height: 40),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Column(children: [
                pw.SizedBox(width: 150, child: pw.Divider()),
                pw.Text('Odebrał (Zleceniodawca)', style: const pw.TextStyle(fontSize: 8)),
              ]),
              pw.Column(children: [
                if (signatureImage != null) pw.Container(height: 60, width: 120, child: pw.Image(signatureImage, fit: pw.BoxFit.contain)),
                pw.SizedBox(width: 150, child: pw.Divider()), 
                pw.Text('Pomiary wykonał (Osoba Uprawniona)', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Imię i Nazwisko: ${prot['author']}', style: const pw.TextStyle(fontSize: 7)),
              ]),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Protokol_${prot['orderName']}_${prot['date']}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> dispProtocols = widget.isAdmin 
      ? _protocols 
      : _protocols.where((p) => p['orderId'].toString() == widget.currentUserEmail).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PROTOKOŁY / POMIARY'),
        backgroundColor: primaryColor, foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : dispProtocols.isEmpty
          ? const Center(child: Text('Brak zapisanych protokołów.'))
          : ListView.builder(
              itemCount: dispProtocols.length,
              itemBuilder: (context, index) {
                final prot = dispProtocols[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.purple, child: Icon(Icons.description, color: Colors.white)),
                    title: Text(prot['orderName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Data: ${prot['date']} | Wykonał: ${prot['author']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isAdmin)
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blueGrey),
                            onPressed: () => _addProtocolDialog(protocol: prot, index: index),
                          ),
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                          onPressed: () => _generatePdf(prot),
                        ),
                      ],
                    ),
                    onTap: () => _generatePdf(prot),
                  ),
                );
              },
            ),
      floatingActionButton: widget.isAdmin ? FloatingActionButton(
        onPressed: _addProtocolDialog,
        backgroundColor: primaryColor,
        child: const Icon(Icons.add_task, color: Colors.white),
      ) : null,
    );
  }
}
