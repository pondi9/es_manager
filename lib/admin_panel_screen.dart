import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'core/app_theme.dart';
import 'services/cloud_sync_service.dart';
import 'attendance_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final Color primaryColor = const Color(0xFF1E293B);
  
  List<String> _positions = ['Elektryk', 'Pomocnik', 'Brygadzista', 'Kierownik', 'Biuro', 'Księgowa', 'Zaopatrzenie'];
  List<String> _groups = ['Ekipa 1', 'Ekipa 2', 'Stadion', 'Biuro'];

  @override
  void initState() {
    super.initState();
    _loadDictionaries();
  }

  Future<void> _loadDictionaries() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _positions = prefs.getStringList('job_positions') ?? _positions;
      _groups = prefs.getStringList('job_groups') ?? _groups;
    });
  }

  Future<void> _saveDictionaries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('job_positions', _positions);
    await prefs.setStringList('job_groups', _groups);
  }

  void _updateEmployee(String docId, Map<String, dynamic> data) {
    FirebaseFirestore.instance.collection('employees').doc(docId).update(data);
  }

  void _confirmDelete(Map<String, dynamic> emp) {
    final String docId = emp['id'];
    final String email = emp['email'] ?? docId;

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("POTWIERDŹ USUNIĘCIE", style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text("Czy na pewno chcesz trwale usunąć pracownika:\n\n$email?\n\nTej operacji nie można cofnąć!"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANULUJ")),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('employees').doc(docId).delete();
              await FirebaseFirestore.instance.collection('attendance').doc(docId).delete();
              final prefs = await SharedPreferences.getInstance();
              prefs.remove('attendance_data_$docId');
              if (mounted) Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pracownik został usunięty.")));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("TAK, USUŃ"),
          ),
        ],
      ),
    );
  }

  void _manageDict(String title, List<String> list, Function(List<String>) onUpdate) {
    showDialog(context: context, builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text("Zarządzaj: $title"),
      content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: list.length, itemBuilder: (context, i) => ListTile(title: Text(list[i]), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { setState(() { list.removeAt(i); }); onUpdate(list); _saveDictionaries(); Navigator.pop(c); })))),
      actions: [
        TextButton(onPressed: () {
          final ctrl = TextEditingController();
          showDialog(context: context, builder: (c2) => AlertDialog(title: const Text("Dodaj nowe"), content: TextField(controller: ctrl, autofocus: true), actions: [ElevatedButton(onPressed: () { if(ctrl.text.isNotEmpty) { setState(() { list.add(ctrl.text); }); onUpdate(list); _saveDictionaries(); Navigator.pop(c2); Navigator.pop(c); } }, child: const Text("DODAJ"))]));
        }, child: const Text("DODAJ NOWE"))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: const Color(0xFF001A2C),
          elevation: 4,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.pop(context),
            tooltip: "Wstecz",
          ),
          title: const Text("ZARZĄDZANIE KADRAMI", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: Colors.orange,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: const [
              Tab(text: "PRACOWNICY"),
              Tab(text: "KIEROWNICY"),
              Tab(text: "KSIĘGOWOŚĆ"),
              Tab(text: "ZAOPATRZENIE"),
              Tab(text: "NOWE KONTA"),
              Tab(text: "WYDARZENIA"),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('employees').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final allDocs = snapshot.data!.docs;
            
            final List<Map<String, dynamic>> employees = [];
            final List<Map<String, dynamic>> managers = [];
            final List<Map<String, dynamic>> accounting = [];
            final List<Map<String, dynamic>> procurement = [];
            final List<Map<String, dynamic>> inactive = [];

            for (var doc in allDocs) {
              final data = doc.data() as Map<String, dynamic>;
              data['id'] = doc.id; 
              final pos = (data['position'] ?? '').toString().toLowerCase();

              if (data['isActive'] == true) {
                if (pos.contains('księgow')) {
                  accounting.add(data);
                } else if (pos.contains('zaopatrz')) {
                  procurement.add(data);
                } else if (pos.contains('kierownik')) {
                  managers.add(data);
                } else {
                  employees.add(data);
                }
              } else {
                inactive.add(data);
              }
            }
            return TabBarView(
              children: [
                _buildList(employees),
                _buildList(managers),
                _buildList(accounting),
                _buildList(procurement),
                _buildList(inactive, isNew: true),
                _buildEventsList(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list, {bool isNew = false}) {
    if (list.isEmpty) return const Center(child: Text("Brak danych", style: TextStyle(color: Colors.grey)));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, i) => EmployeeEditorCard(
        emp: list[i],
        positions: _positions,
        groups: _groups,
        onUpdate: (data) => _updateEmployee(list[i]['id'], data),
        onDelete: () => _confirmDelete(list[i]),
        onManagePositions: () => _manageDict("Stanowiska", _positions, (l) => setState(() => _positions = l)),
        onManageGroups: () => _manageDict("Ekipy", _groups, (l) => setState(() => _groups = l)),
      ),
    );
  }

  Widget _buildEventsList() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('notifications').orderBy('date', descending: true).limit(50).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final n = docs[i].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: theme.cardTheme.color,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: theme.colorScheme.onSurface.withOpacity(0.05), child: Icon(Icons.history_toggle_off, color: theme.colorScheme.primary)),
                title: Text(n['title'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
                subtitle: Text("${n['date']} | ${n['content']}", style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.6))),
              ),
            );
          },
        );
      },
    );
  }
}

