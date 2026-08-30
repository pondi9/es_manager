import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'attendance_screen.dart';
import 'services/cloud_sync_service.dart';

class AccountantReportScreen extends StatefulWidget {
  const AccountantReportScreen({super.key});

  @override
  State<AccountantReportScreen> createState() => _AccountantReportScreenState();
}

class _AccountantReportScreenState extends State<AccountantReportScreen> {
  DateTime _selectedDate = DateTime.now();
  List<dynamic> _employees = [];
  Map<String, dynamic> _allAttendance = {};
  bool _isLoading = true;
  final Color primaryColor = const Color(0xFF00796B);

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    
    try {
      await CloudSyncService().downloadAllAttendanceForAdmin().timeout(const Duration(seconds: 15));
      await CloudSyncService().downloadEmployees().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("Księgowość: Błąd synchronizacji: $e");
    }

    final String? empData = prefs.getString('user_permissions');
    if (empData != null) {
      try {
        final List<dynamic> all = json.decode(empData);
        _employees = all.where((e) {
          if (e == null || e is! Map) return false;
          final String email = (e['email'] ?? '').toString().toLowerCase();
          final String pos = (e['position'] ?? '').toString().toUpperCase();
          final String firstName = (e['firstName'] ?? '').toString().toUpperCase();
          final String lastName = (e['lastName'] ?? '').toString().toUpperCase();
          final bool isActive = e['isActive'] == true;
          
          final bool isSpecial = email == 'admin' || email == 'ksiegowa' || email == 'b' || (firstName == 'B' && lastName == 'B');
          final bool isOffice = pos.contains('KIEROWNIK') || pos.contains('KSIĘGOW') || pos.contains('BIURO');
          
          return isActive && !isSpecial && !isOffice && email.isNotEmpty;
        }).toList();
        
        _employees.sort((a, b) => (a['lastName'] ?? '').toString().compareTo((b['lastName'] ?? '').toString()));
      } catch (_) {}
    }

