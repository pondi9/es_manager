import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'core/app_theme.dart';
import 'core/app_constants.dart';
import 'widgets/theme_switcher.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'attendance_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'admin_panel_screen.dart';
import 'storage_screen.dart';
import 'services/cloud_sync_service.dart';
import 'core/app_utils.dart';

class ProcurementDashboardScreen extends StatefulWidget {
  final String userEmail;
  const ProcurementDashboardScreen({super.key, required this.userEmail});

  @override
  State<ProcurementDashboardScreen> createState() => _ProcurementDashboardScreenState();
}

class _ProcurementDashboardScreenState extends State<ProcurementDashboardScreen> {
  bool _isAdmin = false;
  Map<String, dynamic> _userPermissions = {};
  String _displayName = "";
  bool _isLoading = true;

  // Dane
  List<dynamic> _materialOrders = [];
  List<Map<String, dynamic>> _toolRequests = [];
  List<dynamic> _officeOrders = [];
  List<Map<String, dynamic>> _employees = [];

  // Statystyki KPI
  int _newMaterialsCount = 0;
  int _urgentToolsCount = 0;
  int _toBeCollectedCount = 0;
  int _officeRequestsCount = 0;
  int _toBeApprovedCount = 0;

  StreamSubscription? _notifSub;

  @override
  void initState() {
    super.initState();
    _checkAccess();
    _loadData();
    _initNotificationStream();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAccess() async {
    final userEmail = widget.userEmail.trim().toLowerCase();
    _isAdmin = userEmail == AppConstants.adminEmail;
    
    try {
      final userSnap = await FirebaseFirestore.instance.collection('employees').doc(userEmail).get();
      if (userSnap.exists && mounted) {
        setState(() {
          _userPermissions = userSnap.data()?['permissions'] ?? {};
          _displayName = "${userSnap.data()?['firstName'] ?? ''} ${userSnap.data()?['lastName'] ?? ''}".trim();
          if (_displayName.isEmpty) _displayName = userEmail;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Materiały z Magazynu
    try {
      await CloudSyncService().downloadWarehouseOrders().timeout(const Duration(seconds: 5));
    } catch (_) {}
    
    final String? data = prefs.getString('warehouse_orders_v1');
    if (data != null) {
      final List decoded = json.decode(data);
      if (mounted) {
        setState(() {
          _materialOrders = decoded.where((o) => o['type'] == 'MATERIAL_ORDER').toList();
          _officeOrders = decoded.where((o) => o['type'] == 'OFFICE_ORDER' || o['type'] == 'BHP_ORDER').toList();
          _newMaterialsCount = _materialOrders.where((o) => o['status'] == 'NOWE').length;
          _toBeApprovedCount = decoded.where((o) => o['status'] == 'NOWE').length;
          _toBeCollectedCount = decoded.where((o) => o['status'] == 'DO ODBIORU').length;
          _officeRequestsCount = _officeOrders.where((o) => o['status'] == 'NOWE').length;
        });
      }
    }

    // 2. Pracownicy (do mapowania nazwisk)
    try {
      final empSnap = await FirebaseFirestore.instance.collection('employees').get();
      if (mounted) {
        setState(() {
          _employees = empSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  void _initNotificationStream() {
    _notifSub = FirebaseFirestore.instance.collection('notifications')
      .orderBy('timestamp', descending: true)
      .limit(100)
      .snapshots()
      .listen((snap) {
        final List<Map<String, dynamic>> tools = [];
        for (var doc in snap.docs) {
          final n = doc.data();
          if (n['title'] == 'AWARIA SPRZĘTU' || n['title'] == 'ZAPOTRZEBOWANIE NA SPRZĘT') {
            tools.add({...n, 'id': doc.id});
          }
        }
        
        if (mounted) {
          setState(() {
            _toolRequests = tools;
            _urgentToolsCount = tools.where((t) => t['isRead'] == false).length;
          });
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1100;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: isDesktop ? null : Drawer(child: _buildSidebar(isMobile: true)),
      appBar: isDesktop ? null : AppBar(
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text("PULPIT ZAOPATRZENIA", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
        leading: Builder(builder: (context) => IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => Scaffold.of(context).openDrawer(),
        )),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewOrderDialog,
        backgroundColor: Colors.orange[800],
        icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
        label: const Text("ZAMÓW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildKpiGrid(isDesktop),
                            const SizedBox(height: 32),
                            if (isDesktop) 
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: Column(children: [
                                    _buildActiveMaterialsList(),
                                    const SizedBox(height: 24),
                                    _buildOfficeOrdersList(),
                                  ])),
                                  const SizedBox(width: 24),
                                  Expanded(flex: 2, child: _buildToolRequestsList()),
                                ],
                              )
                            else ...[
                              _buildActiveMaterialsList(),
                              const SizedBox(height: 24),
                              _buildOfficeOrdersList(),
                              const SizedBox(height: 24),
                              _buildToolRequestsList(),
                            ],
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF001A2C),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Pulpit Zaopatrzenia",
                style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              Text(
                "Witaj, $_displayName",
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          const ThemeSwitcher(),
          const SizedBox(width: 16),
          _headerIconButton(Icons.refresh_rounded, _loadData),
          const SizedBox(width: 16),
          _headerIconButton(Icons.logout_rounded, _handleLogout),
        ],
      ),
    );
  }

  Widget _headerIconButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: Colors.white10), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: Colors.white.withOpacity(0.6)),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("WYLOGOWAĆ SIĘ?"),
        content: const Text("Czy na pewno chcesz zakończyć sesję?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ANULUJ")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("WYLOGUJ")),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
    }
  }

  Widget _buildKpiGrid(bool isDesktop) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isDesktop ? 4 : 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: isDesktop ? 2.2 : 1.4,
      children: [
        _kpiCard("DO ZATWIERDZENIA", "$_toBeApprovedCount", "Wymaga uwagi", Icons.fact_check_rounded, Colors.teal, badgeCount: _toBeApprovedCount),
        _kpiCard("W REALIZACJI", "${_materialOrders.where((o) => o['status'] == 'ZAMÓWIONE' || o['status'] == 'W REALIZACJI').length}", "U dostawców", Icons.shopping_cart_checkout_rounded, Colors.orange),
        _kpiCard("WODA / BHP / BIURO", "$_officeRequestsCount", "Zapotrzebowanie", Icons.water_drop_rounded, Colors.cyan, badgeCount: _officeRequestsCount),
        _kpiCard("DO ODBIORU", "$_toBeCollectedCount", "Na dziś", Icons.local_shipping_rounded, Colors.purple, badgeCount: _toBeCollectedCount),
      ],
    );
  }

  Widget _kpiCard(String label, String value, String subValue, IconData icon, Color color, {int badgeCount = 0}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface.withOpacity(0.4), letterSpacing: 1)),
                  Icon(icon, color: color, size: 20),
                ],
              ),
              const SizedBox(height: 8),
              Text(value, style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.w900)),
              Text(subValue, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8), fontWeight: FontWeight.bold)),
            ],
          ),
          if (badgeCount > 0)
            Positioned(
              top: -10,
              right: -10,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Text("$badgeCount", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveMaterialsList() {
    final theme = Theme.of(context);
    final activeOrders = _materialOrders.where((o) => o['status'] != 'WYDANE').toList();
    activeOrders.sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));

    return _sectionPanel(
      title: "PILNE MATERIAŁY ZE ZLECEŃ",
      icon: Icons.assignment_rounded,
      child: activeOrders.isEmpty 
        ? const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("Brak aktywnych zamówień materiałów.")))
        : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeOrders.take(10).length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final o = activeOrders[i];
              final statusColor = _getStatusColor(o['status']);
              return ListTile(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StorageScreen(isAdmin: _isAdmin, userEmail: widget.userEmail, userGroup: 'Zaopatrzenie'))),
                title: Text(o['order_name'] ?? "Brak nazwy", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text("Od: ${_getName(o['author'])} | ${o['date']}", style: const TextStyle(fontSize: 11)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(o['status'], style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              );
            },
          ),
    );
  }

  Widget _buildToolRequestsList() {
    final theme = Theme.of(context);
    return _sectionPanel(
      title: "SPRZĘT / AWARIE / ZAPOTRZEBOWANIE",
      icon: Icons.build_circle_rounded,
      child: _toolRequests.isEmpty
        ? const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("Brak zgłoszeń sprzętowych.")))
        : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _toolRequests.take(15).length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = _toolRequests[i];
              final bool isFailure = t['title'] == 'AWARIA SPRZĘTU';
              final bool isRead = t['isRead'] == true;
              return ListTile(
                leading: Icon(isFailure ? Icons.report_problem_rounded : Icons.add_business_rounded, color: isFailure ? Colors.red : Colors.orange, size: 20),
                title: Text(t['title'] ?? "", style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold, fontSize: 12, color: theme.colorScheme.onSurface)),
                subtitle: Text(t['content'] ?? "", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(t['date'] ?? "", style: const TextStyle(fontSize: 8, color: Colors.grey)),
                    if (!isRead) Container(margin: const EdgeInsets.only(top: 4), width: 6, height: 6, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                  ],
                ),
                onTap: () => _markNotifRead(t['id']),
              );
            },
          ),
    );
  }

  Widget _buildOfficeOrdersList() {
    final activeOffice = _officeOrders.where((o) => o['status'] != 'WYDANE').toList();
    activeOffice.sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));

    return _sectionPanel(
      title: "EKSPLOATACJA (WODA / BHP / BIURO)",
      icon: Icons.water_drop_rounded,
      child: activeOffice.isEmpty 
        ? const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("Brak zapotrzebowania na artykuły eksploatacyjne.")))
        : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeOffice.take(10).length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final o = activeOffice[i];
              final statusColor = _getStatusColor(o['status']);
              return ListTile(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StorageScreen(isAdmin: _isAdmin, userEmail: widget.userEmail, userGroup: 'Zaopatrzenie'))),
                leading: Icon(o['type'] == 'BHP_ORDER' ? Icons.security_rounded : Icons.local_drink_rounded, color: Colors.cyan, size: 20),
                title: Text(o['items'] ?? "Zapotrzebowanie", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text("Zgłosił: ${_getName(o['author'])} | ${o['date']}", style: const TextStyle(fontSize: 11)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(o['status'], style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              );
            },
          ),
    );
  }

  Widget _sectionPanel({required String title, required IconData icon, required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 14)),
              ],
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }

  Widget _buildSidebar({bool isMobile = false}) {
    return Container(
      width: 260,
      color: const Color(0xFF001A2C),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [const Icon(Icons.bolt, color: Colors.blue, size: 32), const SizedBox(width: 10), Text("ES CRM", style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -1))]),
                Text("ZAOPATRZENIE / LOGISTYKA", style: GoogleFonts.montserrat(color: Colors.blue.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5))
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _sidebarItem(Icons.dashboard_rounded, "Pulpit Logistyka", true, onTap: () {}),
                _sidebarItem(Icons.shopping_cart_rounded, "Zamówienia materiałów", false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StorageScreen(isAdmin: _isAdmin, userEmail: widget.userEmail, userGroup: 'Zaopatrzenie')))),
                _sidebarItem(Icons.build_rounded, "Zapotrzebowanie / Narzędzia", false, onTap: () {}),
                _sidebarItem(Icons.water_drop_rounded, "Woda / BHP / Biuro", false, onTap: () {}),
                _sidebarItem(Icons.forum_rounded, "Czat", false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(currentUserEmail: widget.userEmail, displayName: _displayName)))),
                const Divider(color: Colors.white10),
                _sidebarItem(Icons.settings_rounded, "Ustawienia", false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(isAdmin: _isAdmin, userEmail: widget.userEmail)))),
                _sidebarItem(Icons.logout_rounded, "Wyloguj", false, onTap: _handleLogout),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, bool active, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active ? Colors.blue.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active ? Border.all(color: Colors.blue.withOpacity(0.3)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? Colors.blue : Colors.white.withOpacity(0.4), size: 20),
            const SizedBox(width: 16),
            Text(label, style: GoogleFonts.montserrat(color: active ? Colors.white : Colors.white.withOpacity(0.4), fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  String _getName(String? email) {
    if (email == null || email.isEmpty) return "-";
    final String sMail = email.trim().toLowerCase();
    try {
      final emp = _employees.firstWhere((e) => (e['email'] ?? '').toString().toLowerCase() == sMail || (e['id'] ?? '').toString().toLowerCase() == sMail, orElse: () => {});
      if (emp.isEmpty) return email;
      return "${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}".trim();
    } catch (_) { return email; }
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

  void _showNewOrderDialog() {
    final List<String> types = ["MATERIAŁY", "SPRZĘT / NARZĘDZIA", "WODA", "BHP", "BIURO"];
    String selType = types.first;
    final itemsC = TextEditingController();
    final noteC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("NOWE ZAPOTRZEBOWANIE", style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selType,
                decoration: const InputDecoration(labelText: "Kategoria", border: OutlineInputBorder()),
                items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setDS(() => selType = v!),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: itemsC,
                maxLines: 5,
                decoration: const InputDecoration(labelText: "Co trzeba zamówić?", hintText: "Wpisz listę produktów...", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteC,
                decoration: const InputDecoration(labelText: "Uwagi (opcjonalnie)", border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANULUJ")),
          ElevatedButton(
            onPressed: () async {
              if (itemsC.text.isEmpty) return;
              
              String typeKey = "MATERIAL_ORDER";
              if (selType == "WODA" || selType == "BIURO") typeKey = "OFFICE_ORDER";
              if (selType == "BHP") typeKey = "BHP_ORDER";
              if (selType == "SPRZĘT / NARZĘDZIA") typeKey = "TOOL_ORDER";

              final now = DateTime.now();
              final String orderNo = "ZAM/${now.year}/${now.month.toString().padLeft(2, '0')}/${now.millisecondsSinceEpoch.toString().characters.takeLast(4)}";

              final n = {
                'id': DateTime.now().millisecondsSinceEpoch.toString(),
                'order_no': orderNo,
                'author': widget.userEmail,
                'date': DateFormat('dd.MM HH:mm').format(now),
                'items': itemsC.text,
                'status': 'NOWE',
                'order_name': "Zapotrzebowanie: $selType",
                'type': typeKey,
                'note': noteC.text,
              };

              await FirebaseFirestore.instance.collection('warehouse').doc(n['id']).set(n);
              await _loadData();
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Zgłoszono zapotrzebowanie!"), backgroundColor: Colors.green));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
            child: const Text("ZAMÓW"),
          )
        ],
      )),
    );
  }

  Future<void> _markNotifRead(String id) async {
    await FirebaseFirestore.instance.collection('notifications').doc(id).update({'isRead': true});
  }
}
