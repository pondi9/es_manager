import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/app_theme.dart';
import 'services/cloud_sync_service.dart';

class EstimationsScreen extends StatefulWidget {
  final bool isAdmin;
  final String currentUserEmail;
  const EstimationsScreen({super.key, required this.isAdmin, required this.currentUserEmail});

  @override
  State<EstimationsScreen> createState() => _EstimationsScreenState();
}

class _EstimationsScreenState extends State<EstimationsScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _estimations = [];
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _priceList = [];
  bool _isLoading = true;
  late TabController _tabController;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // 1. Pobierz Cennik
      final priceSnap = await FirebaseFirestore.instance.collection('settings').doc('price_list').get();
      if (priceSnap.exists) {
        _priceList = List<Map<String, dynamic>>.from(priceSnap.data()?['items'] ?? []);
      } else {
        // Domyślne pozycje jeśli pusto
        _priceList = [
          {'name': 'Punkt elektryczny (robocizna)', 'price': 80.0, 'unit': 'szt.'},
          {'name': 'Montaż rozdzielni (do 24 mod)', 'price': 400.0, 'unit': 'szt.'},
          {'name': 'Układanie kabla YDYp 3x1.5', 'price': 5.5, 'unit': 'mb'},
        ];
      }

      // 2. Pobierz Klientów
      final clientSnap = await FirebaseFirestore.instance.collection('clients').get();
      _clients = clientSnap.docs.map((d) => d.data()).toList();

      // 3. Pobierz Wyceny
      final estSnap = await FirebaseFirestore.instance.collection('estimations').orderBy('timestamp', descending: true).get();
      _estimations = estSnap.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

    } catch (e) {
      debugPrint("Error loading estimations: $e");
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _savePriceList() async {
    await FirebaseFirestore.instance.collection('settings').doc('price_list').set({'items': _priceList});
  }

  void _showPriceListEditor() {
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: const Text("CENNIK USŁUG"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _priceList.length,
              itemBuilder: (c, i) => ListTile(
                title: Text(_priceList[i]['name']),
                subtitle: Text("${_priceList[i]['price']} zł / ${_priceList[i]['unit']}"),
                trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                  setDS(() => _priceList.removeAt(i));
                  _savePriceList();
                }),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("ZAMKNIJ")),
            ElevatedButton(onPressed: () {
              final nCtrl = TextEditingController();
              final pCtrl = TextEditingController();
              final uCtrl = TextEditingController(text: "szt.");
              showDialog(context: context, builder: (c2) => AlertDialog(
                title: const Text("NOWA POZYCJA"),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: nCtrl, decoration: const InputDecoration(labelText: "Nazwa usługi")),
                  TextField(controller: pCtrl, decoration: const InputDecoration(labelText: "Cena netto"), keyboardType: TextInputType.number),
                  TextField(controller: uCtrl, decoration: const InputDecoration(labelText: "Jednostka (szt./mb/h)")),
                ]),
                actions: [
                  ElevatedButton(onPressed: () {
                    if (nCtrl.text.isNotEmpty) {
                      setDS(() => _priceList.add({'name': nCtrl.text, 'price': double.tryParse(pCtrl.text) ?? 0.0, 'unit': uCtrl.text}));
                      _savePriceList();
                      Navigator.pop(c2);
                    }
                  }, child: const Text("DODAJ"))
                ],
              ));
            }, child: const Text("DODAJ USŁUGĘ")),
          ],
        ),
      ),
    );
  }

  void _createNewEstimation() {
    String? selectedClient;
    final titleCtrl = TextEditingController();
    List<Map<String, dynamic>> selectedItems = [];

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDS) {
          double total = selectedItems.fold(0, (sum, item) => sum + (item['price'] * item['qty']));
          
          return AlertDialog(
            title: const Text("NOWA WYCENA"),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Tytuł / Nazwa projektu")),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: "Wybierz klienta"),
                      items: _clients.map((cl) => DropdownMenuItem(value: cl['name'].toString(), child: Text(cl['name']))).toList(),
                      onChanged: (v) => selectedClient = v,
                    ),
                    const Divider(height: 40),
                    const Text("POZYCJE WYCENY:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ...selectedItems.asMap().entries.map((entry) {
                      int i = entry.key;
                      return ListTile(
                        dense: true,
                        title: Text(selectedItems[i]['name']),
                        subtitle: Text("${selectedItems[i]['price']} zł x ${selectedItems[i]['qty']} ${selectedItems[i]['unit']}"),
                        trailing: Text("${(selectedItems[i]['price'] * selectedItems[i]['qty']).toStringAsFixed(2)} zł"),
                        onLongPress: () => setDS(() => selectedItems.removeAt(i)),
                      );
                    }).toList(),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () {
                        showDialog(context: context, builder: (c3) => AlertDialog(
                          title: const Text("DODAJ Z CENNIKA"),
                          content: SizedBox(width: double.maxFinite, child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _priceList.length,
                            itemBuilder: (c, i) => ListTile(
                              title: Text(_priceList[i]['name']),
                              subtitle: Text("${_priceList[i]['price']} zł"),
                              onTap: () {
                                final qCtrl = TextEditingController(text: "1");
                                showDialog(context: context, builder: (c4) => AlertDialog(
                                  title: Text("ILOŚĆ: ${_priceList[i]['name']}"),
                                  content: TextField(controller: qCtrl, keyboardType: TextInputType.number, autofocus: true),
                                  actions: [ElevatedButton(onPressed: () {
                                    setDS(() => selectedItems.add({
                                      'name': _priceList[i]['name'],
                                      'price': _priceList[i]['price'],
                                      'unit': _priceList[i]['unit'],
                                      'qty': double.tryParse(qCtrl.text) ?? 1.0,
                                    }));
                                    Navigator.pop(c4);
                                    Navigator.pop(c3);
                                  }, child: const Text("DODAJ"))],
                                ));
                              },
                            ),
                          )),
                        ));
                      },
                      icon: const Icon(Icons.add_shopping_cart, size: 16),
                      label: const Text("DODAJ POZYCJĘ"),
                    ),
                    const Divider(),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text("SUMA NETTO:", style: TextStyle(fontWeight: FontWeight.bold)),
                      Text("${total.toStringAsFixed(2)} zł", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.blue, fontSize: 18)),
                    ]),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANULUJ")),
              ElevatedButton(onPressed: () async {
                if (titleCtrl.text.isNotEmpty && selectedClient != null) {
                  await FirebaseFirestore.instance.collection('estimations').add({
                    'title': titleCtrl.text,
                    'client': selectedClient,
                    'items': selectedItems,
                    'total': total,
                    'status': 'WERSJA ROBOCZA',
                    'date': DateFormat('dd.MM.yyyy').format(DateTime.now()),
                    'timestamp': FieldValue.serverTimestamp(),
                    'author': widget.currentUserEmail,
                  });
                  Navigator.pop(c);
                  _loadData();
                }
              }, child: const Text("ZAPISZ WYCENĘ")),
            ],
          );
        }
      ),
    );
  }

  Future<void> _generatePDF(Map<String, dynamic> est) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(pw.Page(
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('OFERTA / WYCENA', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.Text('Data: ${est['date']}'),
            ]),
            pw.SizedBox(height: 40),
            pw.Text('KLIENT: ${est['client']}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('PROJEKT: ${est['title']}'),
            pw.SizedBox(height: 40),
            pw.TableHelper.fromTextArray(
              headers: ['Nazwa usługi', 'Ilość', 'Cena jedn.', 'Suma'],
              data: (est['items'] as List).map((it) => [
                it['name'],
                "${it['qty']} ${it['unit']}",
                "${it['price']} zł",
                "${(it['price'] * it['qty']).toStringAsFixed(2)} zł"
              ]).toList(),
            ),
            pw.SizedBox(height: 40),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('RAZEM NETTO:', style: pw.TextStyle(fontSize: 14)),
                pw.Text("${est['total'].toStringAsFixed(2)} zł", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              ]),
            ]),
            pw.SizedBox(height: 100),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('........................\nPodpis Wykonawcy', textAlign: pw.TextAlign.center),
              pw.Text('........................\nPodpis Klienta', textAlign: pw.TextAlign.center),
            ]),
          ],
        );
      },
    ));

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Wycena_${est['client']}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("WYCENY I OFERTY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.settings_applications), onPressed: _showPriceListEditor, tooltip: "Cennik"),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orange,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [Tab(text: "AKTYWNE"), Tab(text: "ZAAKCEPTOWANE")],
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildEstList(status: 'robocza'),
              _buildEstList(status: 'zaakceptowana'),
            ],
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewEstimation,
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add_chart, color: Colors.white),
      ),
    );
  }

  Widget _buildEstList({required String status}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final list = _estimations.where((e) {
      bool matchStatus = status == 'robocza' ? e['status'] != 'ZAAKCEPTOWANA' : e['status'] == 'ZAAKCEPTOWANA';
      return matchStatus;
    }).toList();

    if (list.isEmpty) return Center(child: Text("Brak wycen.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3))));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (c, i) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        color: theme.cardTheme.color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: theme.dividerTheme.color ?? Colors.white10)),
        elevation: isDark ? 0 : 2,
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          title: Text(list[i]['title'] ?? 'Wycena', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          subtitle: Text("${list[i]['client']} | ${list[i]['date']}", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text("${list[i]['total'].toStringAsFixed(2)} zł", style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF007BFF))),
            Text(list[i]['status'], style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.3))),
          ]),
          onTap: () {
            showModalBottomSheet(context: context, backgroundColor: theme.cardTheme.color, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))), builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: const Icon(Icons.picture_as_pdf, color: Colors.red), title: Text("Generuj PDF", style: TextStyle(color: theme.colorScheme.onSurface)), onTap: () { Navigator.pop(c); _generatePDF(list[i]); }),
              ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: Text("Oznacz jako ZAAKCEPTOWANA", style: TextStyle(color: theme.colorScheme.onSurface)), onTap: () async {
                await FirebaseFirestore.instance.collection('estimations').doc(list[i]['id']).update({'status': 'ZAAKCEPTOWANA'});
                Navigator.pop(c);
                _loadData();
              }),
              ListTile(leading: const Icon(Icons.delete_outline, color: Colors.grey), title: Text("Usuń wycenę", style: TextStyle(color: theme.colorScheme.onSurface)), onTap: () async {
                await FirebaseFirestore.instance.collection('estimations').doc(list[i]['id']).delete();
                Navigator.pop(c);
                _loadData();
              }),
            ])));
          },
        ),
      ),
    );
  }
}