class EmployeeEditorCard extends StatefulWidget {
  final Map<String, dynamic> emp;
  final List<String> positions;
  final List<String> groups;
  final Function(Map<String, dynamic>) onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onManagePositions;
  final VoidCallback onManageGroups;

  const EmployeeEditorCard({
    super.key, required this.emp, required this.positions, required this.groups,
    required this.onUpdate, required this.onDelete, required this.onManagePositions, required this.onManageGroups
  });

  @override
  State<EmployeeEditorCard> createState() => _EmployeeEditorCardState();
}

class _EmployeeEditorCardState extends State<EmployeeEditorCard> {
  late TextEditingController _fNC, _lNC, _eC, _loC, _rC, _vLC;
  late TextEditingController _mNoC, _bhpNoC, _sepNoC, _udtNoC, _cNoC, _sepScopeC;
  String? _pos, _grp, _cS, _cE, _mS, _mE, _bhp, _sep, _udt;
  String? _sGrp, _sRole; // SEP Group (G1, G2, G3) and Role (E, D)
  List<String> _mImgs = [], _bhpImgs = [], _sepImgs = [], _udtImgs = [], _cImgs = [];
  Map<String, bool> _excludedDocs = {};
  List<Map<String, dynamic>> _certs = [];
  bool _act = false;
  Map<String, dynamic> _p = {};

  @override
  void initState() { super.initState(); _init(); }

  void _init() {
    _fNC = TextEditingController(text: widget.emp['firstName'] ?? "");
    _lNC = TextEditingController(text: widget.emp['lastName'] ?? "");
    _eC = TextEditingController(text: widget.emp['email'] ?? "");
    _loC = TextEditingController(text: widget.emp['login'] ?? "");
    _rC = TextEditingController(text: widget.emp['rate']?.toString() ?? "0");
    _vLC = TextEditingController(text: widget.emp['vacationLimit']?.toString() ?? "26");

    _mNoC = TextEditingController(text: widget.emp['medicalNo'] ?? "");
    _bhpNoC = TextEditingController(text: widget.emp['bhpNo'] ?? "");
    _sepNoC = TextEditingController(text: widget.emp['sepNo'] ?? "");
    _sepScopeC = TextEditingController(text: widget.emp['sepScope'] ?? "");
    _sGrp = widget.emp['sepGroup'];
    _sRole = widget.emp['sepRole'];
    
    // Fallback for legacy sepCategory
    if (_sGrp == null && _sRole == null && widget.emp['sepCategory'] != null) {
      String cat = widget.emp['sepCategory'].toString().toUpperCase();
      if (cat.contains('G1')) _sGrp = 'G1';
      else if (cat.contains('G2')) _sGrp = 'G2';
      else if (cat.contains('G3')) _sGrp = 'G3';
      
      if (cat.contains('E')) _sRole = 'E';
      else if (cat.contains('D')) _sRole = 'D';
    }

    _udtNoC = TextEditingController(text: widget.emp['udtNo'] ?? "");
    _cNoC = TextEditingController(text: widget.emp['contractNo'] ?? "");

    _pos = widget.emp['position']; _grp = widget.emp['group'];
    _cS = widget.emp['contractStart']; _cE = widget.emp['contractEnd'];
    _mS = widget.emp['medicalStart']; _mE = widget.emp['medicalEnd'];
    _bhp = widget.emp['bhpDate']; _sep = widget.emp['sepDate']; _udt = widget.emp['udtDate'];
    
    _mImgs = _toList(widget.emp['medicalImg'] ?? widget.emp['medicalImgs']);
    _bhpImgs = _toList(widget.emp['bhpImg'] ?? widget.emp['bhpImgs']);
    _sepImgs = _toList(widget.emp['sepImg'] ?? widget.emp['sepImgs']);
    _udtImgs = _toList(widget.emp['udtImg'] ?? widget.emp['udtImgs']);
    _cImgs = _toList(widget.emp['contractImg'] ?? widget.emp['contractImgs']);

    _excludedDocs = Map<String, bool>.from(widget.emp['excludedDocs'] ?? {});
    
    _certs = (widget.emp['additionalCerts'] as List?)?.map((c) => Map<String, dynamic>.from(c)).toList() ?? [];
    
    _act = widget.emp['isActive'] ?? false;
    _p = Map<String, dynamic>.from(widget.emp['permissions'] ?? {});
  }

