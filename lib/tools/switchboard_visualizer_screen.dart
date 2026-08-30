import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/app_utils.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class SwitchboardVisualizerScreen extends StatefulWidget {
  const SwitchboardVisualizerScreen({super.key});

  @override
  State<SwitchboardVisualizerScreen> createState() => _SwitchboardVisualizerScreenState();
}

class _SwitchboardVisualizerScreenState extends State<SwitchboardVisualizerScreen> {
  List<dynamic> _savedProjects = [];
  bool _isListMode = true;
  int _railCount = 3;
  int _modulesPerRail = 12;
  
  // Nowy, bardziej stabilny proxy do obrazów
  final String _proxy = "https://weserv.nl/?url=";

  final List<Map<String, dynamic>> _hagerModules = [
    {
      'id': 'hager_rcd_4p',
      'name': 'RCD 4P (RCCB)',
      'code': 'CDC440J',
      'width': 4,
      'image': 'https://hager.com/pl-pl/-/media/project/hager/hager-com/products/energy-distribution/protection-devices/residual-current-circuit-breakers/cdc440j.png',
    },
    {
      'id': 'hager_mcb_1p_b16',
      'name': 'MCB 1P B16',
      'code': 'MBN116E',
      'width': 1,
      'image': 'https://hager.com/pl-pl/-/media/project/hager/hager-com/products/energy-distribution/protection-devices/miniature-circuit-breakers/mbn116e.png',
    },
    {
      'id': 'hager_mcb_3p_b16',
      'name': 'MCB 3P B16',
      'code': 'MBN316E',
      'width': 3,
      'image': 'https://hager.com/pl-pl/-/media/project/hager/hager-com/products/energy-distribution/protection-devices/miniature-circuit-breakers/mbn316e.png',
    },
    {
      'id': 'hager_spd_4p',
      'name': 'Ogranicznik przepięć T1+T2',
      'code': 'SPN415',
      'width': 4,
      'image': 'https://hager.com/pl-pl/-/media/project/hager/hager-com/products/energy-distribution/protection-devices/surge-protective-devices/spn415.png',
    },
    {
      'id': 'hager_indicator_3p',
      'name': 'Wskaźnik faz 3P',
      'code': 'SVN121',
      'width': 1,
      'image': 'https://hager.com/pl-pl/-/media/project/hager/hager-com/products/energy-distribution/signalling-and-control-devices/visual-signalling-devices/svn121.png',
    },
    {
        'id': 'hager_mcb_1p_b10',
        'name': 'MCB 1P B10',
        'code': 'MBN110E',
        'width': 1,
        'image': 'https://hager.com/pl-pl/-/media/project/hager/hager-com/products/energy-distribution/protection-devices/miniature-circuit-breakers/mbn110e.png',
    },
    {
        'id': 'hager_rcbo_1p',
        'name': 'RCBO 1P+N B16',
        'code': 'ADM416C',
        'width': 2,
        'image': 'https://hager.com/pl-pl/-/media/project/hager/hager-com/products/energy-distribution/protection-devices/residual-current-circuit-breakers-with-overcurrent-protection/adm416c.png',
    }
  ];

  List<List<Map<String, dynamic>>> _rails = [
    [], // Rail 1
    [], // Rail 2
    [], // Rail 3
  ];

