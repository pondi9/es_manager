import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:signature/signature.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'core/app_theme.dart';
import 'core/app_constants.dart';
import 'core/app_utils.dart';
import 'services/cloud_sync_service.dart';
import 'tools/db_labels_screen.dart';
import 'tools/lan_labels_screen.dart';
import 'tools/schematic_creator_screen.dart';
import 'widgets/es_modal.dart';
import 'issues_screen.dart';

// --- SHARED HELPERS ---
String _getEmpName(String? email, List employees, List clients) {
  if (email == null || email.isEmpty) return "-";
  final String sMail = email.trim().toLowerCase();
  if (sMail == 'admin' || sMail == 'escrm@int.pl') return "Administrator";
  try {
    final emp = employees.firstWhere((e) => (e['email'] ?? '').toString().toLowerCase() == sMail || (e['id'] ?? '').toString().toLowerCase() == sMail, orElse: () => null);
    if (emp != null) return "${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}".trim();
  } catch (_) {}
  return email;
}

Future<bool?> _showConfirm(BuildContext context, String title, String content) {
  return showDialog<bool>(context: context, builder: (c) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    content: Text(content),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("ANULUJ")),
      ElevatedButton(onPressed: () => Navigator.pop(c, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("POTWIERDŹ")),
    ],
  ));
}

Widget _sharedSectionLabel(String l, BuildContext context) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 12), 
    child: Text(
      l.toUpperCase(), 
      style: GoogleFonts.montserrat(
        color: theme.colorScheme.onSurface.withOpacity(0.4), 
        fontWeight: FontWeight.w900, 
        fontSize: 9, 
        letterSpacing: 1.5
      )
    )
  );
}

InputDecoration _sharedInputDec(String l, IconData i, BuildContext context) {
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: l,
    labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.bold),
    prefixIcon: Icon(i, color: const Color(0xFF007BFF), size: 20),
    filled: true, 
    fillColor: theme.colorScheme.onSurface.withOpacity(0.05),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

// --- PDF GENERATION ---
Future<void> _genMaterialPDF(Map<String, dynamic> m, Map<String, dynamic> order, List employees, List clients) async {
  final pdf = pw.Document();
  final font = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();
  pw.MemoryImage? logo;
  try { final b = await rootBundle.load('assets/logo.png'); logo = pw.MemoryImage(b.buffer.asUint8List()); } catch (_) {}
  pw.MemoryImage? sig;
  if (m['signature_url'] != null) {
    try {
      final r = await Dio().get<List<int>>(m['signature_url'], options: Options(responseType: ResponseType.bytes));
      if (r.data != null) sig = pw.MemoryImage(Uint8List.fromList(r.data!));
    } catch (_) {}
  }
  List items = m['items_structured'] ?? [];
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    theme: pw.ThemeData.withFont(base: font, bold: fontBold),
    build: (pw.Context context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        if (logo != null) pw.Image(logo, height: 60) else pw.Text("ES MANAGER", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [ 
           pw.Text('ZAMÓWIENIE MATERIAŁU', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
           if (m['order_no'] != null) pw.Text('Nr: ${m['order_no']}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
           pw.Text('Data: ${m['date'] ?? ''}') 
        ]),
      ]),
      pw.Divider(thickness: 2), pw.SizedBox(height: 20),
      pw.Text('BUDOWA / ZLECENIE:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
      pw.Text(order['name'] ?? '-', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),
      pw.Text('ZAMAWIAJĄCY: ${m['author'] ?? '-'}', style: pw.TextStyle(fontSize: 11)),
      pw.SizedBox(height: 30),
      pw.TableHelper.fromTextArray(
        headers: ['LP', 'NAZWA MATERIAŁU', 'ILOŚĆ'],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
        data: List.generate(items.length, (i) => [(i+1).toString(), items[i]['name'] ?? '-', items[i]['qty'] ?? '-']),
      ),
      pw.Spacer(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Column(children: [ if (sig != null) pw.Image(sig, height: 60) else pw.SizedBox(height: 60), pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5)))), pw.Text('Podpis zamawiającego', style: const pw.TextStyle(fontSize: 8)) ], crossAxisAlignment: pw.CrossAxisAlignment.center),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [ pw.Text('zamówienie wygenerowane z ES MANAGER', style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColors.blue700)), pw.Text('ES MANAGER SYSTEM v${AppConstants.appVersion}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)) ]),
      ]),
    ])
  ));
  await Printing.layoutPdf(onLayout: (f) async => pdf.save(), name: 'Zamowienie_${order['name']}.pdf');
}

