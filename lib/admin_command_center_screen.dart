import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'core/app_theme.dart';
import 'core/app_constants.dart';
import 'widgets/theme_switcher.dart';
import 'widgets/es_modal.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'attendance_screen.dart';
import 'orders_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'issues_screen.dart';
import 'notifications_screen.dart';
import 'knowledge_base_screen.dart';
import 'storage_screen.dart';
import 'fleet_screen.dart';
import 'expenses_screen.dart';
import 'clients_screen.dart';
import 'tools_screen.dart';
import 'protocols_screen.dart';
import 'important_files_screen.dart';
import 'estimations_screen.dart';
import 'admin_panel_screen.dart';
import 'client_leads_screen.dart';
import 'hr_dashboard_screen.dart';
import 'procurement_dashboard_screen.dart';
import 'tools_map_screen.dart';
import 'tools/lan_labels_screen.dart';
import 'tools/flashlight_screen.dart';
import 'tools/lux_meter_screen.dart';
import 'tools/cable_calculator_screen.dart';
import 'tools/db_labels_screen.dart';
import 'tools/schematic_creator_screen.dart';
import 'tools/nfc_tag_screen.dart';
import 'tools/switchboard_visualizer_screen.dart';
import 'tools/label_designer_screen.dart';
import 'tools/installation_documentation_screen.dart';
import 'helpful_apps_screen.dart';
import 'services/attendance_service.dart';

class AdminCommandCenterScreen extends StatefulWidget {
  final String userEmail;
  const AdminCommandCenterScreen({super.key, required this.userEmail});

  @override
  State<AdminCommandCenterScreen> createState() => _AdminCommandCenterScreenState();
}

class _AdminCommandCenterScreenState extends State<AdminCommandCenterScreen> {
  bool _isAdmin = false;
  Map<String, dynamic> _userPermissions = {};
  String _displayName = "";
  List<String> _crews = ['Ekipa 1', 'Ekipa 2', 'Stadion', 'Biuro'];
  bool _isLoading = true;
  SharedPreferences? _prefs;

  // Realne dane
  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _allEmployees = [];
  List<Map<String, dynamic>> _allIssues = [];
  List<Map<String, dynamic>> _allTools = [];
  List<Map<String, dynamic>> _allClients = [];
  Map<String, Map<String, dynamic>> _allAttendance = {};
  
  // Statystyki
  int _activeOrdersCount = 0;
  int _urgentOrdersCount = 0;
  int _activeEmployeesCount = 0;
  int _employeesAtWorkToday = 0;
  int _openIssuesCount = 0;
  int _attendanceGapsCount = 0;
  int _workTimeMode = 0; // 0: Month, 1: Total, 2: By Order
  double _totalHoursThisMonth = 0;
  double _totalHoursAllTime = 0;
  String _topPerformerName = "-";
  double _topPerformerHours = 0;
  List<Map<String, dynamic>> _liveActivities = [];
  List<Map<String, dynamic>> _recentAlerts = [];
  List<Map<String, dynamic>> _assignments = [];
  int _unreadChatCount = 0;
  int _unreadAlertCount = 0;
  DateTime? _customAssignmentDate; // null means "Today + Tomorrow"

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _workTimeKey = GlobalKey();

  StreamSubscription? _ordersSub, _empSub, _issueSub, _attSub, _toolsSub, _clientsSub, _noteSub, _assSub;

  @override
  void initState() {
    super.initState();
    _checkAccess();
    _initDataStreams();
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _empSub?.cancel();
    _issueSub?.cancel();
    _attSub?.cancel();
    _toolsSub?.cancel();
    _clientsSub?.cancel();
    _noteSub?.cancel();
    _assSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkAccess() async {
    final userEmail = widget.userEmail.trim().toLowerCase();
    _isAdmin = userEmail == AppConstants.adminEmail;
    _prefs = await SharedPreferences.getInstance();
    
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

  void _initDataStreams() {
    _loadCrews();
    // POBIERZ DANE UŻYTKOWNIKA (GRUPA)
    FirebaseFirestore.instance.collection('employees').doc(widget.userEmail.trim().toLowerCase()).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        final d = snap.data()!;
        setState(() {
          _userPermissions = d['permissions'] ?? {};
          _displayName = "${d['firstName'] ?? ''} ${d['lastName'] ?? ''}".trim();
          if (_displayName.isEmpty) _displayName = widget.userEmail;
          // Zapisz grupę do filtrowania notyfikacji
          _prefs?.setString('user_group', d['group'] ?? "");
        });
      }
    });

    _ordersSub = FirebaseFirestore.instance.collection('orders').snapshots().listen((snap) {
      final orders = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      if (mounted) {
        setState(() {
          _allOrders = orders;
          _activeOrdersCount = orders.where((o) => o['status'] != 'ZAKOŃCZONO').length;
          _updateLiveActivities();
        });
      }
    });

    _empSub = FirebaseFirestore.instance.collection('employees').snapshots().listen((snap) {
      final emps = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      if (mounted) {
        setState(() {
          _allEmployees = emps;
          _activeEmployeesCount = emps.where((e) => e['isActive'] == true).length;
          _calculateAttendanceGaps();
        });
      }
    });

    _issueSub = FirebaseFirestore.instance.collection('issues').snapshots().listen((snap) {
      final issues = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      if (mounted) {
        setState(() {
          _allIssues = issues;
          _openIssuesCount = issues.where((i) => i['status'] != 'ROZWIĄZANO' && i['status'] != 'ZAMKNIĘTY').length;
          _updateLiveActivities();
        });
      }
    });

    _toolsSub = FirebaseFirestore.instance.collection('tools').snapshots().listen((snap) {
      final tools = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      if (mounted) setState(() => _allTools = tools);
    });

    _clientsSub = FirebaseFirestore.instance.collection('clients').snapshots().listen((snap) {
      final clients = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      if (mounted) setState(() => _allClients = clients);
    });

    _attSub = FirebaseFirestore.instance.collection('attendance').snapshots().listen((snap) {
      final attService = AttendanceService();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final currentMonthPrefix = DateFormat('yyyy-MM').format(DateTime.now());
      
      int atWork = 0;
      double totalHMonth = 0;
      double totalHAll = 0;
      Map<String, Map<String, dynamic>> attData = {};

      for (var doc in snap.docs) {
        final data = doc.data();
        final Map<String, dynamic> attMap = data['data'] ?? {};
        attData[doc.id.toLowerCase()] = attMap;

        if (attMap.containsKey(todayStr)) {
          if (attMap[todayStr]['type'] == 'PRACA') atWork++;
        }
        attMap.forEach((date, val) {
          double h = attService.calculateHours(val['in'], val['out']);
          if (val['type'] == 'URLOP') h = 8.0; 
          
          if (val['type'] == 'PRACA') {
            totalHAll += h;
            if (date.startsWith(currentMonthPrefix)) {
              totalHMonth += h;
            }
          }
        });
      }

      if (mounted) {
        setState(() {
          _allAttendance = attData;
          _employeesAtWorkToday = atWork;
          _totalHoursThisMonth = totalHMonth;
          _totalHoursAllTime = totalHAll;
          _isLoading = false;
          _calculateAttendanceGaps();
        });
      }
    });

