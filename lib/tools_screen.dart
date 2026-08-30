import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'core/app_utils.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:signature/signature.dart';
import 'package:dio/dio.dart';
import 'core/app_theme.dart';
import 'services/cloud_sync_service.dart';

class ToolsScreen extends StatefulWidget {
  final bool isAdmin;
  final String currentUserEmail;
  const ToolsScreen({super.key, required this.isAdmin, required this.currentUserEmail});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _tools = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _allNotifications = [];
  final _picker = ImagePicker();
  bool _isLoading = true;
  TabController? _tabController;

  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _buyDateController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _searchController = TextEditingController();
  String _searchQuery = "";
  String _companyAddress = "";
  String _tempManualLoc = "";
  
  String? _selectedOwner;
  String _selectedStatus = 'OK';
  String _selectedType = 'NARZĘDZIE';
  final _meterController = TextEditingController();

  final List<String> _statusOptions = ['OK', 'USZKODZONA', 'W NAPRAWIE', 'DO ODEBRANIA', 'ZUTYLIZOWANE'];
  final List<String> _typeOptions = ['NARZĘDZIE', 'ERBETKA', 'POJAZD', 'INNE'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.isAdmin ? 5 : 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose(); _brandController.dispose(); _modelController.dispose(); _buyDateController.dispose();
    _barcodeController.dispose(); _searchController.dispose(); _meterController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _companyAddress = prefs.getString('comp_address') ?? "";

    try {
      await CloudSyncService().downloadTools().timeout(const Duration(seconds: 5));
      await CloudSyncService().downloadEmployees().timeout(const Duration(seconds: 5));
      await CloudSyncService().downloadOrders().timeout(const Duration(seconds: 5));
    } catch (e) { debugPrint("Cloud download tools failed: $e"); }

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
      final String? empData = prefs.getString('user_permissions');
      if (empData != null) {
        List<dynamic> decoded = json.decode(empData);
        _employees = decoded.where((e) => e['isActive'] == true).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    
    final String? ordersData = prefs.getString('company_orders_v2');
    if (ordersData != null) _orders = List<Map<String, dynamic>>.from(json.decode(ordersData));

    final String? toolsData = prefs.getString('company_tools_v1');
    if (toolsData != null) {
      _tools = List<Map<String, dynamic>>.from(json.decode(toolsData));
    }

    final String? noteData = prefs.getString('company_notifications_v2');
    if (noteData != null) {
      _allNotifications = List<Map<String, dynamic>>.from(json.decode(noteData));
    }
    
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveTools() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_tools_v1', AppUtils.safeJsonEncode(_tools));
    try { await CloudSyncService().uploadTools(); } catch (e) { debugPrint("Cloud upload failed: $e"); }
  }

  Future<void> _saveNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_notifications_v2', AppUtils.safeJsonEncode(_allNotifications));
  }

  Future<void> _sendNotification(String target, String title, String content) async {
    _allNotifications.insert(0, {
      'title': title, 'content': content, 'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
      'target': target, 'isRead': false, 'isArchived': false, 'author': widget.currentUserEmail,
    });
    await _saveNotifications();
    setState(() {});
  }

  void _addHistory(Map<String, dynamic> tool, String action) {
    if (tool['history'] == null) tool['history'] = [];
    List history = List.from(tool['history']);
    history.add({
      'date': DateFormat('dd.MM HH:mm').format(DateTime.now()), 
      'action': action,
      'author': widget.currentUserEmail
    });
    tool['history'] = history;
  }