// --- MAIN SCREEN ---
class OrdersScreen extends StatefulWidget {
  final bool isAdmin;
  final String currentUserEmail;
  final Map<String, dynamic>? userPermissions;
  const OrdersScreen({super.key, required this.isAdmin, required this.currentUserEmail, this.userPermissions});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _tools = [];
  List<Map<String, dynamic>> _clients = [];
  List<String> _groups = [];
  bool _isLoading = true;
  bool _showArchived = false;
  SharedPreferences? _prefs;

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final empSnap = await FirebaseFirestore.instance.collection('employees').get();
      _employees = empSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      final orderSnap = await FirebaseFirestore.instance.collection('orders').get();
      _orders = orderSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      final toolSnap = await FirebaseFirestore.instance.collection('tools').get();
      _tools = toolSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      final clientSnap = await FirebaseFirestore.instance.collection('clients').get();
      _clients = clientSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      _groups = _prefs?.getStringList('job_groups') ?? ['Ekipa 1', 'Ekipa 2', 'Stadion', 'Biuro'];
      await _prefs?.setString('company_orders_v2', AppUtils.safeJsonEncode(_orders));
      await _prefs?.setString('company_tools_v1', AppUtils.safeJsonEncode(_tools));
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      final String? oD = _prefs?.getString('company_orders_v2'); 
      if (oD != null) _orders = List<Map<String, dynamic>>.from(json.decode(oD));
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveOrders() async { 
    if (_prefs != null) { 
      await _prefs!.setString('company_orders_v2', AppUtils.safeJsonEncode(_orders)); 
      await CloudSyncService().uploadOrders(); 
    } 
  }
  Future<void> _saveTools() async { if (_prefs != null) { await _prefs!.setString('company_tools_v1', AppUtils.safeJsonEncode(_tools)); await CloudSyncService().uploadTools(); } }