  List<String> _toList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    return [val.toString()];
  }

  @override
  void dispose() { 
    _fNC.dispose(); _lNC.dispose(); _eC.dispose(); _loC.dispose(); _rC.dispose(); _vLC.dispose(); 
    _mNoC.dispose(); _bhpNoC.dispose(); _sepNoC.dispose(); _udtNoC.dispose(); _cNoC.dispose(); _sepScopeC.dispose();
    super.dispose(); 
  }

  void _save() {
    widget.onUpdate({
      'firstName': _fNC.text.trim(), 'lastName': _lNC.text.trim(),
      'email': _eC.text.trim(), 'login': _loC.text.trim(), 'rate': _rC.text.trim(),
      'vacationLimit': int.tryParse(_vLC.text) ?? 26,
      'medicalNo': _mNoC.text.trim(), 'bhpNo': _bhpNoC.text.trim(),
      'sepNo': _sepNoC.text.trim(), 'sepScope': _sepScopeC.text.trim(),
      'sepGroup': _sGrp, 'sepRole': _sRole,
      'sepCategory': "${_sGrp ?? ''} ${_sRole ?? ''}".trim(), // For legacy display
      'udtNo': _udtNoC.text.trim(), 'contractNo': _cNoC.text.trim(),
      'position': _pos, 'group': _grp, 
      'contractStart': _cS, 'contractEnd': _cE,
      'medicalStart': _mS, 'medicalEnd': _mE,
      'bhpDate': _bhp, 'sepDate': _sep, 'udtDate': _udt,
      'medicalImgs': _mImgs, 'bhpImgs': _bhpImgs, 'sepImgs': _sepImgs, 'udtImgs': _udtImgs, 'contractImgs': _cImgs,
      'additionalCerts': _certs,
      'excludedDocs': _excludedDocs,
      'isActive': _act, 'permissions': _p,
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ZAPISANO"), backgroundColor: Colors.green));
  }

  Future<void> _pickAndUpload(String type, {int? certIdx}) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
    if (image == null) return;

    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    
    try {
      final bytes = await image.readAsBytes();
      final String ext = image.name.split('.').last;
      final String fileName = "${widget.emp['id']}_${type}_${DateTime.now().millisecondsSinceEpoch}.$ext";
      final ref = FirebaseStorage.instance.ref().child('employee_docs/$fileName');
      
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      
      if (mounted) Navigator.pop(context);
      
      setState(() {
        if (certIdx != null) {
          if (_certs[certIdx]['imageUrls'] == null) _certs[certIdx]['imageUrls'] = <String>[];
          (_certs[certIdx]['imageUrls'] as List).add(url);
        } else {
          if (type == 'medical') _mImgs.add(url);
          if (type == 'bhp') _bhpImgs.add(url);
          if (type == 'sep') _sepImgs.add(url);
          if (type == 'udt') _udtImgs.add(url);
          if (type == 'contract') _cImgs.add(url);
        }
      });
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Błąd wysyłania: $e"), backgroundColor: Colors.red));
    }
  }

  void _showImage(String url) {
    showDialog(context: context, builder: (c) => Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.network(url, loadingBuilder: (context, child, progress) => progress == null ? child : const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ZAMKNIJ"))
        ],
      ),
    ));
  }

  void _deleteImage(String type, {int? certIdx, int? imgIdx}) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("USUŃ ZDJĘCIE?"),
        content: const Text("Czy na pewno chcesz usunąć ten skan z bazy?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ANULUJ")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("USUŃ")),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        if (certIdx != null) {
          if (imgIdx != null) {
            (_certs[certIdx]['imageUrls'] as List).removeAt(imgIdx);
          } else {
            _certs[certIdx]['imageUrls'] = [];
          }
        } else {
          if (imgIdx != null) {
            if (type == 'medical') _mImgs.removeAt(imgIdx);
            if (type == 'bhp') _bhpImgs.removeAt(imgIdx);
            if (type == 'sep') _sepImgs.removeAt(imgIdx);
            if (type == 'udt') _udtImgs.removeAt(imgIdx);
            if (type == 'contract') _cImgs.removeAt(imgIdx);
          } else {
            if (type == 'medical') _mImgs = [];
            if (type == 'bhp') _bhpImgs = [];
            if (type == 'sep') _sepImgs = [];
            if (type == 'udt') _udtImgs = [];
            if (type == 'contract') _cImgs = [];
          }
        }
      });
    }
  }

  void _addCert() {
    setState(() {
      _certs.add({'name': '', 'number': '', 'expiryDate': '', 'imageUrls': <String>[]});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color, 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)]
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: CircleAvatar(backgroundColor: _act ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1), child: Icon(_act ? Icons.person : Icons.person_off, color: _act ? Colors.green : Colors.grey)),
          title: Text("${_fNC.text} ${_lNC.text}".trim().isEmpty ? (widget.emp['email'] ?? "Pracownik") : "${_fNC.text} ${_lNC.text}", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          subtitle: Text(_pos ?? 'Brak stanowiska', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SwitchListTile(title: Text("Aktywacja konta", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)), value: _act, onChanged: (v) => setState(() => _act = v)),
                const Divider(),
                Text("UPRAWNIENIA:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                _buildPerms(),
                const Divider(),
                Text("DANE:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                const SizedBox(height: 8),
                Row(children: [Expanded(child: _field("Imię", _fNC)), const SizedBox(width: 8), Expanded(child: _field("Nazwisko", _lNC))]),
                const SizedBox(height: 8),
                _field("E-mail", _eC), const SizedBox(height: 8), _field("Login", _loC),
                const SizedBox(height: 16),
                Text("ZATRUDNIENIE:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _drop("Stanowisko", _pos, widget.positions, (v) => setState(() => _pos = v))),
                  const SizedBox(width: 4),
                  IconButton(icon: const Icon(Icons.edit, size: 18, color: Color(0xFF007BFF)), onPressed: widget.onManagePositions)
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _drop("Ekipa", _grp, widget.groups, (v) => setState(() => _grp = v))),
                  const SizedBox(width: 4),
                  IconButton(icon: const Icon(Icons.settings, size: 18, color: Color(0xFF007BFF)), onPressed: widget.onManageGroups)
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _field("Stawka h", _rC, isNum: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _field("Limit urlopu (dni)", _vLC, isNum: true)),
                ]),
                const SizedBox(height: 20),
                Text("DATY:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _date("Umowa od", _cS, (v) => setState(() => _cS = v), imgUrls: [], onUpload: null, onDeleteImg: null, docKey: 'contractStart')), 
                    const SizedBox(width: 12), 
                    Expanded(child: _date("Umowa do", _cE, (v) => setState(() => _cE = v), imgUrls: _cImgs, onUpload: () => _pickAndUpload('contract'), numCtrl: _cNoC, onDeleteImg: (idx) => _deleteImage('contract', imgIdx: idx), docKey: 'contractEnd', isContract: true))
                  ]
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _date("Badania do", _mE, (v) => setState(() => _mE = v), imgUrls: _mImgs, onUpload: () => _pickAndUpload('medical'), numCtrl: _mNoC, onDeleteImg: (idx) => _deleteImage('medical', imgIdx: idx), docKey: 'medicalEnd')), 
                    const SizedBox(width: 12), 
                    Expanded(child: _date("BHP do", _bhp, (v) => setState(() => _bhp = v), imgUrls: _bhpImgs, onUpload: () => _pickAndUpload('bhp'), numCtrl: _bhpNoC, onDeleteImg: (idx) => _deleteImage('bhp', imgIdx: idx), docKey: 'bhpDate'))
                  ]
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _date("SEP do", _sep, (v) => setState(() => _sep = v), imgUrls: _sepImgs, onUpload: () => _pickAndUpload('sep'), numCtrl: _sepNoC, scopeCtrl: _sepScopeC, sepGrp: _sGrp, sepRole: _sRole, onSepGrpC: (v) => setState(() => _sGrp = v), onSepRoleC: (v) => setState(() => _sRole = v), onDeleteImg: (idx) => _deleteImage('sep', imgIdx: idx), docKey: 'sepDate')), 
                    const SizedBox(width: 12), 
                    Expanded(child: _date("UDT do", _udt, (v) => setState(() => _udt = v), imgUrls: _udtImgs, onUpload: () => _pickAndUpload('udt'), numCtrl: _udtNoC, onDeleteImg: (idx) => _deleteImage('udt', imgIdx: idx), docKey: 'udtDate'))
                  ]
                ),
                const SizedBox(height: 20),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("DODATKOWE UPRAWNIENIA:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                    TextButton.icon(onPressed: _addCert, icon: const Icon(Icons.add, size: 16), label: const Text("DODAJ", style: TextStyle(fontSize: 10))),
                  ],
                ),
                if (_certs.isEmpty) 
                   Padding(padding: const EdgeInsets.all(8), child: Text("Brak dodatkowych uprawnień", style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.2))))
                else
                  ..._certs.asMap().entries.map((e) {
                    final int i = e.key;
                    final c = e.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.02), borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.08))),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: TextFormField(
                                initialValue: c['name'],
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(hintText: "Nazwa uprawnienia", isDense: true, border: InputBorder.none),
                                onChanged: (v) => _certs[i]['name'] = v,
                              )),
                              IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => setState(() => _certs.removeAt(i))),
                            ],
                          ),
                          const Divider(height: 12),
                          _date("Ważne do", c['expiryDate'], (v) => setState(() => _certs[i]['expiryDate'] = v), imgUrls: (c['imageUrls'] as List?)?.map((e)=>e.toString()).toList(), onUpload: () => _pickAndUpload('cert', certIdx: i), onDeleteImg: (idx) => _deleteImage('cert', certIdx: i, imgIdx: idx)),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: c['number'],
                            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              labelText: "NR DOKUMENTU",
                              labelStyle: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                              isDense: true,
                              prefixIcon: const Icon(Icons.tag, size: 14),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onChanged: (v) => _certs[i]['number'] = v,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    final passCtrl = TextEditingController();
                    showDialog(context: context, builder: (ctx) => AlertDialog(
                      backgroundColor: theme.cardTheme.color,
                      title: Text("ZRESETUJ HASŁO", style: TextStyle(color: theme.colorScheme.onSurface)),
                      content: TextField(controller: passCtrl, style: TextStyle(color: theme.colorScheme.onSurface), decoration: const InputDecoration(labelText: "Nowe tymczasowe hasło")),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANULUJ")),
                        ElevatedButton(onPressed: () {
                          if (passCtrl.text.isNotEmpty) {
                            widget.onUpdate({
                              'password': passCtrl.text,
                              'forcePasswordReset': true,
                            });
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("HASŁO ZRESETOWANE")));
                          }
                        }, child: const Text("ZRESETUJ"))
                      ],
                    ));
                  },
                  icon: const Icon(Icons.lock_reset),
                  label: const Text("ZRESETUJ HASŁO PRACOWNIKA"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 44)),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text("ZAPISZ ZMIANY"), style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.green[700], foregroundColor: Colors.white)),
                const SizedBox(height: 12),
                TextButton.icon(onPressed: widget.onDelete, icon: const Icon(Icons.delete, color: Colors.red), label: const Text("USUŃ KONTO", style: TextStyle(color: Colors.red))),
              ]),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPerms() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final List<Map<String, dynamic>> categories = [
      {
        'title': 'OPERACJE',
        'items': [
          {'id': 'attendance', 'name': 'Obecność', 'icon': Icons.calendar_today_rounded},
          {'id': 'orders', 'name': 'Zlecenia', 'icon': Icons.assignment_rounded},
          {'id': 'chat', 'name': 'Czat', 'icon': Icons.forum_rounded},
          {'id': 'issues', 'name': 'Problemy', 'icon': Icons.report_problem_rounded},
          {'id': 'expenses', 'name': 'Koszty', 'icon': Icons.receipt_long_rounded},
          {'id': 'access_hr_pulpit', 'name': 'Pulpit HR', 'icon': Icons.admin_panel_settings_rounded},
          {'id': 'access_procurement_pulpit', 'name': 'Pulpit Zaopatrzenia', 'icon': Icons.shopping_cart_checkout_rounded},
        ]
      },
      {
        'title': 'LOGISTYKA',
        'items': [
          {'id': 'storage', 'name': 'Magazyn', 'icon': Icons.inventory_2_rounded},
          {'id': 'tools', 'name': 'Sprzęt', 'icon': Icons.construction_rounded},
          {'id': 'fleet', 'name': 'Flota', 'icon': Icons.local_shipping_rounded},
          {'id': 'tools_map', 'name': 'Mapa GPS', 'icon': Icons.map_rounded},
        ]
      },
      {
        'title': 'DOKUMENTY',
        'items': [
          {'id': 'knowledge_base', 'name': 'Standard', 'icon': Icons.auto_stories_rounded},
          {'id': 'protocols', 'name': 'Protokoły', 'icon': Icons.fact_check_rounded},
          {'id': 'estimations', 'name': 'Wyceny', 'icon': Icons.calculate_rounded},
          {'id': 'important_files', 'name': 'Pliki', 'icon': Icons.file_present_rounded},
          {'id': 'installation_docs', 'name': 'Zdjęcia', 'icon': Icons.photo_library_rounded},
        ]
      },
      {
        'title': 'NARZĘDZIA TECHNICZNE',
        'items': [
          {'id': 'lan_labels', 'name': 'Opis LAN', 'icon': Icons.lan_rounded},
          {'id': 'db_labels', 'name': 'Opisy Rozdz.', 'icon': Icons.label_important_outline},
          {'id': 'schematic', 'name': 'Schematy', 'icon': Icons.schema_outlined},
          {'id': 'visualizer', 'name': 'Wizualizacja', 'icon': Icons.view_quilt_rounded},
          {'id': 'cable_calc', 'name': 'Kable', 'icon': Icons.electrical_services},
          {'id': 'nfc', 'name': 'NFC', 'icon': Icons.nfc},
          {'id': 'label_printer', 'name': 'Drukarka', 'icon': Icons.print_rounded},
          {'id': 'flashlight', 'name': 'Latarka', 'icon': Icons.flashlight_on},
          {'id': 'lux_meter', 'name': 'Luksomierz', 'icon': Icons.light_mode},
        ]
      },
    ];

    final Map<String, String> special = {
      'manage_orders': 'PEŁNA EDYCJA ZLECEŃ',
      'can_takeover_orders': 'PRZEJMOWANIE ZLECEŃ',
      'kadry': 'ADMINISTRACJA KADRAMI',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("DOSTĘP DO MODUŁÓW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.4))),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    for (var cat in categories) {
                      for (var item in cat['items'] as List) {
                        _p[item['id']] = true;
                      }
                    }
                    special.keys.forEach((k) => _p[k] = true);
                  }),
                  child: const Text("Włącz wszystko", style: TextStyle(fontSize: 10, color: Colors.green))
                ),
                TextButton(onPressed: () => setState(() => _p = {}), child: const Text("Wyłącz", style: TextStyle(fontSize: 10, color: Colors.red))),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        ...categories.map((cat) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cat['title'], style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFF007BFF), letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (cat['items'] as List).map((item) {
                  final bool isSel = _p[item['id']] == true;
                  return InkWell(
                    onTap: () => setState(() => _p[item['id']] = !isSel),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFF007BFF) : theme.colorScheme.onSurface.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSel ? const Color(0xFF007BFF) : theme.colorScheme.onSurface.withOpacity(0.05)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item['icon'], size: 14, color: isSel ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.4)),
                          const SizedBox(width: 8),
                          Text(
                            item['name'], 
                            style: TextStyle(
                              fontSize: 10, 
                              fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                              color: isSel ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.7)
                            )
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        )).toList(),

        const Divider(height: 32),
        Text("UPRAWNIENIA SPECJALNE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.orange.shade700, letterSpacing: 1.5)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: special.entries.map((e) {
            final bool isSel = _p[e.key] == true;
            return InkWell(
              onTap: () => setState(() => _p[e.key] = !isSel),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSel ? Colors.orange.shade800 : theme.colorScheme.onSurface.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSel ? Colors.orange.shade800 : theme.colorScheme.onSurface.withOpacity(0.05)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_rounded, size: 14, color: isSel ? Colors.white : Colors.orange.shade800.withOpacity(0.5)),
                    const SizedBox(width: 8),
                    Text(
                      e.value, 
                      style: TextStyle(
                        fontSize: 9, 
                        fontWeight: FontWeight.w900, 
                        color: isSel ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.7)
                      )
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _field(String l, TextEditingController c, {bool isNum = false}) {
    final theme = Theme.of(context);
    return TextField(
      controller: c, 
      keyboardType: isNum ? TextInputType.number : TextInputType.text, 
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: l, 
        labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
        border: const OutlineInputBorder(), 
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      )
    );
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
        text = "PO TERMINIE: ${diff.abs()} dni";
        col = Colors.red;
      } else if (diff == 0) {
        text = "WYGASA DZISIAJ";
        col = Colors.orange;
      } else {
        text = "ZOSTAŁO: $diff dni";
        if (diff <= 30) col = Colors.orange;
        else if (diff <= 90) col = Colors.yellow[800]!;
      }

      return Text(
        text,
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: col),
      );
    } catch (_) {
      return const SizedBox();
    }
  }

  Widget _drop(String l, String? v, List<String> opts, Function(String) onC) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<String>(
      value: opts.contains(v) ? v : null, 
      dropdownColor: theme.cardTheme.color,
      style: TextStyle(color: theme.colorScheme.onSurface),
      items: opts.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12)))).toList(), 
      onChanged: (val) => onC(val!), 
      decoration: InputDecoration(
        labelText: l, 
        labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
        border: const OutlineInputBorder(), 
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      )
    );
  }

  Widget _date(String l, String? v, Function(String) onP, {List<String>? imgUrls, VoidCallback? onUpload, TextEditingController? numCtrl, TextEditingController? scopeCtrl, String? sepGrp, String? sepRole, Function(String?)? onSepGrpC, Function(String?)? onSepRoleC, Function(int)? onDeleteImg, String? docKey, bool isContract = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool isExcluded = docKey != null && _excludedDocs[docKey] == true;
    final bool isIndefinite = v == "NIEOKREŚLONY";
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: isExcluded ? 0.4 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
              border: Border.all(color: isExcluded ? Colors.grey.withOpacity(0.2) : theme.colorScheme.onSurface.withOpacity(0.15)), 
              borderRadius: BorderRadius.circular(16)
            ), 
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: (isExcluded || isIndefinite) ? null : () async { 
                          DateTime? d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035)); 
                          if (d != null) onP(DateFormat('dd.MM.yyyy').format(d)); 
                        }, 
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, 
                          children: [
                            Row(
                              children: [
                                Text(
                                  l.toUpperCase(), 
                                  style: TextStyle(
                                    fontSize: 10, 
                                    fontWeight: FontWeight.w900,
                                    color: isExcluded ? Colors.grey : theme.colorScheme.primary.withOpacity(0.7),
                                    letterSpacing: 0.5
                                  )
                                ),
                                if (isExcluded)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                    child: const Text("WYKLUCZONE", style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.grey)),
                                  ),
                              ],
                            ), 
                            const SizedBox(height: 4),
                            Text(
                              isIndefinite ? "CZAS NIEOKREŚLONY" : ((v == null || v.isEmpty) ? 'USTAW DATĘ' : v), 
                              style: TextStyle(
                                fontSize: 14, 
                                fontWeight: FontWeight.w900, 
                                color: (isIndefinite) ? Colors.green : ((v == null || v.isEmpty) ? theme.colorScheme.onSurface.withOpacity(0.2) : theme.colorScheme.onSurface)
                              )
                            ),
                            if (v != null && v.isNotEmpty && !isExcluded && !isIndefinite) ...[
                              const SizedBox(height: 2),
                              _buildDaysRemaining(v),
                            ]
                          ]
                        ),
                      ),
                    ),
                    if (isContract && !isExcluded)
                      IconButton(
                        icon: Icon(isIndefinite ? Icons.all_inclusive_rounded : Icons.timer_rounded, size: 20, color: isIndefinite ? Colors.green : Colors.grey),
                        onPressed: () => onP(isIndefinite ? "" : "NIEOKREŚLONY"),
                        tooltip: isIndefinite ? "Ustaw datę końcową" : "Ustaw na czas nieokreślony",
                      ),
                    if (docKey != null)
                      IconButton(
                        icon: Icon(isExcluded ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: isExcluded ? Colors.orange : Colors.grey.withOpacity(0.3)),
                        onPressed: () => setState(() => _excludedDocs[docKey] = !isExcluded),
                        tooltip: isExcluded ? "Przywróć sprawdzanie" : "Wyklucz ze sprawdzania",
                      ),
                    if (v != null && v.isNotEmpty && !isExcluded)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20, color: Colors.redAccent),
                        onPressed: () => onP(""),
                        tooltip: "Wyczyść datę",
                      ),
                    if (onUpload != null && !isExcluded) ...[
                      IconButton(
                        icon: const Icon(Icons.add_a_photo_rounded, size: 22, color: Colors.blue), 
                        onPressed: onUpload,
                        tooltip: "Dodaj skan",
                      ),
                    ]
                  ],
                ),
                if (imgUrls != null && imgUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: imgUrls.length,
                      itemBuilder: (ctx, idx) => Stack(
                        children: [
                          InkWell(
                            onTap: () => _showImage(imgUrls[idx]),
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
                          if (onDeleteImg != null && !isExcluded)
                            Positioned(
                              top: -2, right: 2,
                              child: InkWell(
                                onTap: () => onDeleteImg(idx),
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
            )
          ),
        ),
        if (!isExcluded && (numCtrl != null || onSepGrpC != null)) ...[
          const SizedBox(height: 8),
          if (onSepGrpC != null) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: sepGrp,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: "GRUPA",
                      labelStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      DropdownMenuItem(value: 'G1', child: FittedBox(fit: BoxFit.scaleDown, child: Text("G1 - Elektryczne", style: const TextStyle(fontSize: 12)))),
                      DropdownMenuItem(value: 'G2', child: FittedBox(fit: BoxFit.scaleDown, child: Text("G2 - Cieplne", style: const TextStyle(fontSize: 12)))),
                      DropdownMenuItem(value: 'G3', child: FittedBox(fit: BoxFit.scaleDown, child: Text("G3 - Gazowe", style: const TextStyle(fontSize: 12)))),
                    ],
                    onChanged: onSepGrpC,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: sepRole,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: "ROLA",
                      labelStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      DropdownMenuItem(value: 'E', child: Text("E - Eksploatacja", style: const TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'D', child: Text("D - Dozór", style: const TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'E+D', child: Text("E+D", style: const TextStyle(fontSize: 12))),
                    ],
                    onChanged: onSepRoleC,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (numCtrl != null)
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: numCtrl,
                    style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: "NR DOKUMENTU / SERIA",
                      labelStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.tag_rounded, size: 16),
                    ),
                  ),
                ),
              if (numCtrl != null && scopeCtrl != null) const SizedBox(width: 8),
              if (scopeCtrl != null)
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: scopeCtrl,
                    style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: "ZAKRES UPRAWNIEŃ",
                      labelStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.electric_bolt_rounded, size: 16),
                      hintText: "np. do 1 kV",
                      hintStyle: const TextStyle(fontSize: 10, color: Colors.grey)
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