  String _getName(String? email) {
    if (email == null || email.isEmpty || email == 'magazyn') return email == 'magazyn' ? 'MAGAZYN' : "-";
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

  Color _getStatusColor(String s) { 
    if (s == 'OK') return AppTheme.accentGreen; 
    if (s == 'USZKODZONA') return Colors.red; 
    if (s == 'W NAPRAWIE') return AppTheme.accentOrange; 
    if (s == 'DO ODEBRANIA') return AppTheme.accentBlue; 
    return AppTheme.textMuted; 
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    int reportsCount = _allNotifications.where((n) => (n['title'] == 'AWARIA SPRZĘTU' || n['title'] == 'ZAPOTRZEBOWANIE NA NARZĘDZIA') && n['isRead'] == false).length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)))
        : Column(
            children: [
              _buildModernHeader(reportsCount),
              _buildSearchBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: widget.isAdmin 
                  ? [
                      _buildToolsList(mode: 'warehouse'),
                      _buildToolsList(mode: 'team'),
                      _buildToolsList(mode: 'orders'),
                      _buildReportsList(isArchived: false),
                      _buildToolsList(mode: 'archive'),
                    ]
                  : [
                      _buildToolsList(mode: 'mine'),
                      _buildToolsList(mode: 'warehouse'),
                      _buildToolsList(mode: 'orders'),
                      _buildToolsList(mode: 'archive'),
                    ],
                ),
              ),
            ],
          ),
      floatingActionButton: widget.isAdmin 
        ? FloatingActionButton(
            backgroundColor: const Color(0xFF001A2C),
            onPressed: () => _showToolDialog(),
            child: const Icon(Icons.add, color: Colors.white),
          )
        : null,
    );
  }

  Widget _buildModernHeader(int reportsCount) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, bottom: 0),
      decoration: const BoxDecoration(
        color: Color(0xFF001A2C),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("BAZA SPRZĘTU", style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
                    Text("Zarządzaj narzędziami firmowymi", style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6))),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: () {
                        setState(() => _isLoading = true);
                        _loadData();
                      },
                      tooltip: "Odśwież bazę",
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_shopping_cart, color: Colors.orange),
                      onPressed: () => _showRequestToolDialog(),
                      tooltip: "Zapotrzebowanie",
                    ),
                    if (widget.isAdmin)
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                        onPressed: _exportToolsToPdf,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: Colors.orange,
            indicatorWeight: 4,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            tabs: widget.isAdmin 
            ? [
                const Tab(text: "MAGAZYN"),
                const Tab(text: "EKIPA"),
                const Tab(text: "BUDOWY"),
                Tab(child: Row(children: [
                  const Text("ZGŁOSZENIA"),
                  if (reportsCount > 0) 
                    Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: Text("$reportsCount", style: const TextStyle(fontSize: 8, color: Colors.white)))
                ])),
                const Tab(text: "ARCHIWUM"),
              ]
            : [
                const Tab(text: "MOJE"),
                const Tab(text: "MAGAZYN"),
                const Tab(text: "NA BUDOWIE"),
                const Tab(text: "ARCHIWUM"),
              ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: "Szukaj nazwy, marki lub pracownika...",
            hintStyle: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.3)),
            prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurface.withOpacity(0.3)),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF007BFF)),
              onPressed: () => _openScanner(isSearch: true),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildToolsList({required String mode}) {
    List<Map<String, dynamic>> allFiltered = _tools.where((t) {
      final owner = t['owner']?.toString().toLowerCase() ?? 'magazyn';
      final name = t['name']?.toString().toLowerCase() ?? '';
      final brand = t['brand']?.toString().toLowerCase() ?? '';
      final barcode = t['barcode']?.toString().toLowerCase() ?? '';
      final matchesSearch = name.contains(_searchQuery) || brand.contains(_searchQuery) || owner.contains(_searchQuery) || barcode.contains(_searchQuery);
      
      if (!matchesSearch) return false;

      switch (mode) {
        case 'archive':
          return t['status'] == 'ZUTYLIZOWANE';
        case 'warehouse':
          return (t['owner'] == 'magazyn' || t['owner'] == null) && t['status'] != 'ZUTYLIZOWANE' && (t['assignedOrderId'] == null || t['assignedOrderId'] == "");
        case 'mine':
          return t['owner']?.toString().toLowerCase() == widget.currentUserEmail.toLowerCase() && t['status'] != 'ZUTYLIZOWANE';
        case 'team':
          return t['owner'] != 'magazyn' && t['owner'] != null && t['status'] != 'ZUTYLIZOWANE';
        case 'orders':
          return t['assignedOrderId'] != null && t['status'] != 'ZUTYLIZOWANE';
        default:
          return t['status'] != 'ZUTYLIZOWANE';
      }
    }).toList();

    if (allFiltered.isEmpty) {
      String msg = "Brak narzędzi w tej sekcji";
      if (mode == 'mine') msg = "Nie masz przypisanych narzędzi";
      if (mode == 'warehouse') msg = "Magazyn jest pusty";
      if (mode == 'orders') msg = "Brak sprzętu na budowach";

      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(msg, style: const TextStyle(color: Colors.grey)),
        ],
      ));
    }

    if (mode == 'team' && widget.isAdmin) {
      Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var t in allFiltered) {
        String owner = t['owner'] ?? 'brak';
        grouped.putIfAbsent(owner, () => []).add(t);
      }
      List<String> owners = grouped.keys.toList()..sort();

      return ListView.builder(
        padding: const EdgeInsets.only(top: 10, bottom: 100),
        itemCount: owners.length,
        itemBuilder: (context, idx) {
          String owner = owners[idx];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(_getName(owner).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.textMuted, letterSpacing: 1.5)),
              ),
              ...grouped[owner]!.map((t) => _toolCard(t, false)),
            ],
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 10, bottom: 100),
      itemCount: allFiltered.length,
      itemBuilder: (context, idx) => _toolCard(allFiltered[idx], mode == 'archive'),
    );
  }

  Widget _toolCard(Map<String, dynamic> tool, bool isArchived) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = tool['status'] ?? 'OK';
    final type = tool['type'] ?? 'NARZĘDZIE';
    final isAtOrder = tool['assignedOrderId'] != null;
    final isOwnedByMe = tool['owner']?.toString().toLowerCase() == widget.currentUserEmail.toLowerCase();
    final isFree = tool['owner'] == 'magazyn' || tool['owner'] == null;
    final int toolIndex = _tools.indexOf(tool);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 6))],
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: (widget.isAdmin && !isArchived) ? () => _showToolDialog(tool: tool, index: toolIndex) : null,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildToolIcon(type, status, tool['photoUrl']),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(tool['name'], style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.onSurface))),
                                _buildStatusBadge(status),
                              ],
                            ),
                            Text("${tool['brand']} ${tool['model']}", style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.4))),
                            const SizedBox(height: 12),
                            if (isAtOrder)
                              _infoLabel(Icons.location_on, "BUDOWA: ${tool['assignedOrderName']}", Colors.orange)
                            else if (tool['manualLocation'] != null && tool['manualLocation'].isNotEmpty)
                              _infoLabel(Icons.warehouse_outlined, "MIEJSCE: ${tool['manualLocation']}", const Color(0xFF007BFF)),
                            
                            if (type == 'ERBETKA' && tool['lastMeterReading'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: _infoLabel(Icons.bolt, "Licznik: ${tool['lastMeterReading']} kWh", Colors.purple),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.isAdmin && !isArchived)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.02), border: Border(top: BorderSide(color: theme.dividerTheme.color ?? Colors.white10, width: 0.5))),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (status == 'DO ODEBRANIA')
                          _modernActionBtn("ODBIERZ", const Color(0xFF007BFF), () => _confirmPickup(tool, toolIndex)),
                        if (isFree)
                          _modernActionBtn("POBIERZ", Colors.green, () => _takeTool(tool, toolIndex)),
                        if (isOwnedByMe) ...[
                          _modernActionBtn("PRZEKAŻ", Colors.purple, () => _showTransferQR(tool, toolIndex)),
                          if (isAtOrder) ...[
                             _modernActionBtn("DO BUSA", Colors.orange, () => _returnToBus(tool, toolIndex)),
                             _modernActionBtn("ZWROT", Colors.teal, () => _returnToWarehouse(tool, toolIndex)),
                          ] else ...[
                            _modernActionBtn("NA BUDOWĘ", const Color(0xFF007BFF), () => _showPostawBudowaDialog(tool, toolIndex)),
                            _modernActionBtn("ZMIEŃ LOK.", Colors.orange, () => _showDodajLokalizacjeDialog(tool, toolIndex)),
                            _modernActionBtn("ZWRÓĆ", Colors.redAccent, () => _returnToWarehouse(tool, toolIndex)),
                          ],
                        ],
                        _modernActionBtn(status == 'USZKODZONA' ? "NAPRAWIONO" : "AWARIA", status == 'USZKODZONA' ? Colors.blueGrey : Colors.red, () => status == 'USZKODZONA' ? _cancelIssue(tool, toolIndex) : _reportIssue(tool, toolIndex), isGhost: true),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolIcon(String type, String status, String? photoUrl) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return Container(
        width: 60, height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          image: DecorationImage(image: NetworkImage(photoUrl), fit: BoxFit.cover),
          border: Border.all(color: _getStatusColor(status).withOpacity(0.5), width: 2),
        ),
      );
    }
    IconData icon;
    if (type == 'ERBETKA') icon = Icons.electrical_services;
    else if (type == 'POJAZD') icon = Icons.directions_car;
    else icon = Icons.build_outlined;

    return Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        color: _getStatusColor(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: _getStatusColor(status), size: 30),
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(status, style: TextStyle(color: _getStatusColor(status), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }

  Widget _infoLabel(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color))),
      ],
    );
  }

  Widget _modernActionBtn(String label, Color color, VoidCallback onTap, {bool isGhost = false}) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: isGhost ? Colors.transparent : color,
        foregroundColor: isGhost ? color : Colors.white,
        elevation: isGhost ? 0 : 2,
        shadowColor: color.withOpacity(0.3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        minimumSize: const Size(60, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isGhost ? BorderSide(color: color, width: 1.5) : BorderSide.none,
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildReportsList({bool isArchived = false}) {
    final reports = _allNotifications.where((n) => (n['title'] == 'AWARIA SPRZĘTU' || n['title'] == 'ZAPOTRZEBOWANIE NA NARZĘDZIA' || n['title'].toString().startsWith('RE:')) && n['isArchived'] == isArchived).toList();
    if (reports.isEmpty) return const Center(child: Text("Brak zgłoszeń."));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: reports.length,
      itemBuilder: (context, idx) {
        final r = reports[idx];
        final isEmergency = r['title'] == 'AWARIA SPRZĘTU';
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: isArchived ? Colors.grey[200] : (isEmergency ? Colors.red[50] : Colors.green[50]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(r['title'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            subtitle: Text(r['content'], style: const TextStyle(fontSize: 11)),
            trailing: isArchived ? null : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.reply, color: AppTheme.accentBlue), onPressed: () => _adminReplyDialog(r)),
                IconButton(icon: const Icon(Icons.archive_outlined, color: Colors.blueGrey), onPressed: () {
                  setState(() { r['isArchived'] = true; r['isRead'] = true; });
                  _saveNotifications();
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- LOGIKA DIALOGÓW (ZACHOWANA Z POPRZEDNIEJ WERSJI, LEKKO ODŚWIEŻONA) ---

  void _adminReplyDialog(Map<String, dynamic> report) {
    final replyController = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('ODPOWIEDŹ NA ZGŁOSZENIE'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Zgłoszenie: ${report['content']}', style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 16),
        TextField(controller: replyController, decoration: const InputDecoration(labelText: 'Treść odpowiedzi', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANULUJ")),
        ElevatedButton(onPressed: () {
          if (replyController.text.isNotEmpty) {
            _sendNotification(report['author'], 'RE: ${report['title']}', 'ODP: ${replyController.text}');
            setState(() => report['isArchived'] = true);
            _saveNotifications();
            Navigator.pop(context);
          }
        }, child: const Text('WYŚLIJ'))
      ],
    ));
  }

  void _reportIssue(Map<String, dynamic> tool, int masterIndex) { 
    final c = TextEditingController(); 
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text('AWARIA: ${tool['name']}'), 
      content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Opisz problem'), maxLines: 3), 
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
        ElevatedButton(onPressed: () { 
          if(c.text.isNotEmpty) { 
            setState(() { 
              _tools[masterIndex]['status'] = 'USZKODZONA'; 
              _addHistory(_tools[masterIndex], 'Zgłoszono awarię: ${c.text}'); 
            }); 
            _saveTools(); 
            _sendNotification('admin', 'AWARIA SPRZĘTU', 'Pracownik ${_getName(widget.currentUserEmail)} zgłosił awarię: ${tool['name']}. OPIS: ${c.text}'); 
            Navigator.pop(context); 
          } 
        }, child: const Text('WYŚLIJ'))
      ]
    )); 
  }
  
  void _cancelIssue(Map<String, dynamic> tool, int masterIndex) { 
    setState(() { 
      _tools[masterIndex]['status'] = 'OK'; 
      _addHistory(tool, 'Anulowano awarię.'); 
    }); 
    _saveTools(); 
    _sendNotification('admin', 'ANULOWANO AWARIĘ', 'Pracownik ${_getName(widget.currentUserEmail)} wycofał zgłoszenie: ${tool['name']}.'); 
  }
  
  void _confirmPickup(Map<String, dynamic> tool, int masterIndex) { 
    setState(() { 
      _tools[masterIndex]['status'] = 'OK'; 
      _addHistory(tool, 'Odebrano sprzęt.'); 
    }); 
    _saveTools(); 
    _sendNotification('admin', 'SPRZĘT ODEBRANY', 'Pracownik ${_getName(widget.currentUserEmail)} odebrał narzędzie: ${tool['name']}.'); 
  }
  
  void _takeTool(Map<String, dynamic> tool, int index) async { 
    final latCtrl = TextEditingController(text: "50.0121107");
    final lngCtrl = TextEditingController(text: "21.9540645");
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text("POBIERZ: ${tool['name']}"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Sprzęt zostanie przypisany do Ciebie.", style: TextStyle(fontSize: 12)),
        const SizedBox(height: 15),
        TextField(controller: latCtrl, decoration: const InputDecoration(labelText: 'Szerokość (Lat)')),
        TextField(controller: lngCtrl, decoration: const InputDecoration(labelText: 'Długość (Lng)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANULUJ")),
        ElevatedButton(onPressed: () async {
          setState(() { 
            tool['owner'] = widget.currentUserEmail; 
            tool['status'] = 'OK'; 
            tool['manualLocation'] = "BUS";
            tool['lastLat'] = double.tryParse(latCtrl.text.replaceAll(',', '.')) ?? 50.0121107;
            tool['lastLng'] = double.tryParse(lngCtrl.text.replaceAll(',', '.')) ?? 21.9540645;
            tool['lastLocDate'] = DateFormat('dd.MM HH:mm').format(DateTime.now());
            _addHistory(tool, "Pobrano z magazynu (BUS)."); 
          }); 
          await _saveTools(); 
          _sendNotification('admin', 'SPRZĘT POBRANY', 'Pracownik ${_getName(widget.currentUserEmail)} pobrał: ${tool['name']} (BUS)'); 
          Navigator.pop(context);
        }, child: const Text("POTWIERDŹ"))
      ],
    ));
  }

  void _showPostawBudowaDialog(Map<String, dynamic> tool, int index) {
    String? selectedOrderId; 
    final initialMeter = TextEditingController(text: tool['lastMeterReading']?.toString() ?? "0"); 
    final latCtrl = TextEditingController(text: tool['lastLat']?.toString() ?? '50.0121107');
    final lngCtrl = TextEditingController(text: tool['lastLng']?.toString() ?? '21.9540645');
    final activeOrders = _orders.where((o) => o['status'] != 'ZAKOŃCZONO').toList();

    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDS) => AlertDialog(
      title: Text('NA BUDOWĘ: ${tool['name']}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          isExpanded: true, 
          decoration: const InputDecoration(labelText: 'Wybierz budowę'), 
          items: activeOrders.map((o) => DropdownMenuItem(value: o['id'].toString(), child: Text(o['name']))).toList(), 
          onChanged: (v) {
            selectedOrderId = v;
            final order = activeOrders.firstWhere((o) => o['id'].toString() == v);
            double? foundLat = double.tryParse(order['lat']?.toString() ?? '');
            double? foundLng = double.tryParse(order['lng']?.toString() ?? '');
            if (foundLat != null && foundLng != null) {
              setDS(() { latCtrl.text = foundLat.toString(); lngCtrl.text = foundLng.toString(); });
            }
          }
        ),
        const SizedBox(height: 15),
        TextField(controller: latCtrl, decoration: const InputDecoration(labelText: 'Lat'), keyboardType: TextInputType.number),
        TextField(controller: lngCtrl, decoration: const InputDecoration(labelText: 'Lng'), keyboardType: TextInputType.number),
        if (tool['type'] == 'ERBETKA') TextField(controller: initialMeter, decoration: const InputDecoration(labelText: 'Stan licznika'), keyboardType: TextInputType.number),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
        ElevatedButton(onPressed: () async {
          if (selectedOrderId != null) {
            final order = _orders.firstWhere((o) => o['id'].toString() == selectedOrderId);
            setState(() {
              _tools[index]['assignedOrderId'] = selectedOrderId;
              _tools[index]['assignedOrderName'] = order['name'];
              _tools[index]['manualLocation'] = order['name'];
              _tools[index]['lastLat'] = double.tryParse(latCtrl.text.replaceAll(',', '.')) ?? 50.0121107;
              _tools[index]['lastLng'] = double.tryParse(lngCtrl.text.replaceAll(',', '.')) ?? 21.9540645;
              _tools[index]['lastLocDate'] = DateFormat('dd.MM HH:mm').format(DateTime.now());
            });
            await _saveTools(); Navigator.pop(context);
          }
        }, child: const Text('ZATWIERDŹ'))
      ],
    )));
  }

  void _showDodajLokalizacjeDialog(Map<String, dynamic> tool, int index) {
    final nameCtrl = TextEditingController(text: tool['manualLocation'] ?? '');
    final latCtrl = TextEditingController(text: tool['lastLat']?.toString() ?? '50.0121107');
    final lngCtrl = TextEditingController(text: tool['lastLng']?.toString() ?? '21.9540645');
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text('ZMIEŃ LOKALIZACJĘ: ${tool['name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nazwa miejsca")),
        TextField(controller: latCtrl, decoration: const InputDecoration(labelText: 'Lat'), keyboardType: TextInputType.number),
        TextField(controller: lngCtrl, decoration: const InputDecoration(labelText: 'Lng'), keyboardType: TextInputType.number),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
        ElevatedButton(onPressed: () async {
          setState(() {
            _tools[index]['assignedOrderId'] = null;
            _tools[index]['assignedOrderName'] = null;
            _tools[index]['manualLocation'] = nameCtrl.text.isNotEmpty ? nameCtrl.text : "BUS";
            _tools[index]['lastLat'] = double.tryParse(latCtrl.text.replaceAll(',', '.')) ?? 50.0121107;
            _tools[index]['lastLng'] = double.tryParse(lngCtrl.text.replaceAll(',', '.')) ?? 21.9540645;
          });
          await _saveTools(); Navigator.pop(context);
        }, child: const Text('ZAPISZ'))
      ],
    ));
  }

  void _returnToBus(Map<String, dynamic> tool, int index) async {
    setState(() {
      _tools[index]['assignedOrderId'] = null;
      _tools[index]['assignedOrderName'] = null;
      _tools[index]['manualLocation'] = "BUS";
      _tools[index]['lastLat'] = 50.0121107;
      _tools[index]['lastLng'] = 21.9540645;
      _addHistory(_tools[index], "Zabrano z budowy do BUSA.");
    });
    await _saveTools();
  }

  void _returnToWarehouse(Map<String, dynamic> tool, int index) {
    final finalMeter = TextEditingController(text: tool['lastMeterReading']?.toString() ?? "0"); 
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text('ZWROT NA MAGAZYN: ${tool['name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Potwierdź zwrot sprzętu.', style: TextStyle(fontSize: 13)),
        if (tool['type'] == 'ERBETKA') TextField(controller: finalMeter, decoration: const InputDecoration(labelText: 'Stan końcowy'), keyboardType: TextInputType.number),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
        ElevatedButton(onPressed: () async {
          setState(() { 
            _tools[index]['assignedOrderId'] = null; 
            _tools[index]['assignedOrderName'] = null; 
            _tools[index]['owner'] = 'magazyn'; 
            _tools[index]['lastLat'] = 50.0121107;
            _tools[index]['lastLng'] = 21.9540645;
            if (tool['type'] == 'ERBETKA') { _tools[index]['lastMeterReading'] = double.tryParse(finalMeter.text) ?? 0.0; } 
            _addHistory(_tools[index], "Zwrócono na magazyn."); 
          }); 
          await _saveTools(); 
          _sendNotification('admin', 'SPRZĘT ZWRÓCONY', 'Pracownik ${_getName(widget.currentUserEmail)} zwrócił ${tool['name']}.');
          Navigator.pop(context); 
        }, child: const Text('POTWIERDŹ'))
      ],
    ));
  }

  void _showToolDialog({Map<String, dynamic>? tool, int? index}) {
    String? toolPhotoUrl = tool?['photoUrl'];
    bool isUploading = false;
    if (tool != null) {
      _nameController.text = tool['name'] ?? ""; _brandController.text = tool['brand'] ?? ""; _modelController.text = tool['model'] ?? ""; _buyDateController.text = tool['buyDate'] ?? "";
      _barcodeController.text = tool['barcode'] ?? ""; _selectedOwner = (tool['owner'] == 'brak' || tool['owner'] == null) ? 'magazyn' : tool['owner'];
      _selectedStatus = tool['status'] ?? 'OK'; _selectedType = tool['type'] ?? 'NARZĘDZIE'; _meterController.text = tool['lastMeterReading']?.toString() ?? "";
    } else {
      _nameController.clear(); _brandController.clear(); _modelController.clear(); _buyDateController.text = DateFormat('dd.MM.yyyy').format(DateTime.now());
      _barcodeController.clear(); _selectedOwner = 'magazyn'; _selectedStatus = 'OK'; _selectedType = 'NARZĘDZIE'; _meterController.clear();
    }
    final latCtrl = TextEditingController(text: tool?['lastLat']?.toString() ?? '');
    final lngCtrl = TextEditingController(text: tool?['lastLng']?.toString() ?? '');

    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDS) => AlertDialog(
      title: Text(tool == null ? 'NOWY SPRZĘT' : 'EDYTUJ SPRZĘT'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: _selectedType, decoration: const InputDecoration(labelText: 'Typ'), items: _typeOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (val) => setDS(() => _selectedType = val!)),
        const SizedBox(height: 10),
        if (isUploading) const CircularProgressIndicator()
        else if (toolPhotoUrl != null) 
          Stack(children: [ 
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(toolPhotoUrl!, height: 100, width: double.infinity, fit: BoxFit.cover)),
            Positioned(right: 0, top: 0, child: CircleAvatar(backgroundColor: Colors.black54, radius: 15, child: IconButton(icon: const Icon(Icons.close, size: 15, color: Colors.white), onPressed: () => setDS(() => toolPhotoUrl = null))))
          ])
        else 
          ElevatedButton.icon(onPressed: () async {
            final src = await showDialog<ImageSource>(context: context, builder: (ctx) => AlertDialog(title: const Text('ŹRÓDŁO'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, ImageSource.gallery), child: const Text('GALERIA')), TextButton(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: const Text('APARAT'))]));
            if (src != null) {
              final img = await _picker.pickImage(source: src, imageQuality: 40);
              if (img != null) { setDS(() => isUploading = true); final fn = 'tool_${DateTime.now().millisecondsSinceEpoch}.jpg'; final ref = FirebaseStorage.instance.ref().child('tools/$fn'); if (kIsWeb) await ref.putData(await img.readAsBytes()); else await ref.putFile(File(img.path)); final url = await ref.getDownloadURL(); setDS(() { toolPhotoUrl = url; isUploading = false; }); }
            }
          }, icon: const Icon(Icons.add_a_photo), label: const Text('ZDJĘCIE')),
        TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nazwa')),
        TextField(controller: _brandController, decoration: const InputDecoration(labelText: 'Marka')),
        TextField(controller: _barcodeController, decoration: const InputDecoration(labelText: 'Kod/SN')),
        DropdownButtonFormField<String>(
          value: _selectedOwner, 
          decoration: const InputDecoration(labelText: 'Właściciel'), 
          items: [ 
            const DropdownMenuItem(value: 'magazyn', child: Text('MAGAZYN')), 
            ..._employees.map((e) {
              String name = "${e['firstName'] ?? ''} ${e['lastName'] ?? ''}".trim();
              if (name.isEmpty) name = e['email'] ?? e['id'] ?? 'Pracownik';
              return DropdownMenuItem(value: e['email'] ?? e['id'], child: Text(name));
            }) 
          ], 
          onChanged: (val) => setDS(() => _selectedOwner = val)
        ),
        DropdownButtonFormField<String>(value: _selectedStatus, decoration: const InputDecoration(labelText: 'Status'), items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (val) => setDS(() => _selectedStatus = val!)),
      ])),
      actions: [
        if (tool != null) TextButton(onPressed: () async { setState(() => _tools.removeAt(index!)); await _saveTools(); Navigator.pop(context); }, child: const Text('USUŃ', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
        ElevatedButton(onPressed: () async {
          if (_nameController.text.isNotEmpty) {
            setState(() {
              final data = tool != null ? Map<String, dynamic>.from(tool) : <String, dynamic>{};
              data['id'] = tool?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
              data['name'] = _nameController.text;
              data['brand'] = _brandController.text;
              data['owner'] = _selectedOwner;
              data['status'] = _selectedStatus;
              data['type'] = _selectedType;
              data['barcode'] = _barcodeController.text;
              data['photoUrl'] = toolPhotoUrl;
              if (index == null) _tools.add(data); else _tools[index] = data;
            });
            await _saveTools(); Navigator.pop(context);
          }
        }, child: const Text('ZAPISZ'))
      ],
    )));
  }

  // --- LOGIKA TRANSFERU P2P ---

  void _showTransferQR(Map<String, dynamic> tool, int index) {
    final String transferData = "TRANSFER:${tool['id']}:${widget.currentUserEmail}";
    final String qrUrl = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$transferData";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: [
            const Icon(Icons.swap_horizontal_circle_rounded, color: Colors.purple, size: 48),
            const SizedBox(height: 16),
            const Text("PRZEKAŻ SPRZĘT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text(tool['name'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Niech drugi pracownik zeskanuje ten kod swoim telefonem, aby przejąć narzędzie.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.withOpacity(0.2), width: 2),
              ),
              child: Image.network(
                qrUrl,
                height: 200,
                width: 200,
                loadingBuilder: (context, child, progress) => progress == null ? child : const CircularProgressIndicator(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANULUJ")),
        ],
      ),
    );
  }

  void _handleP2PTransfer(String toolId, String previousOwnerEmail) async {
    final toolIdx = _tools.indexWhere((t) => t['id'].toString() == toolId);
    if (toolIdx == -1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Błąd: Nie znaleziono narzędzia.")));
      return;
    }

    final tool = _tools[toolIdx];
    final String newOwner = widget.currentUserEmail;

    if (previousOwnerEmail.toLowerCase() == newOwner.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Już jesteś właścicielem tego sprzętu.")));
      return;
    }

    setState(() {
      tool['owner'] = newOwner;
      tool['manualLocation'] = "BUS (PRZEJĘTE)";
      tool['assignedOrderId'] = null; // Clear assignment since it's now in B's bus
      tool['assignedOrderName'] = null;
      tool['lastLocDate'] = DateFormat('dd.MM HH:mm').format(DateTime.now());
      _addHistory(tool, "Przejęto bezpośrednio od: $previousOwnerEmail");
    });

    await _saveTools();
    
    await _sendNotification(
      'admin', 
      'TRANSFER P2P: ${tool['name']}', 
      'Pracownik ${_getName(newOwner)} przejął narzędzie bezpośrednio od ${_getName(previousOwnerEmail)}.'
    );
    
    await _sendNotification(
      previousOwnerEmail, 
      'SPRZĘT PRZEKAZANY', 
      'Twoje narzędzie ${tool['name']} zostało przejęte przez ${_getName(newOwner)}.'
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Przejęto: ${tool['name']}"),
        backgroundColor: Colors.green,
      )
    );
  }

  void _openScanner({bool isSearch = false, Function(String)? onScanned}) {
    showDialog(context: context, builder: (c) => AlertDialog(contentPadding: EdgeInsets.zero, content: SizedBox(width: 300, height: 400, child: Stack(children: [
      MobileScanner(onDetect: (capture) {
        final List<Barcode> barcodes = capture.barcodes;
        if (barcodes.isNotEmpty) {
          final String code = barcodes.first.rawValue ?? "";
          if (code.isNotEmpty) {
            Navigator.pop(c);
            
            // Logika obsługi transferu P2P
            if (code.startsWith("TRANSFER:")) {
              final parts = code.split(":");
              if (parts.length >= 3) {
                _handleP2PTransfer(parts[1], parts[2]);
              }
              return;
            }

            if (isSearch) { setState(() { _searchQuery = code.toLowerCase(); _searchController.text = code; }); }
            else if (onScanned != null) onScanned(code);
          }
        }
      }),
      Positioned(top: 10, right: 10, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(c))),
    ]))));
  }

  void _showRequestToolDialog() {
    List<Map<String, dynamic>> items = [{'name': '', 'qty': ''}];
    final SignatureController sigCtrl = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    String? photoUrl;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("ZAPOTRZEBOWANIE NA SPRZĘT"),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...items.asMap().entries.map((entry) {
                    int i = entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Text("${i+1}.", style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              decoration: const InputDecoration(labelText: "Nazwa narzędzia", isDense: true),
                              onChanged: (v) => items[i]['name'] = v,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              decoration: const InputDecoration(labelText: "Ilość", isDense: true),
                              onChanged: (v) => items[i]['qty'] = v,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                            onPressed: () => setDS(() => items.removeAt(i)),
                          )
                        ],
                      ),
                    );
                  }).toList(),
                  TextButton.icon(
                    onPressed: () => setDS(() => items.add({'name': '', 'qty': ''})),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text("DODAJ POZYCJĘ"),
                  ),
                  const SizedBox(height: 16),
                  if (isSaving) 
                    const CircularProgressIndicator()
                  else if (photoUrl != null)
                    Stack(children: [
                      Image.network(photoUrl!, height: 100),
                      Positioned(right: 0, top: 0, child: IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setDS(() => photoUrl = null)))
                    ])
                  else
                    ElevatedButton.icon(
                      onPressed: () async {
                        final XFile? img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 40);
                        if (img != null) {
                          setDS(() => isSaving = true);
                          final fn = 'req_tool_${DateTime.now().millisecondsSinceEpoch}.jpg';
                          final ref = FirebaseStorage.instance.ref().child('warehouse/$fn');
                          if (kIsWeb) await ref.putData(await img.readAsBytes()); else await ref.putFile(File(img.path));
                          final url = await ref.getDownloadURL();
                          setDS(() { photoUrl = url; isSaving = false; });
                        }
                      },
                      icon: const Icon(Icons.add_a_photo),
                      label: const Text("DODAJ ZDJĘCIE (OPCJA)"),
                    ),
                  const Divider(height: 32),
                  const Text("PODPIS PRACOWNIKA:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(12)),
                    child: Signature(controller: sigCtrl, height: 120, backgroundColor: Colors.grey[50]!),
                  ),
                  TextButton(onPressed: () => sigCtrl.clear(), child: const Text("WYCZYŚĆ PODPIS", style: TextStyle(fontSize: 10, color: Colors.red))),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANULUJ")),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                String itemsText = items.where((it) => it['name'].isNotEmpty).map((it) => "${it['name']} - ${it['qty']}").join("\n");
                if (itemsText.isEmpty) return;
                if (sigCtrl.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Proszę złożyć podpis!")));
                  return;
                }

                setDS(() => isSaving = true);
                
                String? signatureUrl;
                try {
                  final sigData = await sigCtrl.toPngBytes();
                  if (sigData != null) {
                    final ref = FirebaseStorage.instance.ref().child("signatures/sig_req_${DateTime.now().millisecondsSinceEpoch}.png");
                    await ref.putData(sigData);
                    signatureUrl = await ref.getDownloadURL();
                  }
                } catch (_) {}

                final id = "REQ_${DateTime.now().millisecondsSinceEpoch}";
                final newReq = {
                  'id': id,
                  'type': 'TOOL_REQUEST',
                  'order_name': 'ZAPOTRZEBOWANIE NA SPRZĘT',
                  'items': itemsText,
                  'items_structured': items.where((it) => it['name'].isNotEmpty).toList(),
                  'author': widget.currentUserEmail,
                  'date': DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
                  'status': 'NOWE',
                  'photoUrl': photoUrl,
                  'signature_url': signatureUrl,
                };

                final prefs = await SharedPreferences.getInstance();
                final String? whData = prefs.getString('warehouse_orders_v1');
                List whOrders = whData != null ? json.decode(whData) : [];
                whOrders.insert(0, newReq);
                await prefs.setString('warehouse_orders_v1', AppUtils.safeJsonEncode(whOrders));
                await CloudSyncService().uploadWarehouseOrders();
                
                _sendNotification('admin', 'ZAPOTRZEBOWANIE NA SPRZĘT', 'Pracownik ${_getName(widget.currentUserEmail)} zgłosił zapotrzebowanie na sprzęt.');
                
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Zgłoszono zapotrzebowanie!")));
                }
              },
              child: const Text("WYŚLIJ"),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _exportToolsToPdf() async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, theme: pw.ThemeData.withFont(base: font, bold: fontBold), build: (pw.Context context) {
      return [ 
        pw.Header(level: 0, child: pw.Text('WYKAZ NARZĘDZI - ES CRM', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))), 
        pw.SizedBox(height: 10), 
        pw.TableHelper.fromTextArray(headers: ['Nazwa', 'Marka', 'Wlasciciel', 'Status'], data: _tools.map((t) => [ t['name'] ?? '', t['brand'] ?? '', t['owner'] == 'magazyn' ? 'MAGAZYN' : _getName(t['owner']), t['status'] ?? 'OK' ]).toList()) 
      ];
    }));
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Wykaz_Narzedzi.pdf');
  }
}