  bool _canEdit() => widget.isAdmin || (widget.userPermissions?['manage_orders'] == true);

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final disp = _orders.where((o) => (o['status'] == 'ZAKOŃCZONO') == _showArchived).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_showArchived ? "ARCHIWUM" : "ZLECENIA"), 
        actions: [
          if (_canEdit() && !_showArchived) IconButton(icon: const Icon(Icons.add_circle_outline, size: 28), onPressed: () => _showFullOrderDialog()),
          IconButton(icon: Icon(_showArchived ? Icons.business_center : Icons.archive_outlined), onPressed: () => setState(() => _showArchived = !_showArchived)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () { setState(() => _isLoading = true); _loadData(); }),
        ]
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: disp.isEmpty 
          ? Center(child: Text("Brak zleceń.", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26)))
          : ListView.builder(padding: const EdgeInsets.all(12), itemCount: disp.length, itemBuilder: (c, i) => _orderCard(disp[i])),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    List stages = order['stages'] as List? ?? [];
    int done = stages.where((s) => s['status'] == 'ZAKOŃCZONO').length;
    double progress = stages.isEmpty ? 0 : done / stages.length;
    Color sc = progress == 1.0 ? Colors.green : (progress > 0 ? Colors.orange : Colors.blue);
    if (order['status'] == 'ZAKOŃCZONO') sc = Colors.grey;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.cardTheme.color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: sc.withOpacity(0.5), width: 1.5)),
      child: InkWell(
        onTap: () async {
          final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailView(order: order, isAdmin: widget.isAdmin, currentUserEmail: widget.currentUserEmail, getName: (e) => _getEmpName(e, _employees, _clients), saveOrders: _saveOrders, saveTools: _saveTools, toolsDB: _tools, canEdit: _canEdit(), tools: _tools, clients: _clients, prefs: _prefs)));
          if (res == 'EDIT') _showFullOrderDialog(order: order);
          _loadData();
        },
        child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: sc.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.apartment_rounded, color: sc, size: 24)),
            title: Text(order['name'] ?? 'Zlecenie', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
            subtitle: Text(order['location'] ?? 'Brak adresu', style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38)),
            trailing: Text("${(progress*100).round()}%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: sc)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _actBtn(Icons.near_me, "MAPA", Colors.green, () => _launchMap(order['location'])),
            const SizedBox(width: 8),
            if (_canEdit()) _actBtn(Icons.edit, "EDYTUJ", const Color(0xFF007BFF), () => _showFullOrderDialog(order: order)),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: isDark ? Colors.white10 : Colors.black12),
          ]),
        ])),
      ),
    );
  }

  Widget _actBtn(IconData i, String l, Color c, VoidCallback t) => ElevatedButton.icon(onPressed: t, icon: Icon(i, size: 14), label: Text(l, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: c.withOpacity(0.1), foregroundColor: c, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));

  void _launchMap(String? l) async {
    if (l == null || l.isEmpty) return;
    final u = Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(l)}");
    if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  void _showFullOrderDialog({Map<String, dynamic>? order}) {
    final nC = TextEditingController(text: order?['name']);
    final lC = TextEditingController(text: order?['location']);
    final startC = TextEditingController(text: order?['startDate']);
    final endC = TextEditingController(text: order?['endDate']);
    final codeC = TextEditingController(text: order?['client_access_code']);
    String stat = order?['status'] ?? 'NOWE';
    String? selResp = order?['responsible_person'];
    List<String> selCrews = List<String>.from(order?['assigned_crews'] ?? []);
    List<String> selEmps = List<String>.from(order?['assigned_employees'] ?? []);
    List stages = List.from(order?['stages'] ?? []);

    showEsModal(context, title: order == null ? "NOWE ZLECENIE" : "EDYTUJ ZLECENIE", maxWidth: 800, content: StatefulBuilder(builder: (ctx, setDS) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sharedSectionLabel("INFORMACJE OGÓLNE", ctx),
        _field(nC, "Nazwa budowy", Icons.apartment, ctx),
        const SizedBox(height: 12),
        _field(lC, "Lokalizacja", Icons.location_on, ctx),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _field(startC, "Start", Icons.calendar_today, ctx, readOnly: true, onTap: () async {
            final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2030));
            if (d != null) setDS(() => startC.text = DateFormat('dd.MM.yyyy').format(d));
          })),
          const SizedBox(width: 12),
          Expanded(child: _field(endC, "Koniec", Icons.event_available, ctx, readOnly: true, onTap: () async {
            final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2030));
            if (d != null) setDS(() => endC.text = DateFormat('dd.MM.yyyy').format(d));
          })),
        ]),
        const SizedBox(height: 12),
        _field(codeC, "KOD KLIENTA", Icons.vpn_key_rounded, ctx),
        const SizedBox(height: 16),
        _sharedSectionLabel("STATUS I ODPOWIEDZIALNOŚĆ", ctx),
        DropdownButtonFormField<String>(
          value: stat,
          decoration: _sharedInputDec("Status zlecenia", Icons.info_outline, ctx),
          items: ['NOWE', 'W TRAKCIE', 'ZAKOŃCZONO'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (v) => setDS(() => stat = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _employees.any((e) => (e['email'] ?? e['id']) == selResp) ? selResp : null,
          decoration: _sharedInputDec("Osoba odpowiedzialna", Icons.person_pin_rounded, ctx),
          items: _employees.map((e) => DropdownMenuItem(value: (e['email'] ?? e['id']).toString(), child: Text("${e['firstName'] ?? ''} ${e['lastName'] ?? ''}"))).toList(),
          onChanged: (v) => setDS(() => selResp = v),
        ),
        const SizedBox(height: 16),
        _sharedSectionLabel("EKIPY I PRACOWNICY", ctx),
        Wrap(spacing: 8, children: [
           ...selCrews.map((c) => Chip(label: Text(c, style: const TextStyle(fontSize: 10)), onDeleted: () => setDS(() => selCrews.remove(c)))),
           ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text("DODAJ EKIPĘ", style: TextStyle(fontSize: 10)), onPressed: () async {
              final List<String>? picked = await _showMultiPicker(context, "WYBIERZ EKIPY", _groups, selCrews);
              if (picked != null) setDS(() => selCrews = picked);
           }),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
           ...selEmps.map((e) => Chip(label: Text(_getEmpName(e, _employees, []), style: const TextStyle(fontSize: 10)), onDeleted: () => setDS(() => selEmps.remove(e)))),
           ActionChip(avatar: const Icon(Icons.person_add, size: 16), label: const Text("DODAJ PRACOWNIKA", style: TextStyle(fontSize: 10)), onPressed: () async {
              final List<String>? picked = await _showEmployeeMultiPicker(context, selEmps);
              if (picked != null) setDS(() => selEmps = picked);
           }),
        ]),
        const Divider(height: 32),
        _sharedSectionLabel("HARMONOGRAM ETAPÓW", ctx),
        ...stages.asMap().entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(child: TextFormField(initialValue: e.value['name'], decoration: const InputDecoration(labelText: "Nazwa etapu", border: InputBorder.none), onChanged: (v) => stages[e.key]['name'] = v)),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setDS(() => stages.removeAt(e.key))),
          ]),
        )),
        TextButton.icon(onPressed: () => setDS(() => stages.add({'name': 'Nowy etap', 'status': 'OCZEKUJE'})), icon: const Icon(Icons.add_circle_outline), label: const Text("DODAJ ETAP")),
      ]);
    }), actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANULUJ")),
      ElevatedButton(onPressed: () async {
        if (nC.text.isEmpty) return;
        final String id = order?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
        final Map<String, dynamic> d = { 
          ... (order ?? {}), 
          'id': id, 'name': nC.text, 'location': lC.text, 
          'startDate': startC.text, 'endDate': endC.text,
          'client_access_code': codeC.text.trim().toUpperCase(),
          'responsible_person': selResp,
          'assigned_crews': selCrews, 'assigned_employees': selEmps, 
          'stages': stages, 'status': stat 
        };
        await FirebaseFirestore.instance.collection('orders').doc(id).set(d);
        await _loadData();
        Navigator.pop(context);
      }, child: const Text("ZAPISZ ZLECENIE")),
    ]);
  }

  Future<List<String>?> _showMultiPicker(BuildContext context, String title, List<String> options, List<String> current) async {
    List<String> selected = List<String>.from(current);
    return showDialog<List<String>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: Text(title), content: SizedBox(width: 400, child: ListView.builder(shrinkWrap: true, itemCount: options.length, itemBuilder: (c, i) => CheckboxListTile(title: Text(options[i]), value: selected.contains(options[i]), onChanged: (v) => setS(() => v == true ? selected.add(options[i]) : selected.remove(options[i]))))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANULUJ")), ElevatedButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text("ZATWIERDŹ"))])));
  }

  Future<List<String>?> _showEmployeeMultiPicker(BuildContext context, List<String> current) async {
    List<String> selected = List<String>.from(current);
    return showDialog<List<String>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text("WYBIERZ PRACOWNIKÓW"), content: SizedBox(width: 400, child: ListView.builder(shrinkWrap: true, itemCount: _employees.length, itemBuilder: (c, i) {
      final e = _employees[i]; final email = (e['email'] ?? e['id']).toString();
      return CheckboxListTile(title: Text("${e['firstName'] ?? ''} ${e['lastName'] ?? ''}"), subtitle: Text(email, style: const TextStyle(fontSize: 10)), value: selected.contains(email), onChanged: (v) => setS(() => v == true ? selected.add(email) : selected.remove(email)));
    })), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANULUJ")), ElevatedButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text("ZATWIERDŹ"))])));
  }

  Widget _field(TextEditingController c, String l, IconData i, BuildContext context, {bool readOnly = false, VoidCallback? onTap}) => TextField(controller: c, readOnly: readOnly, onTap: onTap, decoration: _sharedInputDec(l, i, context));
}

