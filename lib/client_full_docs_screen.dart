import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'core/app_theme.dart';
import 'core/pdf_generator.dart';
import 'protocols_screen.dart';

class ClientFullDocsScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const ClientFullDocsScreen({super.key, required this.order});

  @override
  State<ClientFullDocsScreen> createState() => _ClientFullDocsScreenState();
}

class _ClientFullDocsScreenState extends State<ClientFullDocsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _switchboards = [];
  List<Map<String, dynamic>> _lanLabels = [];
  List<Map<String, dynamic>> _protocols = [];
  List<Map<String, dynamic>> _schematics = [];

  @override
  void initState() {
    super.initState();
    _fetchAllDocs();
  }

  Future<void> _fetchAllDocs() async {
    final String orderName = widget.order['name'] ?? "";
    final String orderId = widget.order['id'].toString();

    try {
      final sbSnap = await FirebaseFirestore.instance
          .collection('switchboards')
          .where('const_name', isEqualTo: orderName)
          .get();
      _switchboards = sbSnap.docs.map((d) => d.data()).toList();

      final lanSnap = await FirebaseFirestore.instance
          .collection('lan_labels')
          .where('const_name', isEqualTo: orderName)
          .get();
      _lanLabels = lanSnap.docs.map((d) => d.data()).toList();

      final protSnap = await FirebaseFirestore.instance
          .collection('protocols')
          .where('orderId', isEqualTo: orderId)
          .get();
      _protocols = protSnap.docs.map((d) => d.data()).toList();

      final schSnap = await FirebaseFirestore.instance
          .collection('schematics')
          .where('name', isEqualTo: orderName)
          .get();
      _schematics = schSnap.docs.map((d) => d.data()).toList();

    } catch (e) {
      debugPrint("Error fetching docs: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)))
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildCategoryHeader("DOKUMENTY FORMALNE", Icons.folder_shared_rounded, Colors.green),
              _buildFormalDocs(),
              const SizedBox(height: 32),

              _buildCategoryHeader("POMIARY I TESTY", Icons.bolt_rounded, Colors.amber),
              _buildProtocols(),
              const SizedBox(height: 32),

              _buildCategoryHeader("OPISY ROZDZIELNI I LAN", Icons.settings_input_component_rounded, Colors.blue),
              _buildTechnicalDocs(),
              const SizedBox(height: 32),

              if (_schematics.isNotEmpty) ...[
                _buildCategoryHeader("SCHEMATY IDEOWE", Icons.schema_rounded, Colors.indigo),
                _buildSchematics(),
                const SizedBox(height: 32),
              ],
            ],
          ),
    );
  }

  Widget _buildCategoryHeader(String title, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, left: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Text(
            title, 
            style: GoogleFonts.montserrat(
              color: theme.colorScheme.onSurface, 
              fontSize: 13, 
              fontWeight: FontWeight.w900, 
              letterSpacing: 1.5
            )
          ),
        ],
      ),
    );
  }

  Widget _buildFormalDocs() {
    final List files = widget.order['project_files'] as List? ?? [];
    if (files.isEmpty) return _emptyInfo("Brak wgranych plików projektowych.");

    // Grupowanie według kategorii
    final Map<String, List<dynamic>> grouped = {};
    for (var f in files) {
      String cat = f['category'] ?? "Inne";
      if (!grouped.containsKey(cat)) grouped[cat] = [];
      grouped[cat]!.add(f);
    }

    return Column(
      children: grouped.entries.map((e) => _buildExpandableCategory(e.key, e.value)).toList(),
    );
  }

  Widget _buildExpandableCategory(String category, List files) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)]
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(category, style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w800)),
          leading: const Icon(Icons.folder_copy_rounded, color: Color(0xFF007BFF), size: 20),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          iconColor: const Color(0xFF007BFF),
          collapsedIconColor: theme.colorScheme.onSurface.withOpacity(0.3),
          children: files.map((f) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.02), borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              dense: true,
              title: Text(f['name'], style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.download_rounded, color: Color(0xFF007BFF), size: 18),
              onTap: () => launchUrl(Uri.parse(f['path'])),
            ),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildProtocols() {
    if (_protocols.isEmpty) return _emptyInfo("Brak zarejestrowanych protokołów pomiarowych.");
    return Column(
      children: _protocols.map((p) => _docTile(
        p['orderName'] ?? "Protokół", 
        "Data: ${p['date']} | Wykonał: ${p['author']}", 
        Icons.fact_check_rounded, 
        const Color(0xFFF59E0B),
        () {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dokument dostępny do wglądu u wykonawcy.")));
        }
      )).toList(),
    );
  }

  Widget _buildTechnicalDocs() {
    List<Widget> items = [];
    for (var sb in _switchboards) {
      items.add(_docTile(
        "Rozdzielnia: ${sb['db_name']}", 
        "Pobierz opis obwodów (PDF)", 
        Icons.electrical_services_rounded, 
        Colors.blue,
        () => PdfGenerator.generateSwitchboardPdf(sb)
      ));
    }
    for (var lan in _lanLabels) {
      items.add(_docTile(
        "Patch Panel: ${lan['pp_name']}", 
        "Pobierz opis portów LAN (PDF)", 
        Icons.lan_rounded, 
        Colors.teal,
        () => PdfGenerator.generateLanPdf(lan)
      ));
    }

    if (items.isEmpty) return _emptyInfo("Brak dokumentacji technicznej rozdzielni/LAN.");
    return Column(children: items);
  }

  Widget _buildSchematics() {
    return Column(
      children: _schematics.map((s) => _docTile(
        "Schemat: ${s['name']}", 
        "Schemat ideowy instalacji", 
        Icons.schema_rounded, 
        Colors.indigo,
        () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Schemat dostępny w biurze projektowym.")))
      )).toList(),
    );
  }

  Widget _docTile(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        trailing: const Icon(Icons.open_in_new_rounded, color: Color(0xFF007BFF), size: 18),
      ),
    );
  }

  Widget _emptyInfo(String text) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.cardTheme.color, 
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Icon(Icons.info_outline_rounded, color: theme.colorScheme.onSurface.withOpacity(0.1), size: 32),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 12, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}
