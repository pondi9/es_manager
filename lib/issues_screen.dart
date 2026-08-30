import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/es_modal.dart';
import 'core/app_utils.dart';
import 'core/app_theme.dart';
import 'core/app_constants.dart';

class IssuesScreen extends StatefulWidget {
  final bool isAdmin;
  final String currentUserEmail;
  final String? orderId; 
  final String? orderName;
  final String? stageName;
  final List<dynamic>? stages;
  final String? initialIssueId;

  const IssuesScreen({
    super.key, 
    required this.isAdmin, 
    required this.currentUserEmail,
    this.orderId,
    this.orderName,
    this.stageName,
    this.stages,
    this.initialIssueId,
  });

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _recordingPath;
  XFile? _pickedImage;
  bool _isUploading = false;
  String _selectedPriority = "NORMALNY";
  
  // New UI State
  String _searchQuery = "";
  String _filterStatus = "Wszystkie";
  String? _selectedIssueId;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _commentCtrl = TextEditingController();
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _selectedIssueId = widget.initialIssueId;
    _loadCurrentUserName();
  }

  Future<void> _loadCurrentUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserName = prefs.getString('user_name');
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _commentCtrl.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/issue_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() { _isRecording = true; _recordingPath = null; });
      }
    } catch (e) { debugPrint("Start recording error: $e"); }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() { _isRecording = false; _recordingPath = path; });
    } catch (e) { debugPrint("Stop recording error: $e"); }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 50);
    if (image != null) setState(() => _pickedImage = image);
  }

  Future<void> _submitIssue({required String title, required String description}) async {
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Podaj tytuł problemu!")));
      return;
    }
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Podaj opis problemu!")));
      return;
    }

    setState(() => _isUploading = true);

    try {
      String? imageUrl;
      String? audioUrl;

      if (_pickedImage != null) {
        final imageRef = FirebaseStorage.instance.ref().child("issues/img_${DateTime.now().millisecondsSinceEpoch}.jpg");
        if (kIsWeb) { await imageRef.putData(await _pickedImage!.readAsBytes()); } 
        else { await imageRef.putFile(File(_pickedImage!.path)); }
        imageUrl = await imageRef.getDownloadURL();
      }

      if (_recordingPath != null && !kIsWeb) {
        final audioRef = FirebaseStorage.instance.ref().child("issues/audio_${DateTime.now().millisecondsSinceEpoch}.m4a");
        await audioRef.putFile(File(_recordingPath!));
        audioUrl = await audioRef.getDownloadURL();
      }

      final issueData = {
        'orderId': widget.orderId ?? 'general',
        'orderName': widget.orderName ?? 'Ogólne',
        'stageName': widget.stageName,
        'title': title,
        'description': description,
        'reportedBy': widget.currentUserEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
        'imageUrl': imageUrl,
        'audioUrl': audioUrl,
        'status': 'NOWY', // NOWY, W TRAKCIE, OCZEKUJE, ROZWIĄZANO, ZAMKNIĘTY
        'priority': _selectedPriority,
        'discussion': [],
        'solution': null,
        'resolvedBy': null,
        'resolvedAt': null,
      };

      await FirebaseFirestore.instance.collection('issues').add(issueData);

      await AppUtils.sendNotification(
        title: "⚠️ PROBLEM (${_selectedPriority}): ${widget.orderName ?? 'Budowa'}",
        content: title,
        target: 'admin',
        author: widget.currentUserEmail,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Zgłoszenie zostało wysłane!")));
      }
    } catch (e) {
      debugPrint("Submit issue error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Błąd wysyłania: $e")));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showAddIssueDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? selectedStage = widget.stageName;

    showEsModal(
      context,
      title: "NOWE ZGŁOSZENIE",
      content: StatefulBuilder(
        builder: (ctx, setS) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldLabel("TYTUŁ PROBLEMU"),
              TextField(
                controller: titleCtrl,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: _inputDecoration("np. Brak zasilania w salonie"),
              ),
              const SizedBox(height: 16),

              _buildFieldLabel("OPIS SZCZEGÓŁOWY"),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: _inputDecoration("Opisz co dokładnie się dzieje..."),
              ),
              const SizedBox(height: 16),

              _buildFieldLabel("ETAP REALIZACJI"),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
                child: DropdownButton<String>(
                  value: selectedStage,
                  isExpanded: true,
                  dropdownColor: theme.cardTheme.color,
                  underline: const SizedBox(),
                  hint: Text("Wybierz etap (opcjonalnie)", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 13)),
                  items: (widget.stages != null && widget.stages!.isNotEmpty)
                      ? widget.stages!.map((e) {
                          final String name = e is Map ? (e['name'] ?? "Bez nazwy") : e.toString();
                          return DropdownMenuItem<String>(
                            value: name,
                            child: Text(name, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13)),
                          );
                        }).toList()
                      : ["Ogólne", "Inne"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13)))).toList(),
                  onChanged: (v) => setS(() => selectedStage = v),
                ),
              ),
              const SizedBox(height: 16),

              _buildFieldLabel("PRIORYTET"),
              Row(
                children: ["NISKI", "NORMALNY", "PILNY"].map((p) {
                  final bool isSel = _selectedPriority == p;
                  Color pCol = p == 'PILNY' ? Colors.red : (p == 'NORMALNY' ? Colors.orange : Colors.blue);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () => setS(() => _selectedPriority = p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSel ? pCol.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSel ? pCol : (isDark ? Colors.white10 : Colors.black12), width: 2),
                          ),
                          child: Center(
                            child: Text(
                              p,
                              style: TextStyle(
                                color: isSel ? (isDark ? Colors.white : pCol) : (isDark ? Colors.white38 : Colors.black38),
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: _mediaBtn(
                      icon: Icons.camera_alt_rounded, 
                      label: _pickedImage != null ? "ZDJĘCIE DODANE" : "DODAJ ZDJĘCIE",
                      active: _pickedImage != null,
                      onTap: () async { await _pickImage(); setS(() {}); },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _mediaBtn(
                      icon: _isRecording ? Icons.stop : Icons.mic_rounded, 
                      label: _isRecording ? "NAGRYWANIE..." : (_recordingPath != null ? "GŁOS NAGRANY" : "NAGRAJ GŁOS"),
                      active: _recordingPath != null || _isRecording,
                      onTap: () async { if (_isRecording) await _stopRecording(); else await _startRecording(); setS(() {}); },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              if (_isUploading) 
                const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)))
              else
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007BFF), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    onPressed: () {
                      if (titleCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("TYTUŁ PROBLEMU jest obowiązkowy!")));
                        return;
                      }
                      _submitIssue(
                        title: titleCtrl.text.trim(),
                        description: descCtrl.text.trim(),
                      );
                    },
                    child: const Text("WYŚLIJ ZGŁOSZENIE", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                ),
            ],
          );
        }
      ),
    );
  }


  Widget _buildFieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(label, style: GoogleFonts.montserrat(color: Colors.white38, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
  );

  InputDecoration _inputDecoration(String hint) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 13),
      filled: true, 
      fillColor: Colors.white.withOpacity(isDark ? 0.05 : 1.0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: isDark ? BorderSide.none : BorderSide(color: theme.dividerTheme.color ?? Colors.black12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: isDark ? BorderSide.none : BorderSide(color: theme.dividerTheme.color ?? Colors.black12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _mediaBtn({required IconData icon, required String label, required bool active, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: active ? (icon == Icons.camera_alt_rounded ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1)) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: active ? (icon == Icons.camera_alt_rounded ? Colors.green : Colors.red) : (isDark ? Colors.transparent : Colors.black12)),
        ),
        child: Column(
          children: [
            Icon(icon, color: active ? (icon == Icons.camera_alt_rounded ? Colors.green : Colors.red) : (isDark ? Colors.white38 : Colors.black38), size: 24),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: active ? (isDark ? Colors.white : Colors.black87) : (isDark ? Colors.white38 : Colors.black38), fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildTopBar(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return _buildDesktopLayout();
          } else {
            return _buildMobileLayout();
          }
        },
      ),
    );
  }

  PreferredSizeWidget _buildTopBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return AppBar(
      backgroundColor: theme.appBarTheme.backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: isDark ? Colors.white70 : Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("PROBLEMY I UWAGI", style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
          if (widget.orderName != null)
            Text(widget.orderName!, style: GoogleFonts.montserrat(color: const Color(0xFF007BFF), fontWeight: FontWeight.bold, fontSize: 10)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007BFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: _showAddIssueDialog,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text("NOWE ZGŁOSZENIE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left Column: List
        SizedBox(
          width: 400,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Colors.white10, width: 1)),
            ),
            child: _buildIssueList(isDesktop: true),
          ),
        ),
        // Right Column: Details
        Expanded(
          child: _selectedIssueId == null
              ? _buildEmptyDetails()
              : _buildIssueDetails(_selectedIssueId!),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return _selectedIssueId == null 
        ? _buildIssueList(isDesktop: false) 
        : _buildIssueDetails(_selectedIssueId!, isMobile: true);
  }

  Widget _buildEmptyDetails() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.speaker_notes_outlined, size: 64, color: theme.colorScheme.onSurface.withOpacity(0.05)),
          const SizedBox(height: 16),
          Text("Wybierz zgłoszenie z listy,\naby zobaczyć szczegóły", 
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildIssueList({required bool isDesktop}) {
    Query query = FirebaseFirestore.instance.collection('issues');
    if (widget.orderId != null) query = query.where('orderId', isEqualTo: widget.orderId);
    else if (!widget.isAdmin) query = query.where('reportedBy', isEqualTo: widget.currentUserEmail);
    
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildListHeader(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)));
              
              var issues = snapshot.data!.docs.map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id}).toList();
              
              // Local Search & Filter
              issues = issues.where((i) {
                final matchSearch = (i['description'] ?? "").toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
                                   (i['title'] ?? "").toString().toLowerCase().contains(_searchQuery.toLowerCase());
                final matchStatus = _filterStatus == "Wszystkie" || i['status'] == _filterStatus.toUpperCase();
                return matchSearch && matchStatus;
              }).toList();

              issues.sort((a, b) {
                final t1 = a['timestamp'] as Timestamp?;
                final t2 = b['timestamp'] as Timestamp?;
                if (t1 == null) return 1; if (t2 == null) return -1;
                return t2.compareTo(t1);
              });

              if (issues.isEmpty) return Center(child: Text("Brak zgłoszeń.", style: TextStyle(color: theme.brightness == Brightness.dark ? Colors.white24 : Colors.black26)));

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: issues.length,
                itemBuilder: (context, index) => _buildCompactIssueCard(issues[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.cardTheme.color?.withOpacity(0.5),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Szukaj...",
              hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
              prefixIcon: Icon(Icons.search, color: isDark ? Colors.white24 : Colors.black26, size: 18),
              filled: true, fillColor: Colors.white.withOpacity(isDark ? 0.05 : 1.0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: isDark ? BorderSide.none : BorderSide(color: theme.dividerTheme.color ?? Colors.grey.shade200)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ["Wszystkie", "Nowy", "W trakcie", "Do ustalenia", "Rozwiązano", "Zamknięty"].map((s) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(s, style: TextStyle(fontSize: 10, color: _filterStatus == s ? Colors.white : (isDark ? Colors.white60 : Colors.black54))),
                  selected: _filterStatus == s,
                  selectedColor: const Color(0xFF007BFF),
                  backgroundColor: isDark ? const Color(0xFF001A2C) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: _filterStatus == s ? const Color(0xFF007BFF) : (isDark ? Colors.white10 : Colors.grey.shade200)),
                  ),
                  showCheckmark: false,
                  onSelected: (val) { if (val) setState(() => _filterStatus = s); },
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactIssueCard(Map<String, dynamic> issue) {
    final String id = issue['id'];
    final bool isSelected = _selectedIssueId == id;
    final String status = issue['status'] ?? 'NOWY';
    final String priority = issue['priority'] ?? 'NORMALNY';
    final Color prioCol = _getPriorityColor(priority);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF007BFF).withOpacity(0.1) : theme.cardTheme.color,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isSelected ? const Color(0xFF007BFF) : (theme.dividerTheme.color ?? Colors.white.withOpacity(0.05))),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)]
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedIssueId = id),
        borderRadius: BorderRadius.circular(15),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, decoration: BoxDecoration(color: prioCol, borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15)))),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(issue['title'] ?? issue['description'] ?? "Zgłoszenie bez tytułu", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12))),
                          const SizedBox(width: 8),
                          Text(issue['date']?.toString().split(' ').first ?? "", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 9)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _miniBadge(status, _getStatusColor(status)),
                          const SizedBox(width: 8),
                          Text(issue['reportedBy']?.toString().split('@').first ?? "", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 9, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(issue['stageName'] ?? "Ogólne", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 10))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniBadge(String text, Color col) {
    IconData icon;
    bool isClosed = text.toUpperCase() == 'ZAMKNIĘTY';
    
    switch (text.toUpperCase()) {
      case 'NOWY': icon = Icons.fiber_new_rounded; break;
      case 'W TRAKCIE': icon = Icons.engineering_rounded; break;
      case 'OCZEKUJE': icon = Icons.hourglass_empty_rounded; break;
      case 'ROZWIĄZANO': icon = Icons.check_circle_rounded; break;
      case 'ZAMKNIĘTY': icon = Icons.lock_outline_rounded; break;
      case 'PILNY': icon = Icons.warning_amber_rounded; break;
      case 'NORMALNY': icon = Icons.info_outline; break;
      case 'NISKI': icon = Icons.arrow_downward_rounded; break;
      default: icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isClosed ? col.withOpacity(0.2) : col.withOpacity(0.1), 
        borderRadius: BorderRadius.circular(8), 
        border: Border.all(color: isClosed ? col.withOpacity(0.5) : col.withOpacity(0.3))
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isClosed ? Colors.white70 : col, size: 10),
          const SizedBox(width: 4),
          Text(
            text.toUpperCase(), 
            style: TextStyle(
              color: isClosed ? Colors.white : col, 
              fontSize: 8, 
              fontWeight: FontWeight.w900, 
              letterSpacing: 0.5
            )
          ),
        ],
      ),
    );
  }

  Widget _buildIssueDetails(String issueId, {bool isMobile = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('issues').doc(issueId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (!snap.data!.exists) return _buildEmptyDetails();
        
        final rawData = snap.data!.data() as Map<String, dynamic>;
        final data = {...rawData, 'id': snap.data!.id};
        final discussion = data['discussion'] as List? ?? [];
        final status = data['status'] ?? 'NOWY';
        final priority = data['priority'] ?? 'NORMALNY';
        final Color statusCol = _getStatusColor(status);

        return Column(
          children: [
            if (isMobile) 
              Container(
                color: theme.appBarTheme.backgroundColor,
                child: IconButton(icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.white), onPressed: () => setState(() => _selectedIssueId = null)),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Management Bar
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(isDark ? 0.02 : 1.0),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200),
                        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text("AKTUALNY STATUS:", style: GoogleFonts.montserrat(color: isDark ? Colors.white38 : Colors.black38, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
                              const SizedBox(width: 12),
                              _miniBadge(status, statusCol),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ["NOWY", "W TRAKCIE", "DO USTALENIA", "ROZWIĄZANO", "ZAMKNIĘTY"].map((s) {
                              bool isCurrent = status == s;
                              if (isCurrent) return const SizedBox();
                              
                              return InkWell(
                                onTap: () => s == 'ROZWIĄZANO' ? _handleResolve(data) : _changeStatusDirectly(data, s),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: _getStatusColor(s).withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.sync_rounded, size: 12, color: _getStatusColor(s)),
                                      const SizedBox(width: 6),
                                      Text(s, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 9, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data['title'] ?? data['description'] ?? "Zgłoszenie bez tytułu", style: GoogleFonts.montserrat(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w900, fontSize: 22)),
                              if (data['title'] != null && data['description'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12.0),
                                  child: Text(data['description'], style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 14, height: 1.5)),
                                ),
                            ],
                          ),
                        ),
                        if (widget.isAdmin) IconButton(icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent), onPressed: () => _confirmDelete(issueId)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _metaIcon(Icons.person_outline, data['reportedBy'] ?? "Nieznany"),
                        const SizedBox(width: 16),
                        _metaIcon(Icons.calendar_today_outlined, data['date'] ?? "-"),
                        const SizedBox(width: 16),
                        _miniBadge(priority, _getPriorityColor(priority)),
                      ],
                    ),
                    const Divider(height: 48),

                    // Description & Media
                    Text("OPIS I MEDIA", style: GoogleFonts.montserrat(color: isDark ? Colors.white38 : Colors.black38, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
                    const SizedBox(height: 16),
                    if (data['imageUrl'] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(data['imageUrl'], width: double.infinity, fit: BoxFit.cover)),
                      ),
                    if (data['audioUrl'] != null)
                      _audioPlayerWidget(data['audioUrl']),

                    const Divider(height: 48),

                    // Timeline Discussion
                    Text("USTALENIA I DYSKUSJA", style: GoogleFonts.montserrat(color: isDark ? Colors.white38 : Colors.black38, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
                    const SizedBox(height: 24),
                    ...discussion.map((msg) => _buildTimelineItem(msg)).toList(),
                    
                    if (data['solution'] != null)
                      _buildSolutionItem(data),

                    const SizedBox(height: 100), // Bottom padding
                  ],
                ),
              ),
            ),

            // Bottom Input
            if (status != 'ZAMKNIĘTY')
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.appBarTheme.backgroundColor,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -5))],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: "Dodaj ustalenie lub komentarz...",
                          hintStyle: const TextStyle(color: Colors.white24),
                          filled: true, fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (status != 'ROZWIĄZANY' && status != 'ROZWIĄZANO')
                      IconButton(
                        style: IconButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.1)),
                        icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                        onPressed: () => _handleResolve(data),
                        tooltip: "Rozwiąż problem",
                      ),
                    Material(
                      color: const Color(0xFF007BFF),
                      borderRadius: BorderRadius.circular(12),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        onPressed: () async {
                          if (_commentCtrl.text.isEmpty) return;
                          final String authorName = widget.isAdmin 
                              ? "SZEF" 
                              : (_currentUserName ?? widget.currentUserEmail);
                          
                          await FirebaseFirestore.instance.collection('issues').doc(issueId).update({
                            'discussion': FieldValue.arrayUnion([{
                              'text': _commentCtrl.text.trim(),
                              'author': authorName,
                              'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
                            }])
                          });
                          _commentCtrl.clear();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _metaIcon(IconData icon, String text, {Color? col}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: col ?? theme.colorScheme.onSurface.withOpacity(0.3)),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: col ?? theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> msg) {
    bool isAdmin = msg['author'] == "SZEF" || msg['author'] == "ADMIN";
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isAdmin ? const Color(0xFF007BFF) : (isDark ? Colors.white10 : Colors.grey.shade200),
            child: Icon(
              isAdmin ? Icons.engineering_rounded : Icons.person_rounded,
              size: 14,
              color: isAdmin ? Colors.white : (isDark ? Colors.white70 : Colors.black45),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(msg['author'], style: TextStyle(color: isAdmin ? const Color(0xFF007BFF) : (isDark ? Colors.white70 : Colors.black87), fontWeight: FontWeight.bold, fontSize: 11)),
                    Text(msg['date'], style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 8)),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(isAdmin ? 0.05 : 0.02) : (isAdmin ? Colors.blue.shade50 : Colors.grey.shade100), 
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(15),
                      bottomLeft: Radius.circular(15),
                      bottomRight: Radius.circular(15),
                    ),
                    border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent)
                  ),
                  child: Text(msg['text'], style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 12, height: 1.4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSolutionItem(Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: Colors.green, size: 20),
              const SizedBox(width: 10),
              Text("USTALONE ROZWIĄZANIE", style: GoogleFonts.montserrat(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Text(data['solution'], style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text("Rozwiązano przez: ${data['resolvedBy']} | ${data['resolvedAt']}", style: const TextStyle(color: Colors.white38, fontSize: 9)),
          if (data['status'] == 'ROZWIĄZANY' && widget.isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                onPressed: () => _handleClose(data),
                child: const Text("ZAMKNIJ ZGŁOSZENIE"),
              ),
            ),
        ],
      ),
    );
  }

  Widget _audioPlayerWidget(String url) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          const Icon(Icons.play_circle_fill, color: Color(0xFF007BFF), size: 32),
          const SizedBox(width: 12),
          const Text("NAGRANIE GŁOSOWE", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton(onPressed: () => _audioPlayer.play(UrlSource(url)), child: const Text("ODTWÓRZ")),
        ],
      ),
    );
  }

  Future<void> _changeStatusDirectly(Map<String, dynamic> data, String newStatus) async {
    final String oldStatus = data['status'] ?? "NOWY";
    final String now = DateFormat('dd.MM HH:mm').format(DateTime.now());
    final String user = widget.isAdmin ? "SZEF" : "INWESTOR";

    await FirebaseFirestore.instance.collection('issues').doc(data['id']).update({
      'status': newStatus,
      'discussion': FieldValue.arrayUnion([{
        'text': "🔄 ZMIANA STATUSU: $oldStatus ➔ $newStatus",
        'author': "SYSTEM",
        'date': now,
      }])
    });
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Zmieniono status na $newStatus")));
  }

  void _handleResolve(Map<String, dynamic> data) {
    final solCtrl = TextEditingController();
    showEsModal(
      context,
      title: "ROZWIĄŻ PROBLEM",
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Opisz w jaki sposób problem został rozwiązany. Ta informacja zostanie zapisana w historii.", 
            style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: solCtrl,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration("Wpisz opis rozwiązania..."),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANULUJ", style: TextStyle(color: Colors.white38))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
          onPressed: () async {
            final solution = solCtrl.text.trim();
            if (solution.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Opisz najpierw sposób rozwiązania problemu!"), backgroundColor: Colors.orange));
              return;
            }
            
            try {
              final now = DateFormat('dd.MM HH:mm').format(DateTime.now());
              final userLabel = widget.isAdmin ? "ADMIN" : "INWESTOR";

              await FirebaseFirestore.instance.collection('issues').doc(data['id']).update({
                'status': 'ROZWIĄZANO',
                'solution': solution,
                'resolvedBy': widget.currentUserEmail,
                'resolvedAt': now,
                'discussion': FieldValue.arrayUnion([{
                  'text': "✅ PROBLEM ROZWIĄZANY: $solution",
                  'author': userLabel,
                  'date': now,
                }])
              });
              
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Problem został rozwiązany"), backgroundColor: Colors.green));
              }
            } catch (e) {
              debugPrint("Resolve issue error: $e");
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Błąd zapisu: $e"), backgroundColor: Colors.red));
            }
          }, 
          child: const Text("ZATWIERDŹ", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }


  void _handleClose(Map<String, dynamic> data) async {
    final bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text("ZAMKNĄĆ ZGŁOSZENIE?"),
      content: const Text("Zgłoszenie zostanie przeniesione do historii jako zamknięte."),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("NIE")), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("TAK"))],
    ));
    if (confirm == true) _updateStatus(data['id'], "ZAMKNIĘTY");
  }

  void _updateStatus(String id, String status) async {
    await FirebaseFirestore.instance.collection('issues').doc(id).update({'status': status});
  }

  void _confirmDelete(String id) async {
    final bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text("USUŃ TRWALE?"),
      content: const Text("Czy na pewno chcesz bezpowrotnie usunąć to zgłoszenie?"),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ANULUJ")), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("USUŃ"))],
    ));
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('issues').doc(id).delete();
      setState(() => _selectedIssueId = null);
    }
  }

  Color _getStatusColor(String s) {
    switch (s.toUpperCase()) {
      case 'NOWY': return Colors.red;
      case 'W TRAKCIE': return Colors.orange;
      case 'OCZEKUJE': return Colors.blue;
      case 'DO USTALENIA': return Colors.amber;
      case 'ROZWIĄZANO': return Colors.green;
      case 'ZAMKNIĘTY': return Colors.blueGrey;
      default: return Colors.grey;
    }
  }

  Color _getPriorityColor(String p) {
    switch (p) {
      case 'PILNY': return Colors.red;
      case 'NORMALNY': return Colors.orange;
      case 'NISKI': return Colors.blue;
      default: return Colors.grey;
    }
  }
}