    _noteSub = FirebaseFirestore.instance.collection('notifications').snapshots().listen((snap) {
      final String userEmail = widget.userEmail.trim().toLowerCase();
      final String userGroup = _prefs?.getString('user_group') ?? "";
      final String groupTarget = userGroup.isNotEmpty ? 'group:$userGroup' : 'NONE';

      final all = snap.docs.map((d) => d.data() as Map<String, dynamic>).where((n) {
        if (n['isRead'] == true) return false;
        final String target = (n['target'] ?? "").toString().toLowerCase();
        return target == 'all' || target == userEmail || target == groupTarget.toLowerCase() || (_isAdmin && target == 'admin');
      }).toList();

      if (mounted) setState(() { _recentAlerts = all; _unreadChatCount = all.where((n) => n['title'] == 'NOWA WIADOMOŚĆ' || n['title'] == 'WIADOMOŚĆ DLA EKIPY').length; _unreadAlertCount = all.length; });
    });

    _assSub = FirebaseFirestore.instance.collection('assignments').snapshots().listen((snap) {
      if (mounted) setState(() { _assignments = snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList(); });
    });
  }

  void _calculateAttendanceGaps() {
    if (_allEmployees.isEmpty) return;
    
    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    final isBizDay = today.weekday != DateTime.saturday && today.weekday != DateTime.sunday;
    
    if (!isBizDay) {
      setState(() => _attendanceGapsCount = 0);
      return;
    }

    int gaps = 0;
    for (var emp in _allEmployees) {
      if (emp['isActive'] == true) {
        final String email = (emp['email'] ?? emp['id'] ?? "").toString().toLowerCase();
        if (email.isEmpty || email == AppConstants.adminEmail) continue;
        
        final att = _allAttendance[email]?[todayStr];
        if (att == null) {
          gaps++;
        } else {
          final String type = att['type']?.toString().toUpperCase() ?? "";
          if (type != 'PRACA' && type != 'URLOP' && type != 'L4' && type != 'DELEGACJA') {
            gaps++;
          }
        }
      }
    }
    setState(() => _attendanceGapsCount = gaps);
  }

  void _updateLiveActivities() {
    List<Map<String, dynamic>> activities = [];
    for (var o in _allOrders) {
      final stages = o['stages'] as List? ?? [];
      for (var s in stages) {
        final logs = s['logs'] as List? ?? [];
        for (var l in logs) {
          activities.add({
            'text': "${l['author'] != null ? _getShortEmpName(l['author']) : 'SYSTEM'}: ${l['text']}",
            'time': l['date'] ?? "",
            'icon': _getActivityIcon(l['text']),
            'color': _getActivityColor(l['text']),
            'timestamp': _parseDate(l['date']),
            'orderName': o['name'],
            'order': o,
          });
        }
      }
    }
    for (var i in _allIssues) {
      activities.add({
        'text': "ZGŁOSZONO PROBLEM: ${i['description']}",
        'time': i['date'] ?? "",
        'icon': Icons.warning_amber_rounded,
        'color': Colors.red,
        'timestamp': _parseDate(i['date']),
        'orderId': i['orderId'],
      });
    }
    activities.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));
    _liveActivities = activities.take(15).toList();
    
    // Licznik pilnych zleceń
    _urgentOrdersCount = _allOrders.where((o) => o['status'] != 'ZAKOŃCZONO' && _isOrderUrgent(o)).length;
  }

  bool _isOrderUrgent(Map<String, dynamic> o) {
    if (_hasRecentIssues(o['id'])) return true;
    
    // Sprawdzanie czy przypisano jakiekolwiek ekipy
    final crews = o['assigned_crews'] as List? ?? (o['assigned_crew'] != null ? [o['assigned_crew']] : []);
    if (crews.isEmpty || (crews.length == 1 && crews.first.toString().isEmpty)) return true;
    
    // Sprawdzanie terminów
    if (o['endDate'] != null && o['endDate'].toString().isNotEmpty) {
      try {
        final end = DateFormat('dd.MM.yyyy').parse(o['endDate']);
        if (end.isBefore(DateTime.now())) return true;
      } catch (_) {}
    }
    return false;
  }

  String _getShortEmpName(String email) {
    final e = _allEmployees.firstWhere((e) => (e['email'] ?? '').toString().toLowerCase() == email.toLowerCase(), orElse: () => {});
    if (e.isNotEmpty) return "${e['firstName'] ?? ''} ${e['lastName']?[0] ?? ''}.".trim();
    return email.split('@')[0];
  }

  String _getEmpFullName(String? email) {
    if (email == null || email.isEmpty) return "-";
    final sMail = email.trim().toLowerCase();
    if (sMail == 'admin' || sMail == 'escrm@int.pl') return "Administrator";
    final emp = _allEmployees.firstWhere((e) => (e['email'] ?? '').toString().toLowerCase() == sMail, orElse: () => {});
    if (emp.isNotEmpty) return "${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}".trim();
    return email;
  }

  bool _hasRecentIssues(String orderId) {
    return _allIssues.any((i) => i['orderId'] == orderId && i['status'] != 'ROZWIĄZANO' && i['status'] != 'ZAMKNIĘTY');
  }

  DateTime _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return DateTime(2000);
    try {
      final now = DateTime.now();
      final parts = dateStr.split(' ');
      final dateParts = parts[0].split('.');
      final timeParts = parts[1].split(':');
      return DateTime(now.year, int.parse(dateParts[1]), int.parse(dateParts[0]), int.parse(timeParts[0]), int.parse(timeParts[1]));
    } catch (_) { return DateTime(2000); }
  }

  IconData _getActivityIcon(String text) {
    if (text.contains("✅")) return Icons.check_circle_rounded;
    if (text.contains("🚀") || text.contains("MELDUNEK")) return Icons.engineering_rounded;
    if (text.contains("📸")) return Icons.photo_library_rounded;
    return Icons.info_outline_rounded;
  }

  Color _getActivityColor(String text) {
    if (text.contains("✅")) return Colors.green;
    if (text.contains("🚀")) return Colors.blue;
    if (text.contains("📸")) return Colors.purple;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 700;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: isDesktop ? null : Drawer(child: _buildSidebar(isMobile: true)),
      appBar: isDesktop ? null : AppBar(
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text("CENTRUM DOWODZENIA", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
        leading: Builder(builder: (context) => IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => Scaffold.of(context).openDrawer(),
        )),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded), 
            onPressed: _handleLogout,
            tooltip: "Wyloguj się",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(),
          Expanded(
            child: isDesktop ? _buildDesktopDashboardContent() : _buildMobileDashboardContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDashboardContent() {
    if (_isLoading && _allOrders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildKpiGrid(),
                const SizedBox(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          _buildAssignmentsPanel(),
                          const SizedBox(height: 32),
                          _buildMainOrdersPanel(),
                          const SizedBox(height: 32),
                          _buildLiveActivityPanel(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          SizedBox(key: _workTimeKey, child: _buildWorkTimeAnalysisPanel()),
                          const SizedBox(height: 32),
                          _buildTodayInCompanyPanel(),
                          const SizedBox(height: 32),
                          _buildUrgentMattersPanel(),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileDashboardContent() {
    if (_isLoading && _allOrders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Witaj, $_displayName 👋",
            style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            "Oto aktualna sytuacja w Twojej firmie.",
            style: TextStyle(color: Colors.grey.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          
          // 2x2 KPI Grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _kpiCard("PRACOWNICY", "$_activeEmployeesCount", "$_employeesAtWorkToday w pracy", Icons.people_alt_rounded, Colors.blue, 
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen())),
                badgeCount: _attendanceGapsCount),
              _kpiCard("AKTYWNE ZLECENIA", "$_activeOrdersCount", "$_urgentOrdersCount uwagi", Icons.assignment_rounded, Colors.orange, 
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail, userPermissions: _userPermissions))),
                badgeCount: _urgentOrdersCount),
              _kpiCard("CZAS PRACY", "${_totalHoursThisMonth.toInt()}h", "W tym miesiącu", Icons.access_time_filled_rounded, Colors.green, 
                onTap: _scrollToWorkTime),
              _kpiCard("PROBLEMY", "$_openIssuesCount", "Otwarte", Icons.warning_rounded, Colors.red, 
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssuesScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail))),
                badgeCount: _openIssuesCount),
            ],
          ),
          
          const SizedBox(height: 24),
          SizedBox(key: _workTimeKey, child: _buildWorkTimeAnalysisPanel()),
          
          const SizedBox(height: 24),
          _buildAssignmentsPanel(isMobile: true),
          
          const SizedBox(height: 24),
          _buildMainOrdersPanel(limit: 3),
          
          const SizedBox(height: 24),
          _buildUrgentMattersPanel(),
          
          const SizedBox(height: 24),
          _buildLiveActivityPanel(limit: 3),
          
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  void _scrollToWorkTime() {
    if (_workTimeKey.currentContext != null) {
      Scrollable.ensureVisible(
        _workTimeKey.currentContext!,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dateStr = DateFormat('d MMMM yyyy', 'pl_PL').format(now);
    final bool canGoBack = Navigator.canPop(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.white10)),
      ),
      child: Row(
        children: [
          if (canGoBack) ...[
            _headerIconButton(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
            const SizedBox(width: 24),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Dzień dobry, $_displayName 👋",
                style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                "Oto aktualna sytuacja w Twojej firmie.",
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const ThemeSwitcher(),
          const SizedBox(width: 16),
          _headerIconButton(Icons.notifications_none_rounded, () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)));
          }),
          const SizedBox(width: 16),
          _headerIconButton(Icons.refresh_rounded, () => setState(() {})),
          const SizedBox(width: 16),
          _headerIconButton(Icons.logout_rounded, _handleLogout),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("WYLOGOWAĆ SIĘ?"),
        content: const Text("Czy na pewno chcesz zakończyć sesję i wrócić do ekranu logowania?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ANULUJ")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("WYLOGUJ")
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context, 
          MaterialPageRoute(builder: (_) => LoginScreen()),
          (route) => false
        );
      }
    }
  }

  Widget _headerIconButton(IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
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

  Widget _buildKpiGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 5,
      crossAxisSpacing: 20,
      mainAxisSpacing: 20,
      childAspectRatio: 1.6,
      children: [
        _kpiCard("PRACOWNICY", "$_activeEmployeesCount", "$_employeesAtWorkToday w pracy", Icons.people_alt_rounded, Colors.blue, 
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen())),
          badgeCount: _attendanceGapsCount),
        _kpiCard("AKTYWNE ZLECENIA", "$_activeOrdersCount", "$_urgentOrdersCount wymaga uwagi", Icons.assignment_rounded, Colors.orange, 
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail, userPermissions: _userPermissions))),
          badgeCount: _urgentOrdersCount),
        _kpiCard("CZAS PRACY", "${_totalHoursThisMonth.toStringAsFixed(0)}h", "W tym miesiącu", Icons.access_time_filled_rounded, Colors.green, 
          onTap: _scrollToWorkTime),
        _kpiCard("PROBLEMY", "$_openIssuesCount", "Otwarte zgłoszenia", Icons.warning_rounded, Colors.red, 
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssuesScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail))),
          badgeCount: _openIssuesCount),
        _kpiCard("FINANSE", "Brak danych", "Moduł zostanie aktywowany wkrótce", Icons.account_balance_wallet_rounded, Colors.purple, 
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExpensesScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))),
      ],
    );
  }

  Widget _kpiCard(String label, String value, String subValue, IconData icon, Color color, {VoidCallback? onTap, int badgeCount = 0}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          hoverColor: color.withOpacity(0.05),
          splashColor: color.withOpacity(0.1),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label, style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface.withOpacity(0.4), letterSpacing: 1)),
                        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: GoogleFonts.montserrat(fontSize: value.length > 5 ? 20 : 28, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface))),
                        const SizedBox(height: 4),
                        Text(subValue, style: TextStyle(color: color.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Icon(Icons.arrow_outward_rounded, size: 12, color: theme.colorScheme.onSurface.withOpacity(0.1)),
                ),
              if (badgeCount > 0)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.cardTheme.color ?? Colors.white, width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)],
                    ),
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    child: Center(
                      child: Text(
                        "$badgeCount",
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainOrdersPanel({int? limit}) {
    final theme = Theme.of(context);
    final activeOrders = _allOrders.where((o) => o['status'] != 'ZAKOŃCZONO').toList();
    return _dashboardPanel(
      title: "AKTUALNE ZLECENIA",
      icon: Icons.list_alt_rounded,
      onAction: limit == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail, userPermissions: _userPermissions))),
      child: Column(
        children: [
          if (limit == null) ...[
            _ordersTableHeader(),
            const Divider(height: 1),
          ],
          if (activeOrders.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Text("Brak aktywnych zleceń.", style: TextStyle(color: Colors.grey)))
          else
            ...(limit == null ? activeOrders.take(10) : activeOrders.take(limit)).map((o) => _orderRow(o, isMobile: limit != null)),
          
          if (limit != null && activeOrders.length > limit)
            _seeAllButton(() => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail, userPermissions: _userPermissions)))),
        ],
      ),
    );
  }

  Widget _ordersTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: [
          Expanded(flex: 3, child: _headerCell("ZLECENIE")),
          Expanded(flex: 2, child: _headerCell("STATUS")),
          Expanded(flex: 2, child: _headerCell("POSTĘP")),
          Expanded(flex: 2, child: _headerCell("TERMIN")),
          Expanded(flex: 2, child: _headerCell("EKIPA")),
          Expanded(flex: 1, child: _headerCell("")),
        ],
      ),
    );
  }

  Widget _headerCell(String text) {
    return Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey.withOpacity(0.6), letterSpacing: 1));
  }

  Widget _orderRow(Map<String, dynamic> o, {bool isMobile = false}) {
    final theme = Theme.of(context);
    List stages = o['stages'] as List? ?? [];
    int done = stages.where((s) => s['status'] == 'ZAKOŃCZONO').length;
    double progress = stages.isEmpty ? 0 : done / stages.length;
    bool hasIssues = _hasRecentIssues(o['id']);
    
    final crews = o['assigned_crews'] as List? ?? (o['assigned_crew'] != null ? [o['assigned_crew']] : []);
    bool noCrew = crews.isEmpty || (crews.length == 1 && crews.first.toString().isEmpty);

    if (isMobile) {
      return InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailView(
          order: o, isAdmin: _isAdmin, currentUserEmail: widget.userEmail, getName: _getEmpFullName, saveOrders: () async {}, saveTools: () async {}, toolsDB: _allTools, canEdit: true, tools: _allTools, clients: _allClients, prefs: _prefs,
        ))),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerTheme.color ?? Colors.white10))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o['name'] ?? "Brak nazwy", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    _statusChip(o['status'] ?? 'NOWE', isUrgent: hasIssues),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${(progress * 100).toInt()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SizedBox(width: 60, child: _progressMini(progress, hideText: true)),
                ],
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.primary.withOpacity(0.3), size: 18),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailView(
        order: o, 
        isAdmin: _isAdmin, 
        currentUserEmail: widget.userEmail, 
        getName: _getEmpFullName, 
        saveOrders: () async {}, // Dashboard should not save here
        saveTools: () async {},
        toolsDB: _allTools,
        canEdit: _isAdmin || (_userPermissions['manage_orders'] == true),
        tools: _allTools,
        clients: _allClients,
        prefs: _prefs,
      ))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerTheme.color ?? Colors.white10))),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(o['name'] ?? "Brak nazwy", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            Expanded(flex: 2, child: _statusChip(o['status'] ?? 'NOWE', isUrgent: hasIssues)),
            Expanded(flex: 2, child: _progressMini(progress)),
            Expanded(flex: 2, child: Text(o['endDate'] ?? "-", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12))),
            Expanded(flex: 2, child: noCrew 
              ? Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 14), const SizedBox(width: 4), const Text("Nie przypisano", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))])
              : Text(crews.join(", "), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(flex: 1, child: Icon(Icons.chevron_right_rounded, color: theme.colorScheme.primary.withOpacity(0.3))),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status, {bool isUrgent = false}) {
    Color col = isUrgent ? Colors.red : Colors.blue;
    if (status == 'ZAKOŃCZONO') col = Colors.green;
    if (status == 'NOWE') col = Colors.orange;
    return Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: col, shape: BoxShape.circle)), const SizedBox(width: 8), Text(status, style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 10))]);
  }

  Widget _progressMini(double val, {bool hideText = false}) {
    final theme = Theme.of(context);
    return Row(children: [
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: val, backgroundColor: theme.colorScheme.onSurface.withOpacity(0.05), color: val == 1.0 ? Colors.green : Colors.blue, minHeight: 6))), 
      if (!hideText) ...[const SizedBox(width: 12), Text("${(val * 100).toInt()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))]
    ]);
  }

  Widget _buildLiveActivityPanel({int? limit}) {
    return _dashboardPanel(
      title: "OSTATNIA AKTYWNOŚĆ",
      icon: Icons.bolt_rounded,
      child: Column(
        children: [
          if (_liveActivities.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Text("Brak ostatniej aktywności.", style: TextStyle(color: Colors.grey)))
          else
            ...(limit == null ? _liveActivities.take(8) : _liveActivities.take(limit)).map((a) => _activityItem(a['text'], a['time'], a['icon'], a['color'], orderName: a['orderName'], order: a['order'])),
          
          if (limit != null && _liveActivities.length > limit)
            _seeAllButton(() {
               // Navigation to some history view or just expand
               setState(() {}); // For now we don't have a dedicated history screen for all activities
            }),
        ],
      ),
    );
  }

  Widget _seeAllButton(VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
        child: const Text("ZOBACZ WSZYSTKIE", textAlign: TextAlign.center, style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
      ),
    );
  }

  Widget _activityItem(String text, String time, IconData icon, Color color, {String? orderName, Map<String, dynamic>? order}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: order == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailView(
        order: order, 
        isAdmin: _isAdmin, 
        currentUserEmail: widget.userEmail, 
        getName: _getEmpFullName, 
        saveOrders: () async {},
        saveTools: () async {},
        toolsDB: _allTools,
        canEdit: _isAdmin || (_userPermissions['manage_orders'] == true),
        tools: _allTools,
        clients: _allClients,
        prefs: _prefs,
      ))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 16)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), if (orderName != null) Text(orderName, style: TextStyle(color: theme.colorScheme.primary.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold))])),
            Text(time, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3), fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkTimeAnalysisPanel() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Aggregating data based on _workTimeMode
    List<_AnalysisEntry> entries = [];
    String topName = "-";
    double topVal = 0;

    final attService = AttendanceService();
    final currentMonthPrefix = DateFormat('yyyy-MM').format(DateTime.now());

    if (_workTimeMode == 0) { // TEN MIESIĄC
      _allAttendance.forEach((email, data) {
        double sum = 0;
        data.forEach((date, val) {
          if (date.startsWith(currentMonthPrefix) && val['type'] == 'PRACA') {
            sum += attService.calculateHours(val['in'], val['out']);
          }
        });
        if (sum > 0) {
          String name = _getShortEmpName(email);
          entries.add(_AnalysisEntry(label: name, value: sum, email: email));
          if (sum > topVal) { topVal = sum; topName = name; }
        }
      });
    } else if (_workTimeMode == 1) { // OD POCZĄTKU
      _allAttendance.forEach((email, data) {
        double sum = 0;
        data.forEach((date, val) {
          if (val['type'] == 'PRACA') {
            sum += attService.calculateHours(val['in'], val['out']);
          }
        });
        if (sum > 0) {
          String name = _getShortEmpName(email);
          entries.add(_AnalysisEntry(label: name, value: sum, email: email));
          if (sum > topVal) { topVal = sum; topName = name; }
        }
      });
    } else { // WG ZLECENIA
      Map<String, double> orderHours = {};
      _allAttendance.forEach((email, data) {
        data.forEach((date, val) {
          if (val['type'] == 'PRACA') {
            String orderName = val['orderName'] ?? "Nieokreślone";
            double h = attService.calculateHours(val['in'], val['out']);
            orderHours[orderName] = (orderHours[orderName] ?? 0) + h;
          }
        });
      });
      orderHours.forEach((name, sum) {
        entries.add(_AnalysisEntry(label: name, value: sum));
        if (sum > topVal) { topVal = sum; topName = name; }
      });
    }

    entries.sort((a, b) => b.value.compareTo(a.value));
    final double maxVal = entries.isEmpty ? 1 : entries.first.value;

    return _dashboardPanel(
      title: "CZAS PRACY",
      icon: Icons.access_time_filled_rounded,
      child: Column(
        children: [
          // View Switcher
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  _modeTab(0, "MIESIĄC"),
                  _modeTab(1, "ŁĄCZNIE"),
                  _modeTab(2, "ZLECENIA"),
                ],
              ),
            ),
          ),

          // Summary Mini Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniWorkStat("Miesiąc", "${_totalHoursThisMonth.toInt()}h"),
                _miniWorkStat("Lider", "$topName (${topVal.toInt()}h)"),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          if (entries.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("Brak danych pracy.", style: TextStyle(color: Colors.grey, fontSize: 11, fontStyle: FontStyle.italic))))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              itemCount: entries.take(8).length,
              itemBuilder: (context, idx) {
                final e = entries[idx];
                return _workTimeBar(e, maxVal);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _modeTab(int mode, String label) {
    bool active = _workTimeMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _workTimeMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: active ? Colors.white : Colors.grey, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ),
      ),
    );
  }

  Widget _miniWorkStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey.withOpacity(0.6))),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _workTimeBar(_AnalysisEntry e, double maxVal) {
    final theme = Theme.of(context);
    final double percent = e.value / maxVal;
    
    return InkWell(
      onTap: () {
        if (_workTimeMode == 2) {
          // Find matching order
          final order = _allOrders.firstWhere((o) => (o['name'] ?? "").toString().trim() == e.label.trim(), orElse: () => {});
          if (order.isNotEmpty) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailView(
              order: order, 
              isAdmin: _isAdmin, 
              currentUserEmail: widget.userEmail, 
              getName: _getEmpFullName, 
              saveOrders: () async {},
              saveTools: () async {},
              toolsDB: _allTools,
              canEdit: true,
              tools: _allTools,
              clients: _allClients,
              prefs: _prefs,
            )));
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(e.label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text("${e.value.toStringAsFixed(1)} h", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blue)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 6,
                backgroundColor: theme.colorScheme.onSurface.withOpacity(0.05),
                color: Colors.blue.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentsPanel({bool isMobile = false}) {
    final theme = Theme.of(context);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final tomorrow = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));
    
    // Pokaż wszystkie rozdysponowania
    List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(_assignments);

    // Sort by date (ascending) then by name
    list.sort((a, b) {
      int dateComp = a['date'].toString().compareTo(b['date'].toString());
      if (dateComp != 0) return dateComp;
      return (a['empName'] ?? "").toString().compareTo(b['empName'] ?? "");
    });
    
    return _dashboardPanel(
      title: "ROZDYSPONOWANIE PRACY (WSZYSTKIE)",
      icon: Icons.assignment_ind_rounded,
      onAction: _showAddAssignmentDialog,
      actionIcon: Icons.add_task_rounded,
      child: Column(
        children: [
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40), 
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_available_rounded, size: 40, color: Colors.grey.withOpacity(0.2)),
                    const SizedBox(height: 12),
                    const Text("Brak zaplanowanych zadań.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                )
              )
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (c, i) => Divider(height: 1, color: theme.dividerTheme.color ?? Colors.white10),
              itemBuilder: (c, i) {
                final item = list[i];
                final bool showDateHeader = i == 0 || list[i-1]['date'] != item['date'];
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDateHeader)
                       Container(
                         width: double.infinity,
                         padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                         color: theme.colorScheme.onSurface.withOpacity(0.03),
                         child: Text(
                           item['date'] == today ? "DZISIAJ" : (item['date'] == tomorrow ? "JUTRO" : item['date']),
                           style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: theme.colorScheme.primary.withOpacity(0.5), letterSpacing: 1),
                         ),
                       ),
                    _assignmentRow(item, isMobile),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _tabBtnSmall(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.blue.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? Colors.blue.withOpacity(0.5) : Colors.white10),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.blue : Colors.grey, fontSize: 10, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _assignmentRow(Map<String, dynamic> a, bool isMobile) {
    final theme = Theme.of(context);
    final status = a['status'] ?? 'PENDING';
    Color statusColor = Colors.orange;
    String statusLabel = "OCZEKUJE";
    IconData statusIcon = Icons.hourglass_empty_rounded;

    if (status == 'ACCEPTED') {
      statusColor = Colors.green;
      statusLabel = "PRZYJĘTE";
      statusIcon = Icons.check_circle_rounded;
    } else if (status == 'REJECTED') {
      statusColor = Colors.red;
      statusLabel = "ODRZUCONE";
      statusIcon = Icons.cancel_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.onSurface.withOpacity(0.05),
            child: Text(a['empName']?.substring(0, 1).toUpperCase() ?? "?", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a['empName'] ?? "Nieznany", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(a['orderName'] ?? "Brak budowy", style: TextStyle(color: theme.colorScheme.primary.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (!isMobile) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 12),
                  const SizedBox(width: 6),
                  Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
              onPressed: () => _confirmDeleteAssignment(a),
            ),
          ] else
            Icon(statusIcon, color: statusColor, size: 16),
        ],
      ),
    );
  }

  void _confirmDeleteAssignment(Map<String, dynamic> a) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("USUŃ ZADANIE?"),
        content: Text("Czy na pewno chcesz usunąć zadanie dla: ${a['empName']}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANULUJ")),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('assignments').doc(a['id']).delete();
              if (mounted) Navigator.pop(ctx);
            }, 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("USUŃ")
          ),
        ],
      ),
    );
  }

  Future<void> _loadCrews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCrews = prefs.getStringList('job_groups');
      if (savedCrews != null && savedCrews.isNotEmpty) {
        setState(() => _crews = savedCrews);
      }
    } catch (_) {}
  }

  void _showAddAssignmentDialog() {
    List<String> selectedEmpEmails = [];
    List<String> selectedCrews = [];
    String? selectedOrderName;
    DateTime assignmentDate = DateTime.now();
    final noteCtrl = TextEditingController();
    bool isSaving = false;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Połącz ekipy z bazy pracowników z listą domyślną
    final Set<String> crewOptionsSet = _allEmployees
      .where((e) => e['group'] != null && e['group'].toString().isNotEmpty)
      .map((e) => e['group'].toString().trim())
      .toSet();
    crewOptionsSet.addAll(_crews.map((c) => c.trim()));
    
    final List<String> crewOptions = crewOptionsSet.toList()..sort();

    showEsModal(
      context,
      title: "PRZYPISZ PRACĘ (GRUPOWO)",
      content: StatefulBuilder(
        builder: (ctx, setDS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("DATA ZADANIA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(context: ctx, initialDate: assignmentDate, firstDate: DateTime(2024), lastDate: DateTime(2030));
                    if (picked != null) setDS(() => assignmentDate = picked);
                  }, 
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text(DateFormat('dd.MM.yyyy').format(assignmentDate), style: const TextStyle(fontWeight: FontWeight.bold))
                )
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            const Text("WYBIERZ EKIPY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...selectedCrews.map((c) => Chip(
                  backgroundColor: Colors.orange.withOpacity(0.1),
                  label: Text(c, style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
                  onDeleted: () => setDS(() => selectedCrews.remove(c)),
                )),
                ActionChip(
                  label: const Text("DODAJ EKIPĘ", style: TextStyle(fontSize: 10)),
                  avatar: const Icon(Icons.add, size: 14),
                  onPressed: () async {
                    final picked = await _showMultiStringPicker(ctx, "WYBIERZ EKIPY", crewOptions, selectedCrews);
                    if (picked != null) setDS(() => selectedCrews = picked);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text("WYBIERZ DODATKOWYCH PRACOWNIKÓW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...selectedEmpEmails.map((e) => Chip(
                  backgroundColor: Colors.blue.withOpacity(0.1),
                  label: Text(_getShortEmpName(e), style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                  onDeleted: () => setDS(() => selectedEmpEmails.remove(e)),
                )),
                ActionChip(
                  label: const Text("DODAJ OSÓB", style: TextStyle(fontSize: 10)),
                  avatar: const Icon(Icons.person_add, size: 14),
                  onPressed: () async {
                    final allEmpEmails = _allEmployees.where((e) => e['isActive'] == true).map((e) => (e['email'] ?? e['id']).toString()).toList();
                    final picked = await _showMultiStringPicker(ctx, "WYBIERZ PRACOWNIKÓW", allEmpEmails, selectedEmpEmails, isEmails: true);
                    if (picked != null) setDS(() => selectedEmpEmails = picked);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text("WYBIERZ BUDOWĘ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedOrderName,
              isExpanded: true,
              dropdownColor: const Color(0xFF001A2C),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
              items: _allOrders.where((o) => o['status'] != 'ZAKOŃCZONO').map<DropdownMenuItem<String>>((o) {
                final String name = (o['name'] ?? "Bez nazwy").toString();
                return DropdownMenuItem<String>(value: name, child: Text(name));
              }).toList(),
              onChanged: (v) => setDS(() => selectedOrderName = v),
            ),
            const SizedBox(height: 20),
            const Text("UWAGI (OPCJONALNIE)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
              decoration: InputDecoration(
                border: const OutlineInputBorder(), 
                hintText: "Np. Spotkanie o 7:00", 
                hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2)),
                fillColor: theme.colorScheme.onSurface.withOpacity(0.03),
                filled: true,
              ),
            ),
            const SizedBox(height: 24),
            if (isSaving)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (selectedEmpEmails.isEmpty && selectedCrews.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Wybierz przynajmniej jedną osobę lub ekipę!")));
                      return;
                    }
                    if (selectedOrderName == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Wybierz budowę!")));
                      return;
                    }
                    setDS(() => isSaving = true);
                    
                    try {
                      // Zbierz wszystkich unikalnych pracowników
                      Set<String> finalEmails = Set<String>.from(selectedEmpEmails);
                      for (var crew in selectedCrews) {
                        final members = _allEmployees.where((e) => e['group']?.toString().trim() == crew.trim() && e['isActive'] == true);
                        for (var m in members) {
                          finalEmails.add((m['email'] ?? m['id']).toString());
                        }
                      }

                      if (finalEmails.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Nie znaleziono aktywnych pracowników w wybranych ekipach!")));
                        setDS(() => isSaving = false);
                        return;
                      }

                      final String dateStr = DateFormat('yyyy-MM-dd').format(assignmentDate);
                      WriteBatch batch = FirebaseFirestore.instance.batch();
                      
                      for (var email in finalEmails) {
                        final emp = _allEmployees.firstWhere((e) => (e['email'] ?? e['id']) == email, orElse: () => {});
                        if (emp.isEmpty) continue;
                        
                        final empName = "${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}".trim();
                        final String docId = "${DateTime.now().millisecondsSinceEpoch}_$email";
                        
                        batch.set(FirebaseFirestore.instance.collection('assignments').doc(docId), {
                          'id': docId,
                          'empEmail': email,
                          'empName': empName.isEmpty ? email : empName,
                          'orderName': selectedOrderName,
                          'note': noteCtrl.text.trim(),
                          'date': dateStr,
                          'status': 'PENDING',
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                      }
                      
                      await batch.commit();
                      if (ctx.mounted) Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Rozdysponowano zadania dla ${finalEmails.length} osób."), backgroundColor: Colors.green));
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Błąd zapisu: $e"), backgroundColor: Colors.red));
                        setDS(() => isSaving = false);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007BFF), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text("ZAPISZ I ROZDYSPONUJ", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<List<String>?> _showMultiStringPicker(BuildContext context, String title, List<String> options, List<String> initial, {bool isEmails = false}) async {
    List<String> selected = List<String>.from(initial);
    String filter = "";
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final filteredOptions = options.where((o) {
            final label = isEmails ? _getEmpFullName(o) : o;
            return label.toLowerCase().contains(filter.toLowerCase()) || o.toLowerCase().contains(filter.toLowerCase());
          }).toList();

          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setS(() => filter = v),
                  decoration: InputDecoration(
                    hintText: "Szukaj...",
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredOptions.length,
                itemBuilder: (c, i) {
                  final opt = filteredOptions[i];
                  final label = isEmails ? _getEmpFullName(opt) : opt;
                  return CheckboxListTile(
                    title: Text(label, style: const TextStyle(fontSize: 13)),
                    subtitle: isEmails ? Text(opt, style: const TextStyle(fontSize: 10)) : null,
                    value: selected.contains(opt),
                    onChanged: (v) {
                      setS(() {
                        if (v == true) selected.add(opt); else selected.remove(opt);
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANULUJ")),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text("ZATWIERDŹ")),
            ],
          );
        }
      ),
    );
  }

  Widget _buildTodayInCompanyPanel() {
    return _dashboardPanel(
      title: "DZISIAJ W FIRMIE",
      icon: Icons.today_rounded,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _todayInfoRow("Obecnych", "$_employeesAtWorkToday osób", Icons.people_alt_rounded, Colors.blue, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen(userEmail: widget.userEmail, currentUserEmail: widget.userEmail, isAdminView: true)))),
            _todayInfoRow("Aktywne zlecenia", "$_activeOrdersCount", Icons.assignment_rounded, Colors.indigo, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))),
            _todayInfoRow("Nowe problemy", "$_openIssuesCount", Icons.report_problem_rounded, Colors.red, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssuesScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))),
          ],
        ),
      ),
    );
  }

  Widget _todayInfoRow(String label, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 12), Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)), const Spacer(), Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900))])));
  }

  Widget _buildUrgentMattersPanel() {
    final urgentIssues = _allIssues.where((i) => i['status'] != 'ROZWIĄZANO' && i['status'] != 'ZAMKNIĘTY').toList();
    
    final noCrewOrders = _allOrders.where((o) {
      if (o['status'] == 'ZAKOŃCZONO') return false;
      final crews = o['assigned_crews'] as List? ?? (o['assigned_crew'] != null ? [o['assigned_crew']] : []);
      return crews.isEmpty || (crews.length == 1 && crews.first.toString().isEmpty);
    }).toList();
    
    // Zlecenia po terminie
    final overdueOrders = _allOrders.where((o) {
      if (o['status'] == 'ZAKOŃCZONO') return false;
      if (o['endDate'] == null || o['endDate'].toString().isEmpty) return false;
      try {
        final end = DateFormat('dd.MM.yyyy').parse(o['endDate']);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        return end.isBefore(today);
      } catch (_) { return false; }
    }).toList();

    return _dashboardPanel(
      title: "WYMAGA UWAGI",
      icon: Icons.notification_important_rounded,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (urgentIssues.isEmpty && noCrewOrders.isEmpty && overdueOrders.isEmpty && _attendanceGapsCount == 0)
              const Center(child: Text("Wszystko pod kontrolą 🟢", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)))
            else ...[
              if (urgentIssues.isNotEmpty) ...urgentIssues.take(3).map((i) => _urgentItem("PROBLEM: ${i['description']}", Colors.red, 
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssuesScreen(
                  isAdmin: _isAdmin, 
                  currentUserEmail: widget.userEmail, 
                  orderId: i['orderId'], 
                  initialIssueId: i['id']
                ))))),
              
              if (overdueOrders.isNotEmpty) ...overdueOrders.take(3).map((o) => _urgentItem("PO TERMINIE: ${o['name']}", Colors.redAccent, 
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailView(order: o, isAdmin: _isAdmin, currentUserEmail: widget.userEmail, getName: _getEmpFullName, saveOrders: () async {}, saveTools: () async {}, toolsDB: _allTools, canEdit: true, tools: _allTools, clients: _allClients, prefs: _prefs))))),
              
              if (noCrewOrders.isNotEmpty) ...noCrewOrders.take(3).map((o) => _urgentItem("BRAK EKIPY: ${o['name']}", Colors.orange, 
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailView(order: o, isAdmin: _isAdmin, currentUserEmail: widget.userEmail, getName: _getEmpFullName, saveOrders: () async {}, saveTools: () async {}, toolsDB: _allTools, canEdit: true, tools: _allTools, clients: _allClients, prefs: _prefs))))),
              
              if (_attendanceGapsCount > 0) _urgentItem("BRAKI W OBECNOŚCIACH ($_attendanceGapsCount osób)", Colors.blueGrey, 
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen(userEmail: widget.userEmail, currentUserEmail: widget.userEmail, isAdminView: true)))),
              
              if (urgentIssues.length > 3 || overdueOrders.length > 3 || noCrewOrders.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text("I więcej... Sprawdź moduły szczegółowe.", style: TextStyle(fontSize: 10, color: Colors.grey.withOpacity(0.6))),
                )
            ]
          ],
        ),
      ),
    );
  }

  Widget _urgentItem(String text, Color color, {VoidCallback? onTap}) {
    return InkWell(onTap: onTap, child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.2))), child: Row(children: [Icon(Icons.error_outline_rounded, color: color, size: 16), const SizedBox(width: 12), Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12))])));
  }

  Widget _dashboardPanel({required String title, required IconData icon, required Widget child, VoidCallback? onAction, IconData? actionIcon}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(color: theme.cardTheme.color, borderRadius: BorderRadius.circular(24), border: Border.all(color: theme.dividerTheme.color ?? Colors.white10), boxShadow: theme.brightness == Brightness.dark ? null : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24), 
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary), 
                const SizedBox(width: 12), 
                Expanded(child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5, color: theme.colorScheme.onSurface))),
                if (onAction != null) IconButton(icon: Icon(actionIcon ?? Icons.open_in_new_rounded, size: 18, color: Colors.blue), onPressed: onAction),
              ]
            )
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }

  Widget _buildSidebar({bool isMobile = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final groups = _getSidebarGroups();
    
    return Container(
      width: 260,
      color: isDark ? theme.colorScheme.surface : const Color(0xFF001A2C),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [const Icon(Icons.bolt, color: Color(0xFF007BFF), size: 32), const SizedBox(width: 10), Text("ES CRM", style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -1))]),
                Text("CENTRUM DOWODZENIA", style: GoogleFonts.montserrat(color: const Color(0xFF007BFF).withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5))
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero, 
              children: [
                for (var group in groups) ...[
                  _sidebarSectionHeader(group['title']),
                  ...(group['items'] as List).map((m) => _sidebarItem(m['icon'], m['title'], m['active'] ?? false, onTap: m['onTap'])).toList(),
                  const SizedBox(height: 16),
                ]
              ]
            )
          ),
          const Divider(color: Colors.white10),
          _sidebarItem(Icons.settings_rounded, "Ustawienia", false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(isAdmin: _isAdmin, userEmail: widget.userEmail)))),
          _sidebarItem(Icons.logout_rounded, "Wyloguj się", false, onTap: _handleLogout),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sidebarSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: const Color(0xFF007BFF).withOpacity(0.6),
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, bool active, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color inactiveColor = Colors.white.withOpacity(0.4);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: active ? const Color(0xFF007BFF).withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12), border: active ? Border.all(color: const Color(0xFF007BFF).withOpacity(0.3)) : null),
        child: Row(children: [Icon(icon, color: active ? const Color(0xFF007BFF) : inactiveColor, size: 20), const SizedBox(width: 16), Text(label, style: GoogleFonts.montserrat(color: active ? Colors.white : inactiveColor, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w600))]),
      ),
    );
  }

  List<Map<String, dynamic>> _getSidebarGroups() {
    bool hasP(String id) {
      if (_isAdmin) return true;
      return _userPermissions[id] == true;
    }

    final List<Map<String, dynamic>> groups = [];

    // GRUPA 1: ADMINISTRACJA
    groups.add({
      'title': 'Administracja',
      'items': [
        {'id': 'dashboard', 'title': 'Pulpit Sterowniczy', 'icon': Icons.psychology_rounded, 'onTap': null, 'active': true},
        {'id': 'modules_grid', 'title': 'Widok kafelkowy', 'icon': Icons.grid_view_rounded, 'onTap': () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(userEmail: widget.userEmail, ignoreRedirect: true)))},
        if (hasP('access_hr_pulpit')) {'id': 'hr_pulpit', 'title': 'Pulpit HR / Kadry', 'icon': Icons.admin_panel_settings_rounded, 'onTap': () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HrDashboardScreen(userEmail: widget.userEmail)))},
        if (hasP('access_procurement_pulpit')) {'id': 'procurement_pulpit', 'title': 'Pulpit Zaopatrzenia', 'icon': Icons.shopping_cart_checkout_rounded, 'onTap': () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProcurementDashboardScreen(userEmail: widget.userEmail)))},
        if (hasP('kadry')) {'id': 'kadry', 'title': 'Kadry i Pracownicy', 'icon': Icons.people_alt_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()))},
        if (hasP('clients')) {'id': 'clients', 'title': 'Baza Klientów', 'icon': Icons.group_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientsScreen(isAdmin: _isAdmin)))},
        if (_isAdmin) {'id': 'leads', 'title': 'Zapytania (Leads)', 'icon': Icons.contact_page_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientLeadsScreen()))},
      ],
    });

    // GRUPA 2: REALIZACJA I OPERACJE
    groups.add({
      'title': 'Operacje i Budowy',
      'items': [
        if (hasP('orders')) {'id': 'orders', 'title': 'Aktywne Zlecenia', 'icon': Icons.assignment_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail, userPermissions: _userPermissions)))},
        {'id': 'attendance', 'title': 'Lista obecności', 'icon': Icons.calendar_today_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen(userEmail: widget.userEmail, currentUserEmail: widget.userEmail)))},
        if (hasP('orders')) {'id': 'issues', 'title': 'Problemy i Uwagi', 'icon': Icons.report_problem_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssuesScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))},
        if (hasP('expenses')) {'id': 'expenses', 'title': 'Koszty i Wydatki', 'icon': Icons.receipt_long_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExpensesScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))},
      ],
    });

    // GRUPA 3: ZASOBY I LOGISTYKA
    groups.add({
      'title': 'Logistyka i Zasoby',
      'items': [
        if (hasP('storage')) {'id': 'storage', 'title': 'Magazyn główny', 'icon': Icons.inventory_2_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => StorageScreen(isAdmin: _isAdmin, userEmail: widget.userEmail, userGroup: "")))},
        if (hasP('tools')) {'id': 'tools', 'title': 'Sprzęt i Narzędzia', 'icon': Icons.construction_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ToolsScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))},
        if (hasP('tools_map')) {'id': 'tools_map', 'title': 'Mapa sprzętu GPS', 'icon': Icons.map_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ToolsMapScreen()))},
        if (hasP('fleet')) {'id': 'fleet', 'title': 'Flota pojazdów', 'icon': Icons.local_shipping_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => FleetScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))},
      ],
    });

    // GRUPA 4: DOKUMENTACJA I STANDARDY
    groups.add({
      'title': 'Standardy i Dokumenty',
      'items': [
        if (hasP('knowledge_base')) {'id': 'knowledge_base', 'title': 'Standard Firmowy', 'icon': Icons.auto_stories_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => KnowledgeBaseScreen(isAdmin: _isAdmin)))},
        if (hasP('protocols')) {'id': 'protocols', 'title': 'Protokoły i Odbiory', 'icon': Icons.fact_check_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProtocolsScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))},
        if (hasP('estimations')) {'id': 'estimations', 'title': 'Wyceny i Oferty', 'icon': Icons.calculate_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => EstimationsScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))},
        if (hasP('important_files')) {'id': 'important_files', 'title': 'Pliki firmowe', 'icon': Icons.file_present_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImportantFilesScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))},
        if (hasP('installation_docs')) {'id': 'installation_docs', 'title': 'Zdjęcia instalacji', 'icon': Icons.photo_library_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InstallationDocumentationScreen()))},
      ],
    });

    // GRUPA 5: NARZĘDZIA SPECJALISTYCZNE
    groups.add({
      'title': 'Narzędzia Elektryka',
      'items': [
        if (hasP('lan_labels')) {'id': 'lan_labels', 'title': 'Opis sieci LAN', 'icon': Icons.lan_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => LanLabelsScreen()))},
        if (hasP('db_labels')) {'id': 'db_labels', 'title': 'Opisy Rozdzielnic', 'icon': Icons.label_important_outline, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => DbLabelsScreen()))},
        if (hasP('schematic')) {'id': 'schematic', 'title': 'Kreator Schematów', 'icon': Icons.schema_outlined, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => SchematicCreatorScreen()))},
        if (hasP('visualizer')) {'id': 'visualizer', 'title': 'Wizualizacja Rozdz.', 'icon': Icons.view_quilt_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SwitchboardVisualizerScreen()))},
        if (hasP('cable_calc')) {'id': 'cable_calc', 'title': 'Kalkulator Kabli', 'icon': Icons.electrical_services, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => CableCalculatorScreen()))},
        if (hasP('nfc')) {'id': 'nfc', 'title': 'Obsługa NFC', 'icon': Icons.nfc, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => NfcTagScreen()))},
        if (hasP('label_printer')) {'id': 'label_printer', 'title': 'Drukarka etykiet', 'icon': Icons.print_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabelDesignerScreen()))},
        if (hasP('flashlight')) {'id': 'flashlight', 'title': 'Latarka', 'icon': Icons.flashlight_on, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => FlashlightScreen()))},
        if (hasP('lux_meter')) {'id': 'lux_meter', 'title': 'Luksomierz', 'icon': Icons.light_mode, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => LuxMeterScreen()))},
      ],
    });

    // GRUPA 6: KOMUNIKACJA
    groups.add({
      'title': 'Komunikacja',
      'items': [
        if (hasP('chat')) {'id': 'chat', 'title': 'Komunikator firmowy', 'icon': Icons.forum_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(currentUserEmail: widget.userEmail, displayName: _displayName)))},
        if (hasP('messages')) {'id': 'messages', 'title': 'Komunikaty / Ogłoszenia', 'icon': Icons.notifications_active_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))},
        if (hasP('helpful_apps')) {'id': 'helpful_apps', 'title': 'Przydatne linki', 'icon': Icons.apps_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpfulAppsScreen()))},
      ],
    });

    return groups;
  }
}

class _AnalysisEntry {
  final String label;
  final double value;
  final String? email;
  _AnalysisEntry({required this.label, required this.value, this.email});
}
