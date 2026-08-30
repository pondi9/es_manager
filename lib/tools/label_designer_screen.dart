import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class LabelDesignerScreen extends StatefulWidget {
  final List<String>? initialLabels;
  const LabelDesignerScreen({super.key, this.initialLabels});
  @override
  State<LabelDesignerScreen> createState() => _LabelDesignerScreenState();
}

class _LabelDesignerScreenState extends State<LabelDesignerScreen> {
  List<Map<String, dynamic>> _items = [];
  final Color primaryColor = const Color(0xFF263238);
  double _fontSize = 12;
  bool _isBold = false;
  String _printMode = "TAPE"; 
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;
  bool _isScanning = false;
  bool _isPrinting = false;
  bool _isConnecting = false;
  String _statusMessage = "Gotowy";
  List<ScanResult> _scanResults = [];

  @override
  void initState() { super.initState(); _initItems(); }

  void _initItems() {
    if (widget.initialLabels != null && widget.initialLabels!.isNotEmpty) {
      _items = widget.initialLabels!.where((t) => t.trim().isNotEmpty).map((t) => {'text': t.trim(), 'qty': 1}).toList();
    }
    if (_items.isEmpty) _items.add({'text': '', 'qty': 1});
  }

  void _addItem() { setState(() => _items.add({'text': '', 'qty': 1})); }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
  }

  void _startScan() async {
    if (kIsWeb) return;
    await _requestPermissions();
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) return;
    setState(() { _isScanning = true; _scanResults.clear(); });
    try {
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      FlutterBluePlus.scanResults.listen((results) { if (mounted) setState(() { _scanResults = results; }); });
    } catch (e) {}
    Future.delayed(const Duration(seconds: 10), () { if (mounted) setState(() { _isScanning = false; }); });
  }

  void _showPrintDialog() {
    if (kIsWeb) { _printPdfWeb(); return; }
    _startScan();
    showDialog(
      context: context,
      barrierDismissible: !_isPrinting,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return StreamBuilder<List<ScanResult>>(
            stream: FlutterBluePlus.scanResults,
            builder: (context, snapshot) {
              final results = snapshot.data ?? _scanResults;
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text('CENTRUM TESTOWE v5.1'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_connectedDevice == null) ...[
                          const Text('KROK 1: Wybierz drukarkę', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          if (_isScanning) const LinearProgressIndicator(),
                          Container(
                            height: 180,
                            margin: const EdgeInsets.only(top: 10),
                            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                            child: ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (c, i) => ListTile(
                                leading: Icon(Icons.bluetooth, color: _isConnecting ? Colors.grey : Colors.blue),
                                title: Text(results[i].device.platformName.isNotEmpty ? results[i].device.platformName : 'Urządzenie ${results[i].device.remoteId}', style: const TextStyle(fontSize: 11)),
                                subtitle: const Text('Kliknij aby połączyć', style: TextStyle(fontSize: 9)),
                                trailing: _isConnecting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                                onTap: _isConnecting ? null : () async {
                                  setDialogState(() { _isConnecting = true; });
                                  try {
                                    await results[i].device.connect().timeout(const Duration(seconds: 8));
                                    List<BluetoothService> services = await results[i].device.discoverServices();
                                    for (var s in services) {
                                      if (s.uuid.toString().toLowerCase().contains('be3dd650')) {
                                        for (var char in s.characteristics) {
                                          if (char.uuid.toString().toLowerCase().contains('be3dd651')) { _writeChar = char; }
                                        }
                                      }
                                    }
                                    setState(() { _connectedDevice = results[i].device; });
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd: $e')));
                                  } finally {
                                    if (mounted) setDialogState(() { _isConnecting = false; });
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () { setState(() { _connectedDevice = results.isNotEmpty ? results.first.device : null; }); setDialogState((){}); },
                            child: const Text('WEJDŹ DO TESTÓW MIMO WSZYSTKO (AWARYJNIE)', style: TextStyle(fontSize: 9, color: Colors.orange)),
                          ),
                        ] else ...[
                          const Icon(Icons.check_circle, color: Colors.green, size: 40),
                          const Text('POŁĄCZONO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
                          const Divider(height: 30),
                          
                          _testButton("OPCJA A: Raster 8B", Colors.blue, () => _runTest(1, setDialogState)),
                          _testButton("OPCJA B: Raster 16B", Colors.indigo, () => _runTest(2, setDialogState)),
                          _testButton("OPCJA C: Tekst ASCII", Colors.teal, () => _runTest(3, setDialogState)),
                          _testButton("OPCJA D: Sam wysuw", Colors.orange, () => _runTest(4, setDialogState)),
                          _testButton("OPCJA E: Thermal Kick", Colors.red, () => _runTest(5, setDialogState)),
                          
                          if (_isPrinting) ...[
                            const SizedBox(height: 10),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 5),
                            Text(_statusMessage, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                          ],

                          const SizedBox(height: 15),
                          TextButton(onPressed: () async { if (_connectedDevice != null) await _connectedDevice!.disconnect(); setState(() { _connectedDevice = null; _writeChar = null; }); setDialogState(() {}); _startScan(); }, child: const Text('ROZŁĄCZ', style: TextStyle(color: Colors.red, fontSize: 10))),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [ if (!_isPrinting) TextButton(onPressed: () => Navigator.pop(context), child: const Text('ZAMKNIJ')) ],
              );
            }
          );
        }
      ),
    );
  }

  Widget _testButton(String label, Color color, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isPrinting ? null : onPressed,
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }

  Future<void> _runTest(int mode, Function setDialogState) async {
    // Jeśli writeChar jest null, spróbuj go znaleźć na szybko
    if (_writeChar == null && _connectedDevice != null) {
       List<BluetoothService> services = await _connectedDevice!.discoverServices();
       for (var s in services) {
         if (s.uuid.toString().toLowerCase().contains('be3dd650')) {
           for (var char in s.characteristics) {
             if (char.uuid.toString().toLowerCase().contains('be3dd651')) { _writeChar = char; }
           }
         }
       }
    }

    if (_writeChar == null) {
      setDialogState(() { _statusMessage = "Błąd: Brak kanału 651!"; });
      return;
    }

    setDialogState(() { _isPrinting = true; _statusMessage = "Start..."; });

    try {
      await _writeChar!.write([0x1b, 0x40], withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 300));

      if (mode == 1) {
        for(int i=0; i<80; i++) {
          await _writeChar!.write([0x16, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff], withoutResponse: false);
          await Future.delayed(const Duration(milliseconds: 50));
        }
      } else if (mode == 2) {
        for(int i=0; i<50; i++) {
          await _writeChar!.write([0x16, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff], withoutResponse: false);
          await Future.delayed(const Duration(milliseconds: 70));
        }
      } else if (mode == 3) {
        await _writeChar!.write(utf8.encode("TEST DYMO"), withoutResponse: false);
      } else if (mode == 4) {
        for(int i=0; i<40; i++) {
          await _writeChar!.write([0x0a, 0x0d], withoutResponse: false);
          await Future.delayed(const Duration(milliseconds: 30));
        }
      } else if (mode == 5) {
        for(int i=0; i<40; i++) {
          await _writeChar!.write([0x1b, 0x73, 0x01], withoutResponse: false);
          await _writeChar!.write([0x16, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff], withoutResponse: false);
          await Future.delayed(const Duration(milliseconds: 80));
        }
      }

      await _writeChar!.write([0x1b, 0x45], withoutResponse: false);
      setDialogState(() { _isPrinting = false; _statusMessage = "ZAKOŃCZONO!"; });
    } catch (e) {
      setDialogState(() { _isPrinting = false; _statusMessage = "Błąd: $e"; });
    }
  }

  void _printPdfWeb() async {
    try {
      final pdf = await _generatePdfDoc();
      await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Labels');
    } catch (e) {}
  }

  Future<pw.Document> _generatePdfDoc() async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    pdf.addPage(pw.Page(pageFormat: const PdfPageFormat(25.0 * PdfPageFormat.cm, 1.2 * PdfPageFormat.cm, marginAll: 0), build: (context) => pw.Row(children: _items.expand((item) => List<pw.Widget>.generate(item['qty'], (index) => pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 10), child: pw.Center(child: pw.Text(item['text'], style: pw.TextStyle(font: font, fontSize: _fontSize)))))).toList())));
    return pdf;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text('EDYTOR ETYKIET v5.1'), backgroundColor: primaryColor, foregroundColor: Colors.white, actions: [IconButton(icon: const Icon(Icons.print), onPressed: _showPrintDialog)]),
      body: Column(children: [
        Container(padding: const EdgeInsets.all(12), color: Colors.white, child: Row(children: [
          Expanded(child: DropdownButtonFormField<String>(value: _printMode, items: const [DropdownMenuItem(value: "TAPE", child: Text('Taśma 12mm'))], onChanged: (v) => setState(() => _printMode = v!))),
          const SizedBox(width: 8),
          Expanded(child: Slider(value: _fontSize, min: 6, max: 24, divisions: 18, onChanged: (v) => setState(() => _fontSize = v))),
        ])),
        Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: _items.length, itemBuilder: (context, index) => Card(elevation: 0, margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[300]!)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
          Text('${index + 1}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(width: 10),
          Expanded(child: TextField(decoration: const InputDecoration(hintText: 'Tekst...', border: InputBorder.none), onChanged: (v) => _items[index]['text'] = v, controller: TextEditingController(text: _items[index]['text'])..selection = TextSelection.collapsed(offset: _items[index]['text'].length))),
          IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 16), onPressed: () => setState(() => _items.removeAt(index))),
        ]))))),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: _addItem, backgroundColor: Colors.teal[700], child: const Icon(Icons.add, color: Colors.white)),
    );
  }
}