  String _projectName = "Nowa Rozdzielnia";

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('switchboard_visualizations_v1');
    if (data != null) {
      setState(() {
        _savedProjects = json.decode(data);
      });
    }
  }

  Future<void> _showPdfPreview() async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    // Cache images for PDF
    Map<String, pw.MemoryImage> imageCache = {};
    for (var rail in _rails) {
      for (var module in rail) {
        if (!imageCache.containsKey(module['image'])) {
          try {
            final String imageUrl = kIsWeb 
                ? '$_proxy${Uri.encodeComponent(module['image'])}' 
                : module['image'];
            final response = await http.get(Uri.parse(imageUrl));
            if (response.statusCode == 200) {
              imageCache[module['image']] = pw.MemoryImage(response.bodyBytes);
            }
          } catch (e) {
            debugPrint("PDF Image load failed: $e");
          }
        }
      }
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      orientation: pw.PageOrientation.portrait,
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      build: (context) => [
        pw.Header(level: 0, child: pw.Text('WIZUALIZACJA ROZDZIELNI: ${_projectName.toUpperCase()}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 20),
        ..._rails.asMap().entries.map((railEntry) {
          final railIdx = railEntry.key;
          final rail = railEntry.value;
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 5),
                child: pw.Text('SZYNA DIN #${railIdx + 1}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              ),
              pw.Container(
                height: 100,
                width: double.infinity,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                  border: pw.Border(
                    top: pw.BorderSide(color: PdfColors.grey400, width: 2),
                    bottom: pw.BorderSide(color: PdfColors.grey400, width: 2),
                  ),
                ),
                child: pw.Row(
                  children: rail.map((m) {
                    final img = imageCache[m['image']];
                    double pdfBaseWidth = 480.0 / _modulesPerRail; 
                    return pw.Container(
                      width: pdfBaseWidth * m['width'],
                      margin: const pw.EdgeInsets.symmetric(horizontal: 0.5),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Expanded(
                            child: img != null 
                              ? pw.Image(img, fit: pw.BoxFit.contain) 
                              : pw.Center(
                                  child: pw.Column(
                                    mainAxisAlignment: pw.MainAxisAlignment.center,
                                    children: [
                                      pw.Text('HAGER', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                                      pw.Text(m['code'], style: const pw.TextStyle(fontSize: 4, color: PdfColors.grey600)),
                                    ]
                                  )
                                ),
                          ),
                          pw.Container(
                            width: double.infinity,
                            color: PdfColors.blueGrey800,
                            padding: const pw.EdgeInsets.symmetric(vertical: 1),
                            child: pw.Text(m['code'], textAlign: pw.TextAlign.center, style: const pw.TextStyle(color: PdfColors.white, fontSize: 5)),
                          )
                        ]
                      )
                    );
                  }).toList(),
                ),
              ),
              pw.SizedBox(height: 15),
            ],
          );
        }).toList(),
        pw.Footer(
          margin: const pw.EdgeInsets.only(top: 20),
          leading: pw.Text('Wygenerowano w systemie ES CRM', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        )
      ],
    ));

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Wizualizacja_$_projectName.pdf');
  }

  Future<void> _saveCurrentProject() async {
    final prefs = await SharedPreferences.getInstance();
    final project = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': _projectName,
      'rails': _rails,
      'railCount': _railCount,
      'modulesPerRail': _modulesPerRail,
      'date': DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
    };

    setState(() {
      _savedProjects.insert(0, project);
      _isListMode = true;
    });

    await prefs.setString('switchboard_visualizations_v1', AppUtils.safeJsonEncode(_savedProjects));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Projekt został zapisany!')));
  }

  void _loadProject(Map<String, dynamic> project) {
    setState(() {
      _projectName = project['name'];
      _railCount = project['railCount'] ?? 3;
      _modulesPerRail = project['modulesPerRail'] ?? 12;
      _rails = List<List<Map<String, dynamic>>>.from(
        (project['rails'] as List).map((rail) => List<Map<String, dynamic>>.from(rail))
      );
      _isListMode = false;
    });
  }

  void _deleteProject(int index) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedProjects.removeAt(index);
    });
    await prefs.setString('switchboard_visualizations_v1', AppUtils.safeJsonEncode(_savedProjects));
  }

  void _showNewProjectDialog() {
    int tempRails = 3;
    int tempMods = 12;
    String tempName = "Nowa Rozdzielnia";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setST) => AlertDialog(
          title: const Text('KONFIGURACJA ROZDZIELNI'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Nazwa (np. Rozdzielnia Parter)'),
                onChanged: (v) => tempName = v,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: tempRails,
                      decoration: const InputDecoration(labelText: 'Ilość szyn DIN'),
                      items: [1, 2, 3, 4, 5, 6].map((i) => DropdownMenuItem(value: i, child: Text('$i rzędy'))).toList(),
                      onChanged: (v) => setST(() => tempRails = v!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: tempMods,
                      decoration: const InputDecoration(labelText: 'Modułów w rzędzie'),
                      items: [8, 12, 18, 24].map((i) => DropdownMenuItem(value: i, child: Text('$i mod.'))).toList(),
                      onChanged: (v) => setST(() => tempMods = v!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _projectName = tempName;
                  _railCount = tempRails;
                  _modulesPerRail = tempMods;
                  _rails = List.generate(_railCount, (_) => []);
                  _isListMode = false;
                });
                Navigator.pop(context);
              },
              child: const Text('STWÓRZ'),
            ),
          ],
        ),
      ),
    );
  }

  void _addModuleToRail(int railIdx, Map<String, dynamic> module) {
    double currentWidth = 0;
    for (var m in _rails[railIdx]) {
      currentWidth += (m['width'] as num);
    }

    if (currentWidth + (module['width'] as num) > _modulesPerRail) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Brak miejsca na szynie! Wykorzystano $currentWidth / $_modulesPerRail mod.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _rails[railIdx].add({
        ...module,
        'custom_desc': '',
      });
    });
  }

  void _removeModule(int railIdx, int moduleIdx) {
    setState(() {
      _rails[railIdx].removeAt(moduleIdx);
    });
  }

  void _showModulePicker(int railIdx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('WYBIERZ MODUŁ HAGER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _hagerModules.length,
                itemBuilder: (context, index) {
                  final m = _hagerModules[index];
                  return InkWell(
                    onTap: () {
                      _addModuleToRail(railIdx, m);
                      Navigator.pop(context);
                    },
                    child: Card(
                      elevation: 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Image.network(
                              kIsWeb ? '$_proxy${Uri.encodeComponent(m['image'])}' : m['image'],
                              fit: BoxFit.contain,
                              errorBuilder: (c, e, s) => const Icon(Icons.electrical_services, size: 50),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(m['name'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          Text(m['code'], style: const TextStyle(fontSize: 9, color: Colors.grey)),
                          Text('Szerokość: ${m['width']} mod.', style: const TextStyle(fontSize: 8)),
                        ],
                      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECEFF1),
      appBar: AppBar(
        title: Text(_isListMode ? 'WIZUALIZACJE ROZDZIELNI' : _projectName),
        backgroundColor: const Color(0xFF263238),
        foregroundColor: Colors.white,
        leading: !_isListMode ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _isListMode = true),
        ) : null,
        actions: [
          if (!_isListMode) IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              final c = TextEditingController(text: _projectName);
              showDialog(context: context, builder: (c2) => AlertDialog(
                title: const Text('Nazwa projektu'),
                content: TextField(controller: c),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c2), child: const Text('ANULUJ')),
                  ElevatedButton(onPressed: () {
                    setState(() => _projectName = c.text);
                    Navigator.pop(c2);
                  }, child: const Text('OK'))
                ],
              ));
            },
          ),
          if (!_isListMode) IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _showPdfPreview, tooltip: 'Pobierz PDF'),
          if (!_isListMode) IconButton(icon: const Icon(Icons.save), onPressed: _saveCurrentProject),
        ],
      ),
      body: _isListMode ? _buildProjectList() : _buildEditor(),
      floatingActionButton: _isListMode 
        ? FloatingActionButton.extended(
            onPressed: _showNewProjectDialog,
            backgroundColor: Colors.deepPurple,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('NOWA WIZUALIZACJA', style: TextStyle(color: Colors.white)),
          )
        : null,
    );
  }

  Widget _buildProjectList() {
    if (_savedProjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.view_quilt_outlined, size: 64, color: Colors.grey.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text('Brak zapisanych projektów', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _savedProjects.length,
      itemBuilder: (context, index) {
        final p = _savedProjects[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.deepPurple, child: Icon(Icons.view_quilt, color: Colors.white, size: 18)),
            title: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Data: ${p['date']} | Szyn: ${(p['rails'] as List).length}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteProject(index),
            ),
            onTap: () => _loadProject(p),
          ),
        );
      },
    );
  }

  Widget _buildEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ...List.generate(_rails.length, (railIdx) => _buildRail(railIdx)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => setState(() => _rails.add([])),
            icon: const Icon(Icons.add_box),
            label: const Text('DODAJ KOLEJNĄ SZYNĘ DIN'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildRail(int railIdx) {
    double currentUsage = 0;
    for (var m in _rails[railIdx]) {
      currentUsage += (m['width'] as num);
    }
    bool isFull = currentUsage >= _modulesPerRail;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SZYNA DIN #${railIdx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    Text('Zajętość: $currentUsage / $_modulesPerRail mod.', 
                      style: TextStyle(fontSize: 10, color: isFull ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: () {
                    setState(() => _rails.removeAt(railIdx));
                  },
                )
              ],
            ),
          ),
          // DIN Rail background
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border.symmetric(horizontal: BorderSide(color: Colors.grey[400]!, width: 2)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.grey[300]!, Colors.grey[100]!, Colors.grey[300]!],
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._rails[railIdx].asMap().entries.map((e) => _buildModule(railIdx, e.key, e.value)),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: InkWell(
                      onTap: () => _showModulePicker(railIdx),
                      child: Container(
                        width: 60,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.withOpacity(0.3), style: BorderStyle.solid),
                        ),
                        child: const Icon(Icons.add, color: Colors.indigo),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModule(int railIdx, int moduleIdx, Map<String, dynamic> module) {
    double baseWidth = 40.0;
    double width = baseWidth * module['width'];

    return Stack(
      children: [
        Container(
          width: width,
          height: 140,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 2)],
          ),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Image.network(
                    kIsWeb ? '$_proxy${Uri.encodeComponent(module['image'])}' : module['image'],
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => const Icon(Icons.bolt, color: Colors.amber),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 2),
                color: Colors.blueGrey[800],
                child: Text(
                  module['code'],
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0, right: 0,
          child: GestureDetector(
            onTap: () => _removeModule(railIdx, moduleIdx),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
