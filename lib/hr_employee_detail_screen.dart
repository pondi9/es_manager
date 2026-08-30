import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'services/attendance_service.dart';
import 'core/app_utils.dart';
import 'core/app_theme.dart';
import 'widgets/es_modal.dart';
import 'core/app_constants.dart';

class HrEmployeeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> employee;
  final int initialTab;
  const HrEmployeeDetailScreen({super.key, required this.employee, this.initialTab = 0});

  @override
  State<HrEmployeeDetailScreen> createState() => _HrEmployeeDetailScreenState();
}

class _HrEmployeeDetailScreenState extends State<HrEmployeeDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AttendanceService _attendanceService = AttendanceService();
  
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  
  Map<String, dynamic> _attendanceData = {};
  bool _isLoadingAttendance = true;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _employeeSub;
  Map<String, dynamic> _currentEmployeeData = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
    _currentEmployeeData = widget.employee;
    _initStreams();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _attendanceSub?.cancel();
    _employeeSub?.cancel();
    super.dispose();
  }

  void _initStreams() {
    final email = (_currentEmployeeData['email'] ?? _currentEmployeeData['id'] ?? '').toString().toLowerCase().trim();
    
    _employeeSub = FirebaseFirestore.instance.collection('employees').doc(email).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        setState(() {
          _currentEmployeeData = snap.data()!;
          _currentEmployeeData['id'] = snap.id;
        });
      }
    });

    _attendanceSub = FirebaseFirestore.instance.collection('attendance').doc(email).snapshots().listen((snap) {
      if (mounted) {
        setState(() {
          if (snap.exists) {
            _attendanceData = (snap.data() as Map<String, dynamic>)['data'] ?? {};
          } else {
            _attendanceData = {};
          }
          _isLoadingAttendance = false;
        });
      }
    });
  }

  Future<void> _updateDocField(String field, dynamic value) async {
    final id = _currentEmployeeData['id'];
    await FirebaseFirestore.instance.collection('employees').doc(id).update({field: value});
  }

  Future<void> _pickAndUpload(String type, {int? certIdx}) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;

    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    
    try {
      final bytes = await image.readAsBytes();
      final String ext = image.name.split('.').last;
      final String fileName = "${_currentEmployeeData['id']}_${type}_${DateTime.now().millisecondsSinceEpoch}.$ext";
      final ref = FirebaseStorage.instance.ref().child('employee_docs/$fileName');
      
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      if (mounted) Navigator.pop(context);
      
      if (certIdx != null) {
        List certs = List.from(_currentEmployeeData['additionalCerts'] ?? []);
        if (certs[certIdx]['imageUrls'] == null) certs[certIdx]['imageUrls'] = [];
        (certs[certIdx]['imageUrls'] as List).add(url);
        await _updateDocField('additionalCerts', certs);
      } else {
        final String listKey = "${type}Imgs";
        List imgs = List.from(_currentEmployeeData[listKey] ?? []);
        imgs.add(url);
        await _updateDocField(listKey, imgs);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Błąd: $e"), backgroundColor: Colors.red));
    }
  }

  void _deleteImage(String type, int imgIdx, {int? certIdx}) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("USUŃ SKAN?"),
        content: const Text("Czy na pewno chcesz usunąć to zdjęcie?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ANULUJ")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("USUŃ")),
        ],
      ),
    );

    if (confirm == true) {
      if (certIdx != null) {
        List certs = List.from(_currentEmployeeData['additionalCerts'] ?? []);
        (certs[certIdx]['imageUrls'] as List).removeAt(imgIdx);
        await _updateDocField('additionalCerts', certs);
      } else {
        final String listKey = "${type}Imgs";
        List imgs = List.from(_currentEmployeeData[listKey] ?? []);
        imgs.removeAt(imgIdx);
        await _updateDocField(listKey, imgs);
      }
    }
  }

  Future<void> _printAttendance() async {
    final pdf = pw.Document();
    final ttf = await PdfGoogleFonts.robotoRegular();
    final ttfBold = await PdfGoogleFonts.robotoBold();
    final logoBytes = (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
    
    final int year = _selectedYear;
    final int month = _selectedMonth;
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    
    final String name = "${_currentEmployeeData['firstName'] ?? ''} ${_currentEmployeeData['lastName'] ?? ''}".trim();
    final polishMonths = ["STYCZEŃ", "LUTY", "MARZEC", "KWIECIEŃ", "MAJ", "CZERWIEC", "LIPIEC", "SIERPIEŃ", "WRZESIEŃ", "PAŹDZIERNIK", "LISTOPAD", "GRUDZIEŃ"];
    final polishDays = ["nd", "pn", "wt", "śr", "cz", "pt", "so"];
    final monthLabel = "${polishMonths[month - 1]} $year";
    final monthPrefix = "$year-${month.toString().padLeft(2, '0')}";
    
    final approval = _attendanceData['approval_$monthPrefix'] ?? {};
    final mainSignature = approval['signature'] != null ? base64Decode(approval['signature']) : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20), 
        theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        build: (pw.Context context) {
          return [
            pw.Column(
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
                  pw.Text("Pracownik: $name", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
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
                      final dData = _attendanceData[dKey] ?? {};
                      
                      final h = dData['type'] == 'URLOP' ? 8.0 : _attendanceService.calculateHours(dData['in'], dData['out']);
                      final sigD = (dData['signature'] != null && dData['signature'].toString().isNotEmpty) ? base64Decode(dData['signature']) : null;
                      
                      bool isW = dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
                      PdfColor bg = isW ? PdfColors.grey100 : PdfColors.white;
                      if (dData['type'] == 'URLOP') bg = PdfColors.blue50;
                      if (dData['type'] == 'L4') bg = PdfColors.red50;

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
                  pw.Text("SUMA GODZIN W MIESIĄCU: ${_calculateMonthlyTotal(monthPrefix).toStringAsFixed(1)} h", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  if (mainSignature != null) pw.Column(children: [
                    pw.Container(width: 120, height: 40, decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey200)), child: pw.Image(pw.MemoryImage(mainSignature), fit: pw.BoxFit.contain)),
                    pw.Text("PODPIS ZATWIERDZAJĄCY", style: const pw.TextStyle(fontSize: 6)),
                  ]),
                ]),
              ],
            )
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: "Arkusz_Obecnosci_${name}_$monthPrefix.pdf");
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

  double _calculateMonthlyTotal(String prefix) {
    double total = 0;
    _attendanceData.forEach((key, value) {
      if (key.startsWith(prefix) && !key.startsWith('approval')) {
        if (value['type'] == 'URLOP') total += 8.0;
        else if (value['type'] == 'PRACA') total += _attendanceService.calculateHours(value['in'], value['out']);
      }
    });
    return total;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "WAŻNE": return Colors.green;
      case "DO 90 DNI": return Colors.yellow[700]!;
      case "DO 30 DNI": return Colors.orange;
      case "PO TERMINIE": return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final String name = "${_currentEmployeeData['firstName'] ?? ''} ${_currentEmployeeData['lastName'] ?? ''}".trim();
    final String position = _currentEmployeeData['position'] ?? 'Pracownik';
    final bool isActive = _currentEmployeeData['isActive'] ?? false;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        title: Text(name.isEmpty ? "Szczegóły" : name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.blue,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: "PODSUMOWANIE"),
            Tab(text: "OBECNOŚĆ"),
            Tab(text: "URLOPY"),
            Tab(text: "DOKUMENTY I UPRAWNIENIA"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSummaryTab(theme, isDark),
          _buildAttendanceTab(theme, isDark),
          _buildVacationTab(theme, isDark),
          _buildDocumentsTab(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildSummaryTab(ThemeData theme, bool isDark) {
    final name = "${_currentEmployeeData['firstName'] ?? ''} ${_currentEmployeeData['lastName'] ?? ''}".trim();
    final initials = name.isEmpty ? "?" : name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase();
    
    double totalHoursYear = 0;
    int vacationUsedYear = 0;
    final currentYearPrefix = "${DateTime.now().year}-";
    
    _attendanceData.forEach((date, val) {
      if (date.startsWith(currentYearPrefix)) {
        if (val['type'] == 'PRACA' || val['type'] == 'DELEGACJA') {
          totalHoursYear += _attendanceService.calculateHours(val['in'], val['out']);
        } else if (val['type'] == 'URLOP') {
          vacationUsedYear++;
        }
      }
    });

    final int vacationLimit = _currentEmployeeData['vacationLimit'] ?? 26;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blue.withOpacity(0.1),
                  child: Text(initials, style: GoogleFonts.montserrat(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue)),
                ),
                const SizedBox(height: 16),
                Text(name, style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.w900)),
                Text(_currentEmployeeData['position'] ?? "Stanowisko nieokreślone", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_currentEmployeeData['isActive'] ?? false) ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    (_currentEmployeeData['isActive'] ?? false) ? "AKTYWNY" : "NIEAKTYWNY",
                    style: TextStyle(
                      color: (_currentEmployeeData['isActive'] ?? false) ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _infoCard("GODZINY (${DateTime.now().year})", "${totalHoursYear.toInt()}h", Icons.access_time_rounded, Colors.blue, theme)),
              const SizedBox(width: 16),
              Expanded(child: _infoCard("URLOPY (${DateTime.now().year})", "$vacationUsedYear / $vacationLimit", Icons.beach_access_rounded, Colors.orange, theme)),
            ],
          ),
          const SizedBox(height: 24),
          _sectionPanel(
            title: "DANE KONTAKTOWE",
            icon: Icons.contact_mail_rounded,
            theme: theme,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _detailRow("Email", _currentEmployeeData['email'] ?? "Brak danych", Icons.email_outlined, theme),
                  const Divider(height: 24),
                  _detailRow("Telefon", _currentEmployeeData['phone'] ?? "Brak danych", Icons.phone_outlined, theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTab(ThemeData theme, bool isDark) {
    final months = List.generate(12, (i) => i + 1);
    final years = [2024, 2025, 2026];
    final monthPrefix = "$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}";
    
    final List<Map<String, dynamic>> monthDays = [];
    _attendanceData.forEach((date, val) {
      if (date.startsWith(monthPrefix) && (val['type'] == 'PRACA' || val['type'] == 'DELEGACJA' || val['type'] == 'URLOP' || val['type'] == 'L4')) {
        monthDays.add({...val, 'date': date});
      }
    });
    
    monthDays.sort((a, b) => b['date'].compareTo(a['date']));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          color: theme.cardTheme.color,
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedMonth,
                  decoration: const InputDecoration(labelText: "Miesiąc", border: OutlineInputBorder()),
                  items: months.map((m) => DropdownMenuItem(value: m, child: Text(DateFormat('MMMM', 'pl_PL').format(DateTime(2024, m))))).toList(),
                  onChanged: (v) => setState(() => _selectedMonth = v!),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedYear,
                  decoration: const InputDecoration(labelText: "Rok", border: OutlineInputBorder()),
                  items: years.map((y) => DropdownMenuItem(value: y, child: Text("$y"))).toList(),
                  onChanged: (v) => setState(() => _selectedYear = v!),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: _printAttendance,
                icon: const Icon(Icons.print_rounded, color: Colors.blue),
                tooltip: "Drukuj listę obecności",
              ),
            ],
          ),
        ),
        if (_attendanceData['approval_${_selectedYear}-${_selectedMonth.toString().padLeft(2, '0')}']?['signature'] != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            color: Colors.green.withOpacity(0.05),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Text("MIESIĄC ZATWIERDZONY PODPISEM", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
                const Spacer(),
                Container(
                  width: 80, height: 30,
                  decoration: BoxDecoration(border: Border.all(color: Colors.green.withOpacity(0.2)), borderRadius: BorderRadius.circular(4)),
                  child: Image.memory(base64Decode(_attendanceData['approval_${_selectedYear}-${_selectedMonth.toString().padLeft(2, '0')}']['signature']), fit: BoxFit.contain),
                ),
              ],
            ),
          ),
        Expanded(
          child: _isLoadingAttendance 
            ? const Center(child: CircularProgressIndicator())
            : monthDays.isEmpty 
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 64, color: Colors.grey.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    const Text("Brak wpisów w tym miesiącu", style: TextStyle(color: Colors.grey)),
                  ],
                ))
              : ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: monthDays.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final day = monthDays[i];
                    final date = DateFormat('dd.MM.yyyy').format(DateTime.parse(day['date']));
                    final hours = _attendanceService.calculateHours(day['in'], day['out']);
                    final String? sigBase64 = day['signature'];
                    
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.work_outline_rounded, color: Colors.blue, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(day['orderName'] ?? day['order'] ?? "Brak zlecenia", style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                                if (day['notes'] != null && day['notes'].toString().isNotEmpty)
                                  Text("Uwagi: ${day['notes']}", style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
                              ],
                            ),
                          ),
                          if (sigBase64 != null && sigBase64.isNotEmpty)
                            Container(
                              width: 60, height: 40,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.2)), borderRadius: BorderRadius.circular(8)),
                              child: Image.memory(base64Decode(sigBase64), fit: BoxFit.contain),
                            ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(day['type'] == 'URLOP' ? "URLOP" : (day['type'] == 'L4' ? 'L4' : "${hours.toStringAsFixed(1)}h"), style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, color: day['type'] == 'URLOP' ? Colors.orange : (day['type'] == 'L4' ? Colors.red : Colors.blue))),
                              if (day['type'] != 'URLOP' && day['type'] != 'L4') Text("${day['in']} - ${day['out']}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildVacationTab(ThemeData theme, bool isDark) {
    final currentYear = DateTime.now().year;
    final currentYearPrefix = "$currentYear-";
    final List<Map<String, dynamic>> vacations = [];
    
    _attendanceData.forEach((date, val) {
      if (date.startsWith(currentYearPrefix) && val['type'] == 'URLOP') {
        vacations.add({...val, 'date': date});
      }
    });
    
    vacations.sort((a, b) => b['date'].compareTo(a['date']));
    
    final int vacationLimit = _currentEmployeeData['vacationLimit'] ?? 26;
    final used = vacations.length;
    final progress = (used / vacationLimit).clamp(0.0, 1.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionPanel(
            title: "LIMIT URLOPOWY $currentYear",
            icon: Icons.beach_access_rounded,
            theme: theme,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Wykorzystano: $used dni", style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text("Pozostało: ${vacationLimit - used} dni", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 12,
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text("Limit roczny: $vacationLimit dni", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text("LISTA WPISÓW", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 12),
          if (vacations.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("Brak wpisów urlopowych", style: TextStyle(color: Colors.grey))))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: vacations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final v = vacations[i];
                final date = DateFormat('dd.MM.yyyy').format(DateTime.parse(v['date']));
                return ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.dividerTheme.color ?? Colors.white10)),
                  tileColor: theme.cardTheme.color,
                  leading: const Icon(Icons.event_available_rounded, color: Colors.orange),
                  title: Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("Dzień urlopu"),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDocRow(String label, String? date, List<String> imgUrls, IconData icon, ThemeData theme, {String? docNo, String? fieldKey, String? noKey, int? certIdx, String? category, String? scope}) {
    final statusMap = _getDocStatus(date);
    final status = statusMap['label'];
    final color = _getStatusColor(status);
    
    // Logic for exclusion
    final Map<String, dynamic> excludedDocs = Map<String, dynamic>.from(_currentEmployeeData['excludedDocs'] ?? {});
    final bool isExcluded = fieldKey != null && excludedDocs[fieldKey] == true;
    final bool isIndefinite = date == "NIEOKREŚLONY";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isExcluded ? Colors.grey.withOpacity(0.1) : (theme.dividerTheme.color ?? Colors.white10)),
      ),
      child: Opacity(
        opacity: isExcluded ? 0.4 : 1.0,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, color: isExcluded ? Colors.grey : (isIndefinite ? Colors.green : color), size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (isExcluded)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                              child: const Text("WYKLUCZONE", style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.grey)),
                            ),
                        ],
                      ),
                      if (fieldKey == 'sep' && !isExcluded) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _getSepFullDescription(_currentEmployeeData),
                            style: TextStyle(fontSize: 10, color: theme.colorScheme.primary.withOpacity(0.8), fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                      
                      // Numer i Kategoria (Edytowalne)
                      if (!isExcluded && (noKey != null || certIdx != null))
                        InkWell(
                          onTap: () => _editDocNumber(label, noKey, certIdx),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text("Nr: ${docNo ?? 'brak'}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.edit, size: 10, color: Colors.blue),
                                ],
                              ),
                              if (fieldKey == 'sep') ...[
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text("Kat: ${category ?? 'brak'}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.edit, size: 10, color: Colors.blue),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text("Zakres: ${scope ?? 'brak'}", style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.edit, size: 10, color: Colors.blue),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                      // Data ważności (Edytowalna)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: isExcluded ? null : () => _editDocDate(label, fieldKey == 'contractStart' ? 'contractStart' : (fieldKey == 'contract' ? 'contractEnd' : (fieldKey == 'medical' ? 'medicalEnd' : (fieldKey == 'bhp' ? 'bhpDate' : (fieldKey == 'sep' ? 'sepDate' : (fieldKey == 'udt' ? 'udtDate' : 'expiryDate'))))), date, certIdx),
                            child: Row(
                              children: [
                                Text(
                                  isIndefinite ? "CZAS NIEOKREŚLONY" : ((date == null || date.isEmpty) ? "USTAW DATĘ" : "Ważne do: $date"), 
                                  style: TextStyle(
                                    fontSize: 12, 
                                    fontWeight: (date == null || date.isEmpty || isIndefinite) ? FontWeight.bold : FontWeight.bold,
                                    color: isIndefinite ? Colors.green : ((date == null || date.isEmpty) ? Colors.orange : theme.colorScheme.onSurface.withOpacity(0.6))
                                  )
                                ),
                                if (!isExcluded && !isIndefinite) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.calendar_today, size: 12, color: Colors.blue),
                                ]
                              ],
                            ),
                          ),
                          if (!isExcluded && fieldKey == 'contract' && !isIndefinite)
                            IconButton(
                              icon: const Icon(Icons.all_inclusive_rounded, size: 16, color: Colors.green),
                              onPressed: () => _updateDocField('contractEnd', "NIEOKREŚLONY"),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: "Ustaw na czas nieokreślony",
                            ),
                          if (!isExcluded && date != null && date.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            if (!isIndefinite) _buildDaysRemaining(date),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.red),
                              onPressed: () => _editDocDate(label, fieldKey == 'contractStart' ? 'contractStart' : (fieldKey == 'contract' ? 'contractEnd' : (fieldKey == 'medical' ? 'medicalEnd' : (fieldKey == 'bhp' ? 'bhpDate' : (fieldKey == 'sep' ? 'sepDate' : (fieldKey == 'udt' ? 'udtDate' : 'expiryDate'))))), "", certIdx),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: "Wyczyść datę",
                            ),
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    if (fieldKey != null && fieldKey != 'contractStart')
                      IconButton(
                        icon: Icon(isExcluded ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: isExcluded ? Colors.orange : Colors.grey.withOpacity(0.3)),
                        onPressed: () => _toggleDocExclusion(fieldKey),
                        tooltip: isExcluded ? "Przywróć sprawdzanie" : "Wyklucz ze sprawdzania",
                      ),
                    if (!isExcluded) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text(status, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                      if (fieldKey != null && fieldKey != 'contractStart')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: IconButton(
                            icon: const Icon(Icons.add_a_photo_rounded, size: 20, color: Colors.blue),
                            onPressed: () => _pickAndUpload(fieldKey, certIdx: certIdx),
                            tooltip: "Dodaj skan",
                          ),
                        ),
                    ],
                  ],
                ),
              ],
            ),
            if (!isExcluded && imgUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: imgUrls.length,
                  itemBuilder: (ctx, idx) => Stack(
                    children: [
                      InkWell(
                        onTap: () => _showImagePreview(imgUrls[idx]),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(image: NetworkImage(imgUrls[idx]), fit: BoxFit.cover),
                            border: Border.all(color: Colors.white10),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -2, right: 2,
                        child: InkWell(
                          onTap: () => _deleteImage(fieldKey ?? 'cert', idx, certIdx: certIdx),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 10, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleDocExclusion(String fieldKey) async {
    final Map<String, dynamic> excludedDocs = Map<String, dynamic>.from(_currentEmployeeData['excludedDocs'] ?? {});
    final bool current = excludedDocs[fieldKey] ?? false;
    excludedDocs[fieldKey] = !current;
    
    await _updateDocField('excludedDocs', excludedDocs);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(current ? "Przywrócono sprawdzanie dokumentu." : "Wykluczono dokument ze sprawdzania."),
      backgroundColor: current ? Colors.green : Colors.orange,
    ));
  }

  void _editDocNumber(String label, String? key, int? certIdx) {
    final bool isSep = key == 'sepNo';
    final ctrl = TextEditingController(text: certIdx != null ? _currentEmployeeData['additionalCerts'][certIdx]['number'] : _currentEmployeeData[key]);
    final scopeCtrl = TextEditingController(text: _currentEmployeeData['sepScope'] ?? "");
    String? selGrp = _currentEmployeeData['sepGroup'];
    String? selRole = _currentEmployeeData['sepRole'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) => AlertDialog(
          title: Text("EDYTUJ DANE: $label"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: ctrl, decoration: const InputDecoration(labelText: "Numer dokumentu")),
                if (isSep) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selGrp,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: "Grupa"),
                          items: [
                            DropdownMenuItem(value: 'G1', child: FittedBox(fit: BoxFit.scaleDown, child: Text("G1 - Elektryczne"))),
                            DropdownMenuItem(value: 'G2', child: FittedBox(fit: BoxFit.scaleDown, child: Text("G2 - Cieplne"))),
                            DropdownMenuItem(value: 'G3', child: FittedBox(fit: BoxFit.scaleDown, child: Text("G3 - Gazowe"))),
                          ],
                          onChanged: (v) => setDS(() => selGrp = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selRole,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: "Rola"),
                          items: [
                            DropdownMenuItem(value: 'E', child: Text("E - Eksploatacja")),
                            DropdownMenuItem(value: 'D', child: Text("D - Dozór")),
                            DropdownMenuItem(value: 'E+D', child: Text("E+D")),
                          ],
                          onChanged: (v) => setDS(() => selRole = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: scopeCtrl, decoration: const InputDecoration(labelText: "Zakres (np. urządzenia do 1kV)", hintText: "np. urządzenia do 1kV")),
                ]
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANULUJ")),
            ElevatedButton(onPressed: () async {
              if (certIdx != null) {
                List certs = List.from(_currentEmployeeData['additionalCerts'] ?? []);
                certs[certIdx]['number'] = ctrl.text.trim();
                await _updateDocField('additionalCerts', certs);
              } else {
                final Map<String, dynamic> updates = {key!: ctrl.text.trim()};
                if (isSep) {
                  updates['sepGroup'] = selGrp;
                  updates['sepRole'] = selRole;
                  updates['sepScope'] = scopeCtrl.text.trim();
                  updates['sepCategory'] = "${selGrp ?? ''} ${selRole ?? ''}".trim();
                }
                await FirebaseFirestore.instance.collection('employees').doc(_currentEmployeeData['id']).update(updates);
              }
              Navigator.pop(ctx);
            }, child: const Text("ZAPISZ")),
          ],
        ),
      ),
    );
  }

  void _editDocDate(String label, String? key, String? current, int? certIdx) async {
    if (current == "") {
      if (certIdx != null) {
        List certs = List.from(_currentEmployeeData['additionalCerts'] ?? []);
        certs[certIdx]['expiryDate'] = "";
        await _updateDocField('additionalCerts', certs);
      } else {
        await _updateDocField(key!, "");
      }
      return;
    }
    
    final DateTime initial = current != null && current.isNotEmpty ? DateFormat('dd.MM.yyyy').parse(current) : DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (picked != null) {
      final String formatted = DateFormat('dd.MM.yyyy').format(picked);
      if (certIdx != null) {
        List certs = List.from(_currentEmployeeData['additionalCerts'] ?? []);
        certs[certIdx]['expiryDate'] = formatted;
        await _updateDocField('additionalCerts', certs);
      } else {
        await _updateDocField(key!, formatted);
      }
    }
  }

  Widget _buildDocumentsTab(ThemeData theme, bool isDark) {
    final List<Map<String, dynamic>> mainDocs = [
      {'label': 'Umowa (START)', 'key': 'contractStart', 'icon': Icons.history_edu_rounded, 'field': 'contractStart'},
      {'label': 'Umowa (KONIEC)', 'key': 'contractEnd', 'imgKey': 'contractImgs', 'noKey': 'contractNo', 'icon': Icons.description_outlined, 'field': 'contract'},
      {'label': 'Badania lekarskie', 'key': 'medicalEnd', 'imgKey': 'medicalImgs', 'noKey': 'medicalNo', 'icon': Icons.medical_services_outlined, 'field': 'medical'},
      {'label': 'Szkolenie BHP', 'key': 'bhpDate', 'imgKey': 'bhpImgs', 'noKey': 'bhpNo', 'icon': Icons.security_rounded, 'field': 'bhp'},
      {'label': 'Uprawnienia SEP', 'key': 'sepDate', 'imgKey': 'sepImgs', 'noKey': 'sepNo', 'icon': Icons.flash_on_rounded, 'field': 'sep'},
      {'label': 'Uprawnienia UDT', 'key': 'udtDate', 'imgKey': 'udtImgs', 'noKey': 'udtNo', 'icon': Icons.settings_input_component_rounded, 'field': 'udt'},
    ];

    final List<dynamic> additionalCerts = _currentEmployeeData['additionalCerts'] ?? [];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text("DOKUMENTY PODSTAWOWE", style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.5)),
        const SizedBox(height: 12),
        ...mainDocs.map((doc) => _buildDocRow(
          doc['label'] as String, 
          _currentEmployeeData[doc['key']] as String?, 
          _toList(_currentEmployeeData[doc['imgKey']]),
          doc['icon'] as IconData, 
          theme,
          docNo: _currentEmployeeData[doc['noKey']],
          fieldKey: doc['field'],
          noKey: doc['noKey'],
          category: _getSepFullLabel(_currentEmployeeData),
          scope: _currentEmployeeData['sepScope'],
        )),
        
        if (additionalCerts.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text("DODATKOWE UPRAWNIENIA", style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          ...List.generate(additionalCerts.length, (i) {
            final cert = additionalCerts[i];
            return _buildDocRow(
              cert['name'] ?? 'Inne uprawnienie', 
              cert['expiryDate'] as String?, 
              _toList(cert['imageUrls']),
              Icons.verified_user_rounded, 
              theme,
              docNo: cert['number'],
              certIdx: i
            );
          }),
        ],
      ],
    );
  }

  List<String> _toList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    return [val.toString()];
  }

  String _getSepFullLabel(Map<String, dynamic> emp) {
    final String grp = emp['sepGroup'] ?? "";
    final String role = emp['sepRole'] ?? "";
    if (grp.isEmpty && role.isEmpty) return emp['sepCategory'] ?? "";
    return "$grp - $role";
  }

  String _getSepFullDescription(Map<String, dynamic> emp) {
    final String grp = emp['sepGroup'] ?? "";
    if (grp == 'G1') return "Eksploatacja urządzeń, instalacji i sieci elektroenergetycznych";
    if (grp == 'G2') return "Urządzenia wytwarzające, przetwarzające, przesyłające i zużywające ciepło";
    if (grp == 'G3') return "Urządzenia, instalacje i sieci gazowe";
    return "";
  }

  Map<String, dynamic> _getDocStatus(String? dateStr) {
    if (dateStr == "NIEOKREŚLONY") return {'label': "WAŻNE", 'diff': 9999};
    if (dateStr == null || dateStr.isEmpty) return {'label': "BRAK", 'diff': 0};
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

  void _showImagePreview(String url) {
    showDialog(context: context, builder: (c) => Dialog(
      backgroundColor: Colors.transparent,
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(url, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator())),
            ),
          ),
          IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 32), onPressed: () => Navigator.pop(c)),
        ],
      ),
    ));
  }

  Widget _buildDaysRemaining(String dateStr) {
    try {
      final expiry = DateFormat('dd.MM.yyyy').parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final diff = expiry.difference(today).inDays;

      String text = "";
      Color col = Colors.green;

      if (diff < 0) {
        text = "PO TERMINIE: ${diff.abs()} DNI";
        col = Colors.red;
      } else if (diff == 0) {
        text = "WYGASA DZISIAJ";
        col = Colors.orange;
      } else {
        text = "ZOSTAŁO: $diff DNI";
        if (diff <= 30) col = Colors.orange;
        else if (diff <= 90) col = Colors.yellow[800]!;
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: col.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: col)),
      );
    } catch (_) {
      return const SizedBox();
    }
  }

  Widget _infoCard(String label, String value, IconData icon, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, IconData icon, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blue),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.bold)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionPanel({required String title, required IconData icon, required Widget child, required ThemeData theme}) {
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
}