    _allAttendance.clear();
    for (var emp in _employees) {
      if (emp == null || emp is! Map) continue;
      final String email = (emp['email'] ?? '').toString();
      if (email.isEmpty) continue;
      final String? data = prefs.getString('attendance_data_$email');
      if (data != null) {
        try {
          _allAttendance[email] = json.decode(data);
        } catch (_) { _allAttendance[email] = {}; }
      } else {
        _allAttendance[email] = {};
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  double _getMonthlyHours(String email) {
    double total = 0;
    final dynamic rawData = _allAttendance[email];
    if (rawData == null || rawData is! Map) return 0;
    
    rawData.forEach((key, val) {
      try {
        final date = DateTime.parse(key);
        if (date.month == _selectedDate.month && date.year == _selectedDate.year) {
          if (val != null && val is Map) {
            total += _calcDayH(val);
          }
        }
      } catch(_) {}
    });
    return total;
  }

  double _calcDayH(Map<dynamic, dynamic>? dayData) {
    if (dayData == null) return 0.0;
    try {
      final String type = (dayData['type'] ?? 'PRACA').toString();
      if (type == 'URLOP') return 8.0;
      if (type == 'ŚWIĘTO') return 0.0;
      
      final String? s = dayData['in']?.toString();
      final String? e = dayData['out']?.toString();
      if (s == null || e == null || s.isEmpty || e.isEmpty) return 0;
      
      final List<String> start = s.split(':'); 
      final List<String> end = e.split(':');
      if (start.length < 2 || end.length < 2) return 0;
      
      final int sMin = (int.tryParse(start[0]) ?? 0) * 60 + (int.tryParse(start[1]) ?? 0);
      final int eMin = (int.tryParse(end[0]) ?? 0) * 60 + (int.tryParse(end[1]) ?? 0);
      return eMin > sMin ? (eMin - sMin) / 60.0 : 0;
    } catch (_) { return 0; }
  }

  List<String> _getVacationDates(String email) {
    final List<String> dates = [];
    final dynamic rawData = _allAttendance[email];
    if (rawData == null || rawData is! Map) return [];
    
    rawData.forEach((key, val) {
      if (val != null && val is Map && (val['type'] ?? '').toString() == 'URLOP') {
        try {
          final d = DateTime.parse(key);
          if (d.month == _selectedDate.month && d.year == _selectedDate.year) {
            dates.add(DateFormat('dd.MM').format(d));
          }
        } catch(_) {}
      }
    });
    dates.sort();
    return dates;
  }

  Future<pw.Document> _generateSummaryPdfDoc() async {
    final pdf = pw.Document();
    pw.Font font = pw.Font.helvetica();
    pw.Font fontBold = pw.Font.helveticaBold();
    try {
      font = await PdfGoogleFonts.notoSansRegular();
      fontBold = await PdfGoogleFonts.notoSansBold();
    } catch (_) {}

    final monthName = DateFormat('MMMM yyyy', 'pl_PL').format(_selectedDate).toUpperCase();
    final List<dynamic> activeEmployees = _employees.where((e) => e != null && e is Map).toList();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('ZBIORCZY RAPORT CZASU PRACY', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text(monthName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey700)),
            ]
          )
        ),
        pw.SizedBox(height: 20),
        if (activeEmployees.isEmpty)
          pw.Center(child: pw.Text('Brak danych'))
        else
          pw.TableHelper.fromTextArray(
            headers: ['Lp.', 'Pracownik', 'Godziny', 'Urlopy'],
            data: List<List<String>>.generate(activeEmployees.length, (index) {
              final Map<dynamic, dynamic> e = activeEmployees[index];
              final String email = (e['email'] ?? '').toString();
              final String name = "${e['firstName'] ?? ''} ${e['lastName'] ?? ''}".trim();
              final String displayName = name.isNotEmpty ? name : email;
              return [
                (index + 1).toString(),
                displayName,
                "${_getMonthlyHours(email).toStringAsFixed(1)} h",
                _getVacationDates(email).join(', '),
              ];
            }),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
            cellStyle: const pw.TextStyle(fontSize: 10),
            columnWidths: { 0: const pw.FixedColumnWidth(30), 1: const pw.FlexColumnWidth(2), 2: const pw.FixedColumnWidth(60), 3: const pw.FlexColumnWidth(3) },
            cellAlignment: pw.Alignment.centerLeft,
          ),
      ],
    ));
    return pdf;
  }

  Future<pw.Document> _generateIndividualPdfDoc(Map<dynamic, dynamic> emp) async {
    final String email = (emp['email'] ?? '').toString();
    final String firstName = (emp['firstName'] ?? '').toString();
    final String lastName = (emp['lastName'] ?? '').toString();
    final String displayName = (firstName.isNotEmpty || lastName.isNotEmpty) ? "$firstName $lastName".trim() : email;
    
    final pdf = pw.Document();
    pw.Font font = pw.Font.helvetica();
    pw.Font fontBold = pw.Font.helveticaBold();
    try {
      font = await PdfGoogleFonts.notoSansRegular();
      fontBold = await PdfGoogleFonts.notoSansBold();
    } catch (_) {}
    
    pw.MemoryImage? logoImage;
    try {
      final ByteData bytes = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    final String polishMonthName = DateFormat('MMMM yyyy', 'pl_PL').format(_selectedDate);
    final int daysCount = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    
    Map<dynamic, dynamic> attData = {};
    final dynamic raw = _allAttendance[email];
    if (raw != null && raw is Map) attData = raw;

    double monthlyTotal = 0;
    int vacCount = 0;
    final List<pw.TableRow> rows = [];

    // Dodaj nagłówek tabeli
    rows.add(pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Data', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white), textAlign: pw.TextAlign.center)),
        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Wej./Typ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white), textAlign: pw.TextAlign.center)),
        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Wyj.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white), textAlign: pw.TextAlign.center)),
        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Suma', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white), textAlign: pw.TextAlign.center)),
        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Komentarz / Budowa', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white))),
        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Podpis', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white), textAlign: pw.TextAlign.center)),
      ],
    ));

    for (int i = 1; i <= daysCount; i++) {
      final currentDay = DateTime(_selectedDate.year, _selectedDate.month, i);
      final String key = "${currentDay.year}-${currentDay.month.toString().padLeft(2, '0')}-${currentDay.day.toString().padLeft(2, '0')}";
      final dynamic dayDataRaw = attData[key];
      final Map<dynamic, dynamic>? dayData = (dayDataRaw != null && dayDataRaw is Map) ? dayDataRaw : null;
      
      final String type = (dayData?['type'] ?? 'PRACA').toString();
      final double h = _calcDayH(dayData);
      monthlyTotal += h;
      if (type == 'URLOP') vacCount++;

      String hoursStr = h > 0 ? '${h.toStringAsFixed(1)}h' : (type == 'ŚWIĘTO' ? 'ŚWIĘTO' : '');
      if (type == 'URLOP') hoursStr = '8.0h';

      pw.Widget sigWidget = pw.SizedBox();
      final String? daySigB64 = dayData?['signatureB64']?.toString();
      if (daySigB64 != null && daySigB64.length > 20) {
        try {
          sigWidget = pw.Image(pw.MemoryImage(base64Decode(daySigB64)), height: 22, width: 50, fit: pw.BoxFit.contain);
        } catch (_) {}
      }
      
      rows.add(pw.TableRow(
        children: [
          pw.Padding(padding: const pw.EdgeInsets.all(1.0), child: pw.Text(DateFormat('dd.MM (EEE)', 'pl_PL').format(currentDay), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(1.0), child: pw.Text(type == 'PRACA' ? (dayData?['in']?.toString() ?? '') : type, style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(1.0), child: pw.Text(type == 'PRACA' ? (dayData?['out']?.toString() ?? '') : '', style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(1.0), child: pw.Text(hoursStr, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(1.0), child: pw.Text((dayData?['comment'] ?? '').toString(), style: const pw.TextStyle(fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(0.5), child: pw.Center(child: sigWidget)),
        ],
      ));
    }

    final String monthKey = "${_selectedDate.year}_${_selectedDate.month}";
    final String monthlyNotes = (attData['__notes_$monthKey']?['v'] ?? "").toString();
    final String? monthlySigB64 = attData['__sig_$monthKey']?['v']?.toString();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      header: (context) => pw.Column(children: [
        if (logoImage != null) pw.Container(alignment: pw.Alignment.center, height: 25, child: pw.Image(logoImage)),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, 
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('LISTA OBECNOŚCI', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.Text('Pracownik: $displayName', style: const pw.TextStyle(fontSize: 8)),
              ]
            ),
            pw.Text(polishMonthName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ]
        ),
        pw.SizedBox(height: 2),
      ]),
      footer: (context) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Wygenerowano z systemu ES CRM', style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey600))),
      build: (context) => [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey, width: 0.4),
          columnWidths: {
            0: const pw.FixedColumnWidth(65), 
            1: const pw.FixedColumnWidth(50), 
            2: const pw.FixedColumnWidth(40), 
            3: const pw.FixedColumnWidth(55),
            4: const pw.FlexColumnWidth(), 
            5: const pw.FixedColumnWidth(60)
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
              children: [
                pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Data', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Wej./Typ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Wyj.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Suma', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Komentarz / Budowa', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white))),
                pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Podpis', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              ],
            ),
            ...rows,
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, 
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start, 
              children: [
                pw.Container(width: 300, child: pw.Text('UWAGI: $monthlyNotes', style: const pw.TextStyle(fontSize: 7), maxLines: 2, overflow: pw.TextOverflow.clip)),
                pw.SizedBox(height: 2),
                pw.Text('URLOP W MIESIĄCU: $vacCount dni', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                pw.SizedBox(height: 5),
                if (monthlySigB64 != null && monthlySigB64.length > 20)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Image(pw.MemoryImage(base64Decode(monthlySigB64)), height: 35, width: 140, fit: pw.BoxFit.contain),
                      pw.SizedBox(height: 1),
                      pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5)))),
                      pw.Text('PODPIS PRACOWNIKA', style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700)),
                    ]
                  )
                else
                  pw.Container(
                    width: 150, 
                    decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))), 
                    child: pw.Center(child: pw.Padding(padding: const pw.EdgeInsets.only(top: 1), child: pw.Text('PODPIS PRACOWNIKA (BRAK)', style: const pw.TextStyle(fontSize: 6, color: PdfColors.red900)))),
                  ),
              ]
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(5),
              decoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
              child: pw.Column(
                children: [
                  pw.Text('SUMA GODZIN:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${monthlyTotal.toStringAsFixed(1)} h', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                ]
              ),
            ),
          ]
        ),
      ],
    ));
    return pdf;
  }

  Future<void> _generateSummaryPdf() async {
    try {
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
      final pdf = await _generateSummaryPdfDoc();
      if (mounted) Navigator.pop(context);
      await Printing.layoutPdf(onLayout: (f) async => pdf.save(), name: 'Raport_Zbiorczy.pdf');
    } catch (e) {
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd: $e'), backgroundColor: Colors.red)); }
    }
  }

  void _showSummaryPreview() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('PODGLĄD RAPORTU'), backgroundColor: primaryColor, foregroundColor: Colors.white),
      body: PdfPreview(
        build: (format) async { try { final pdf = await _generateSummaryPdfDoc(); return pdf.save(); } catch (e) { return Uint8List(0); } },
        allowSharing: true, allowPrinting: true, 
        initialPageFormat: PdfPageFormat.a4, 
        canChangePageFormat: false,
        canChangeOrientation: false,
        maxPageWidth: 800,
        pdfFileName: 'Raport_Zbiorczy.pdf',
        onError: (context, error) => Center(child: Text('Błąd: $error')),
      ),
    )));
  }

  Future<void> _printIndividualPdf(Map<dynamic, dynamic> emp) async {
    try {
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
      final pdf = await _generateIndividualPdfDoc(emp);
      if (mounted) Navigator.pop(context);
      final String email = (emp['email'] ?? '').toString();
      final String name = "${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}".trim();
      final String displayName = name.isNotEmpty ? name : email;
      await Printing.layoutPdf(onLayout: (f) async => pdf.save(), name: 'Lista_$displayName.pdf');
    } catch (e) {
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd: $e'), backgroundColor: Colors.red)); }
    }
  }

  void _showIndividualPreview(Map<dynamic, dynamic> emp) {
    final String email = (emp['email'] ?? '').toString();
    Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceScreen(
      userEmail: email,
      isAccountantView: true,
      initialDate: _selectedDate,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final String monthName = DateFormat('MMMM yyyy', 'pl_PL').format(_selectedDate).toUpperCase();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('PANEL KSIĘGOWOŚCI'), backgroundColor: primaryColor, foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.sync), onPressed: _loadAllData, tooltip: 'Odśwież dane'),
          IconButton(icon: const Icon(Icons.remove_red_eye), onPressed: _showSummaryPreview, tooltip: 'Podgląd raportu'),
          IconButton(icon: const Icon(Icons.summarize), onPressed: _generateSummaryPdf, tooltip: 'Drukuj raport'),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(children: [
            Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: primaryColor, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30))), child: Column(children: [
              Text(monthName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2022), lastDate: DateTime(2035), locale: const Locale('pl', 'PL'));
                  if (picked != null) { setState(() { _selectedDate = picked; }); _loadAllData(); }
                },
                icon: const Icon(Icons.calendar_month, size: 18), label: const Text('ZMIEŃ MIESIĄC'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              ),
            ])),
            Expanded(child: Padding(padding: const EdgeInsets.all(12.0), child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 6 : (MediaQuery.of(context).size.width > 800 ? 4 : 2), crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.8),
              itemCount: _employees.length,
              itemBuilder: (context, index) {
                final Map<dynamic, dynamic> e = _employees[index];
                final String firstName = (e['firstName'] ?? '').toString();
                final String lastName = (e['lastName'] ?? '').toString();
                final String email = (e['email'] ?? '').toString();
                final double hours = _getMonthlyHours(email);
                final List<String> vacDates = _getVacationDates(email);
                return Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))], border: Border.all(color: Colors.grey[200]!)),
                  child: InkWell(
                    onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceScreen(userEmail: email, isAccountantView: true, initialDate: _selectedDate))); _loadAllData(); },
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      CircleAvatar(radius: 25, backgroundColor: primaryColor.withOpacity(0.1), child: Text(firstName.isNotEmpty ? firstName[0].toUpperCase() : email.isNotEmpty ? email[0].toUpperCase() : '?', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold))),
                      const SizedBox(height: 8),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text((firstName.isNotEmpty || lastName.isNotEmpty) ? "$firstName $lastName" : email, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(height: 4),
                      Text("${hours.toStringAsFixed(1)} h", style: TextStyle(color: Colors.teal[700], fontWeight: FontWeight.bold, fontSize: 14)),
                      if (vacDates.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: Text("Urlop: ${vacDates.join(', ')}", textAlign: TextAlign.center, style: TextStyle(color: Colors.orange[900], fontSize: 9, fontWeight: FontWeight.bold))),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton(icon: const Icon(Icons.remove_red_eye, color: Colors.blue, size: 22), onPressed: () => _showIndividualPreview(e), tooltip: 'Podgląd'),
                        const SizedBox(width: 10),
                        IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 22), onPressed: () => _printIndividualPdf(e), tooltip: 'Drukuj'),
                      ]),
                    ]),
                  ),
                );
              },
            ))),
          ]),
    );
  }
}