// --- DETAIL VIEW ---
class OrderDetailView extends StatefulWidget {
  final Map<String, dynamic> order; final bool isAdmin; final String currentUserEmail; final String Function(String?) getName; final Future<void> Function() saveOrders; final Future<void> Function() saveTools; final List<Map<String, dynamic>> toolsDB; final bool canEdit; final List<Map<String, dynamic>> tools; final List<Map<String, dynamic>> clients; final SharedPreferences? prefs;
  const OrderDetailView({super.key, required this.order, required this.isAdmin, required this.currentUserEmail, required this.getName, required this.saveOrders, required this.saveTools, required this.toolsDB, required this.canEdit, required this.tools, required this.clients, this.prefs});
  @override
  State<OrderDetailView> createState() => _OrderDetailViewState();
}

class _OrderDetailViewState extends State<OrderDetailView> with SingleTickerProviderStateMixin {
  late TabController _tab;
  late Map<String, dynamic> _localOrder;

  StreamSubscription? _sub;

  @override
  void initState() { 
    super.initState(); 
    _tab = TabController(length: 8, vsync: this); 
    _localOrder = Map<String, dynamic>.from(widget.order); 
    _setupStream();
  }

  void _setupStream() {
    _sub = FirebaseFirestore.instance.collection('orders').doc(_localOrder['id'].toString()).snapshots().listen((s) {
      if (s.exists && mounted) {
        setState(() {
          _localOrder = s.data() as Map<String, dynamic>;
        });
      }
    });
  }

