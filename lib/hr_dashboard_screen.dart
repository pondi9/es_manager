import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'core/app_theme.dart';
import 'core/app_constants.dart';
import 'widgets/theme_switcher.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'attendance_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'admin_panel_screen.dart';
import 'admin_command_center_screen.dart';
import 'hr_employee_detail_screen.dart';
import 'services/attendance_service.dart';

class HrDashboardScreen extends StatefulWidget {
  final String userEmail;
  const HrDashboardScreen({super.key, required this.userEmail});

  @override
  State<HrDashboardScreen> createState() => _HrDashboardScreenState();
}

class _HrDashboardScreenState extends State<HrDashboardScreen> {
  bool _isAdmin = false;
  Map<String, dynamic> _userPermissions = {};
  String _displayName = "";
  bool _isLoading = true;

  // Dane
  List<Map<String, dynamic>> _allEmployees = [];
  Map<String, Map<String, dynamic>> _allAttendance = {};
  
  // Filtry
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  // Statystyki
  int _activeEmployeesCount = 0;
  double _totalHoursThisMonth = 0;
  int _vacationDaysThisMonth = 0;
  int _docsToFixCount = 0;

  final GlobalKey _attendanceKey = GlobalKey();
  final GlobalKey _documentsKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription? _empSub, _attSub;

  @override
  void initState() {
    super.initState();
    _checkAccess();
    _initDataStreams();
  }

