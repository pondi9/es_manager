import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'services/attendance_service.dart';
import 'core/app_theme.dart';
import 'core/app_constants.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';
import 'package:flutter/services.dart';
import 'services/cloud_sync_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/theme_switcher.dart';
import 'dashboard_screen.dart';
import 'chat_screen.dart';
import 'orders_screen.dart';
import 'settings_screen.dart';
import 'admin_panel_screen.dart';
import 'notifications_screen.dart';
import 'tools/switchboard_visualizer_screen.dart';
import 'tools/label_designer_screen.dart';
import 'tools/installation_documentation_screen.dart';
import 'helpful_apps_screen.dart';
import 'storage_screen.dart';
import 'fleet_screen.dart';
import 'expenses_screen.dart';
import 'clients_screen.dart';
import 'tools_screen.dart';
import 'protocols_screen.dart';
import 'knowledge_base_screen.dart';
import 'issues_screen.dart';
import 'important_files_screen.dart'; 
import 'estimations_screen.dart';
import 'tools_map_screen.dart';
import 'tools/lan_labels_screen.dart';
import 'tools/flashlight_screen.dart';
import 'tools/lux_meter_screen.dart';
import 'tools/cable_calculator_screen.dart';
import 'tools/db_labels_screen.dart';
import 'tools/schematic_creator_screen.dart';
import 'tools/nfc_tag_screen.dart';
import 'client_leads_screen.dart';
import 'admin_command_center_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final String userEmail; // Email osoby, której listę oglądamy
  final String? currentUserEmail; // Email zalogowanego użytkownika
  final bool isAdminView;

  const AttendanceScreen({
    super.key, 
    required this.userEmail, 
    this.currentUserEmail,
    this.isAdminView = false
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceService _service = AttendanceService();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  Map<String, dynamic> _data = {};
  List<dynamic> _orders = [];
  String _employeeDisplayName = "";
  bool _loading = true;
  bool _showEditPanel = false;
  bool _isAdmin = false;
  Map<String, dynamic> _userPermissions = {};
  String _effectiveUserEmail = "";
  String _viewerEmail = "";
  bool _viewerIsAdmin = false;

  final _inController = TextEditingController(text: "07:00");
  final _outController = TextEditingController(text: "15:00");
  final _notesController = TextEditingController();
  String? _selectedOrder;
  String _selectedType = 'PRACA';

  final SignatureController _dailySignatureController = SignatureController(
    penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );
  final SignatureController _monthlySignatureController = SignatureController(
    penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _initData();
  }

  @override
  void dispose() {
    _inController.dispose();
    _outController.dispose();
    _notesController.dispose();
    _dailySignatureController.dispose();
    _monthlySignatureController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();

    // Kto ogląda (zalogowany użytkownik)
    _viewerEmail = (widget.currentUserEmail ?? widget.userEmail).trim().toLowerCase();
    _viewerIsAdmin = _viewerEmail == AppConstants.adminEmail;

    // Kogo oglądamy (pracownik)
    final targetEmployeeEmail = widget.userEmail.trim().toLowerCase();
    _isAdmin = targetEmployeeEmail == AppConstants.adminEmail; // Flaga dla logiki widoku

    // POBIERZ UPRAWNIENIA PRACOWNIKA (DLA MENU BOCZNEGO)
    try {
      final empSnap = await FirebaseFirestore.instance.collection('employees').doc(targetEmployeeEmail).get();
      if (empSnap.exists) {
        final d = empSnap.data();
        if (d != null) {
          _userPermissions = d['permissions'] ?? {};
          String fn = d['firstName'] ?? "";
          String ln = d['lastName'] ?? "";
          if (fn.isNotEmpty || ln.isNotEmpty) {
            _employeeDisplayName = "$fn $ln".trim();
          }
        }
      }
    } catch (_) {}

    if (_employeeDisplayName.isEmpty) {
      final String? empData = prefs.getString('user_permissions');
      if (empData != null) {
        try {
          List<dynamic> emps = json.decode(empData);
          final me = emps.firstWhere((e) => e['email'].toString().toLowerCase() == widget.userEmail.toLowerCase(), orElse: () => null);
          if (me != null) _employeeDisplayName = "${me['firstName'] ?? ''} ${me['lastName'] ?? ''}".trim();
        } catch (_) {}
      }
    }
    
    if (_employeeDisplayName.isEmpty) _employeeDisplayName = widget.userEmail;

    try {
      await CloudSyncService().downloadOrders().timeout(const Duration(seconds: 5));
    } catch (_) {}

    final String? ordersJson = prefs.getString('company_orders_v2');
    if (ordersJson != null) {
      try {
        final decoded = json.decode(ordersJson);
        if (decoded is List) _orders = decoded;
      } catch (_) {}
    }

    await _service.syncWithCloud(widget.userEmail);
    _data = await _service.getLocalData(widget.userEmail);
    
    if (mounted) {
      setState(() => _loading = false);
      _loadDayData(_selectedDay!);
      _loadMonthlyApprovalData();
    }
  }

  void _loadDayData(DateTime day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    final dayData = _data[key] ?? {};
    setState(() {
      String inT = dayData['in'] ?? "07:00";
      String outT = dayData['out'] ?? "15:00";
      _inController.text = (inT == "-" || inT.isEmpty) ? "07:00" : inT;
      _outController.text = (outT == "-" || outT.isEmpty) ? "15:00" : outT;
      _selectedType = dayData['type'] ?? 'PRACA';
      
      final orderName = dayData['orderName'];
      bool found = false;
      for (var o in _orders) {
        if (o['name']?.toString().trim() == orderName?.toString().trim()) { found = true; break; }
      }
      _selectedOrder = found ? orderName : null;
      _dailySignatureController.clear();
      _notesController.text = dayData['notes'] ?? "";
    });
  }

  void _loadMonthlyApprovalData() {
    final monthKey = DateFormat('yyyy-MM').format(_focusedDay);
    final approvalData = _data['approval_$monthKey'] ?? {};
    // Note: We don't overwrite _notesController here to avoid losing current typing if editing daily notes
    _monthlySignatureController.clear();
  }

  Future<void> _saveDay() async {
    if (_selectedType == 'PRACA' && (_selectedOrder == null || _selectedOrder!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("WYBIERZ BUDOWĘ!"), backgroundColor: Colors.redAccent));
      return;
    }
    
    final key = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    Uint8List? sigBytes = await _dailySignatureController.toPngBytes();
    final dayData = {
      'in': _selectedType == 'PRACA' ? _inController.text : "-",
      'out': _selectedType == 'PRACA' ? _outController.text : "-",
      'orderName': _selectedType == 'PRACA' ? _selectedOrder : _selectedType,
      'type': _selectedType,
      'notes': _notesController.text,
      'signature': (sigBytes != null && _dailySignatureController.isNotEmpty) ? base64Encode(sigBytes) : _data[key]?['signature'],
      'lastModifiedBy': _viewerEmail,
      'lastModifiedAt': DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
    };
    setState(() => _loading = true);
    await _service.updateDay(widget.userEmail, key, dayData);
    _data = await _service.getLocalData(widget.userEmail);
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ZAPISANO DZIEŃ")));
    }
  }

  Future<void> _saveMonthlyApproval() async {
    final monthKey = DateFormat('yyyy-MM').format(_focusedDay);
    Uint8List? sigBytes = await _monthlySignatureController.toPngBytes();
    final approvalData = {
      'notes': _notesController.text,
      'signature': (sigBytes != null && _monthlySignatureController.isNotEmpty) ? base64Encode(sigBytes) : _data['approval_$monthKey']?['signature'],
      'date': DateTime.now().toIso8601String(),
      'approvedBy': _viewerEmail,
    };
    setState(() => _loading = true);
    await _service.updateDay(widget.userEmail, 'approval_$monthKey', approvalData);
    _data = await _service.getLocalData(widget.userEmail);
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("MIESIĄC ZATWIERDZONY")));
    }
  }

  double _calculateMonthlyTotal() {
    double total = 0;
    final prefix = DateFormat('yyyy-MM').format(_focusedDay);
    _data.forEach((key, value) {
      if (key.startsWith(prefix) && !key.startsWith('approval')) {
        if (value['type'] == 'URLOP') total += 8.0;
        else if (value['type'] == 'PRACA') total += _service.calculateHours(value['in'], value['out']);
      }
    });
    return total;
  }

  int _calculateWorkDays() {
    int count = 0;
    final prefix = DateFormat('yyyy-MM').format(_focusedDay);
    _data.forEach((key, value) {
      if (key.startsWith(prefix) && !key.startsWith('approval')) {
        if (value['type'] == 'PRACA' && _service.calculateHours(value['in'], value['out']) > 0) {
          count++;
        }
      }
    });
    return count;
  }

  int _calculateAbsences() {
    int count = 0;
    final prefix = DateFormat('yyyy-MM').format(_focusedDay);
    _data.forEach((key, value) {
      if (key.startsWith(prefix) && !key.startsWith('approval')) {
        if (value['type'] == 'CHOROBA' || value['type'] == 'INNE') {
          count++;
        }
      }
    });
    return count;
  }

  int _calculateHolidays(String periodPrefix) {
    int count = 0;
    _data.forEach((key, value) {
      if (key.startsWith(periodPrefix) && !key.startsWith('approval') && value['type'] == 'URLOP') count++;
    });
    return count;
  }

  List<MapEntry<String, dynamic>> _getSortedMonthDays() {
    final prefix = DateFormat('yyyy-MM').format(_focusedDay);
    var list = _data.entries.where((e) => e.key.startsWith(prefix) && !e.key.startsWith('approval')).toList();
    list.sort((a, b) => a.key.compareTo(b.key));
    return list;
  }

  Future<void> _generatePdf(bool showPreviewOnly) async {
    final pdf = pw.Document();
    final ttf = await PdfGoogleFonts.robotoRegular();
    final ttfBold = await PdfGoogleFonts.robotoBold();
    final logoBytes = (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
    
    final int year = _focusedDay.year;
    final int month = _focusedDay.month;
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    
    final polishMonths = ["STYCZEŃ", "LUTY", "MARZEC", "KWIECIEŃ", "MAJ", "CZERWIEC", "LIPIEC", "SIERPIEŃ", "WRZESIEŃ", "PAŹDZIERNIK", "LISTOPAD", "GRUDZIEŃ"];
    final polishDays = ["nd", "pn", "wt", "śr", "cz", "pt", "so"];
    final monthLabel = "${polishMonths[month - 1]} $year";
    final monthKey = DateFormat('yyyy-MM').format(_focusedDay);
    final approval = _data['approval_$monthKey'] ?? {};
    final mainSignature = approval['signature'] != null ? base64Decode(approval['signature']) : null;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20), 
        theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text("ARKUSZ OBECNOŚCI", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Electric Systems CRM", style: const pw.TextStyle(fontSize: 8)),
                ]),
                pw.Image(pw.MemoryImage(logoBytes), height: 35),
              ]),
              pw.SizedBox(height: 10),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("Pracownik: $_employeeDisplayName", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.Text("Miesiąc: $monthLabel", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ]),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.2),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(2.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                    children: [
                      _pdfCell('Dzień', isHeader: true, fontSize: 8, verticalPadding: 4),
                      _pdfCell('Wejście', isHeader: true, fontSize: 8, verticalPadding: 4),
                      _pdfCell('Wyjście', isHeader: true, fontSize: 8, verticalPadding: 4),
                      _pdfCell('Suma', isHeader: true, fontSize: 8, verticalPadding: 4),
                      _pdfCell('Podpis / Typ', isHeader: true, fontSize: 8, verticalPadding: 4),
                    ],
                  ),
                  ...List.generate(daysInMonth, (index) {
                    final d = index + 1;
                    final dt = DateTime(year, month, d);
                    final dName = polishDays[dt.weekday % 7];
                    final dKey = "$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}";
                    final dData = _data[dKey] ?? {};
                    final h = dData['type'] == 'URLOP' ? 8.0 : _service.calculateHours(dData['in'], dData['out']);
                    final sigD = (dData['signature'] != null && dData['signature'].toString().isNotEmpty) ? base64Decode(dData['signature']) : null;
                    
                    bool isW = dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
                    PdfColor bg = isW ? PdfColors.grey100 : PdfColors.white;
                    if (dData['type'] == 'URLOP') bg = PdfColors.blue50;
                    if (dData['type'] == 'ŚWIĘTO') bg = PdfColors.red50;

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: bg),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                          child: pw.Text("$d.$month ($dName)", style: pw.TextStyle(fontSize: 8, fontWeight: isW ? pw.FontWeight.bold : pw.FontWeight.normal)),
                        ),
                        _pdfCell(dData['in'] ?? '-', fontSize: 8, verticalPadding: 3),
                        _pdfCell(dData['out'] ?? '-', fontSize: 8, verticalPadding: 3),
                        _pdfCell(h > 0 ? "${h.toStringAsFixed(1)}h" : "-", fontSize: 8, verticalPadding: 3),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(1),
                          child: (dData['type'] != null && dData['type'] != 'PRACA') 
                            ? pw.Center(child: pw.Text(dData['type'], style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)))
                            : (sigD != null ? pw.Center(child: pw.Image(pw.MemoryImage(sigD), height: 16)) : pw.SizedBox(height: 16)),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text("SUMA GODZIN W MIESIĄCU: ${_calculateMonthlyTotal().toStringAsFixed(1)} h", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                if (mainSignature != null) pw.Column(children: [
                  pw.Container(width: 120, height: 40, decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey200)), child: pw.Image(pw.MemoryImage(mainSignature), fit: pw.BoxFit.contain)),
                  pw.Text("PODPIS ZATWIERDZAJĄCY", style: const pw.TextStyle(fontSize: 6)),
                ]),
              ]),
            ],
          );
        },
      ),
    );

    if (showPreviewOnly) {
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(appBar: AppBar(title: const Text("PODGLĄD RAPORTU")), body: PdfPreview(build: (format) => pdf.save(), canChangePageFormat: false))));
    } else {
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    }
  }

  pw.Widget _pdfCell(String text, {bool isHeader = false, double fontSize = 9, double verticalPadding = 5}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 3),
      child: pw.Center(
        child: pw.Text(
          text, 
          style: pw.TextStyle(
            color: isHeader ? PdfColors.white : PdfColors.black, 
            fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal, 
            fontSize: fontSize
          )
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool isDesktop = width > 1100;
    final theme = Theme.of(context);

    if (_loading) return Scaffold(backgroundColor: theme.scaffoldBackgroundColor, body: const Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: isDesktop ? null : Drawer(child: _buildSidebarMobile()),
      appBar: isDesktop ? null : AppBar(
        title: Text(widget.isAdminView ? "LOGI: $_employeeDisplayName" : "LISTA OBECNOŚCI"),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          const ThemeSwitcher(),
          IconButton(icon: const Icon(Icons.print_rounded), onPressed: () => _generatePdf(false)),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _initData),
        ],
      ),
      body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildSidebarMobile() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final modules = _getSidebarModules();

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: const Color(0xFF001A2C)),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt, color: Color(0xFF007BFF), size: 32),
                      const SizedBox(width: 10),
                      Text(
                        "ES CRM", 
                        style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -1)
                      )
                    ],
                  ),
                  Text(
                    "ZARZĄDZANIE CZASEM", 
                    style: GoogleFonts.montserrat(color: const Color(0xFF007BFF).withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)
                  )
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: modules.map((m) {
                bool active = m['active'] ?? false;
                return ListTile(
                  leading: Icon(m['icon'], color: active ? const Color(0xFF007BFF) : null),
                  title: Text(
                    m['title'], 
                    style: TextStyle(
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: active ? const Color(0xFF007BFF) : null
                    )
                  ),
                  onTap: () {
                    if (m['onTap'] != null) {
                      Navigator.pop(context); // Close drawer
                      m['onTap']();
                    } else {
                      Navigator.pop(context);
                    }
                  },
                );
              }).toList(),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: const Text("Ustawienia"),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(isAdmin: _isAdmin, userEmail: _effectiveUserEmail))),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getSidebarModules() {
    bool hasP(String id) {
      if (_isAdmin) return true; // Jeśli oglądany jest adminem
      return _userPermissions[id] == true;
    }

    final List<Map<String, dynamic>> modules = [
      if (_viewerIsAdmin) ...[
        {'id': 'dashboard', 'title': 'Pulpit', 'icon': Icons.dashboard_rounded, 'onTap': () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AdminCommandCenterScreen(userEmail: _viewerEmail))), 'active': false},
        {'id': 'modules_grid', 'title': 'Widok kafelkowy', 'icon': Icons.grid_view_rounded, 'onTap': () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(userEmail: _viewerEmail, ignoreRedirect: true)))},
      ] else ...[
        {'id': 'dashboard', 'title': 'Pulpit', 'icon': Icons.dashboard_rounded, 'onTap': () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(userEmail: _viewerEmail)))},
      ],
      {'id': 'attendance', 'title': 'Lista obecności', 'icon': Icons.calendar_today_rounded, 'onTap': null, 'active': true},
    ];

    if (hasP('orders')) {
      modules.add({'id': 'orders', 'title': 'Zlecenia', 'icon': Icons.assignment_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersScreen(isAdmin: _viewerIsAdmin, currentUserEmail: _viewerEmail, userPermissions: _userPermissions)))});
      modules.add({'id': 'issues', 'title': 'Problemy', 'icon': Icons.report_problem_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssuesScreen(isAdmin: _viewerIsAdmin, currentUserEmail: _viewerEmail)))});
    }
    if (hasP('chat')) modules.add({'id': 'chat', 'title': 'Komunikator', 'icon': Icons.forum_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(currentUserEmail: _viewerEmail, displayName: _viewerIsAdmin ? "ADMIN" : _employeeDisplayName)))});
    if (hasP('knowledge_base')) modules.add({'id': 'knowledge_base', 'title': 'Standard', 'icon': Icons.auto_stories_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => KnowledgeBaseScreen(isAdmin: _viewerIsAdmin)))});
    if (hasP('expenses')) modules.add({'id': 'expenses', 'title': 'Koszty', 'icon': Icons.receipt_long_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExpensesScreen(isAdmin: _viewerIsAdmin, currentUserEmail: _viewerEmail)))});
    if (hasP('messages')) modules.add({'id': 'messages', 'title': 'Komunikaty', 'icon': Icons.notifications_active_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(isAdmin: _viewerIsAdmin, currentUserEmail: _viewerEmail)))});
    if (hasP('tools')) modules.add({'id': 'tools', 'title': 'Sprzęt', 'icon': Icons.construction_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ToolsScreen(isAdmin: _viewerIsAdmin, currentUserEmail: _viewerEmail)))});
    if (hasP('lan_labels')) modules.add({'id': 'lan_labels', 'title': 'Opis LAN', 'icon': Icons.lan_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => LanLabelsScreen()))});
    if (hasP('fleet')) modules.add({'id': 'fleet', 'title': 'Flota', 'icon': Icons.local_shipping_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => FleetScreen(isAdmin: _viewerIsAdmin, currentUserEmail: _viewerEmail)))});
    if (hasP('clients')) modules.add({'id': 'clients', 'title': 'Klienci', 'icon': Icons.group_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientsScreen(isAdmin: _viewerIsAdmin)))});
    if (hasP('storage')) modules.add({'id': 'storage', 'title': 'Magazyn', 'icon': Icons.inventory_2_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => StorageScreen(isAdmin: _viewerIsAdmin, userEmail: _viewerEmail, userGroup: "")))});
    if (hasP('protocols')) modules.add({'id': 'protocols', 'title': 'Protokoły', 'icon': Icons.fact_check_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProtocolsScreen(isAdmin: _viewerIsAdmin, currentUserEmail: _viewerEmail)))});
    if (hasP('helpful_apps')) modules.add({'id': 'helpful_apps', 'title': 'Narzędzia', 'icon': Icons.apps_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpfulAppsScreen()) )});
    if (hasP('important_files')) modules.add({'id': 'important_files', 'title': 'Pliki', 'icon': Icons.file_present_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImportantFilesScreen(isAdmin: _viewerIsAdmin, currentUserEmail: _viewerEmail)))});
    if (hasP('estimations')) modules.add({'id': 'estimations', 'title': 'Wyceny', 'icon': Icons.calculate_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => EstimationsScreen(isAdmin: _viewerIsAdmin, currentUserEmail: _viewerEmail)))});
    
    // NARZĘDZIA DODATKOWE
    if (hasP('tools_map')) modules.add({'id': 'tools_map', 'title': 'Mapa sprzętu', 'icon': Icons.map_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ToolsMapScreen()))});
    if (hasP('flashlight')) modules.add({'id': 'flashlight', 'title': 'Latarka', 'icon': Icons.flashlight_on, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => FlashlightScreen()))});
    if (hasP('lux_meter')) modules.add({'id': 'lux_meter', 'title': 'Luksomierz', 'icon': Icons.light_mode, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => LuxMeterScreen()))});
    if (hasP('cable_calc')) modules.add({'id': 'cable_calc', 'title': 'Kable', 'icon': Icons.electrical_services, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => CableCalculatorScreen()))});
    if (hasP('db_labels')) modules.add({'id': 'db_labels', 'title': 'Opisy rozdz.', 'icon': Icons.label_important_outline, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => DbLabelsScreen()))});
    if (hasP('schematic')) modules.add({'id': 'schematic', 'title': 'Schematy', 'icon': Icons.schema_outlined, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => SchematicCreatorScreen()))});
    if (hasP('nfc')) modules.add({'id': 'nfc', 'title': 'NFC', 'icon': Icons.nfc, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => NfcTagScreen()))});
    if (hasP('visualizer')) modules.add({'id': 'visualizer', 'title': 'Wizualizacja', 'icon': Icons.view_quilt_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SwitchboardVisualizerScreen()))});
    if (hasP('label_printer')) modules.add({'id': 'label_printer', 'title': 'Drukarka', 'icon': Icons.print_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabelDesignerScreen()))});
    if (hasP('installation_docs')) modules.add({'id': 'installation_docs', 'title': 'Zdjęcia inst.', 'icon': Icons.photo_library_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InstallationDocumentationScreen()))});

    if (hasP('kadry')) modules.add({'id': 'kadry', 'title': 'Zarządzanie kadrami', 'icon': Icons.people_alt_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()))});
    if (_viewerIsAdmin) modules.add({'id': 'leads', 'title': 'Zapytania', 'icon': Icons.contact_page_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientLeadsScreen()))});
    
    if (hasP('kadry') || _viewerIsAdmin) modules.add({'id': 'settings', 'title': 'Ustawienia', 'icon': Icons.settings_rounded, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(isAdmin: _viewerIsAdmin, userEmail: _viewerEmail)))});

    return modules;
  }

  // --- DESKTOP LAYOUT ---

  Widget _buildDesktopLayout() {
    final theme = Theme.of(context);
    return Row(
      children: [
        _buildSidebarDesktop(),
        Expanded(
          child: Column(
            children: [
              _buildDesktopTopBar(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildStatsRowDesktop(),
                            const SizedBox(height: 32),
                            _buildCalendarCardDesktop(),
                            const SizedBox(height: 40),
                            _buildRecentEntriesDesktop(),
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                    if (_showEditPanel)
                      Container(
                        width: 380,
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          border: Border(left: BorderSide(color: theme.dividerTheme.color ?? Colors.white10))
                        ),
                        child: _buildEditPanelDesktop(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarDesktop() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final modules = _getSidebarModules();

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
                Row(
                  children: [
                    const Icon(Icons.bolt, color: Color(0xFF007BFF), size: 32),
                    const SizedBox(width: 10),
                    Text(
                      "ES CRM", 
                      style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -1)
                    )
                  ],
                ),
                Text(
                  "ZARZĄDZANIE CZASEM", 
                  style: GoogleFonts.montserrat(color: const Color(0xFF007BFF).withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)
                )
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: modules.map((m) {
                return _sidebarItemDesktop(m['icon'], m['title'], m['active'] ?? false, onTap: m['onTap']);
              }).toList(),
            ),
          ),
          _sidebarItemDesktop(Icons.settings_rounded, "Ustawienia", false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(isAdmin: _viewerIsAdmin, userEmail: _viewerEmail)))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sidebarItemDesktop(IconData icon, String label, bool active, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF007BFF).withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active ? Border.all(color: const Color(0xFF007BFF).withOpacity(0.3)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? const Color(0xFF007BFF) : const Color(0xFF4A6A8A), size: 20),
            const SizedBox(width: 16),
            Text(
              label, 
              style: GoogleFonts.montserrat(
                color: active ? Colors.white : const Color(0xFF4A6A8A), 
                fontSize: 13, 
                fontWeight: active ? FontWeight.w700 : FontWeight.w600
              )
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTopBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.white10))
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: theme.colorScheme.onSurface),
            onPressed: () => Navigator.pop(context),
            tooltip: "Wstecz",
          ),
          const SizedBox(width: 8),
          Text(
            widget.isAdminView ? "ARKUSZ OBECNOŚCI: $_employeeDisplayName" : "MOJA LISTA OBECNOŚCI",
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 18, color: theme.colorScheme.onSurface),
          ),
          const Spacer(),
          const ThemeSwitcher(),
          const SizedBox(width: 16),
          IconButton(icon: const Icon(Icons.visibility_rounded), onPressed: () => _generatePdf(true), tooltip: "Podgląd PDF"),
          IconButton(icon: const Icon(Icons.print_rounded), onPressed: () => _generatePdf(false), tooltip: "Drukuj / Pobierz PDF"),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _initData, 
            icon: const Icon(Icons.refresh_rounded, size: 18), 
            label: const Text("ODŚWIEŻ DANE"),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007BFF), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRowDesktop() {
    final String currentYear = _focusedDay.year.toString();
    final String currentMonthPrefix = DateFormat('yyyy-MM').format(_focusedDay);
    
    return Row(
      children: [
        _statCardDesktop("PRZEPRACOWANO", "${_calculateMonthlyTotal().toStringAsFixed(1)} h", Icons.access_time_filled, Colors.blue),
        const SizedBox(width: 16),
        _statCardDesktop("DNI PRACY", "${_calculateWorkDays()} dni", Icons.work_rounded, Colors.green),
        const SizedBox(width: 16),
        _statCardDesktop("URLOP (ROK)", "${_calculateHolidays(currentYear)} dni", Icons.beach_access_rounded, Colors.orange, sub: "Wykorzystane"),
        const SizedBox(width: 16),
        _statCardDesktop("URLOP (MIESIĄC)", "${_calculateHolidays(currentMonthPrefix)} dni", Icons.calendar_month_rounded, Colors.purple),
        const SizedBox(width: 16),
        _statCardDesktop("NIEOBECNOŚCI", "${_calculateAbsences()} dni", Icons.person_off_rounded, Colors.red, sub: "L4 / inne"),
      ],
    );
  }

  Widget _statCardDesktop(String label, String value, IconData icon, Color color, {String? sub}) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface.withOpacity(0.4), letterSpacing: 1)),
                Icon(icon, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
            if (sub != null) Text(sub, style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withOpacity(0.3), fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCardDesktop() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 32),
                    onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1)),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    DateFormat('MMMM yyyy', 'pl_PL').format(_focusedDay).toUpperCase(),
                    style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 1, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 32),
                    onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1)),
                  ),
                ],
              ),
              _buildLegend(),
            ],
          ),
          const SizedBox(height: 32),
          TableCalendar(
            locale: 'pl_PL',
            firstDay: DateTime.utc(2023, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            headerVisible: false,
            daysOfWeekHeight: 40,
            rowHeight: 100,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
                _showEditPanel = true;
              });
              _loadDayData(selectedDay);
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) => _buildCalendarDay(day, false),
              todayBuilder: (context, day, focusedDay) => _buildCalendarDay(day, true),
              selectedBuilder: (context, day, focusedDay) => _buildCalendarDay(day, false, isSelected: true),
              outsideBuilder: (context, day, focusedDay) => Opacity(opacity: 0.2, child: _buildCalendarDay(day, false)),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface.withOpacity(0.3), fontSize: 12),
              weekendStyle: TextStyle(fontWeight: FontWeight.w900, color: Colors.redAccent.withOpacity(0.5), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarDay(DateTime day, bool isToday, {bool isSelected = false}) {
    final theme = Theme.of(context);
    final key = DateFormat('yyyy-MM-dd').format(day);
    final dayData = _data[key];
    
    Color typeColor = Colors.transparent;
    String hours = "";
    String order = "";
    
    if (dayData != null) {
      if (dayData['type'] == 'PRACA') {
        typeColor = Colors.green;
        double h = _service.calculateHours(dayData['in'], dayData['out']);
        hours = "${h.toStringAsFixed(1)} h";
        order = dayData['orderName'] ?? "";
      } else if (dayData['type'] == 'URLOP') {
        typeColor = Colors.purple;
        hours = "URLOP";
      } else if (dayData['type'] == 'CHOROBA') {
        typeColor = Colors.red;
        hours = "L4";
      } else if (dayData['type'] == 'ŚWIĘTO') {
        typeColor = Colors.orange;
        hours = "ŚWIĘTO";
      }
    }

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : (isToday ? theme.colorScheme.primary.withOpacity(0.05) : Colors.transparent),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? theme.colorScheme.primary : (isToday ? theme.colorScheme.primary.withOpacity(0.3) : theme.dividerTheme.color ?? Colors.white10),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 12, left: 12,
            child: Text(day.day.toString(), style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.onSurface.withOpacity(isSelected ? 1 : 0.6))),
          ),
          if (dayData != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(hours, style: TextStyle(color: typeColor, fontWeight: FontWeight.w900, fontSize: 10)),
                  ),
                  if (order.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                      child: Text(order, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final theme = Theme.of(context);
    return Row(
      children: [
        _legendItem("Praca", Colors.green),
        _legendItem("Urlop", Colors.purple),
        _legendItem("L4", Colors.red),
        _legendItem("Święto", Colors.orange),
        _legendItem("Brak", theme.colorScheme.onSurface.withOpacity(0.3)),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _buildRecentEntriesDesktop() {
    final sorted = _getSortedMonthDays().reversed.toList();
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("WPISY W TYM MIESIĄCU", style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1, color: theme.colorScheme.onSurface.withOpacity(0.5))),
            TextButton(
              onPressed: _showFullHistoryDialog, 
              child: const Text("HISTORIA CAŁKOWITA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (sorted.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text("Brak wpisów w tym miesiącu.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontStyle: FontStyle.italic)),
            ),
          )
        else
          ...sorted.map((e) => _buildEntryRowDesktop(e)).toList(),
      ],
    );
  }

  void _showFullHistoryDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Local state for the dialog
    String searchQuery = "";
    String? selectedMonth; // e.g. "2026-08"
    String? selectedOrder;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDS) {
          // Prepare list of months available in _data
          final months = _data.keys
            .where((k) => k.length == 10 && DateTime.tryParse(k) != null)
            .map((k) => k.substring(0, 7))
            .toSet().toList()..sort((a,b) => b.compareTo(a));

          // Filter data
          var filtered = _data.entries
            .where((e) => e.key.length == 10 && !e.key.startsWith('approval'))
            .where((e) {
              final date = e.key;
              final data = e.value;
              final orderName = data['orderName']?.toString().toLowerCase() ?? "";
              final type = data['type']?.toString().toLowerCase() ?? "";
              
              bool matchSearch = orderName.contains(searchQuery.toLowerCase()) || type.contains(searchQuery.toLowerCase());
              bool matchMonth = selectedMonth == null || date.startsWith(selectedMonth!);
              bool matchOrder = selectedOrder == null || data['orderName'] == selectedOrder;
              
              return matchSearch && matchMonth && matchOrder;
            }).toList();
          
          filtered.sort((a,b) => b.key.compareTo(a.key));

          return Dialog(
            backgroundColor: theme.scaffoldBackgroundColor,
            insetPadding: const EdgeInsets.all(40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Container(
              width: 1000,
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("HISTORIA OBECNOŚCI", style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 24, color: theme.colorScheme.onSurface)),
                      IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          onChanged: (v) => setDS(() => searchQuery = v),
                          decoration: InputDecoration(
                            hintText: "Szukaj w historii...",
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedMonth,
                          decoration: InputDecoration(
                            labelText: "Miesiąc",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text("Wszystkie")),
                            ...months.map((m) => DropdownMenuItem(value: m, child: Text(m))),
                          ],
                          onChanged: (v) => setDS(() => selectedMonth = v),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedOrder,
                          decoration: InputDecoration(
                            labelText: "Budowa",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text("Wszystkie")),
                            ..._orders.map((o) => DropdownMenuItem(value: o['name'].toString(), child: Text(o['name'].toString()))).toList(),
                          ],
                          onChanged: (v) => setDS(() => selectedOrder = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: filtered.isEmpty 
                      ? Center(child: Text("Brak wpisów spełniających kryteria.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2))))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, idx) {
                            final e = filtered[idx];
                            final date = DateTime.parse(e.key);
                            final data = e.value;
                            double h = data['type'] == 'URLOP' ? 8.0 : _service.calculateHours(data['in'], data['out']);
                            bool hasSig = data['signature'] != null && data['signature'].isNotEmpty;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                  child: Text(DateFormat('dd.MM').format(date), style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                                ),
                                title: Text(data['orderName'] ?? data['type'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text("${data['in']} - ${data['out']} | $h h"),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (hasSig) const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                                    const SizedBox(width: 12),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _selectedDay = date;
                                    _focusedDay = date;
                                    _showEditPanel = true;
                                  });
                                  _loadDayData(date);
                                },
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildEntryRowDesktop(MapEntry<String, dynamic> entry) {
    final date = DateTime.parse(entry.key);
    final theme = Theme.of(context);
    final dayData = entry.value;
    double h = dayData['type'] == 'URLOP' ? 8.0 : _service.calculateHours(dayData['in'], dayData['out']);
    
    Color typeColor = Colors.blue;
    if (dayData['type'] == 'URLOP') typeColor = Colors.purple;
    if (dayData['type'] == 'ŚWIĘTO') typeColor = Colors.orange;
    if (dayData['type'] == 'CHOROBA') typeColor = Colors.red;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedDay = date;
          _showEditPanel = true;
        });
        _loadDayData(date);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  Text(date.day.toString(), style: TextStyle(fontWeight: FontWeight.w900, color: typeColor, fontSize: 16)),
                  Text(DateFormat('MMM', 'pl_PL').format(date).toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: typeColor.withOpacity(0.5), fontSize: 9)),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dayData['orderName'] ?? dayData['type'] ?? "-", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text("${dayData['in']} – ${dayData['out']}", style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Text("${h.toStringAsFixed(1)} h", style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.primary)),
            const SizedBox(width: 16),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurface.withOpacity(0.1)),
          ],
        ),
      ),
    );
  }

  Widget _buildEditPanelDesktop() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final polishDaysLong = ["poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota", "niedziela"];
    final dayName = _selectedDay != null ? polishDaysLong[_selectedDay!.weekday - 1] : "";
    
    final key = _selectedDay != null ? DateFormat('yyyy-MM-dd').format(_selectedDay!) : "";
    final dayData = _data[key] ?? {};
    final String? sigBase64 = dayData['signature'];
    final bool hasSignature = sigBase64 != null && sigBase64.isNotEmpty;

    double currentHours = _service.calculateHours(_inController.text, _outController.text);

    return Column(
      children: [
        // Panel Header
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Edycja dnia", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: theme.colorScheme.onSurface)),
                  Text(
                    _selectedDay != null ? "$dayName, ${DateFormat('dd.MM.yyyy').format(_selectedDay!)}" : "", 
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.bold)
                  ),
                ],
              ),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _showEditPanel = false)),
            ],
          ),
        ),
        const Divider(height: 1),
        
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("TYP DNIA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _typeBtn("PRACA", Colors.green, _selectedType == 'PRACA'),
                    const SizedBox(width: 8),
                    _typeBtn("URLOP", Colors.purple, _selectedType == 'URLOP'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _typeBtn("ŚWIĘTO", Colors.orange, _selectedType == 'ŚWIĘTO'),
                    const SizedBox(width: 8),
                    _typeBtn("L4", Colors.red, _selectedType == 'CHOROBA', val: 'CHOROBA'),
                  ],
                ),
                
                if (_selectedType == 'PRACA') ...[
                  const SizedBox(height: 32),
                  const Text("GODZINY PRACY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _timeFieldInternal("Od:", _inController, (_) => setState(() {}))),
                      const SizedBox(width: 16),
                      Expanded(child: _timeFieldInternal("Do:", _outController, (_) => setState(() {}))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("SUMA GODZIN:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                        Text("${currentHours.toStringAsFixed(1)} h", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.primary)),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  const Text("ZLECENIE / BUDOWA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedOrder, 
                    isExpanded: true, 
                    dropdownColor: theme.cardTheme.color,
                    style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 16)), 
                    items: _orders.map<DropdownMenuItem<String>>((o) => DropdownMenuItem<String>(value: o['name'].toString(), child: Text(o['name'].toString()))).toList(), 
                    onChanged: (val) => setState(() => _selectedOrder = val),
                  ),
                ],
                
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("PODPIS DZIENNY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                    if (hasSignature) 
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.green, size: 12),
                            SizedBox(width: 4),
                            Text("Podpis zapisany ✓", style: TextStyle(color: Colors.green, fontSize: 8, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (hasSignature && _dailySignatureController.isEmpty)
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.03) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerTheme.color ?? Colors.white10)
                    ),
                    child: Stack(
                      children: [
                        Center(child: Image.memory(base64Decode(sigBase64), color: isDark ? Colors.white : null)),
                        Positioned(
                          top: 8, right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF007BFF)),
                            onPressed: () => setState(() => _dailySignatureController.clear()), // This is a bit hacky way to force new signature
                            tooltip: "Podpisz ponownie",
                          ),
                        )
                      ],
                    ),
                  )
                else
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.03) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerTheme.color ?? Colors.white10)
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Signature(controller: _dailySignatureController, backgroundColor: Colors.transparent),
                    ),
                  ),
                if (!hasSignature || _dailySignatureController.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => _dailySignatureController.clear(), child: const Text("WYCZYŚĆ", style: TextStyle(color: Colors.red, fontSize: 10))),
                  ),
                
                const SizedBox(height: 16),
                const Text("UWAGI", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(hintText: "Dodaj uwagi do wpisu...", hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2)), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
        
        // Panel Footer
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerTheme.color ?? Colors.white10))
          ),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _showEditPanel = false), 
                  child: const Text("ANULUJ", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveDay, 
                  style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: theme.colorScheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text("ZAPISZ DZIEŃ", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typeBtn(String label, Color color, bool active, {String? val}) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedType = val ?? label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? color : theme.colorScheme.onSurface.withOpacity(0.05)),
          ),
          child: Center(
            child: Text(label, style: TextStyle(color: active ? color : theme.colorScheme.onSurface.withOpacity(0.3), fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ),
      ),
    );
  }

  // --- MOBILE LAYOUT ---

  Widget _buildMobileLayout() {
    final String currentYear = _focusedDay.year.toString();
    final String currentMonthPrefix = DateFormat('yyyy-MM').format(_focusedDay);
    
    return _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.accentBlue)) : CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildSummaryHeaderMobile()),
        SliverToBoxAdapter(child: _buildHolidayStatsMobile(currentYear, currentMonthPrefix)),
        SliverToBoxAdapter(child: _buildCalendarMobile()),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        _buildDailyListMobile(),
        if (!widget.isAdminView) _buildMonthlyApprovalCardMobile(),
        const SliverToBoxAdapter(child: SizedBox(height: 60)),
      ],
    );
  }

  Widget _buildSummaryHeaderMobile() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final months = ["STYCZEŃ", "LUTY", "MARZEC", "KWIECIEŃ", "MAJ", "CZERWIEC", "LIPIEC", "SIERPIEŃ", "WRZESIEŃ", "PAŹDZIERNIK", "LISTOPAD", "GRUDZIEŃ"];
    final monthTitle = "${months[_focusedDay.month - 1]} ${_focusedDay.year}";
    return Container(
      width: double.infinity, 
      margin: const EdgeInsets.all(16), 
      padding: const EdgeInsets.all(24), 
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : const Color(0xFF001A2C), 
        borderRadius: BorderRadius.circular(24)
      ), 
      child: Column(children: [
        const Text("MIESIĄC", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)), 
        const SizedBox(height: 8), 
        Text("${_calculateMonthlyTotal().toStringAsFixed(1)} h", style: TextStyle(color: theme.colorScheme.primary, fontSize: 36, fontWeight: FontWeight.w900)), 
        const Text("SUMA GODZIN W MIESIĄCU", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold))
      ])
    );
  }

  Widget _buildHolidayStatsMobile(String year, String monthPrefix) {
    int yearHols = _calculateHolidays(year);
    int monthHols = _calculateHolidays(monthPrefix);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(child: _statMiniCardMobile("URLOP (ROK)", "$yearHols dni", Colors.orange)),
          const SizedBox(width: 12),
          Expanded(child: _statMiniCardMobile("URLOP (MIESIĄC)", "$monthHols dni", Colors.blue)),
        ],
      ),
    );
  }

  Widget _statMiniCardMobile(String label, String value, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color, 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.4))),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
      ]),
    );
  }

  Widget _buildCalendarMobile() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16), 
      color: theme.cardTheme.color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: theme.dividerTheme.color ?? Colors.white10)),
      elevation: isDark ? 0 : 4,
      child: TableCalendar(
        locale: 'pl_PL', 
        firstDay: DateTime.utc(2023, 1, 1), 
        lastDay: DateTime.utc(2030, 12, 31), 
        focusedDay: _focusedDay, 
        startingDayOfWeek: StartingDayOfWeek.monday,
        calendarFormat: _calendarFormat, 
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day), 
        eventLoader: (day) => _data.containsKey(DateFormat('yyyy-MM-dd').format(day)) ? [true] : [], 
        onDaySelected: (selectedDay, focusedDay) { 
          setState(() { _selectedDay = selectedDay; _focusedDay = focusedDay; }); 
          _loadDayData(selectedDay); 
          if (!widget.isAdminView) _showEditDayBottomSheet();
        }, 
        onPageChanged: (focusedDay) { 
          setState(() => _focusedDay = focusedDay); 
          _loadMonthlyApprovalData(); 
        }, 
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.7)),
          weekendStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.redAccent),
        ),
        calendarStyle: CalendarStyle(
          selectedDecoration: const BoxDecoration(color: Color(0xFF007BFF), shape: BoxShape.circle), 
          todayDecoration: BoxDecoration(color: Colors.indigo.withOpacity(0.5), shape: BoxShape.circle), 
          markerDecoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
          outsideDaysVisible: false,
          defaultTextStyle: TextStyle(color: theme.colorScheme.onSurface),
          weekendTextStyle: const TextStyle(color: Colors.redAccent),
        ), 
        headerStyle: HeaderStyle(
          formatButtonVisible: false, 
          titleCentered: true,
          titleTextStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.onSurface),
          leftChevronIcon: Icon(Icons.chevron_left, color: theme.colorScheme.onSurface),
          rightChevronIcon: Icon(Icons.chevron_right, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _buildDailyListMobile() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final polishDaysShort = ["nd", "pn", "wt", "śr", "cz", "pt", "so"];
    final sortedDays = _getSortedMonthDays().reversed.toList();
    if (sortedDays.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
    
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8), 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("WPISY W TYM MIESIĄCU", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2, color: theme.colorScheme.onSurface.withOpacity(0.3))),
                TextButton(
                  onPressed: _showFullHistoryDialog,
                  child: const Text("PEŁNA HISTORIA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            )
          ), 
          ListView.builder(
            shrinkWrap: true, 
            physics: const NeverScrollableScrollPhysics(), 
            itemCount: sortedDays.length, 
            itemBuilder: (context, index) {
              final day = sortedDays[index];
              final date = DateTime.parse(day.key);
              final dayName = polishDaysShort[date.weekday % 7];
              final sig = day.value['signature'] != null ? base64Decode(day.value['signature']) : null;
              
              double h = day.value['type'] == 'URLOP' ? 8.0 : _service.calculateHours(day.value['in'], day.value['out']);
              
              Color typeColor = Colors.blue;
              if (day.value['type'] == 'URLOP') typeColor = Colors.orange;
              if (day.value['type'] == 'ŚWIĘTO') typeColor = Colors.red;
              if (day.value['type'] == 'CHOROBA') typeColor = Colors.purple;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color, 
                  borderRadius: BorderRadius.circular(16), 
                  border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
                  boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)]
                ),
                child: Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    shape: const RoundedRectangleBorder(side: BorderSide.none),
                    collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                    leading: Container(
                      width: 45, height: 45,
                      decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(day.key.split('-').last, style: TextStyle(fontWeight: FontWeight.w900, color: typeColor)), 
                        Text(dayName.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: typeColor.withOpacity(0.5)))
                      ]),
                    ),
                    title: Text(day.value['orderName'] ?? day.value['type'] ?? "Brak nazwy", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
                    subtitle: Text(day.value['type'] == 'PRACA' ? "${day.value['in']} - ${day.value['out']} (${h.toStringAsFixed(1)}h)" : day.value['type'], style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.4))),
                    trailing: Icon(Icons.expand_more, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                    children: [
                      const Divider(height: 1, indent: 20, endIndent: 20),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            if (sig != null) Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text("PODPIS:", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.3))),
                              const SizedBox(height: 4),
                              Container(height: 40, alignment: Alignment.centerLeft, child: Image.memory(sig, color: isDark ? Colors.white70 : null)),
                            ])),
                            if (!widget.isAdminView) ElevatedButton.icon(
                              onPressed: () {
                                setState(() { _selectedDay = date; });
                                _loadDayData(date);
                                _showEditDayBottomSheet();
                              }, 
                              icon: const Icon(Icons.edit, size: 14), 
                              label: const Text("EDYTUJ", style: TextStyle(fontSize: 10)),
                              style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.onSurface.withOpacity(0.05), foregroundColor: theme.colorScheme.onSurface, elevation: 0),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            }
          )
        ]
      ),
    );
  }

  Widget _buildMonthlyApprovalCardMobile() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16.0), 
        child: Container(
          padding: const EdgeInsets.all(24), 
          decoration: BoxDecoration(
            color: theme.cardTheme.color, 
            borderRadius: BorderRadius.circular(24), 
            border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
            boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)]
          ), 
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("ZATWIERDZENIE MIESIĄCA", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.onSurface)), 
            const SizedBox(height: 20), 
            TextField(
              controller: _notesController, 
              maxLines: 3, 
              style: TextStyle(color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: "UWAGI / KOMENTARZ", 
                labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                border: const OutlineInputBorder()
              )
            ), 
            const SizedBox(height: 24), 
            Text("GŁÓWNY PODPIS ZATWIERDZAJĄCY:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))), 
            const SizedBox(height: 8), 
            Container(
              decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)), borderRadius: BorderRadius.circular(16)), 
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16), 
                child: Signature(controller: _monthlySignatureController, height: 120, backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50]!)
              )
            ), 
            TextButton(onPressed: () => _monthlySignatureController.clear(), child: const Text("WYCZYŚĆ PODPIS", style: TextStyle(fontSize: 10, color: Colors.red))), 
            const SizedBox(height: 12), 
            ElevatedButton(
              onPressed: _saveMonthlyApproval, 
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56), backgroundColor: Colors.green[700], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), 
              child: const Text("ZATWIERDŹ I WYŚLIJ", style: TextStyle(fontWeight: FontWeight.bold))
            )
          ])
        )
      ),
    );
  }

  void _showEditDayBottomSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) {
          final polishDaysLong = ["poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota", "niedziela"];
          final dayName = polishDaysLong[_selectedDay!.weekday - 1];
          
          final key = DateFormat('yyyy-MM-dd').format(_selectedDay!);
          final dayData = _data[key] ?? {};
          final String? sigBase64 = dayData['signature'];
          final bool hasSignature = sigBase64 != null && sigBase64.isNotEmpty;

          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            decoration: BoxDecoration(color: theme.cardTheme.color, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.1), borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("EDYCJA: ${DateFormat('dd.MM.yyyy').format(_selectedDay!)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: theme.colorScheme.onSurface)),
                          Text(dayName.toUpperCase(), style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ],
                      ),
                      if (hasSignature) 
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: Colors.green, size: 12),
                              SizedBox(width: 4),
                              Text("ZAPISANY ✓", style: TextStyle(color: Colors.green, fontSize: 8, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text("TYP DNIA:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'PRACA', label: Text('PRACA', style: TextStyle(fontSize: 10))),
                        ButtonSegment(value: 'URLOP', label: Text('URLOP', style: TextStyle(fontSize: 10))),
                        ButtonSegment(value: 'ŚWIĘTO', label: Text('ŚWIĘTO', style: TextStyle(fontSize: 10))),
                        ButtonSegment(value: 'CHOROBA', label: Text('L4', style: TextStyle(fontSize: 10))),
                      ],
                      selected: {_selectedType},
                      onSelectionChanged: (val) { setDS(() => _selectedType = val.first); setState(() {}); },
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_selectedType == 'PRACA') ...[
                    Row(children: [
                      Expanded(child: _timeFieldInternal("START", _inController, (v) { setDS((){}); setState((){}); })), 
                      const SizedBox(width: 12), 
                      Expanded(child: _timeFieldInternal("KONIEC", _outController, (v) { setDS((){}); setState((){}); }))
                    ]),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedOrder, 
                      isExpanded: true, 
                      dropdownColor: theme.cardTheme.color,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(labelText: "WYBIERZ BUDOWĘ", labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)), border: const OutlineInputBorder()), 
                      items: _orders.map<DropdownMenuItem<String>>((o) => DropdownMenuItem<String>(value: o['name'].toString(), child: Text(o['name'].toString(), style: const TextStyle(fontSize: 12)))).toList(), 
                      onChanged: (val) { setDS(() => _selectedOrder = val); setState(() {}); },
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text("PODPIS DZIENNY:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  if (hasSignature && _dailySignatureController.isEmpty)
                    Container(
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10)
                      ),
                      child: Stack(
                        children: [
                          Center(child: Image.memory(base64Decode(sigBase64), color: isDark ? Colors.white : null)),
                          Positioned(
                            top: 8, right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF007BFF)),
                              onPressed: () => setDS(() => _dailySignatureController.clear()),
                              tooltip: "Podpisz ponownie",
                            ),
                          )
                        ],
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)), borderRadius: BorderRadius.circular(12)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Signature(controller: _dailySignatureController, height: 100, backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50]!),
                      ),
                    ),
                  if (!hasSignature || _dailySignatureController.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _dailySignatureController.clear(), 
                        icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                        label: const Text("WYCZYŚĆ", style: TextStyle(fontSize: 9, color: Colors.red))
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text("UWAGI", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(hintText: "Dodaj uwagi...", border: const OutlineInputBorder()),
                    onChanged: (v) => setState(() {}),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () { _saveDay(); Navigator.pop(ctx); }, 
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56), backgroundColor: const Color(0xFF001A2C), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), 
                    child: const Text("ZAPISZ DZIEŃ", style: TextStyle(fontWeight: FontWeight.bold))
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        }
      )
    );
  }

  // --- COMMON WIDGETS ---

  Widget _timeFieldInternal(String label, TextEditingController controller, Function(String) onChanged) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller, 
      readOnly: true, 
      style: TextStyle(color: theme.colorScheme.onSurface),
      onTap: () async {
        int initialH = 7; int initialM = 0;
        try {
          final parts = controller.text.split(':');
          if (parts.length == 2) { initialH = int.parse(parts[0]); initialM = int.parse(parts[1]); }
        } catch (_) {}
        
        TimeOfDay? picked = await showTimePicker(
          context: context, 
          initialTime: TimeOfDay(hour: initialH, minute: initialM),
          builder: (context, child) => Theme(data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.padded), child: child!)
        );
        
        if (picked != null) {
          final val = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
          setState(() => controller.text = val);
          onChanged(val);
        }
      }, 
      decoration: InputDecoration(
        labelText: label, 
        labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
        border: const OutlineInputBorder(), 
        prefixIcon: const Icon(Icons.access_time, size: 18)
      )
    );
  }
}
