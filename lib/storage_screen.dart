import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'services/cloud_sync_service.dart';
import 'core/app_utils.dart';

class StorageScreen extends StatefulWidget {
  final bool isAdmin;
  final String userEmail;
  final String userGroup;
  const StorageScreen({super.key, required this.isAdmin, required this.userEmail, required this.userGroup});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  List<dynamic> _allOrders = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  final Color primaryColor = const Color(0xFF455A64);
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // POBIERZ Z CHMURY
    try {
      await CloudSyncService().downloadWarehouseOrders().timeout(const Duration(seconds: 5));
      await CloudSyncService().downloadEmployees().timeout(const Duration(seconds: 5));
    } catch (e) {}

    final String? data = prefs.getString('warehouse_orders_v1');
    if (data != null) {
      _allOrders = json.decode(data);
    }

    // FRESH LOAD of employees to ensure names are available
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
      debugPrint("Storage name mapping error: $e");
      final String? empData = prefs.getString('user_permissions');
      if (empData != null) {
        _employees = List<Map<String, dynamic>>.from(json.decode(empData));
      }
    }

    // Oznacz powiadomienia o zamówieniach jako przeczytane
    try {
      final String myEmail = widget.userEmail.toLowerCase().trim();
      final snap = await FirebaseFirestore.instance.collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();
      
      for (var doc in snap.docs) {
        final n = doc.data();
        bool isWarehouseNote = n['title'] == 'ZAMÓWIENIE MATERIAŁU' || n['title'].toString().contains('STATUS ZAMÓWIENIA');
        bool isForMe = n['target'] == 'all' || n['target'].toString().toLowerCase() == myEmail || (widget.isAdmin && n['target'] == 'admin');
        
        if (isWarehouseNote && isForMe) {
          await doc.reference.update({'isRead': true});
        }
      }
    } catch (e) {
      debugPrint("Błąd aktualizacji powiadomień magazynu: $e");
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('warehouse_orders_v1', AppUtils.safeJsonEncode(_allOrders));
    
    // WYŚLIJ DO CHMURY
    try {
      await CloudSyncService().uploadWarehouseOrders();
    } catch (e) {}
  }

  Future<void> _exportToPdf(Map<String, dynamic> order) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final bool isToolReq = order['type'] == 'TOOL_REQUEST';

    // Załaduj logo jeśli istnieje
    pw.MemoryImage? logoImage;
    try {
      final ByteData bytes = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    // Załaduj podpis jeśli istnieje
    pw.MemoryImage? signatureImage;
    if (order['signature_url'] != null) {
      try {
        final response = await Dio().get<List<int>>(
          order['signature_url'],
          options: Options(responseType: ResponseType.bytes),
        );
        if (response.data != null) {
          signatureImage = pw.MemoryImage(Uint8List.fromList(response.data!));
        }
      } catch (e) {
        debugPrint("Error loading signature for Storage PDF: $e");
      }
    }

    // Przygotuj dane do tabeli
    List items = [];
    if (order['items_structured'] != null) {
      items = order['items_structured'] as List;
    } else {
      // Fallback: parsuj tekst jeśli brak struktury (np. stary rekord)
      String text = order['items'] ?? "";
      List<String> lines = text.split('\n');
      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        if (line.contains(' - ')) {
          List<String> parts = line.split(' - ');
          items.add({
            'name': parts[0].trim(),
            'qty': parts.length > 1 ? parts[1].trim() : ""
          });
        } else {
          items.add({'name': line.trim(), 'qty': '-'});
        }
      }
    }

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Nagłówek firmowy
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoImage != null) pw.Image(logoImage, height: 60) else pw.Text("ES MANAGER", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(isToolReq ? 'ZAPOTRZEBOWANIE NA SPRZĘT' : 'ZAMÓWIENIE MATERIAŁU', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    if (order['order_no'] != null) pw.Text('Numer: ${order['order_no']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('Data: ${order['date'] ?? ''}'),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 20),
            
            // Informacje o budowie
            pw.Text(isToolReq ? 'CEL / OPIS:' : 'BUDOWA / ZLECENIE:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
            pw.Text(order['order_name'] ?? '-', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Text('ZGŁASZAJĄCY: ${_getName(order['author'])}', style: pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 30),

            // Tabela materiałów
            pw.TableHelper.fromTextArray(
              headers: ['LP', isToolReq ? 'NAZWA SPRZĘTU' : 'NAZWA MATERIAŁU', 'ILOŚĆ'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FixedColumnWidth(30),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(1),
              },
              data: List.generate(items.length, (index) => [
                (index + 1).toString(),
                items[index]['name'] ?? '-',
                items[index]['qty'] ?? '-'
              ]),
            ),

            pw.Spacer(),

            // Podpis i Stopka
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  children: [
                    if (signatureImage != null) 
                      pw.Image(signatureImage, height: 60)
                    else 
                      pw.SizedBox(height: 60),
                    pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5)))),
                    pw.Text('Podpis zamawiającego', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('zamówienie wygenerowane z ES MANAGER', style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColors.blue700)),
                    pw.Text('ES MANAGER SYSTEM v8.8.6', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    ));

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Zamowienie_${order['order_name']}.pdf');
  }

  Future<void> _cleanupOldOrders() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('USUWANIE ARCHIWALNYCH'),
        content: const Text('Czy chcesz trwale usunąć zamówienia o statusie "WYDANE" starsze niż 60 dni?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NIE')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('TAK, CZYŚĆ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final now = DateTime.now();
      int count = 0;
      List<dynamic> toDelete = [];
      
      _allOrders.removeWhere((o) {
        if (o['status'] == 'WYDANE') {
          try {
            String dateStr = o['date'];
            DateTime orderDate;
            if (dateStr.contains('.')) {
              List<String> parts = dateStr.split(' ')[0].split('.');
              int day = int.parse(parts[0]);
              int month = int.parse(parts[1]);
              int year = parts.length > 2 ? int.parse(parts[2]) : now.year;
              orderDate = DateTime(year, month, day);
            } else {
              orderDate = now; 
            }

            if (now.difference(orderDate).inDays > 60) {
              toDelete.add(o);
              count++;
              return true;
            }
          } catch (_) {}
        }
        return false;
      });

      if (count > 0) {
        await _saveData();
        // Usuń trwale z chmury każdy ze starych rekordów
        for (var o in toDelete) {
          await CloudSyncService().deleteWarehouseOrder(o);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Usunięto $count starych zamówień.')));
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nie znaleziono starych zamówień do usunięcia.')));
        }
      }
      setState(() => _isLoading = false);
    }
  }

  String _getName(String? email) {
    if (email == null || email.isEmpty) return "-";
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('MAGAZYN / ZAMÓWIENIA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          backgroundColor: const Color(0xFF001A2C),
          foregroundColor: Colors.white,
          actions: [
            if (widget.isAdmin)
              IconButton(
                icon: const Icon(Icons.cleaning_services), 
                onPressed: _cleanupOldOrders,
                tooltip: 'Usuń stare zamówienia',
              ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.orange,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'AKTYWNE'),
              Tab(text: 'WYDANE / ARCHIWUM'),
            ],
          ),
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.cardTheme.color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
                      boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Szukaj po nazwie budowy...',
                        hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3)),
                        prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildOrdersList(isHistory: false),
                      _buildOrdersList(isHistory: true),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildOrdersList({required bool isHistory}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final String userPos = widget.userGroup.toLowerCase();
    final bool isProcurement = userPos == 'zaopatrzenie' || userPos == 'biuro';
    final bool canSeeAll = widget.isAdmin || isProcurement;

    final filteredOrders = _allOrders.where((o) {
      final matchesSearch = o['order_name'].toString().toLowerCase().contains(_searchQuery);
      final isDone = o['status'] == 'WYDANE';
      
      bool isAuthorized = canSeeAll || (o['author'] == widget.userEmail);
      
      return matchesSearch && (isHistory ? isDone : !isDone) && isAuthorized;
    }).toList();

    if (filteredOrders.isEmpty) {
      return Center(child: Text(isHistory ? 'Brak zrealizowanych zamówień.' : 'Brak aktywnych zamówień.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3))));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filteredOrders.length,
      itemBuilder: (context, index) {
        final order = filteredOrders[index];
        final statusColor = _getStatusColor(order['status']);
        final bool isToolReq = order['type'] == 'TOOL_REQUEST';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: isDark ? 0 : 2,
          color: theme.cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), 
            side: BorderSide(color: isToolReq ? Colors.orange.withOpacity(0.3) : (theme.dividerTheme.color ?? Colors.white10))
          ),
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(isToolReq ? Icons.build_circle : Icons.shopping_cart, color: statusColor, size: 20),
              ),
              title: Row(
                children: [
                  Expanded(child: Text(order['order_name'], style: TextStyle(fontWeight: FontWeight.bold, color: isToolReq ? Colors.orange : theme.colorScheme.onSurface))),
                  if (order['order_no'] != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(order['order_no'], style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ),
                ],
              ),
              subtitle: Text('Od: ${_getName(order['author'])} | ${order['date']}', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.6))),
              trailing: PopupMenuButton<String>(
                onSelected: (String newVal) async {
                  setState(() { order['status'] = newVal; });
                  await _saveData();
                  if (order['order_id'] != null) {
                    await CloudSyncService().updateMaterialOrderStatus(order['order_id'], order['id'], newVal);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: statusColor.withOpacity(0.3))),
                  child: Text(order['status'], style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'NOWE', child: Text("NOWE")),
                  const PopupMenuItem(value: 'ZATWIERDZONE', child: Text("ZATWIERDZONE")),
                  const PopupMenuItem(value: 'ZAMÓWIONE', child: Text("ZAMÓWIONE")),
                  const PopupMenuItem(value: 'W REALIZACJI', child: Text("W REALIZACJI")),
                  const PopupMenuItem(value: 'DO ODBIORU', child: Text("DO ODBIORU")),
                  const PopupMenuItem(value: 'WYDANE', child: Text("WYDANE")),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LISTA MATERIAŁÓW:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: theme.colorScheme.primary)),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
                        child: Text(order['items'], style: TextStyle(fontSize: 13, height: 1.4, color: theme.colorScheme.onSurface)),
                      ),
                      if (order['link'] != null && order['link'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: InkWell(
                            onTap: () => launchUrl(Uri.parse(order['link'])),
                            child: Row(
                              children: [
                                const Icon(Icons.link, size: 16, color: Colors.blue),
                                const SizedBox(width: 8),
                                Expanded(child: Text(order['link'], style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline, fontSize: 12))),
                              ],
                            ),
                          ),
                        ),
                      if (order['photoUrl'] != null && order['photoUrl'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => showDialog(context: context, builder: (c) => Dialog(child: Image.network(order['photoUrl']))),
                              child: Image.network(order['photoUrl'], height: 150, width: double.infinity, fit: BoxFit.cover),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (widget.isAdmin || isProcurement)
                            _statusPicker(order)
                          else
                            const SizedBox(),
                          Row(
                            children: [
                              if (widget.isAdmin || isProcurement || (order['author'] == widget.userEmail && order['status'] == 'NOWE'))
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blueGrey),
                                  onPressed: () => _editOrderItems(order),
                                  tooltip: 'Edytuj listę',
                                ),
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                                onPressed: () => _exportToPdf(order),
                                tooltip: 'Exportuj do PDF',
                              ),
                              if (widget.isAdmin || isProcurement)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _deleteOrder(order),
                                  tooltip: 'Usuń zamówienie',
                                ),
                            ],
                          ),
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'NOWE': return Colors.blue;
      case 'ZATWIERDZONE': return Colors.teal;
      case 'ZAMÓWIONE': return Colors.orange;
      case 'W REALIZACJI': return Colors.indigo;
      case 'DO ODBIORU': return Colors.purple;
      case 'WYDANE': return Colors.green;
      default: return Colors.grey;
    }
  }

  Widget _statusPicker(Map<String, dynamic> order) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(canvasColor: theme.cardTheme.color),
      child: DropdownButton<String>(
        value: ['NOWE', 'ZATWIERDZONE', 'ZAMÓWIONE', 'W REALIZACJI', 'DO ODBIORU', 'WYDANE'].contains(order['status']) ? order['status'] : 'NOWE',
        underline: const SizedBox(),
        dropdownColor: theme.cardTheme.color,
        style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 12),
        items: ['NOWE', 'ZATWIERDZONE', 'ZAMÓWIONE', 'W REALIZACJI', 'DO ODBIORU', 'WYDANE'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (val) async {
          setState(() {
            order['status'] = val;
          });
          await _saveData();
          if (order['order_id'] != null) {
            await CloudSyncService().updateMaterialOrderStatus(order['order_id'], order['id'], val!);
          }
          _notifyUser(order);
        },
      ),
    );
  }

  void _notifyUser(Map<String, dynamic> order) async {
    final prefs = await SharedPreferences.getInstance();
    final String? noteData = prefs.getString('company_notifications_v2');
    List<Map<String, dynamic>> notifications = noteData != null ? List<Map<String, dynamic>>.from(json.decode(noteData)) : [];
    
    notifications.insert(0, {
      'title': 'STATUS ZAMÓWIENIA: ${order['status']}',
      'content': 'Status zamówienia dla budowy ${order['order_name']} zmienił się na: ${order['status']}',
      'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
      'target': order['author'],
      'isRead': false,
      'isArchived': false,
      'author': 'Magazyn',
    });
    
    await prefs.setString('company_notifications_v2', AppUtils.safeJsonEncode(notifications));
  }

  void _editOrderItems(Map<String, dynamic> order) {
    List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(order['items_structured'] ?? []);
    if (items.isEmpty && order['items'] != null) {
      // Parse legacy text if needed
      for (var line in order['items'].toString().split('\n')) {
        if (line.trim().isEmpty) continue;
        if (line.contains(' - ')) {
          var p = line.split(' - ');
          items.add({'name': p[0].trim(), 'qty': p[1].trim()});
        } else {
          items.add({'name': line.trim(), 'qty': '-'});
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('EDYTUJ POZYCJE ZAMÓWIENIA'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...items.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: TextFormField(initialValue: e.value['name'], decoration: const InputDecoration(labelText: "Materiał", border: OutlineInputBorder()), onChanged: (v) => items[e.key]['name'] = v)),
                        const SizedBox(width: 8),
                        Expanded(flex: 1, child: TextFormField(initialValue: e.value['qty'], decoration: const InputDecoration(labelText: "Ilość", border: OutlineInputBorder()), onChanged: (v) => items[e.key]['qty'] = v)),
                        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setDS(() => items.removeAt(e.key))),
                      ],
                    ),
                  )),
                  const SizedBox(height: 12),
                  TextButton.icon(onPressed: () => setDS(() => items.add({'name': '', 'qty': ''})), icon: const Icon(Icons.add_circle_outline), label: const Text("DODAJ POZYCJĘ")),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
            ElevatedButton(
            onPressed: () async {
              setState(() {
                order['items_structured'] = items.where((it) => it['name']!.isNotEmpty).toList();
                order['items'] = items.where((it) => it['name']!.isNotEmpty).map((it) => "${it['name']} - ${it['qty']}").join("\n");
              });
              await _saveData();
              
              // Synchronizacja chirurgiczna ze zleceniem
              if (order['order_id'] != null) {
                await CloudSyncService().updateMaterialOrderItems(
                  order['order_id'], 
                  order['id'], 
                  order['items'], 
                  order['items_structured']
                );
              }
              
              if (context.mounted) Navigator.pop(context);
            }, 
            child: const Text('ZAPISZ ZMIANY')
          ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteOrder(Map<String, dynamic> order) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('USUŃ ZAMÓWIENIE?'),
        content: const Text('Czy na pewno chcesz usunąć to zamówienie z magazynu oraz powiązanego zlecenia?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NIE')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('TAK, USUŃ', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _allOrders.remove(order);
      });
      await _saveData();
      
      // Trwałe usunięcie z chmury (Firebase)
      await CloudSyncService().deleteWarehouseOrder(order);

      // Synchronizacja: usuń ze zlecenia (OrdersScreen)
      try {
        final prefs = await SharedPreferences.getInstance();
        final String? ordersData = prefs.getString('company_orders_v2');
        if (ordersData != null) {
          List<dynamic> orders = json.decode(ordersData);
          bool changed = false;
          
          for (var o in orders) {
            if (o['name'] == order['order_name'] && o['material_orders'] != null) {
              List matOrders = o['material_orders'] as List;
              int countBefore = matOrders.length;
              matOrders.removeWhere((mo) => 
                (mo['id'] != null && mo['id'] == order['id']) ||
                (mo['items'] == order['items'] && 
                 mo['date'] == order['date'] && 
                 mo['author'] == order['author'])
              );
              if (matOrders.length != countBefore) changed = true;
            }
          }
          
          if (changed) {
            await prefs.setString('company_orders_v2', AppUtils.safeJsonEncode(orders));
            await CloudSyncService().uploadOrders();
          }
        }
      } catch (e) {
        debugPrint("Błąd synchronizacji usuwania ze zleceń: $e");
      }
    }
  }
}