  @override
  void dispose() {
    _empSub?.cancel();
    _attSub?.cancel();
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

  void _initDataStreams() {
    _empSub = FirebaseFirestore.instance.collection('employees').snapshots().listen((snap) {
      final emps = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      if (mounted) {
        setState(() {
          _allEmployees = emps;
          // Filtracja: Licz tylko aktywnych pracowników (bez admina i kierowników)
          _activeEmployeesCount = emps.where((e) {
            if (e['isActive'] != true) return false;
            final email = (e['email'] ?? e['id'] ?? "").toString().toLowerCase();
            final pos = (e['position'] ?? "").toString().toLowerCase();
            return email != AppConstants.adminEmail.toLowerCase() && !pos.contains('kierownik');
          }).length;
          _calculateDocsToFix();
        });
      }
    });

    _attSub = FirebaseFirestore.instance.collection('attendance').snapshots().listen((snap) {
      Map<String, Map<String, dynamic>> attData = {};
      for (var doc in snap.docs) {
        final data = doc.data();
        attData[doc.id.toLowerCase()] = data['data'] ?? {};
      }

      if (mounted) {
        setState(() {
          _allAttendance = attData;
          _calculateStats();
          _isLoading = false;
        });
      }
    });
  }

  void _calculateStats() {
    final attService = AttendanceService();
    final monthPrefix = "${_selectedYear}-${_selectedMonth.toString().padLeft(2, '0')}";
    
    double hSum = 0;
    int vSum = 0;

    _allAttendance.forEach((email, data) {
      // Filtracja: Nie licz admina i kierowników do statystyk HR
      final emp = _allEmployees.firstWhere((e) => (e['email'] ?? e['id'] ?? "").toString().toLowerCase() == email, orElse: () => {});
      if (emp.isNotEmpty) {
        final pos = (emp['position'] ?? "").toString().toLowerCase();
        if (email == AppConstants.adminEmail.toLowerCase() || pos.contains('kierownik')) return;
      }

      data.forEach((date, val) {
        if (date.startsWith(monthPrefix)) {
          if (val['type'] == 'PRACA') {
            hSum += attService.calculateHours(val['in'], val['out']);
          } else if (val['type'] == 'URLOP') {
            vSum++;
          }
        }
      });
    });

    _totalHoursThisMonth = hSum;
    _vacationDaysThisMonth = vSum;
  }

  void _calculateDocsToFix() {
    int count = 0;
    for (var emp in _allEmployees) {
      if (emp['isActive'] != true) continue;
      
      final email = (emp['email'] ?? emp['id'] ?? "").toString().toLowerCase();
      final pos = (emp['position'] ?? "").toString().toLowerCase();
      if (email == AppConstants.adminEmail.toLowerCase() || pos.contains('kierownik')) continue;

      final Map excluded = emp['excludedDocs'] ?? {};

      final docTypes = [
        {'date': 'medicalEnd', 'no': 'medicalNo', 'imgs': 'medicalImgs', 'exKey': 'medical'},
        {'date': 'bhpDate', 'no': 'bhpNo', 'imgs': 'bhpImgs', 'exKey': 'bhp'},
        {'date': 'sepDate', 'no': 'sepNo', 'imgs': 'sepImgs', 'exKey': 'sep'},
        {'date': 'udtDate', 'no': 'udtNo', 'imgs': 'udtImgs', 'exKey': 'udt'},
        {'date': 'contractEnd', 'no': 'contractNo', 'imgs': 'contractImgs', 'exKey': 'contract'},
      ];

      for (var d in docTypes) {
        if (excluded[d['exKey']] == true) continue;
        
        final status = _getDocStatus(emp[d['date']], no: emp[d['no']], imgs: emp[d['imgs']]);
        final label = status['label'];
        if (label == "PO TERMINIE" || label == "DO 30 DNI" || label == "BRAK DATY" || label == "BRAK DOK.") {
          count++;
        }
      }
      
      final List additional = emp['additionalCerts'] ?? [];
      for (var cert in additional) {
        final status = _getDocStatus(cert['expiryDate'], no: cert['number'], imgs: cert['imageUrls']);
        final label = status['label'];
        if (label == "PO TERMINIE" || label == "DO 30 DNI" || label == "BRAK DATY" || label == "BRAK DOK.") {
          count++;
        }
      }
    }
    _docsToFixCount = count;
  }

  Map<String, dynamic> _getDocStatus(String? dateStr, {dynamic no, dynamic imgs}) {
    if (dateStr == "NIEOKREŚLONY") return {'label': "WAŻNE", 'diff': 9999};
    
    bool hasData = (no != null && no.toString().isNotEmpty) || (imgs != null && (imgs is List ? imgs.isNotEmpty : imgs.toString().isNotEmpty));
    
    if (dateStr == null || dateStr.isEmpty) {
      return {'label': hasData ? "BRAK DATY" : "BRAK DOK.", 'diff': 0};
    }

    try {
      final expiry = DateFormat('dd.MM.yyyy').parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final diff = expiry.difference(today).inDays;

      if (diff < 0) return {'label': "PO TERMINIE", 'diff': diff};
      if (diff <= 30) return {'label': "DO 30 DNI", 'diff': diff};
      if (diff <= 90) return {'label': "DO 90 DNI", 'diff': diff};
      return {'label': "WAŻNE", 'diff': diff};
    } catch (_) {
      return {'label': "BŁĄD DATY", 'diff': 0};
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "WAŻNE": return Colors.green;
      case "DO 90 DNI": return Colors.yellow[700]!;
      case "DO 30 DNI": return Colors.orange;
      case "PO TERMINIE": return Colors.red;
      case "BRAK DATY": return Colors.deepOrange;
      case "BRAK DOK.": return Colors.grey.shade600;
      default: return Colors.grey;
    }
  }

  void _scrollTo(GlobalKey key) {
    if (key.currentContext != null) {
      Scrollable.ensureVisible(key.currentContext!, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
    }
  }

  void _showVacationReport() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final activeEmployees = _allEmployees.where((e) {
      if (e['isActive'] != true) return false;
      final email = (e['email'] ?? e['id'] ?? "").toString().toLowerCase();
      final pos = (e['position'] ?? "").toString().toLowerCase();
      return email != AppConstants.adminEmail.toLowerCase() && !pos.contains('kierownik');
    }).toList();
    
    activeEmployees.sort((a, b) => (a['lastName'] ?? '').compareTo(b['lastName'] ?? ''));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Row(
          children: [
            const Icon(Icons.beach_access_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ZESTAWIENIE URLOPÓW", style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 18, color: theme.colorScheme.onSurface)),
                  Text(DateFormat('MMMM yyyy', 'pl_PL').format(DateTime(_selectedYear, _selectedMonth)), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent),
              onPressed: () => _exportVacationsToPdf(activeEmployees),
              tooltip: "Eksportuj do PDF",
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 500,
          child: ListView.separated(
            itemCount: activeEmployees.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final emp = activeEmployees[i];
              final stats = _getEmployeeMonthStats(emp);
              final List dates = stats['vacationDates'] ?? [];
              
              return ListTile(
                title: Text("${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(dates.isEmpty ? "Brak urlopów" : "Daty: ${dates.join(', ')}", style: const TextStyle(fontSize: 11)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Text("${stats['vacationDays']} dni", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ZAMKNIJ")),
        ],
      ),
    );
  }

  Future<void> _exportVacationsToPdf(List<Map<String, dynamic>> emps) async {
    final pdf = pw.Document();
    final ttf = await PdfGoogleFonts.robotoRegular();
    final ttfBold = await PdfGoogleFonts.robotoBold();
    
    final String monthName = DateFormat('MMMM yyyy', 'pl_PL').format(DateTime(_selectedYear, _selectedMonth));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("ZESTAWIENIE URLOPÓW", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.Text("Okres: $monthName", style: const pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: ['Pracownik', 'Liczba dni', 'Daty urlopu'],
                data: emps.map((e) {
                  final stats = _getEmployeeMonthStats(e);
                  return [
                    "${e['firstName'] ?? ''} ${e['lastName'] ?? ''}",
                    "${stats['vacationDays']} dni",
                    (stats['vacationDates'] as List).join(', ')
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                cellHeight: 25,
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: "Zestawienie_Urlopow_${monthName}.pdf");
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
        title: const Text("PULPIT HR", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
        leading: Builder(builder: (context) => IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => Scaffold.of(context).openDrawer(),
        )),
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
                        controller: _scrollController,
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
                                  Expanded(flex: 2, child: SizedBox(key: _attendanceKey, child: _buildAttendanceTable())),
                                  const SizedBox(width: 24),
                                  Expanded(flex: 1, child: SizedBox(key: _documentsKey, child: _buildDocumentDeadlines())),
                                ],
                              )
                            else ...[
                              SizedBox(key: _attendanceKey, child: _buildAttendanceTable()),
                              const SizedBox(height: 24),
                              SizedBox(key: _documentsKey, child: _buildDocumentDeadlines()),
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
    final theme = Theme.of(context);
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
                "Pulpit HR / Kadry",
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
          _headerIconButton(Icons.refresh_rounded, () => setState(() {})),
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
      if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => LoginScreen()), (route) => false);
    }
  }

  Widget _buildKpiGrid(bool isDesktop) {
    return LayoutBuilder(builder: (context, constraints) {
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: isDesktop ? 4 : 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: isDesktop ? 2.0 : 1.3,
        children: [
          _kpiCard("PRACOWNICY", "$_activeEmployeesCount", "Aktywnych", Icons.people_rounded, Colors.blue, 
            onTap: () => _scrollTo(_attendanceKey)),
          _kpiCard("GODZINY", "${_totalHoursThisMonth.toInt()}h", "W tym miesiącu", Icons.access_time_filled_rounded, Colors.green, 
            onTap: () => _scrollTo(_attendanceKey)),
          _kpiCard("URLOPY", "$_vacationDaysThisMonth dni", "W tym miesiącu", Icons.beach_access_rounded, Colors.orange, 
            onTap: _showVacationReport),
          _kpiCard("DO POPRAWY", "$_docsToFixCount", "Dokumenty", Icons.assignment_late_rounded, Colors.red, badgeCount: _docsToFixCount, 
            onTap: () => _scrollTo(_documentsKey)),
        ],
      );
    });
  }

  Widget _kpiCard(String label, String value, String subValue, IconData icon, Color color, {int badgeCount = 0, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
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
        ),
      ),
    );
  }

  Widget _buildAttendanceTable() {
    final theme = Theme.of(context);
    // Filtracja pracowników dla tabeli obecności
    final activeEmployees = _allEmployees.where((e) {
      if (e['isActive'] != true) return false;
      final email = (e['email'] ?? e['id'] ?? "").toString().toLowerCase();
      final pos = (e['position'] ?? "").toString().toLowerCase();
      return email != AppConstants.adminEmail.toLowerCase() && !pos.contains('kierownik');
    }).toList();
    
    activeEmployees.sort((a, b) => (a['lastName'] ?? '').compareTo(b['lastName'] ?? ''));

    final months = List.generate(12, (i) => i + 1);
    final years = [2024, 2025, 2026];

    return _sectionPanel(
      title: "OBECNOŚĆ I URLOPY",
      icon: Icons.calendar_month_rounded,
      actions: [
        DropdownButton<int>(
          value: _selectedMonth,
          dropdownColor: theme.cardTheme.color,
          items: months.map((m) => DropdownMenuItem(value: m, child: Text(DateFormat('MMMM', 'pl_PL').format(DateTime(2024, m))))).toList(),
          onChanged: (v) => setState(() { _selectedMonth = v!; _calculateStats(); }),
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: _selectedYear,
          dropdownColor: theme.cardTheme.color,
          items: years.map((y) => DropdownMenuItem(value: y, child: Text("$y"))).toList(),
          onChanged: (v) => setState(() { _selectedYear = v!; _calculateStats(); }),
        ),
      ],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          columns: const [
            DataColumn(label: Text("PRACOWNIK")),
            DataColumn(label: Text("GODZINY (M)")),
            DataColumn(label: Text("URLOP (M)")),
            DataColumn(label: Text("WYKORZYSTANY (Y)")),
            DataColumn(label: Text("POZOSTAŁO")),
          ],
          rows: activeEmployees.map((emp) {
            final stats = _getEmployeeMonthStats(emp);
            final yearStats = _getEmployeeYearStats(emp);
            final limit = emp['vacationLimit'] ?? 26;
            final remaining = limit - yearStats['vacationDays']!;

            return DataRow(
              cells: [
                DataCell(
                  InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HrEmployeeDetailScreen(employee: emp, initialTab: 0))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        if ((stats['vacationDates'] as List).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              "Urlopy: ${(stats['vacationDates'] as List).join(', ')}",
                              style: TextStyle(fontSize: 8, color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                            ),
                          ),
                        if ((stats['l4Dates'] as List).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              "L4: ${(stats['l4Dates'] as List).join(', ')}",
                              style: TextStyle(fontSize: 8, color: Colors.red.shade700, fontWeight: FontWeight.w500),
                            ),
                          ),
                        if ((stats['delegationDates'] as List).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              "Delegacje: ${(stats['delegationDates'] as List).join(', ')}",
                              style: TextStyle(fontSize: 8, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                            ),
                          ),
                      ],
                    ),
                  )
                ),
                DataCell(
                  InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HrEmployeeDetailScreen(employee: emp, initialTab: 1))),
                    child: Text("${stats['hours']?.toStringAsFixed(1)} h", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  )
                ),
                DataCell(
                   InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HrEmployeeDetailScreen(employee: emp, initialTab: 2))),
                    child: Text("${stats['vacationDays']} dni", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                  )
                ),
                DataCell(Text("${yearStats['vacationDays']} dni")),
                DataCell(Text("$remaining dni", style: TextStyle(color: remaining < 5 ? Colors.orange : Colors.green, fontWeight: FontWeight.bold))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Map<String, dynamic> _getEmployeeMonthStats(Map<String, dynamic> emp) {
    final email = (emp['email'] ?? emp['id'] ?? '').toString().toLowerCase();
    final data = _allAttendance[email] ?? {};
    final prefix = "${_selectedYear}-${_selectedMonth.toString().padLeft(2, '0')}";
    
    double h = 0;
    int v = 0;
    List<String> vDates = [];
    List<String> l4Dates = [];
    List<String> delDates = [];
    final attService = AttendanceService();

    final sortedDates = data.keys.toList()..sort();

    for (var date in sortedDates) {
      if (date.startsWith(prefix)) {
        final val = data[date];
        final String type = val['type'] ?? 'PRACA';
        final String shortDate = "";
        try {
          final parsed = DateTime.parse(date);
          final formatted = DateFormat('dd.MM').format(parsed);
          
          if (type == 'PRACA') h += attService.calculateHours(val['in'], val['out']);
          if (type == 'URLOP') { v++; vDates.add(formatted); }
          if (type == 'L4') l4Dates.add(formatted);
          if (type == 'DELEGACJA') delDates.add(formatted);
        } catch (_) {}
      }
    }
    return {
      'hours': h, 
      'vacationDays': v, 
      'vacationDates': vDates,
      'l4Dates': l4Dates,
      'delegationDates': delDates
    };
  }

  Map<String, dynamic> _getEmployeeYearStats(Map<String, dynamic> emp) {
    final email = (emp['email'] ?? emp['id'] ?? '').toString().toLowerCase();
    final data = _allAttendance[email] ?? {};
    final prefix = "${_selectedYear}-";
    
    int v = 0;
    data.forEach((date, val) {
      if (date.startsWith(prefix) && val['type'] == 'URLOP') v++;
    });
    return {'vacationDays': v};
  }

  Widget _buildDocumentDeadlines() {
    final theme = Theme.of(context);
    final List<Map<String, dynamic>> items = [];

    for (var emp in _allEmployees) {
      if (emp['isActive'] != true) continue;
      
      final email = (emp['email'] ?? emp['id'] ?? "").toString().toLowerCase();
      final pos = (emp['position'] ?? "").toString().toLowerCase();
      if (email == AppConstants.adminEmail.toLowerCase() || pos.contains('kierownik')) continue;

      final Map excluded = emp['excludedDocs'] ?? {};

      final List<Map<String, String>> docs = [
        {'label': 'Badania lekarskie', 'key': 'medicalEnd', 'no': 'medicalNo', 'imgs': 'medicalImgs', 'exKey': 'medical'},
        {'label': 'Szkolenie BHP', 'key': 'bhpDate', 'no': 'bhpNo', 'imgs': 'bhpImgs', 'exKey': 'bhp'},
        {'label': 'Uprawnienia SEP', 'key': 'sepDate', 'no': 'sepNo', 'imgs': 'sepImgs', 'exKey': 'sep'},
        {'label': 'Uprawnienia UDT', 'key': 'udtDate', 'no': 'udtNo', 'imgs': 'udtImgs', 'exKey': 'udt'},
        {'label': 'Umowa o pracę', 'key': 'contractEnd', 'no': 'contractNo', 'imgs': 'contractImgs', 'exKey': 'contract'},
      ];

      for (var d in docs) {
        if (excluded[d['exKey']] == true) continue; // Skip if excluded

        final statusMap = _getDocStatus(emp[d['key']], no: emp[d['no']], imgs: emp[d['imgs']]);
        if (statusMap['label'] != "WAŻNE") {
           items.add({
             'name': "${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}",
             'type': d['label'],
             'date': emp[d['key']] ?? "-",
             'status': statusMap['label'],
             'diff': statusMap['diff'],
             'emp': emp
           });
        }
      }

      final List additional = emp['additionalCerts'] ?? [];
      for (var cert in additional) {
        final statusMap = _getDocStatus(cert['expiryDate'], no: cert['number'], imgs: cert['imageUrls']);
        if (statusMap['label'] != "WAŻNE") {
          items.add({
            'name': "${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}",
            'type': cert['name'] ?? "Dodatkowe uprawnienie",
            'date': cert['expiryDate'] ?? "-",
            'status': statusMap['label'],
            'diff': statusMap['diff'],
            'emp': emp
          });
        }
      }
    }

    items.sort((a, b) {
      final order = {"PO TERMINIE": 0, "BRAK DATY": 1, "DO 30 DNI": 2, "DO 90 DNI": 3, "BRAK DOK.": 4, "WAŻNE": 5};
      int sComp = (order[a['status']] ?? 9).compareTo(order[b['status']] ?? 9);
      if (sComp != 0) return sComp;
      return (a['diff'] as int).compareTo(b['diff'] as int);
    });

    return _sectionPanel(
      title: "TERMINY I DOKUMENTY",
      icon: Icons.assignment_late_rounded,
      child: items.isEmpty 
        ? const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("Wszystkie dokumenty są ważne 🟢", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))))
        : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.take(20).length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = items[i];
              final status = item['status'];
              final color = _getStatusColor(status);
              final diff = item['diff'] as int;
              
              String diffText = "";
              if (status == "PO TERMINIE") {
                diffText = "Po terminie: ${diff.abs()} dni";
              } else if (status == "BRAK DATY") {
                diffText = "Wymaga uzupełnienia daty";
              } else if (status == "BRAK DOK.") {
                diffText = "Nie dostarczono";
              } else if (status == "WAŻNE") {
                diffText = "Ważne jeszcze $diff dni";
              } else {
                diffText = "Wygasa za: $diff dni";
              }

              return ListTile(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HrEmployeeDetailScreen(employee: item['emp'], initialTab: 3))),
                leading: Container(
                  width: 4, height: 40,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 4)]),
                ),
                title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['type'], style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                    Text(diffText, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(item['date'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    Icon(Icons.chevron_right_rounded, size: 16, color: color.withOpacity(0.5)),
                  ],
                ),
              );
            },
          ),
    );
  }

  Widget _sectionPanel({required String title, required IconData icon, required Widget child, List<Widget>? actions}) {
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
                Expanded(child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 14))),
                if (actions != null) ...actions,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
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
                Text("PULPIT KADROWY", style: GoogleFonts.montserrat(color: Colors.blue.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5))
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _sidebarItem(Icons.dashboard_rounded, "Pulpit Sterowniczy", true, onTap: () {}),
                _sidebarItem(Icons.grid_view_rounded, "Widok kafelkowy", false, onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(userEmail: widget.userEmail, ignoreRedirect: true)))),
                if (_isAdmin || _userPermissions['kadry'] == true)
                  _sidebarItem(Icons.people_alt_rounded, "Kadry i Pracownicy", false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()))),
                _sidebarItem(Icons.calendar_today_rounded, "Lista Obecności", false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen(userEmail: widget.userEmail, currentUserEmail: widget.userEmail)))),
                _sidebarItem(Icons.forum_rounded, "Czat", false, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(currentUserEmail: widget.userEmail, displayName: _displayName, employeesOnly: true)))),
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
}