  @override
  void dispose() { _sub?.cancel(); _tab.dispose(); super.dispose(); }

  void _showImagePreview(String url) {
    showDialog(context: context, builder: (ctx) => Dialog(backgroundColor: Colors.transparent, child: Column(mainAxisSize: MainAxisSize.min, children: [ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(url, fit: BoxFit.contain)), const SizedBox(height: 12), ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("ZAMKNIJ"))])));
  }

  String _getImgUrl(dynamic p) { if (p is Map) return p['url'] ?? ""; return p.toString(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
            title: Text(_localOrder['name'] ?? "Szczegóły"), 
            actions: [
              if (widget.canEdit) 
                IconButton(
                  icon: const Icon(Icons.edit_note_rounded, size: 28), 
                  onPressed: () => Navigator.pop(context, 'EDIT'),
                  tooltip: "Pełna edycja zlecenia",
                )
            ],
            bottom: TabBar(controller: _tab, isScrollable: true, indicatorColor: Colors.orange, tabs: const [ Tab(text: "ETAPY"), Tab(text: "PROBLEMY ⚠️"), Tab(text: "ZAMÓWIENIA"), Tab(text: "KOSZTY"), Tab(text: "PROJEKTY"), Tab(text: "NARZĘDZIA"), Tab(text: "SPRZĘT"), Tab(text: "KONTAKT") ])
          ),
          body: TabBarView(controller: _tab, children: [ _buildStages(), IssuesScreen(isAdmin: widget.isAdmin, currentUserEmail: widget.currentUserEmail, orderId: _localOrder['id'], orderName: _localOrder['name'], stages: _localOrder['stages'] as List?), _buildMat(), _buildCosts(), _buildDocs(), _buildToolsMenu(), _buildTools(), _buildContact() ]),
        );
  }

  Widget _buildStages() {
    List stages = _localOrder['stages'] as List? ?? [];
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: stages.length, itemBuilder: (c, i) => _stageCard(stages[i], i));
  }

  Widget _stageCard(Map<String, dynamic> s, int idx) {
    final theme = Theme.of(context);
    final String? resp = s['responsible_worker'];
    final bool isClaimed = resp != null && resp.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ 
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s['name'] ?? 'Etap', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (isClaimed) 
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, size: 10, color: Colors.blueGrey),
                      const SizedBox(width: 4),
                      Text("Odp: ${widget.getName(resp)}", style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: InkWell(
                    onTap: () => _takeOverStage(idx),
                    child: Row(
                      children: [
                        const Icon(Icons.touch_app_rounded, size: 12, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text("PRZEJMIJ TEN ETAP", style: TextStyle(fontSize: 10, color: Colors.orange[800], fontWeight: FontWeight.w900, decoration: TextDecoration.underline)),
                      ],
                    ),
                  ),
                ),
            ],
          )), 
          _statusDropdown(idx) 
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _miniActBtn(Icons.rocket_launch_rounded, "MELDUNEK", Colors.blue, () => _showMeldunek(idx)),
          const SizedBox(width: 8),
          _miniActBtn(Icons.edit_note_rounded, "WPIS", Colors.indigo, () => _showWpisDialog(idx)),
          const SizedBox(width: 8),
          _miniActBtn(Icons.add_a_photo, "ZDJĘCIE", Colors.orange, () => _addPhoto(idx)),
          const SizedBox(width: 8),
          _miniActBtn(Icons.report_problem_rounded, "PROBLEM", Colors.red, () => _showAddIssue(idx)),
        ]),
        if (s['photos'] != null && (s['photos'] as List).isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: (s['photos'] as List).length,
              itemBuilder: (c, i) => GestureDetector(
                onTap: () => _showImagePreview(_getImgUrl(s['photos'][i])),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                    image: DecorationImage(image: NetworkImage(_getImgUrl(s['photos'][i])), fit: BoxFit.cover)
                  ),
                ),
              ),
            ),
          ),
        ],
        if (s['logs'] != null && (s['logs'] as List).isNotEmpty) ...[
          const Divider(height: 24),
          ... (s['logs'] as List).take(10).map((l) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text("• ${l['text']}", style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.6))))),
        ]
      ]))
    );
  }

  void _takeOverStage(int idx) async {
    final bool? confirm = await _showConfirm(context, "PRZEJĄĆ ETAP?", "Zostaniesz przypisany jako osoba odpowiedzialna za ten etap prac.");
    if (confirm == true) {
      setState(() {
        _localOrder['stages'][idx]['responsible_worker'] = widget.currentUserEmail;
        // Automatycznie zmień status na W TRAKCIE przy przejęciu
        if (_localOrder['stages'][idx]['status'] == 'OCZEKUJE') {
          _localOrder['stages'][idx]['status'] = 'W TRAKCIE';
        }
        _addLog(idx, "Przejęcie etapu przez: ${widget.currentUserEmail}");
      });
      _saveLocalOrder();
    }
  }

  Widget _statusDropdown(int idx) {
    final s = _localOrder['stages'][idx];
    String current = s['status'] ?? 'OCZEKUJE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: _getStatusColor(current).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: DropdownButton<String>(
        value: current, isDense: true, underline: const SizedBox(),
        items: ['OCZEKUJE', 'W TRAKCIE', 'ZAKOŃCZONO'].map((st) => DropdownMenuItem(value: st, child: Text(st, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _getStatusColor(st))))).toList(),
        onChanged: (val) {
          setState(() { 
            _localOrder['stages'][idx]['status'] = val; 
            _addLog(idx, "Zmiana statusu na: $val");
          });
          _saveLocalOrder();
        },
      ),
    );
  }

  void _addLog(int idx, String text) {
    if (_localOrder['stages'][idx]['logs'] == null) _localOrder['stages'][idx]['logs'] = [];
    (_localOrder['stages'][idx]['logs'] as List).insert(0, {
      'text': text, 
      'date': DateFormat('dd.MM HH:mm').format(DateTime.now()), 
      'author': widget.currentUserEmail
    });
  }

  Widget _buildMat() {
    List mats = _localOrder['material_orders'] as List? ?? [];
    return Column(children: [
      Expanded(child: ListView.builder(itemCount: mats.length, itemBuilder: (c, i) {
        final m = mats[i];
        final sc = _getMatStatusColor(m['status']);
        return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(m['date'] ?? '-', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: sc.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(m['status'] ?? 'NOWE', style: TextStyle(color: sc, fontSize: 8, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 8),
          if (m['order_no'] != null) Text(m['order_no'], style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          Text(m['items'] ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.red), onPressed: () => _genMaterialPDF(m, _localOrder, [], [])),
            if (widget.isAdmin) IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () async {
               if (await _confirm("USUŃ?", "Usunąć zamówienie?")) { setState(() { (_localOrder['material_orders'] as List).remove(m); }); _saveLocalOrder(); }
            }),
          ])
        ])));
      })),
      Padding(padding: const EdgeInsets.all(16), child: ElevatedButton.icon(onPressed: () => _addMatDialog(_localOrder), icon: const Icon(Icons.shopping_cart_checkout_rounded), label: const Text("ZAMÓW MATERIAŁY"), style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.orange[800], foregroundColor: Colors.white))),
    ]);
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'W TRAKCIE': return Colors.orange;
      case 'ZAKOŃCZONO': return Colors.green;
      default: return Colors.blue;
    }
  }

  Color _getMatStatusColor(String? status) {
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

  Future<void> _saveLocalOrder() async { await FirebaseFirestore.instance.collection('orders').doc(_localOrder['id'].toString()).set(_localOrder); }

  void _addMatDialog(Map<String, dynamic> order) {
    List<Map<String, dynamic>> items = [{'name': '', 'qty': ''}];
    final sig = SignatureController(penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white);
    showEsModal(context, title: "ZAMÓW MATERIAŁY", maxWidth: 700, content: StatefulBuilder(builder: (ctx, setDS) => Column(mainAxisSize: MainAxisSize.min, children: [
      ...items.asMap().entries.map((e) => Row(children: [
        Expanded(flex: 3, child: TextField(style: const TextStyle(color: Colors.white), decoration: _inputDec("Materiał", ctx), onChanged: (v) => items[e.key]['name'] = v)),
        const SizedBox(width: 8),
        Expanded(flex: 1, child: TextField(style: const TextStyle(color: Colors.white), decoration: _inputDec("Ilość", ctx), onChanged: (v) => items[e.key]['qty'] = v)),
        IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => setDS(() => items.removeAt(e.key))),
      ])),
      TextButton.icon(onPressed: () => setDS(() => items.add({'name': '', 'qty': ''})), icon: const Icon(Icons.add), label: const Text("DODAJ POZYCJĘ")),
      const Divider(),
      _sharedSectionLabel("PODPIS", ctx),
      Container(height: 120, color: Colors.white, child: Signature(controller: sig)),
    ])), actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANULUJ")),
      ElevatedButton(onPressed: () async {
        String txt = items.where((it) => it['name'].isNotEmpty).map((it) => "${it['name']} - ${it['qty']}").join("\n");
        if (txt.isEmpty || sig.isEmpty) return;
        String? sUrl; final d = await sig.toPngBytes(); if (d != null) { final ref = FirebaseStorage.instance.ref().child("sigs/${DateTime.now().millisecondsSinceEpoch}.png"); await ref.putData(d); sUrl = await ref.getDownloadURL(); }
        final now = DateTime.now();
        final String orderNo = "ZAM/${now.year}/${now.month.toString().padLeft(2, '0')}/${now.millisecondsSinceEpoch.toString().characters.takeLast(4)}";
        final n = { 'id': DateTime.now().millisecondsSinceEpoch.toString(), 'order_no': orderNo, 'author': widget.currentUserEmail, 'date': DateFormat('dd.MM HH:mm').format(now), 'items': txt, 'items_structured': items.where((it) => it['name'].isNotEmpty).toList(), 'status': 'NOWE', 'signature_url': sUrl, 'order_name': order['name'], 'order_id': order['id'], 'type': 'MATERIAL_ORDER' };
        setState(() { if (_localOrder['material_orders'] == null) _localOrder['material_orders'] = []; (_localOrder['material_orders'] as List).insert(0, n); });
        await _saveLocalOrder(); 
        await FirebaseFirestore.instance.collection('warehouse').doc(n['id']).set(n);
        Navigator.pop(context);
      }, child: const Text("WYŚLIJ ZAMÓWIENIE")),
    ]);
  }

  InputDecoration _inputDec(String l, BuildContext ctx) => InputDecoration(labelText: l, labelStyle: const TextStyle(color: Colors.white70));

  Widget _buildCosts() {
    final data = widget.prefs?.getString('company_expenses_v1'); List exps = data != null ? json.decode(data) : [];
    final filtered = exps.where((e) => e['orderId'] == _localOrder['id']).toList();
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: filtered.length, itemBuilder: (c, i) => ListTile(title: Text(filtered[i]['title']), trailing: Text("${filtered[i]['amount']} zł", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))));
  }
  
  Widget _buildDocs() {
    List files = _localOrder['project_files'] as List? ?? [];
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: ElevatedButton.icon(onPressed: _addFile, icon: const Icon(Icons.upload_file), label: const Text("DODAJ PLIK"))),
      Expanded(child: ListView.builder(itemCount: files.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.description, color: Colors.blue), title: Text(files[i]['name']), onTap: () => launchUrl(Uri.parse(files[i]['path']))))),
    ]);
  }

  void _addFile() async {
    final res = await FilePicker.platform.pickFiles();
    if (res == null) return;
    final file = res.files.first;
    final ref = FirebaseStorage.instance.ref().child("files/${DateTime.now().millisecondsSinceEpoch}_${file.name}");
    if (kIsWeb) await ref.putData(file.bytes!); else await ref.putFile(File(file.path!));
    final url = await ref.getDownloadURL();
    setState(() { 
      if (_localOrder['project_files'] == null) _localOrder['project_files'] = []; 
      (_localOrder['project_files'] as List).add({'name': file.name, 'path': url, 'date': DateFormat('dd.MM.yyyy').format(DateTime.now())}); 
    });
    _saveLocalOrder();
  }

  Widget _buildToolsMenu() {
    return ListView(padding: const EdgeInsets.all(24), children: [
      ListTile(leading: const Icon(Icons.label), title: const Text("Opisy rozdzielni"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DbLabelsScreen()))),
      ListTile(leading: const Icon(Icons.lan), title: const Text("Sieć LAN"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanLabelsScreen()))),
      ListTile(leading: const Icon(Icons.schema), title: const Text("Schematy"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SchematicCreatorScreen()))),
    ]);
  }

  Widget _buildTools() {
    List erbetki = _localOrder['assigned_erbetki'] as List? ?? [];
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: erbetki.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.build), title: Text(erbetki[i]['name'] ?? 'Sprzęt'), subtitle: Text("Od: ${erbetki[i]['startDate']}")));
  }
  
  Widget _buildContact() {
    final cName = _localOrder['client_name'];
    final client = widget.clients.firstWhere((c) => c['name'] == cName, orElse: () => {});
    List contacts = client['contacts'] as List? ?? [];
    return ListView(padding: const EdgeInsets.all(16), children: contacts.map((c) => Card(child: ListTile(title: Text(c['name'] ?? ""), subtitle: Text(c['phone'] ?? "")))).toList());
  }

  Future<bool> _confirm(String t, String c) async => await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(t), content: Text(c), actions: [ TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("NIE")), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("TAK")) ])) ?? false;
  
  void _showMeldunek(int idx) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("MELDUNEK PRAC"), 
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Zamelduj się na budowie, aby klient wiedział, że rozpoczęliście prace.", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          const SizedBox(height: 16),
          TextField(controller: ctrl, decoration: const InputDecoration(hintText: "Co dziś robicie? (opcjonalnie)")),
        ],
      ), 
      actions: [ 
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANULUJ")), 
        ElevatedButton(
          onPressed: () async {
            String text = ctrl.text.trim();
            String logText = text.isEmpty ? "🚀 MELDUNEK: Rozpoczęto prace na budowie." : "🚀 MELDUNEK: $text";
            setState(() { _addLog(idx, logText); });
            await _saveLocalOrder(); 
            if (mounted) Navigator.pop(c);
          }, 
          child: const Text("WYŚLIJ MELDUNEK")
        ) 
      ]
    ));
  }

  void _showWpisDialog(int idx) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("DODAJ WPIS / KOMENTARZ"), 
      content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: "Opisz postęp prac lub dodaj uwagę...")), 
      actions: [ 
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANULUJ")), 
        ElevatedButton(
          onPressed: () async {
            if (ctrl.text.isEmpty) return;
            setState(() { _addLog(idx, ctrl.text.trim()); });
            await _saveLocalOrder(); 
            if (mounted) Navigator.pop(c);
          }, 
          child: const Text("DODAJ WPIS")
        ) 
      ]
    ));
  }

  void _addPhoto(int idx) async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text("Aparat"), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text("Galeria"), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ],
        ),
      ),
    );
    
    if (source == null) return;

    final picker = ImagePicker();
    final img = await picker.pickImage(source: source, imageQuality: 50);
    if (img != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Przesyłanie zdjęcia...")));
      final ref = FirebaseStorage.instance.ref().child("orders/${_localOrder['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg");
      if (kIsWeb) await ref.putData(await img.readAsBytes()); else await ref.putFile(File(img.path));
      final url = await ref.getDownloadURL();
      setState(() {
        if (_localOrder['stages'][idx]['photos'] == null) _localOrder['stages'][idx]['photos'] = [];
        (_localOrder['stages'][idx]['photos'] as List).add(url);
        _addLog(idx, "📸 Dodano nowe zdjęcie.");
      });
      _saveLocalOrder();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Zdjęcie zostało dodane."), backgroundColor: Colors.green));
    }
  }

  void _showAddIssue(int idx) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text("ZGŁOŚ PROBLEM"), content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: "Opisz problem...")), actions: [ TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANULUJ")), ElevatedButton(onPressed: () async {
      if (ctrl.text.isEmpty) return;
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      await FirebaseFirestore.instance.collection('issues').doc(id).set({
        'id': id, 'orderId': _localOrder['id'], 'orderName': _localOrder['name'], 'stageName': _localOrder['stages'][idx]['name'], 'content': ctrl.text, 'author': widget.currentUserEmail, 'date': DateFormat('dd.MM HH:mm').format(DateTime.now()), 'status': 'NOWY'
      });
      Navigator.pop(c);
    }, child: const Text("ZGŁOŚ")) ]));
  }

  Widget _miniActBtn(IconData i, String l, Color c, VoidCallback t) => InkWell(onTap: t, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 14, color: c), const SizedBox(width: 4), Text(l, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold))])));
}

Widget _field(TextEditingController c, String l, IconData i, BuildContext context, {bool readOnly = false, VoidCallback? onTap}) => TextField(controller: c, readOnly: readOnly, onTap: onTap, decoration: _sharedInputDec(l, i, context));

Future<List<String>?> _showMultiPicker(BuildContext context, String title, List<String> options, List<String> current) async {
  List<String> selected = List<String>.from(current);
  return showDialog<List<String>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: Text(title), content: SizedBox(width: 400, child: ListView.builder(shrinkWrap: true, itemCount: options.length, itemBuilder: (c, i) => CheckboxListTile(title: Text(options[i]), value: selected.contains(options[i]), onChanged: (v) => setS(() => v == true ? selected.add(options[i]) : selected.remove(options[i]))))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANULUJ")), ElevatedButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text("ZATWIERDŹ"))])));
}
