import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

class PdfGenerator {
  static Future<void> generateSwitchboardPdf(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    pw.MemoryImage? logoImage;
    try {
      final ByteData bytes = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    final String dbName = (data['db_name'] ?? 'ROZDZIELNIA').toString().toUpperCase();
    final List items = data['items'] as List? ?? [];

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 40),
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      header: (context) => pw.Column(children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            if (logoImage != null) pw.Container(height: 40, child: pw.Image(logoImage)),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('OPIS ROZDZIELNI', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                pw.Text(dbName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ]
            )
          ]
        ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 10),
      ]),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
          headerHeight: 25,
          cellHeight: 22,
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
          headers: ['Lp.', 'Opis obwodu / Przeznaczenie'],
          columnWidths: {0: const pw.FixedColumnWidth(40), 1: const pw.FlexColumnWidth()},
          data: items.map((l) => [ (l['no'] ?? '').toString(), (l['desc'] ?? '').toString() ]).toList(),
        ),
      ],
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 20),
        child: pw.Text('Wygenerowano z systemu ES Manager | Strona ${context.pageNumber}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      ),
    ));

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Opis_$dbName.pdf');
  }

  static Future<void> generateLanPdf(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    pw.MemoryImage? logoImage;
    try {
      final ByteData bytes = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    final String ppName = (data['pp_name'] ?? 'PATCH PANEL').toString().toUpperCase();
    final List items = data['items'] as List? ?? [];

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      build: (context) => pw.Column(children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            if (logoImage != null) pw.Container(height: 45, child: pw.Image(logoImage)),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('OPIS PORTÓW LAN', style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey700)),
                pw.Text(ppName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ]
            )
          ]
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
          headers: ['Port', 'LAN', 'Opis / Lokalizacja'],
          columnWidths: {0: const pw.FixedColumnWidth(40), 1: const pw.FixedColumnWidth(80), 2: const pw.FlexColumnWidth()},
          data: items.map((l) => [ (l['port'] ?? '').toString(), (l['lan'] ?? '').toString(), (l['desc'] ?? '').toString() ]).toList(),
        ),
      ]),
    ));

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'LAN_$ppName.pdf');
  }
}
