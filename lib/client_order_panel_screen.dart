import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/app_theme.dart';
import 'notifications_screen.dart';
import 'chat_screen.dart';
import 'protocols_screen.dart';
import 'client_full_docs_screen.dart';
import 'issues_screen.dart';
import 'core/app_constants.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'core/app_utils.dart';
import 'services/weather_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/theme_switcher.dart';
import 'widgets/es_modal.dart';
import 'core/nexus_engine.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class ClientOrderPanelScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const ClientOrderPanelScreen({super.key, required this.order});
  @override
  State<ClientOrderPanelScreen> createState() => _ClientOrderPanelScreenState();
}

class _ClientOrderPanelScreenState extends State<ClientOrderPanelScreen> {
  late Map<String, dynamic> _order;
  String? _responsibleName;
  String? _currentUserName;
  String? _currentUserEmail;
  int _selectedIndex = 0;
  int _openIssuesCount = 0;
  List<Map<String, dynamic>> _allIssues = [];
  Map<String, int> _lastReadStates = {};
  Map<String, dynamic>? _weatherData;
  StreamSubscription? _issueSub;
  bool _isEditMode = false;
  final ScrollController _scrollController = ScrollController();
  
  // Drag & Resize state
  String? _draggingTileId;
  double? _dragVisualX;
  double? _dragVisualY;
  String? _resizingTileId;
  double? _resizeVisualW;
  double? _resizeVisualH;

  late List<NexusTile> _nexusTiles;

  final TextEditingController _quickChatCtrl = TextEditingController();
  final WeatherService _weatherService = WeatherService();

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _nexusTiles = _getDefaultNexusTiles();
    _listenToOrderUpdates(); _fetchResponsibleName(); _setupStreams(); _fetchWeather(); _loadNexusBlueprint();
    _loadReadStates();
    _fetchCurrentUserName();
  }

  Future<void> _fetchCurrentUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserName = prefs.getString('user_name');
      _currentUserEmail = prefs.getString(AppConstants.keyUserEmail);
    });
  }

  @override
  void dispose() { _issueSub?.cancel(); _quickChatCtrl.dispose(); _scrollController.dispose(); super.dispose(); }

  Future<void> _loadReadStates() async {
    final prefs = await SharedPreferences.getInstance();
    final String userEmail = prefs.getString(AppConstants.keyUserEmail) ?? 'guest';
    final String key = 'unread_states_${userEmail}_${_order['id']}';
    final String? data = prefs.getString(key);
    if (data != null) {
      setState(() {
        _lastReadStates = Map<String, int>.from(json.decode(data));
      });
    }
  }

  Future<void> _markStageAsRead(String stageName) async {
    final prefs = await SharedPreferences.getInstance();
    final String userEmail = prefs.getString(AppConstants.keyUserEmail) ?? 'guest';
    final String key = 'unread_states_${userEmail}_${_order['id']}';
    
    setState(() {
      _lastReadStates[stageName] = DateTime.now().millisecondsSinceEpoch;
    });
    await prefs.setString(key, json.encode(_lastReadStates));
  }

  List<Map<String, dynamic>> _getStageActivities(Map<String, dynamic> stage) {
    List<Map<String, dynamic>> acts = [];
    final String sName = stage['name'] ?? "";
    
    // Logs
    if (stage['logs'] != null) {
      for (var log in (stage['logs'] as List)) {
        acts.add({
          'type': 'LOG',
          'text': log['text'],
          'author': log['author'] ?? "SYSTEM",
          'dateStr': log['date'],
          'stage': sName,
          'icon': _getActivityIcon(log['text']),
          'color': _getActivityColor(log['text']),
          'timestamp': _parseActivityDate(log['date']),
        });
      }
    }
    
    // Issues
    final stageIssues = _allIssues.where((i) => i['stageName'] == sName);
    for (var issue in stageIssues) {
      acts.add({
        'type': 'ISSUE',
        'text': "⚠️ PROBLEM: ${issue['title']}",
        'author': issue['reportedBy'] ?? "Anonim",
        'dateStr': issue['date'],
        'stage': sName,
        'icon': Icons.warning_amber_rounded,
        'color': Colors.redAccent,
        'timestamp': _parseActivityDate(issue['date']),
      });
      
      // Discussion in issues
      if (issue['discussion'] != null) {
        for (var msg in (issue['discussion'] as List)) {
          acts.add({
            'type': 'COMMENT',
            'text': "💬 ${msg['text']}",
            'author': msg['author'],
            'dateStr': msg['date'],
            'stage': sName,
            'icon': Icons.chat_bubble_outline_rounded,
            'color': Colors.blue,
            'timestamp': _parseActivityDate(msg['date']),
          });
        }
      }
    }

    acts.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
    return acts;
  }

  IconData _getActivityIcon(String text) {
    if (text.contains("✅") || text.contains("ZAKOŃCZONO")) return Icons.check_circle_rounded;
    if (text.contains("🚀") || text.contains("MELDUNEK")) return Icons.engineering_rounded;
    if (text.contains("🗓️")) return Icons.calendar_month_rounded;
    if (text.contains("📁")) return Icons.file_present_rounded;
    if (text.contains("🔌")) return Icons.power_rounded;
    return Icons.info_outline_rounded;
  }

  Color _getActivityColor(String text) {
    if (text.contains("✅")) return Colors.green;
    if (text.contains("🚀")) return Colors.orange;
    if (text.contains("🗓️")) return Colors.blue;
    if (text.contains("📁")) return Colors.indigoAccent;
    if (text.contains("🔌")) return Colors.amber;
    return Colors.white30;
  }

  int _parseActivityDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 0;
    try {
      // Format: dd.MM HH:mm
      final parts = dateStr.split(' ');
      final dateParts = parts[0].split('.');
      final timeParts = parts[1].split(':');
      
      final now = DateTime.now();
      final dt = DateTime(
        now.year, 
        int.parse(dateParts[1]), 
        int.parse(dateParts[0]), 
        int.parse(timeParts[0]), 
        int.parse(timeParts[1])
      );
      // If date is in future (e.g. Dec vs Jan), assume last year
      if (dt.isAfter(now.add(const Duration(days: 1)))) {
        return DateTime(dt.year - 1, dt.month, dt.day, dt.hour, dt.minute).millisecondsSinceEpoch;
      }
      return dt.millisecondsSinceEpoch;
    } catch (_) { return 0; }
  }

  Widget _buildRecentActivityFeed() {
    List<Map<String, dynamic>> allActs = [];
    final List stages = _order['stages'] as List? ?? [];
    for (var s in stages) {
      allActs.addAll(_getStageActivities(s));
    }
    allActs.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
    final displayActs = allActs.take(15).toList();
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bentoHeader("OSTATNIA AKTYWNOŚĆ", "PEŁNA LISTA", _showHistory, icon: Icons.notifications_active_rounded, iconCol: Colors.blueAccent),
          const SizedBox(height: 16),
          if (displayActs.isEmpty)
             Expanded(child: Center(child: Text("Brak aktywności.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.1), fontSize: 11))))
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: displayActs.length,
                itemBuilder: (context, i) {
                  final a = displayActs[i];
                  return InkWell(
                    onTap: () {
                      final stageIdx = stages.indexWhere((s) => s['name'] == a['stage']);
                      if (stageIdx != -1) _showStageDetails(stages[stageIdx], stageIdx + 1);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: a['color'].withOpacity(0.1), shape: BoxShape.circle),
                            child: Icon(a['icon'], color: a['color'], size: 14),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(a['author'].toString().toUpperCase(), style: GoogleFonts.montserrat(color: a['color'], fontWeight: FontWeight.w900, fontSize: 8)),
                                    Text(a['dateStr'], style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 8)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(a['text'], maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 11, height: 1.3, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text("# ${a['stage']}", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.15), fontSize: 8, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<NexusTile> _getDefaultNexusTiles() => [
    NexusTile(id: 'recent_activity', title: 'OSTATNIA AKTYWNOŚĆ', icon: Icons.notifications_active_rounded, width: 4, height: 3, x: 0, y: 0),
    NexusTile(id: 'weather', title: 'POGODA', icon: Icons.cloud_queue_rounded, width: 2, height: 2, x: 4, y: 0),
    NexusTile(id: 'chat', title: 'KOMUNIKACJA', icon: Icons.forum_rounded, width: 2, height: 2, x: 4, y: 2),
    NexusTile(id: 'stages', title: 'ETAPY REALIZACJI', icon: Icons.view_list_rounded, width: 3, height: 4, x: 0, y: 3),
    NexusTile(id: 'next_step', title: 'CO DALEJ?', icon: Icons.calendar_month, width: 3, height: 1, x: 3, y: 4),
    NexusTile(id: 'photos', title: 'ZDJĘCIA', icon: Icons.photo_library, width: 2, height: 2, x: 0, y: 7),
    NexusTile(id: 'docs', title: 'DOKUMENTY', icon: Icons.folder_shared, width: 2, height: 2, x: 2, y: 7),
    NexusTile(id: 'before_after', title: 'PRZED vs PO', icon: Icons.compare, width: 2, height: 2, x: 4, y: 7),
  ];

  void _setupStreams() {
    final String orderId = _order['id'].toString().toLowerCase().trim();
    _issueSub = FirebaseFirestore.instance.collection('issues').where('orderId', isEqualTo: orderId).snapshots().listen((snap) {
      if (mounted) { 
        final all = snap.docs.map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id}).toList(); 
        setState(() { 
          _allIssues = all; 
          // Open issues are only those that are NOT Resolved and NOT Closed
          _openIssuesCount = all.where((i) => 
            i['status'] != 'ROZWIĄZANO' && i['status'] != 'ZAMKNIĘTY'
          ).length; 
        }); 
      }
    });
  }

  Future<String> _getNexusStorageKey() async {
    final prefs = await SharedPreferences.getInstance();
    final String userEmail = prefs.getString(AppConstants.keyUserEmail) ?? 'guest';
    return 'es_nexus_layout_${userEmail}_${_order['id']}';
  }

  Future<void> _loadNexusBlueprint() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _getNexusStorageKey();
    final String? data = prefs.getString(key);
    if (data != null) {
      try {
        final List decoded = json.decode(data);
        setState(() {
          for (var item in decoded) {
            final tileIdx = _nexusTiles.indexWhere((t) => t.id == item['id']);
            if (tileIdx != -1) { 
              _nexusTiles[tileIdx].width = (item['width'] ?? _nexusTiles[tileIdx].width).toDouble(); 
              _nexusTiles[tileIdx].height = (item['height'] ?? _nexusTiles[tileIdx].height).toDouble(); 
              _nexusTiles[tileIdx].x = (item['x'] ?? _nexusTiles[tileIdx].x).toDouble();
              _nexusTiles[tileIdx].y = (item['y'] ?? _nexusTiles[tileIdx].y).toDouble();
              _nexusTiles[tileIdx].order = item['order'] ?? _nexusTiles[tileIdx].order; 
              _nexusTiles[tileIdx].isHidden = item['isHidden'] ?? false; 
            }
          }
          _nexusTiles.sort((a, b) => a.order.compareTo(b.order));
        });
      } catch (e) { debugPrint("Nexus load error: $e"); }
    }
  }

  Future<void> _saveNexusBlueprint() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _getNexusStorageKey();
    final data = _nexusTiles.map((t) => t.toJson()).toList();
    await prefs.setString(key, json.encode(data));
  }

  void _resetNexusLayout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("PRZYWRÓCIĆ DOMYŚLNY UKŁAD?"),
        content: const Text("Czy na pewno chcesz przywrócić domyślny układ kafli? Twoje zmiany zostaną usunięte."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("NIE")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("TAK, PRZYWRÓĆ")),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _nexusTiles = _getDefaultNexusTiles();
      });
      await _saveNexusBlueprint();
    }
  }

  Future<void> _fetchWeather() async {
    final String? loc = _order['location']; if (loc == null || loc.isEmpty || loc.contains("http")) return;
    final data = await _weatherService.getWeatherByAddress(loc);
    if (data != null && mounted) setState(() => _weatherData = data);
  }

  Future<void> _fetchResponsibleName() async {
    final email = _order['responsible_person']; if (email == null) return;
    if (email == AppConstants.adminEmail) { if (mounted) setState(() => _responsibleName = "Marcin Kiczek"); return; }
    try {
      final snap = await FirebaseFirestore.instance.collection('employees').doc(email).get();
      if (snap.exists && mounted) { final d = snap.data(); setState(() => _responsibleName = "${d?['firstName'] ?? ''} ${d?['lastName'] ?? ''}".trim()); }
    } catch (_) {}
  }

  void _listenToOrderUpdates() { FirebaseFirestore.instance.collection('orders').doc(_order['id']).snapshots().listen((snap) { if (snap.exists && mounted) { final oldResp = _order['responsible_person']; setState(() => _order = snap.data()!); if (oldResp != _order['responsible_person']) _fetchResponsibleName(); } }); }
  Future<void> _saveOrderChanges() async { try { await FirebaseFirestore.instance.collection('orders').doc(_order['id']).set(_order); } catch (e) { debugPrint("Save error: $e"); } }

  void _onReorder(List<dynamic> Function(List<dynamic>) reorderFunction) {
    setState(() {
      final visibleTiles = _nexusTiles.where((t) => !t.isHidden || _isEditMode).toList();
      final newVisibleTiles = reorderFunction(visibleTiles).cast<NexusTile>();
      
      for (int i = 0; i < newVisibleTiles.length; i++) {
        newVisibleTiles[i].order = i;
      }
      _nexusTiles.sort((a, b) => a.order.compareTo(b.order));
    });
    _saveNexusBlueprint();
  }

  double _calculateProgress() { final List s = _order['stages'] as List? ?? []; if (s.isEmpty) return 0; int d = s.where((st) => st['status'] == 'ZAKOŃCZONO').length; return d / s.length; }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool isD = width > 1100;
    final bool isMobile = width < 700;
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(children: [
        if (isD) _buildSidebar(),
        Expanded(child: Column(children: [ 
          _buildTopBar(isD, isMobile), 
          Expanded(child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200), 
            child: (isMobile && _selectedIndex == 0) 
              ? _buildMobileDashboard() 
              : _buildCurrentView(isD)
          )) 
        ])),
      ]),
      drawer: isD ? null : Drawer(backgroundColor: const Color(0xFF001A2C), child: _buildSidebar(isMobile: true)),
      bottomNavigationBar: isMobile ? _buildMobileBottomNav() : null,
      floatingActionButton: _selectedIndex == 3 ? FloatingActionButton.extended(
        onPressed: () {
          final List stages = _order['stages'] as List? ?? [];
          if (stages.isEmpty) return;
          final currentStage = stages.firstWhere((s) => s['status'] == 'W TRAKCIE', orElse: () => stages.last);
          _pickAndUploadPhoto(currentStage);
        },
        backgroundColor: const Color(0xFF007BFF),
        icon: const Icon(Icons.add_a_photo_rounded, color: Colors.white),
        label: const Text("DODAJ ZDJĘCIE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ) : null,
    );
  }

  Widget _buildMobileBottomNav() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF001A2C) : Colors.white,
        border: Border(top: BorderSide(color: theme.dividerTheme.color ?? Colors.black12, width: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex == 0 ? 0 : (_selectedIndex == 2 ? 1 : (_selectedIndex == 6 ? 2 : 3)),
        onTap: (idx) {
          setState(() {
            if (idx == 0) _selectedIndex = 0;
            else if (idx == 1) _selectedIndex = 2; // Historia / Aktywność
            else if (idx == 2) _selectedIndex = 6; // Wiadomości
            else _selectedIndex = 0; // Default or Open Drawer
          });
          if (idx == 3) Scaffold.of(context).openDrawer();
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: const Color(0xFF007BFF),
        unselectedItemColor: theme.colorScheme.onSurface.withOpacity(0.4),
        selectedFontSize: 10,
        unselectedFontSize: 10,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: "Pulpit"),
          BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: "Aktywność"),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: "Czat"),
          BottomNavigationBarItem(icon: Icon(Icons.menu_rounded), label: "Menu"),
        ],
      ),
    );
  }

  Widget _buildMobileDashboard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        _buildMobileHeroCard(),
        const SizedBox(height: 24),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.15,
          children: [
            _mobileMenuTile(
              "ETAPY", 
              Icons.view_list_rounded, 
              Colors.blue, 
              "${(_order['stages'] as List? ?? []).where((s)=>s['status']=='ZAKOŃCZONO').length} / ${(_order['stages'] as List? ?? []).length}",
              () => setState(() => _selectedIndex = 1)
            ),
            _mobileMenuTile(
              "ZDJĘCIA", 
              Icons.photo_library_rounded, 
              Colors.orange, 
              "${_calculatePhotoCount()}",
              () => setState(() => _selectedIndex = 3)
            ),
            _mobileMenuTile(
              "WIADOMOŚCI", 
              Icons.forum_rounded, 
              Colors.teal, 
              "OTWÓRZ", 
              () => setState(() => _selectedIndex = 6)
            ),
            _mobileMenuTile(
              "PROBLEMY", 
              Icons.report_problem_rounded, 
              Colors.red, 
              _openIssuesCount == 0 ? "BRAK" : "$_openIssuesCount OTWARTE",
              () => setState(() => _selectedIndex = 5)
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildTodayOnSiteSection(),
        const SizedBox(height: 100), // Bottom padding for nav
      ],
    );
  }

  int _calculatePhotoCount() {
    int count = 0;
    final List stages = _order['stages'] as List? ?? [];
    for (var s in stages) {
      if (s != null && s is Map && s['photos'] != null) count += (s['photos'] as List).length;
    }
    return count;
  }

  Widget _mobileMenuTile(String title, IconData icon, Color color, String info, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
          boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                const SizedBox(height: 4),
                Text(info, style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 12, color: theme.colorScheme.onSurface)),
              ],
            ),
            Row(
              children: [
                Text("OTWÓRZ", style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, color: color, size: 10),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTodayOnSiteSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Data Extraction
    final String dateStr = DateFormat('dd LLLL', 'pl_PL').format(DateTime.now()).toUpperCase();
    final crews = _order['assigned_crews'] as List? ?? (_order['assigned_crew'] != null ? [_order['assigned_crew']] : []);
    final String crew = crews.isNotEmpty ? crews.join(", ") : "ES TEAM";
    final List stages = _order['stages'] as List? ?? [];
    final currentStage = stages.firstWhere((s) => s['status'] == 'W TRAKCIE', orElse: () => null);
    
    // Latest Activity from logs
    Map<String, dynamic>? lastActivity;
    List<Map<String, dynamic>> allActs = [];
    for (var s in stages) {
      allActs.addAll(_getStageActivities(s));
    }
    if (allActs.isNotEmpty) {
      allActs.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
      lastActivity = allActs.first;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF001A2C) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, color: Color(0xFF007BFF), size: 18),
              const SizedBox(width: 12),
              Text(
                "DZISIAJ – $dateStr", 
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w900, 
                  fontSize: 12, 
                  letterSpacing: 1,
                  color: const Color(0xFF007BFF)
                )
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          _todayInfoRow(Icons.groups_rounded, "Ekipa:", crew, Colors.blue),
          const SizedBox(height: 12),
          _todayInfoRow(Icons.construction_rounded, "Aktualny etap:", currentStage?['name'] ?? "Planowanie", Colors.orange),
          const SizedBox(height: 12),
          _todayInfoRow(
            Icons.rocket_launch_rounded, 
            "Ostatnia aktywność:", 
            lastActivity?['text'] ?? "Brak meldunków", 
            Colors.green,
            isLongText: true
          ),
        ],
      ),
    );
  }

  Widget _todayInfoRow(IconData icon, String label, String value, Color iconCol, {bool isLongText = false}) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: isLongText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: iconCol.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: iconCol, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                value, 
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w700, 
                  fontSize: 12, 
                  color: theme.colorScheme.onSurface
                ),
                maxLines: isLongText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildMobileHeroCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final double p = _calculateProgress();
    final timeStats = _calculateTimeStats();

    return InkWell(
      onTap: _showStatusDetails,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark 
              ? [const Color(0xFF001A2C), const Color(0xFF002B4D)] 
              : [Colors.white, const Color(0xFFF8FAFC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
          boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _statusTag(_order['status'] ?? 'W TRAKCIE'),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFF007BFF).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Text("${(p * 100).round()}% GOTOWE", style: const TextStyle(color: Color(0xFF007BFF), fontSize: 10, fontWeight: FontWeight.w900)),
                )
              ],
            ),
            const SizedBox(height: 20),
            Text(_order['name'] ?? "Nazwa Inwestycji", style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 22, color: theme.colorScheme.onSurface, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on_rounded, size: 12, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                const SizedBox(width: 4),
                Expanded(child: Text(_order['location'] ?? "Brak adresu", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 24),
            Stack(
              children: [
                Container(
                  height: 10,
                  width: double.infinity,
                  decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 1000),
                  height: 10,
                  width: (MediaQuery.of(context).size.width - 88) * p,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF007BFF), Color(0xFF00C853)]),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: const Color(0xFF007BFF).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _heroDate("DZIEŃ REALIZACJI", "${timeStats['current']} / ${timeStats['total']}"),
                _heroDate("POZOSTAŁO", "${timeStats['left']} DNI"),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentView(bool isD) {
    switch (_selectedIndex) {
      case 0: return SingleChildScrollView(controller: _scrollController, key: const ValueKey("dashboard"), padding: const EdgeInsets.all(24), child: _buildNexusDashboard(isD));
      case 1: return _wrapWithBack(Padding(padding: const EdgeInsets.all(24), child: _buildStagesList(isLarge: true)), "ETAPY REALIZACJI");
      case 2: return _wrapWithBack(Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _buildFullHistoryView())])), "HISTORIA INWESTYCJI");
      case 3: return _wrapWithBack(Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _buildFullGalleryView())])), "GALERIA ZDJĘĆ");
      case 4: return _wrapWithBack(ClientFullDocsScreen(order: _order), "DOKUMENTY");
      case 5: return _wrapWithBack(IssuesScreen(isAdmin: false, currentUserEmail: _currentUserEmail ?? _order['id'], orderId: _order['id'], orderName: _order['name'], stages: _order['stages'] as List?), "PROBLEMY I UWAGI");
      case 6: return _wrapWithBack(ChatScreen(currentUserEmail: _currentUserEmail ?? _order['id'], displayName: "KLIENT", initialTargetEmail: _order['responsible_person'] ?? AppConstants.adminEmail, isClient: true), "WIADOMOŚCI");
      default: return const Center(child: Text("W budowie...", style: TextStyle(color: Colors.white24)));
    }
  }

  Widget _wrapWithBack(Widget child, String title) {
    final theme = Theme.of(context);
    final bool isMobile = MediaQuery.of(context).size.width < 700;
    
    if (isMobile) return child; // On mobile, we use the TopBar as header

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: theme.appBarTheme.backgroundColor,
            border: Border(bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.white10))
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF007BFF)),
                onPressed: () => setState(() => _selectedIndex = 0),
              ),
              const SizedBox(width: 8),
              Text(
                "POWRÓT DO PULPITU",
                style: GoogleFonts.montserrat(color: const Color(0xFF007BFF), fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                title,
                style: GoogleFonts.montserrat(color: theme.brightness == Brightness.dark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  void _handleTileDragUpdate(NexusTile tile, DragUpdateDetails details, double colWidth, double rowHeight) {
    setState(() {
      _draggingTileId = tile.id;
      _dragVisualX = (_dragVisualX ?? (tile.x * (colWidth + 16))) + details.delta.dx;
      _dragVisualY = (_dragVisualY ?? (tile.y * (rowHeight + 16))) + details.delta.dy;
    });
  }

  void _handleTileDragEnd(NexusTile tile, double colWidth, double rowHeight, int maxCols) {
    if (_dragVisualX == null || _dragVisualY == null) return;

    double newX = (_dragVisualX! / (colWidth + 16)).roundToDouble().clamp(0, maxCols - tile.width);
    double newY = (_dragVisualY! / (rowHeight + 16)).roundToDouble().clamp(0, 100);

    bool collision = _checkCollision(tile.id, newX, newY, tile.width, tile.height);

    setState(() {
      if (!collision) {
        tile.x = newX;
        tile.y = newY;
        _saveNexusBlueprint();
      }
      _draggingTileId = null;
      _dragVisualX = null;
      _dragVisualY = null;
    });
  }

  bool _checkCollision(String id, double x, double y, double w, double h) {
    for (var t in _nexusTiles) {
      if (t.id == id || t.isHidden) continue;
      if (x < t.x + t.width && x + w > t.x && y < t.y + t.height && y + h > t.y) return true;
    }
    return false;
  }

  void _handleTileResizeUpdate(NexusTile tile, DragUpdateDetails details, double colWidth, double rowHeight) {
    setState(() {
      _resizingTileId = tile.id;
      _resizeVisualW = (_resizeVisualW ?? (tile.width * colWidth + (tile.width - 1) * 16)) + details.delta.dx;
      _resizeVisualH = (_resizeVisualH ?? (tile.height * rowHeight + (tile.height - 1) * 16)) + details.delta.dy;
    });
  }

  void _handleTileResizeEnd(NexusTile tile, double colWidth, double rowHeight, int maxCols) {
    if (_resizeVisualW == null || _resizeVisualH == null) return;

    double newW = ((_resizeVisualW! + 16) / (colWidth + 16)).roundToDouble().clamp(1.0, maxCols.toDouble());
    double newH = ((_resizeVisualH! + 16) / (rowHeight + 16)).roundToDouble().clamp(1.0, 20.0);

    // Collision check after resize
    bool collision = _checkCollision(tile.id, tile.x, tile.y, newW, newH);

    setState(() {
      if (!collision) {
        tile.width = newW;
        tile.height = newH;
        _saveNexusBlueprint();
      }
      _resizingTileId = null;
      _resizeVisualW = null;
      _resizeVisualH = null;
    });
  }

  Widget _buildNexusDashboard(bool isD) {
    try {
      final double p = _calculateProgress(); 
      final List st = _order['stages'] as List? ?? []; 
      List ph = []; 
      for (var s in st) if (s != null && s is Map && s['photos'] != null) ph.addAll(s['photos']);
      final lPh = ph.reversed.take(12).toList(); 
      final List pF = _order['project_files'] as List? ?? [];
      
      final visibleTiles = _nexusTiles.where((t) => !t.isHidden || _isEditMode).toList();
      final double screenWidth = MediaQuery.of(context).size.width - (isD ? 260 : 0) - 48;
      
      int cols = isD ? 6 : 2;
      double spacing = 16.0;
      double colWidth = (screenWidth - (cols - 1) * spacing) / cols;
      double rowHeight = 160.0;

      // Calculate Stack height based on tiles
      double maxBottom = 0;
      for (var t in visibleTiles) {
        double h = (_resizingTileId == t.id) ? (_resizeVisualH! / (rowHeight + spacing)) : t.height;
        double y = (_draggingTileId == t.id) ? (_dragVisualY! / (rowHeight + spacing)) : t.y;
        double bottom = (y + h) * (rowHeight + spacing);
        if (bottom > maxBottom) maxBottom = bottom;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFixedKpiPillar(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Divider(color: Colors.white10, thickness: 1),
          ),
          
          if (_isEditMode) Container(margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange.withOpacity(0.3))), child: Row(children: [
            const Icon(Icons.edit_note_rounded, color: Colors.orange, size: 20), 
            const SizedBox(width: 10), 
            Expanded(child: Text("ES NEXUS: Tryb edycji. Przeciągnij za ikonę ⠿ aby zmienić pozycję.", style: GoogleFonts.montserrat(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w700))),
            TextButton.icon(
              onPressed: _resetNexusLayout, 
              icon: const Icon(Icons.refresh_rounded, color: Colors.orange, size: 16), 
              label: const Text("RESETUJ UKŁAD", style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold))
            ),
          ]),),
          
          SizedBox(
            width: screenWidth,
            height: maxBottom + 100, // Extra space at bottom
            child: Stack(
              children: visibleTiles.map((tile) {
                bool isDragging = _draggingTileId == tile.id;
                bool isResizing = _resizingTileId == tile.id;
                
                double left = isDragging ? _dragVisualX! : tile.x * (colWidth + spacing);
                double top = isDragging ? _dragVisualY! : tile.y * (rowHeight + spacing);
                
                double width = isResizing ? _resizeVisualW! : (tile.width * colWidth + (tile.width - 1) * spacing);
                double height = isResizing ? _resizeVisualH! : (tile.height * rowHeight + (tile.height - 1) * spacing);

                return AnimatedPositioned(
                  duration: (isDragging || isResizing) ? Duration.zero : const Duration(milliseconds: 200),
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: NexusTileWrapper(
                    tile: tile, 
                    isEditMode: _isEditMode, 
                    onDelete: () => setState(() { tile.isHidden = !tile.isHidden; _saveNexusBlueprint(); }),
                    onSettings: () => _showTileSettings(tile),
                    onDragUpdate: (details) => _handleTileDragUpdate(tile, details, colWidth, rowHeight),
                    onDragEnd: () => _handleTileDragEnd(tile, colWidth, rowHeight, cols),
                    onResizeUpdate: (details) => _handleTileResizeUpdate(tile, details, colWidth, rowHeight),
                    onResizeEnd: () => _handleTileResizeEnd(tile, colWidth, rowHeight, cols),
                    child: _buildTileContent(tile, p, lPh, pF),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      );
    } catch (e) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Text("KRYTYCZNY BŁĄD RENDEROWANIA: $e", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ));
    }
  }

  void _showTileSettings(NexusTile tile) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text("USTAWIENIA: ${tile.title}"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Szerokość (1-6):"),
        Slider(value: tile.width, min: 1, max: 6, divisions: 5, label: tile.width.toInt().toString(), onChanged: (v) => setState(() => tile.width = v)),
        const Text("Wysokość (1-6):"),
        Slider(value: tile.height, min: 1, max: 6, divisions: 5, label: tile.height.toInt().toString(), onChanged: (v) => setState(() => tile.height = v)),
      ]),
      actions: [TextButton(onPressed: () { _saveNexusBlueprint(); Navigator.pop(ctx); }, child: const Text("ZAPISZ"))],
    ));
  }

  Widget _buildTileContent(NexusTile tile, double p, List lPh, List pF) {
    switch (tile.id) {
      case 'stages': return _buildStagesList(isLarge: tile.width > 3);
      case 'recent_activity': return _buildRecentActivityFeed();
      case 'weather': return _buildWeatherBox(isDetailed: tile.width > 2);
      case 'chat': return _buildChatBento();
      case 'next_step': return _buildNextStepSection();
      case 'photos': return _buildPhotosBento(lPh, tile.width.toInt());
      case 'docs': return _buildDocsBento(pF);
      case 'before_after': return _buildBeforeAfterSection();
      default: return const SizedBox();
    }
  }

  Widget _buildTopBar(bool isD, bool isMobile) {
    final double p = _calculateProgress();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 12), 
      decoration: BoxDecoration(
        color: isDark ? theme.appBarTheme.backgroundColor : Colors.white, 
        border: Border(bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.black12))
      ), 
      child: Row(children: [
        if (!isD && !isMobile) IconButton(icon: Icon(Icons.menu, color: isDark ? Colors.white : Colors.black87), onPressed: () => Scaffold.of(context).openDrawer()),
        if (isMobile && _selectedIndex != 0) IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF007BFF)), onPressed: () => setState(() => _selectedIndex = 0)),
        
        if (isD) ...[ _buildHeroHeader(), const SizedBox(width: 48), _buildProgressHeader(p) ]
        else if (!isMobile) ...[ _buildHeroHeader() ],
        
        if (isMobile) ...[
          if (_selectedIndex == 0) ...[
            const Icon(Icons.bolt, color: Color(0xFF007BFF), size: 24),
            const SizedBox(width: 8),
            Text("ES CRM", style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.onSurface)),
          ] else ...[
            Text(_getViewTitle(), style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 14, color: theme.colorScheme.onSurface)),
          ]
        ],

        const Spacer(), 
        if (isMobile) 
          _topBarIcon(Icons.notifications_none_rounded, null, const Color(0xFF007BFF), () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(isAdmin: false, currentUserEmail: _currentUserEmail ?? _order['id'])))), 

        if (!isMobile) ...[
          _topBarIcon(Icons.notifications_none_rounded, null, const Color(0xFF007BFF), () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(isAdmin: false, currentUserEmail: _currentUserEmail ?? _order['id'])))), 
          _topBarIcon(Icons.mail_outline_rounded, null, const Color(0xFF007BFF), _openChat), 
          const SizedBox(width: 10),
        ],
        const ThemeSwitcher(),
        const SizedBox(width: 10),
        if (!isMobile) IconButton(icon: Icon(_isEditMode ? Icons.check_circle_rounded : Icons.edit_square, color: _isEditMode ? Colors.green : (isDark ? Colors.white70 : Colors.black45), size: 24), onPressed: () { setState(() => _isEditMode = !_isEditMode); if (!_isEditMode) _saveNexusBlueprint(); }, tooltip: "Edytuj Pulpit"),
        if (!isMobile) const SizedBox(width: 20), 
        if (!isMobile) Row(children: [ 
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_order['client_name'] ?? "Klient", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w900, fontSize: 13)), 
            Text("INWESTOR", style: TextStyle(color: const Color(0xFF007BFF), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1))
          ]), 
          const SizedBox(width: 12), 
          Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF007BFF), width: 1.5)), child: CircleAvatar(radius: 16, backgroundColor: theme.colorScheme.surfaceVariant, child: Icon(Icons.person, color: isDark ? Colors.white : Colors.black54, size: 18))) 
        ])
        else Container(padding: const EdgeInsets.all(1), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF007BFF), width: 1)), child: CircleAvatar(radius: 14, backgroundColor: theme.colorScheme.surfaceVariant, child: Icon(Icons.person, color: isDark ? Colors.white : Colors.black54, size: 16)))
    ]));
  }

  String _getViewTitle() {
    switch (_selectedIndex) {
      case 1: return "ETAPY REALIZACJI";
      case 2: return "HISTORIA INWESTYCJI";
      case 3: return "GALERIA ZDJĘĆ";
      case 4: return "DOKUMENTY";
      case 5: return "PROBLEMY I UWAGI";
      case 6: return "WIADOMOŚCI";
      default: return "ES CRM";
    }
  }

  Widget _buildSidebar({bool isMobile = false}) {
    final theme = Theme.of(context);
    // Force dark colors for sidebar branding
    return Container(
      width: 260, 
      decoration: const BoxDecoration(
        color: Color(0xFF001A2C), 
        border: Border(right: BorderSide(color: Colors.white10, width: 0.5))
      ), 
      child: Column(children: [ 
        Padding(padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Row(children: [const Icon(Icons.bolt, color: Color(0xFF007BFF), size: 32), const SizedBox(width: 10), Text("ES CRM", style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -1))]), Text("DZIENNIK INWESTYCJI", style: GoogleFonts.montserrat(color: const Color(0xFF007BFF).withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)) ])), 
        _sidebarItem(0, "Pulpit", Icons.dashboard_rounded), 
        _sidebarItem(1, "Etapy realizacji", Icons.view_list_rounded), 
        _sidebarItem(2, "Historia realizacji", Icons.history_rounded), 
        _sidebarItem(3, "Zdjęcia", Icons.photo_library_rounded), 
        _sidebarItem(4, "Dokumenty", Icons.folder_shared_rounded), 
        _sidebarItem(5, "Problemy i uwagi", Icons.report_problem_rounded), 
        _sidebarItem(6, "Wiadomości", Icons.chat_bubble_rounded), 
        const Spacer(), 
        _buildSidebarContact() 
      ])
    );
  }
  Widget _sidebarItem(int i, String t, IconData ic) { 
    bool active = _selectedIndex == i; 
    // Sidebar stays dark for branding, so we use light/muted colors regardless of global theme
    const inactiveColor = Color(0xFF4A6A8A);
    const activeColor = Color(0xFF007BFF);
    
    return InkWell(
      onTap: () { setState(() => _selectedIndex = i); if (Scaffold.of(context).isDrawerOpen) Navigator.pop(context); }, 
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), 
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.15) : Colors.transparent, 
          borderRadius: BorderRadius.circular(12), 
          border: active ? Border.all(color: activeColor.withOpacity(0.3)) : null
        ), 
        child: Row(children: [
          Icon(ic, color: active ? activeColor : inactiveColor, size: 20), 
          const SizedBox(width: 16), 
          Text(t, style: GoogleFonts.montserrat(color: active ? Colors.white : inactiveColor, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w600))
        ])
      )
    ); 
  }
  Widget _buildSidebarContact() {
    // Sidebar is always dark, so we use dark-theme specific colors here
    return Container(
      margin: const EdgeInsets.all(16), 
      padding: const EdgeInsets.all(20), 
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF003366), Color(0xFF001A2C)], 
          begin: Alignment.topLeft, 
          end: Alignment.bottomRight
        ), 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: const Color(0xFF004080))
      ), 
      child: Column(children: [
        const Text("Masz pytanie?", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)), 
        const SizedBox(height: 12), 
        ElevatedButton(
          onPressed: _openChat, 
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007BFF), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0), 
          child: const Text("NAPISZ WIADOMOŚĆ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900))
        ), 
        const SizedBox(height: 20), 
        Image.asset('assets/logo.png', height: 40, errorBuilder: (c,e,s) => const Icon(Icons.bolt, color: Colors.blue))
      ])
    );
  }
  Widget _buildHeroHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(children: [ 
      Container(width: 40, height: 40, decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF007BFF).withOpacity(0.5)), image: _order['photo_url'] != null ? DecorationImage(image: NetworkImage(_order['photo_url']), fit: BoxFit.cover) : null), child: _order['photo_url'] == null ? const Icon(Icons.apartment_rounded, color: Color(0xFF007BFF), size: 20) : null), 
      const SizedBox(width: 12), 
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          Text(_order['name'] ?? "Budynek", style: GoogleFonts.montserrat(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w900, fontSize: 14)), 
          const SizedBox(width: 8), 
          _statusTag(_order['status'] ?? 'W TRAKCIE')
        ]), 
        Text(_order['location'] ?? "Lokalizacja", style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 10, fontWeight: FontWeight.w600))
      ]), 
      const SizedBox(width: 24), 
      Row(children: [_heroDate("START", _order['startDate'] ?? "-"), const SizedBox(width: 16), _heroDate("KONIEC", _order['endDate'] ?? "-")]) 
    ]);
  }
  Widget _buildProgressHeader(double p) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(children: [ 
      Stack(alignment: Alignment.center, children: [SizedBox(width: 40, height: 40, child: CircularProgressIndicator(value: p, strokeWidth: 5, backgroundColor: theme.colorScheme.surfaceVariant, color: const Color(0xFF007BFF), strokeCap: StrokeCap.round)), Text("${(p * 100).round()}%", style: GoogleFonts.montserrat(color: isDark ? Colors.white : Colors.black87, fontSize: 10, fontWeight: FontWeight.w900))]), 
      const SizedBox(width: 12), 
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text("POSTĘP REALIZACJI", style: GoogleFonts.montserrat(color: isDark ? Colors.white38 : Colors.black38, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 1)), 
        Text("${(_order['stages'] as List? ?? []).where((s)=>s['status']=='ZAKOŃCZONO').length} / ${(_order['stages'] as List? ?? []).length} etapów", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 10, fontWeight: FontWeight.w800))
      ]) 
    ]);
  }
  Widget _topBarIcon(IconData i, String? b, Color c, VoidCallback? o) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(onTap: o, child: Stack(clipBehavior: Clip.none, children: [Icon(i, color: isDark ? Colors.white70 : Colors.black45, size: 24), if (b != null) Positioned(right: -4, top: -4, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: Text(b, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))))]));
  }
  Widget _heroDate(String l, String d) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: GoogleFonts.montserrat(color: isDark ? Colors.white24 : Colors.black26, fontSize: 7, fontWeight: FontWeight.w900)), Text(d.toUpperCase(), style: GoogleFonts.montserrat(color: isDark ? Colors.white70 : Colors.black87, fontSize: 10, fontWeight: FontWeight.w900))]);
  }
  Widget _statusTag(String s) { 
    Color col = const Color(0xFF007BFF); 
    IconData icon = Icons.info_outline_rounded;
    bool isClosed = s.toUpperCase() == 'ZAMKNIĘTY';
    
    switch (s.toUpperCase()) {
      case 'ZAKOŃCZONO': 
      case 'ROZWIĄZANO':
        col = const Color(0xFF00C853); 
        icon = Icons.check_circle_rounded;
        break;
      case 'W TRAKCIE':
        col = Colors.orange;
        icon = Icons.engineering_rounded;
        break;
      case 'NOWY':
        col = Colors.red;
        icon = Icons.fiber_new_rounded;
        break;
      case 'DO USTALENIA':
        col = Colors.amber;
        icon = Icons.help_outline_rounded;
        break;
      case 'ZAMKNIĘTY':
        col = Colors.blueGrey;
        icon = Icons.lock_outline_rounded;
        break;
      case 'OCZEKUJE':
        col = Colors.blue;
        icon = Icons.hourglass_empty_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), 
      decoration: BoxDecoration(
        color: isClosed ? col.withOpacity(0.3) : col.withOpacity(0.15), 
        borderRadius: BorderRadius.circular(10), 
        border: Border.all(color: isClosed ? col.withOpacity(0.6) : col.withOpacity(0.4), width: 1.2)
      ), 
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isClosed ? Colors.white70 : col, size: 12),
          const SizedBox(width: 6),
          Text(
            s.toUpperCase(), 
            style: TextStyle(
              color: isClosed ? Colors.white : col, 
              fontSize: 9, 
              fontWeight: FontWeight.w900, 
              letterSpacing: 0.5
            )
          ),
        ],
      )
    ); 
  }

  // --- Adaptive Widgets ---
  Widget _buildWeatherBox({bool isDetailed = false}) { 
    if (_weatherData == null) return const Center(child: Icon(Icons.wb_cloudy_outlined, color: Colors.white10, size: 30)); 
    final int code = _weatherData!['code'] ?? 0; 
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(20), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [ 
          _bentoHeader("POGODA", "LIVE", () {}, icon: Icons.cloud_queue_rounded, iconCol: Colors.lightBlueAccent), 
          const SizedBox(height: 12),
          Row(children: [
            Text(_weatherService.getWeatherIcon(code), style: const TextStyle(fontSize: 30)), 
            const SizedBox(width: 12), 
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${_weatherData!['temp']}°C", style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.w900)), 
              Text(_weatherService.getWeatherDesc(code).toUpperCase(), style: GoogleFonts.montserrat(color: const Color(0xFF007BFF), fontSize: 8, fontWeight: FontWeight.w900))
            ]))
          ]), 
          if (isDetailed) ...[ 
            const Divider(height: 24), 
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_weatherMeta(Icons.air_rounded, "WIATR", "${_weatherData!['wind']} km/h"), _weatherMeta(Icons.location_city_rounded, "MIASTO", _weatherData!['city'] ?? "Budowa")]), 
            const SizedBox(height: 12), 
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ _miniForecast("12:00", "☀️", "22°"), _miniForecast("15:00", "⛅", "24°"), _miniForecast("18:00", "🌧️", "19°") ]) 
          ] 
        ]
      )
    ); 
  }
  Widget _buildTodayActivity({bool isCompact = false}) { final List st = _order['stages'] as List? ?? []; final cur = st.firstWhere((s) => s['status'] == 'W TRAKCIE', orElse: () => null); final String ts = DateFormat('dd.MM').format(DateTime.now()); List<Map<String, dynamic>> ev = []; for (var s in st) { if (s['photos'] != null) for (var p in (s['photos'] as List)) if (p['date'] == DateFormat('dd.MM.yyyy').format(DateTime.now())) ev.add({'time': p['time'] ?? '??:??', 'text': '📸 Zdjęcie: ${s['name']}', 'icon': Icons.camera_alt_rounded, 'color': Colors.blue}); if (s['logs'] != null) for (var log in (s['logs'] as List)) if (log['date'].toString().contains(ts)) ev.add({'time': log['date'].toString().split(' ').last, 'text': log['text'], 'icon': log['text'].toString().contains('MELDUNEK') ? Icons.rocket_launch_rounded : Icons.info_outline, 'color': log['text'].toString().contains('MELDUNEK') ? Colors.orange : Colors.blueGrey}); } ev.sort((a, b) => b['time'].compareTo(a['time'])); return Container(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ _bentoHeader("DZIŚ NA BUDOWIE", "LIVE", () {}, icon: Icons.wb_sunny_rounded, iconCol: Colors.amber), const SizedBox(height: 16), _activityMeta(Icons.groups_rounded, "Ekipa:", _order['assigned_crew'] ?? "ES TEAM"), _activityMeta(Icons.construction_rounded, "Obecnie:", cur?['name'] ?? "Planowanie"), if (!isCompact) ...[ const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: Colors.white10)), if (ev.isEmpty) const Center(child: Text("Brak aktywności dzisiaj.", style: TextStyle(color: Colors.white10, fontSize: 10))) else Column(children: ev.take(3).map((e) => _activityLog(e['time'], e['text'], e['icon'], e['color'])).toList()) ], const Spacer(), SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _showHistory, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007BFF).withOpacity(0.1), foregroundColor: const Color(0xFF007BFF), side: const BorderSide(color: Color(0xFF007BFF), width: 1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text("PEŁNY DZIENNIK", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))) ])); }
  Widget _buildStagesList({bool isLarge = false}) { final List stages = _order['stages'] as List? ?? []; return Container(padding: const EdgeInsets.all(20), child: Column(children: [ _bentoHeader("ETAPY REALIZACJI", "ZAPROPONUJ", _suggestNewStage), const SizedBox(height: 16), Expanded(child: ListView.builder(itemCount: stages.length, itemBuilder: (context, i) => _stageRow(i + 1, stages[i]))), ])); }
  Widget _buildChatBento() { 
    final String orderId = _order['id'].toString().toLowerCase().trim(); 
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20), 
      child: Column(children: [ 
        _bentoHeader("KOMUNIKACJA", "CZAT", _openChat), 
        Expanded(child: StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('private_messages').snapshots(), builder: (context, snap) { 
          if (!snap.hasData) return const SizedBox(); 
          final docs = snap.data!.docs.map((d) => d.data() as Map<String, dynamic>).where((m) => m['senderEmail'].toString().toLowerCase() == orderId || m['receiverEmail'].toString().toLowerCase() == orderId).toList(); 
          docs.sort((a, b) { final t1 = a['timestamp'] as Timestamp?; final t2 = b['timestamp'] as Timestamp?; if (t1 == null) return -1; if (t2 == null) return 1; return t2.compareTo(t1); }); 
          final display = docs.take(5).toList(); 
          if (display.isEmpty) return Center(child: Text("Brak wiadomości.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.1), fontSize: 11))); 
          return ListView.builder(padding: EdgeInsets.zero, itemCount: display.length, reverse: true, itemBuilder: (context, idx) { 
            final m = display[idx]; 
            bool isMe = m['senderEmail'].toString().toLowerCase() == orderId; 
            return Align(alignment: isMe ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: isMe ? const Color(0xFF007BFF).withOpacity(0.2) : theme.colorScheme.onSurface.withOpacity(0.05), borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [Text(m['text'] ?? "", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 10, fontWeight: FontWeight.w600)), Text(m['date'] ?? "", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 7))]))); 
          }); 
        })), 
        const SizedBox(height: 12), 
        Row(children: [ 
          Expanded(child: TextField(controller: _quickChatCtrl, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12), decoration: InputDecoration(hintText: "Napisz...", hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2)), filled: true, fillColor: theme.colorScheme.onSurface.withOpacity(0.03), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))), 
          const SizedBox(width: 8), 
          Material(color: const Color(0xFF007BFF), borderRadius: BorderRadius.circular(10), child: IconButton(icon: const Icon(Icons.send_rounded, color: Colors.white, size: 16), onPressed: () async { if (_quickChatCtrl.text.trim().isNotEmpty) { String txt = _quickChatCtrl.text; _quickChatCtrl.clear(); await _sendQuickMessage(txt); } })) 
        ]) 
      ])
    ); 
  }
  Widget _buildNextStepSection() { 
    final next = (_order['stages'] as List? ?? []).firstWhere((s)=>s['status']=='OCZEKUJE', orElse: ()=>null); 
    final theme = Theme.of(context);
    return _bentoBox(padding: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ 
      _bentoHeader("CO DALEJ?", "PLAN", () {}), 
      const SizedBox(height: 16), 
      if (next != null) Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF007BFF).withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.calendar_month, color: Color(0xFF007BFF), size: 20)), 
        const SizedBox(width: 12), 
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Następny etap:", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 10)), 
          Text(next['name'] ?? "", style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 14), overflow: TextOverflow.ellipsis), 
          Text("Start: ${next['planned_start'] ?? 'Wkrótce'}", style: const TextStyle(color: Color(0xFF007BFF), fontSize: 10, fontWeight: FontWeight.bold))
        ]))
      ]) else Center(child: Text("Brak planów", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 11))) 
    ])); 
  }
  Widget _buildBeforeAfterSection() => _bentoBox(padding: 16, child: Column(children: [_bentoHeader("PRZED vs PO", "ZOBACZ", () {}), const SizedBox(height: 12), ClipRRect(borderRadius: BorderRadius.circular(16), child: Stack(children: [Image.network("https://images.unsplash.com/photo-1581094794329-c8112a89af12?q=80&w=2070", height: 120, width: double.infinity, fit: BoxFit.cover), Positioned(left: 10, bottom: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), color: Colors.black54, child: const Text("PRZED", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))), Positioned(right: 10, bottom: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), color: Color(0xFF007BFF), child: const Text("PO", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))), Center(child: Container(width: 1.5, height: 120, color: Colors.white))]))]));
  Widget _buildPhotosBento(List lPh, int w) {
    final theme = Theme.of(context);
    return _bentoBox(padding: 16, child: Column(children: [
      _bentoHeader("ZDJĘCIA", "WSZYSTKIE", _showFullGallery), 
      const SizedBox(height: 12), 
      if (lPh.isEmpty) 
        Expanded(child: Center(child: Text("Brak zdjęć", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.1))))) 
      else 
        Expanded(
          child: GridView.builder(
            shrinkWrap: true, 
            physics: const NeverScrollableScrollPhysics(), 
            itemCount: lPh.length, 
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: w > 2 ? 4 : 3, mainAxisSpacing: 8, crossAxisSpacing: 8), 
            itemBuilder: (c, i) => InkWell(
              onTap: () => _showPhotoPreview(_getImgUrl(lPh[i])), 
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12), 
                child: Image.network(
                  _getImgUrl(lPh[i]), 
                  fit: BoxFit.cover, 
                  errorBuilder: (c,e,s) => Container(color: theme.colorScheme.onSurface.withOpacity(0.05))
                )
              )
            )
          )
        ), 
      const SizedBox(height: 12), 
      TextButton.icon(
        onPressed: _showFullGallery, 
        icon: const Icon(Icons.photo_library, size: 14), 
        label: const Text("WSZYSTKIE", style: TextStyle(fontSize: 10))
      )
    ]));
  }
  Widget _buildDocsBento(List pF) {
    final theme = Theme.of(context);
    return _bentoBox(padding: 16, child: Column(children: [
      _bentoHeader("DOKUMENTY", "CENTRUM", () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientFullDocsScreen(order: _order)))), 
      const SizedBox(height: 12), 
      if (pF.isEmpty) 
        Expanded(child: Center(child: Text("Brak plików", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.1))))) 
      else 
        Expanded(child: ListView.builder(itemCount: pF.length, itemBuilder: (context, idx) => _docRow(pF[idx]['name'], pF[idx]['category'] ?? "Dokument", pF[idx]['path']))) 
    ]));
  }
  Widget _buildFullHistoryView() { 
    final theme = Theme.of(context);
    final List stages = _order['stages'] as List? ?? []; 
    List logs = []; 
    for (var s in stages) if (s['logs'] != null) logs.addAll(s['logs']); 
    
    if (logs.isEmpty) return Center(child: Text("Brak wpisów", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2)))); 
    
    return ListView.builder(
      itemCount: logs.length, 
      itemBuilder: (ctx, i) => Container(
        margin: const EdgeInsets.only(bottom: 12), 
        child: _bentoBox(
          padding: 16, 
          child: ListTile(
            leading: const Icon(Icons.history_rounded, color: Color(0xFF007BFF)), 
            title: Text(
              logs[i]['text'] ?? "", 
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold)
            ), 
            subtitle: Text(
              logs[i]['date'] ?? "", 
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 11)
            )
          )
        )
      )
    ); 
  }
  Widget _buildFullGalleryView() { 
    final theme = Theme.of(context);
    final List stages = _order['stages'] as List? ?? []; 
    Map<String, List<dynamic>> grouped = {}; 
    for (var s in stages) if (s['photos'] != null) for (var p in (s['photos'] as List)) { 
      String d = p is Map ? (p['date'] ?? "Inne") : "Inne"; 
      if (!grouped.containsKey(d)) grouped[d] = []; 
      grouped[d]!.add(p); 
    } 
    final sorted = grouped.keys.toList()..sort((a, b) => b.compareTo(a)); 
    
    if (grouped.isEmpty) return Center(child: Text("Brak zdjęć", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2)))); 
    
    return ListView.builder(
      itemCount: sorted.length, 
      itemBuilder: (ctx, idx) { 
        final d = sorted[idx]; 
        final phs = grouped[d]!; 
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12), 
              child: Text(d, style: GoogleFonts.montserrat(color: const Color(0xFF007BFF), fontWeight: FontWeight.bold))
            ), 
            GridView.builder(
              shrinkWrap: true, 
              physics: const NeverScrollableScrollPhysics(), 
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8), 
              itemCount: phs.length, 
              itemBuilder: (ctx, i) => InkWell(
                onTap: () => _showPhotoPreview(_getImgUrl(phs[i])), 
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12), 
                  child: Image.network(
                    _getImgUrl(phs[i]), 
                    fit: BoxFit.cover, 
                    errorBuilder: (c,e,s) => Container(color: theme.colorScheme.onSurface.withOpacity(0.05))
                  )
                )
              )
            )
          ]
        ); 
      }
    ); 
  }
  void _suggestNewStage() {
    final c = TextEditingController();
    showEsModal(
      context,
      title: "ZAPROPONUJ NOWY ETAP",
      content: StatefulBuilder(
        builder: (context, setS) {
          final theme = Theme.of(context);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: c, 
                autofocus: true, 
                style: TextStyle(color: theme.colorScheme.onSurface), 
                decoration: InputDecoration(
                  labelText: "Nazwa etapu", 
                  labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)), 
                  hintText: "np. Dodatkowe gniazdo", 
                  hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2)),
                  filled: true,
                  fillColor: theme.colorScheme.onSurface.withOpacity(0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                )
              ),
            ],
          );
        }
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANULUJ")),
        ElevatedButton(
          onPressed: () async {
            if (c.text.isEmpty) return;
            setState(() {
              if (_order['stages'] == null) _order['stages'] = [];
              (_order['stages'] as List).add({
                'name': c.text.toUpperCase(), 
                'status': 'OCZEKUJE NA AKCEPTACJĘ', 
                'logs': [{'text': 'Propozycja dodana przez klienta', 'date': DateFormat('dd.MM HH:mm').format(DateTime.now()), 'author': 'INWESTOR'}], 
                'photos': []
              });
            });
            Navigator.pop(context);
            await _saveOrderChanges();
            await AppUtils.sendNotification(
              title: "NOWA PROPOZYCJA ETAPU", 
              content: "Klient zaproponował nowy etap: '${c.text}'", 
              target: _order['responsible_person'] ?? 'admin', 
              author: "ES CRM"
            );
          }, 
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007BFF), foregroundColor: Colors.white), 
          child: const Text("WYŚLIJ", style: TextStyle(fontWeight: FontWeight.bold))
        )
      ],
    );
  }
  Future<void> _sendQuickMessage(String t) async { if (t.trim().isEmpty) return; final String oId = _order['id'].toString().toLowerCase().trim(); final String rEm = (_order['responsible_person'] ?? AppConstants.adminEmail).toString().toLowerCase().trim(); List<String> ids = [oId, rEm]; ids.sort(); final String rId = ids.join('_'); final nMsg = {'text': t, 'senderEmail': oId, 'senderName': "KLIENT", 'receiverEmail': rEm, 'roomId': rId, 'timestamp': FieldValue.serverTimestamp(), 'date': DateFormat('dd.MM HH:mm').format(DateTime.now()), 'isRead': false}; await FirebaseFirestore.instance.collection('private_messages').add(nMsg); await AppUtils.sendNotification(title: "NOWA WIADOMOŚĆ", content: t, target: rEm == AppConstants.adminEmail.toLowerCase() ? 'admin' : rEm, author: "KLIENT"); }
  void _showStatusDetails() { 
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final List stages = _order['stages'] as List? ?? []; 
    final bool hasIssues = _openIssuesCount > 0; 
    
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardTheme.color, 
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24), 
          side: BorderSide(color: hasIssues ? Colors.orange : const Color(0xFF007BFF))
        ), 
        title: Row(children: [
          Icon(hasIssues ? Icons.warning_amber_rounded : Icons.verified_user_rounded, color: hasIssues ? Colors.orange : Colors.green), 
          const SizedBox(width: 12), 
          Text("RAPORT STANU", style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900))
        ]), 
        content: Column(
          mainAxisSize: MainAxisSize.min, 
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [ 
            _statusDetailRow("Harmonogram", stages.isNotEmpty && stages.every((s)=>s['status']=='ZAKOŃCZONO') ? "Zakończono" : "W trakcie realizacji", Icons.calendar_today), 
            _statusDetailRow("Problemy techniczne", hasIssues ? "Wymaga uwagi ($_openIssuesCount)" : "Brak krytycznych uwag", Icons.report_problem), 
            _statusDetailRow("Opieka inżynierska", "Aktywna (Opiekun: $_responsibleName)", Icons.engineering), 
            const SizedBox(height: 20), 
            Text(
              hasIssues ? "Występują utrudnienia. Pracujemy nad rozwiązaniem." : "Prace przebiegają bez zakłóceń.", 
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12, fontStyle: FontStyle.italic)
            ) 
          ]
        ), 
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("ZAMKNIJ", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))))
        ]
      )
    ); 
  }
  Widget _miniForecast(String t, String i, String tp) {
    final theme = Theme.of(context);
    return Column(children: [
      Text(t, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 7)), 
      Text(i, style: const TextStyle(fontSize: 14)), 
      Text(tp, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.bold))
    ]);
  }
  Widget _buildFixedKpiPillar() { 
    int tp = 0; 
    final List st = _order['stages'] as List? ?? [];
    for (var s in st) if (s != null && s is Map && s['photos'] != null) tp += (s['photos'] as List).length; 
    
    // Time Calculation
    final timeStats = _calculateTimeStats();

    return Row(
      children: [
        Expanded(
          child: _miniStat(
            Icons.access_time_filled, 
            "CZAS REALIZACJI", 
            "DZIEŃ ${timeStats['current']} / ${timeStats['total']}", 
            "Pozostało: ${timeStats['left']} dni",
            col: Colors.amber
          )
        ), 
        const SizedBox(width: 12), 
        Expanded(
          child: InkWell(
            onTap: () => setState(() => _selectedIndex = 3),
            borderRadius: BorderRadius.circular(16),
            child: _miniStat(Icons.photo_library, "ZDJĘCIA", "$tp", "Otwórz galerię", col: Colors.blue),
          ),
        ), 
        const SizedBox(width: 12), 
        Expanded(child: _miniStat(Icons.groups, "EKIPA", (_order['assigned_crews'] as List? ?? (_order['assigned_crew'] != null ? [_order['assigned_crew']] : [])).join(", ").isEmpty ? "ES TEAM" : (_order['assigned_crews'] as List? ?? (_order['assigned_crew'] != null ? [_order['assigned_crew']] : [])).join(", "), "Opiekun: $_responsibleName")), 
        const SizedBox(width: 12), 
        Expanded(
          child: InkWell(
            onTap: () => setState(() => _selectedIndex = 5),
            borderRadius: BorderRadius.circular(16),
            child: _miniStat(
              Icons.warning, 
              "PROBLEMY", 
              _openIssuesCount == 0 ? "BRAK" : "$_openIssuesCount OTWARTE", 
              _openIssuesCount == 0 ? "Brak otwartych" : "Wymaga uwagi", 
              col: _openIssuesCount > 0 ? Colors.red : Colors.green
            ),
          ),
        ), 
      ],
    ); 
  }

  Map<String, dynamic> _calculateTimeStats() {
    try {
      final String? startStr = _order['startDate'];
      final String? endStr = _order['endDate'];
      if (startStr == null || endStr == null || startStr.isEmpty || endStr.isEmpty) {
        return {'current': '-', 'total': '-', 'left': '-'};
      }

      final DateFormat fmt = DateFormat('dd.MM.yyyy');
      final DateTime start = fmt.parse(startStr.trim());
      final DateTime end = fmt.parse(endStr.trim());
      final DateTime now = DateTime.now();
      
      // Clear time part for accurate day calculation
      final DateTime startClean = DateTime(start.year, start.month, start.day);
      final DateTime endClean = DateTime(end.year, end.month, end.day);
      final DateTime nowClean = DateTime(now.year, now.month, now.day);

      final int totalDays = endClean.difference(startClean).inDays + 1;
      int currentDay = nowClean.difference(startClean).inDays + 1;
      
      if (currentDay < 1) currentDay = 0;
      if (currentDay > totalDays) currentDay = totalDays;

      int left = endClean.difference(nowClean).inDays;
      if (left < 0) left = 0;

      return {
        'current': currentDay,
        'total': totalDays,
        'left': left,
      };
    } catch (e) {
      debugPrint("Date calculation error: $e");
      return {'current': '?', 'total': '?', 'left': '?'};
    }
  }

  Widget _miniStat(IconData i, String l, String v, String s, {Color col = const Color(0xFF007BFF)}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12), 
      decoration: BoxDecoration(
        color: theme.cardTheme.color, 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3))
      ), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Row(children: [
            Icon(i, color: col, size: 14), 
            const SizedBox(width: 6), 
            Text(l, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 8, fontWeight: FontWeight.bold))
          ]), 
          const SizedBox(height: 8), 
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(v, style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w900))
          ), 
          Text(s.toUpperCase(), style: TextStyle(color: col, fontSize: 7, fontWeight: FontWeight.bold))
        ]
      )
    );
  }

  Widget _bentoHeader(String t, String l, VoidCallback onTap, {IconData? icon, Color? iconCol}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        if(icon!=null)Icon(icon, color: iconCol ?? const Color(0xFF007BFF), size: 16), 
        if(icon!=null)const SizedBox(width: 8), 
        Text(t, style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 10))
      ]), 
      InkWell(
        onTap: onTap, 
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
          decoration: BoxDecoration(color: const Color(0xFF007BFF).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), 
          child: const Text(
            "ZOBACZ", // Simplified label to "ZOBACZ" for consistency or keep 'l'
            style: TextStyle(color: Color(0xFF007BFF), fontSize: 8, fontWeight: FontWeight.w900)
          )
        )
      )
    ]);
  }
  Widget _sectionHeader(String t) => Row(children: [Container(width: 4, height: 24, decoration: BoxDecoration(color: const Color(0xFF007BFF), borderRadius: BorderRadius.circular(2))), const SizedBox(width: 12), Text(t, style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.5))]);
  Widget _bentoBox({required Widget child, double padding = 20}) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(padding), 
      decoration: BoxDecoration(
        color: theme.cardTheme.color, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2))
      ), 
      child: child
    );
  }
  Widget _activityMeta(IconData i, String l, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8), 
      child: Row(children: [
        Icon(i, color: theme.colorScheme.onSurface.withOpacity(0.2), size: 14), 
        const SizedBox(width: 8), 
        Text(l, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3), fontSize: 10)), 
        const SizedBox(width: 4), 
        Expanded(child: Text(v, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))
      ])
    );
  }

  Widget _activityLog(String t, String txt, IconData i, Color c) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8), 
      child: Row(children: [
        Text(t, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 8)), 
        const SizedBox(width: 10), 
        Icon(i, color: c, size: 12), 
        const SizedBox(width: 8), 
        Expanded(child: Text(txt, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 9, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis))
      ])
    );
  }
  
  Widget _stageRow(int n, Map<String, dynamic> s) { 
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    bool d = s['status'] == 'ZAKOŃCZONO'; 
    Color c = d ? Colors.green : (s['status'] == 'W TRAKCIE' ? Colors.orange : theme.colorScheme.onSurface.withOpacity(0.2)); 
    
    final acts = _getStageActivities(s);
    final lastRead = _lastReadStates[s['name']] ?? 0;
    final int newCount = acts.where((a) => a['timestamp'] > lastRead).length;
    final Map<String, dynamic>? latestAct = acts.isNotEmpty ? acts.first : null;

    return Padding(padding: const EdgeInsets.only(bottom: 16), child: InkWell(
      onTap: () => _showStageDetails(s, n), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 24, height: 24, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.1), border: Border.all(color: c.withOpacity(0.5))), child: Text("$n", style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold))), 
            const SizedBox(width: 12), 
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  Expanded(child: Text(s['name'] ?? "", style: TextStyle(color: d ? theme.colorScheme.onSurface.withOpacity(0.4) : theme.colorScheme.onSurface, fontSize: 12, fontWeight: d ? FontWeight.normal : FontWeight.bold, decoration: d ? TextDecoration.lineThrough : null))),
                  if (newCount > 0) Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(6)),
                    child: Text("NOWE • $newCount", style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900)),
                  ),
                ],
              ), 
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    (s['status'] == 'ZAKOŃCZONO') ? Icons.check_circle_rounded : 
                    (s['status'] == 'W TRAKCIE' ? Icons.engineering_rounded : Icons.hourglass_empty_rounded),
                    color: c, size: 10
                  ),
                  const SizedBox(width: 4),
                  Text(s['status'] ?? "", style: TextStyle(color: c, fontSize: 8, fontWeight: FontWeight.w900)),
                  if (s['photos'] != null && (s['photos'] as List).isNotEmpty) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.photo_library_rounded, color: Colors.blue, size: 10),
                    const SizedBox(width: 4),
                    Text("${(s['photos'] as List).length}", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 8, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
              if (s['photos'] != null && (s['photos'] as List).isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: (s['photos'] as List).length,
                    itemBuilder: (c, i) => Container(
                      margin: const EdgeInsets.only(right: 6),
                      width: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05)),
                        image: DecorationImage(image: NetworkImage(_getImgUrl(s['photos'][i])), fit: BoxFit.cover)
                      ),
                    ),
                  ),
                ),
              ],
            ])), 
            if (d) const Icon(Icons.check_circle, color: Colors.green, size: 16) 
          ]),
          if (latestAct != null) Padding(
            padding: const EdgeInsets.only(left: 36, top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.03), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(latestAct['icon'], color: latestAct['color'].withOpacity(0.5), size: 10),
                  const SizedBox(width: 6),
                  Expanded(child: Text("${latestAct['author']}: ${latestAct['text']}", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 9))),
                  const SizedBox(width: 4),
                  Text(latestAct['dateStr'].split(' ').last, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 7)),
                ],
              ),
            ),
          ),
        ],
      )
    )); 
  }

  void _showStageDetails(Map<String, dynamic> initialStage, int number) {
    final TextEditingController commentCtrl = TextEditingController();
    final String stageName = initialStage['name'] ?? "Bez nazwy";
    final String orderId = _order['id'].toString();
    
    _markStageAsRead(stageName);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "StageDetails",
      barrierColor: Colors.black.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) => StatefulBuilder(
        builder: (context, setS) {
          final theme = Theme.of(context);
          // Re-find the stage in the latest _order to ensure we have fresh data
          final List stages = _order['stages'] as List? ?? [];
          final stage = stages.firstWhere((s) => s['name'] == stageName, orElse: () => initialStage);
          final List logs = stage['logs'] as List? ?? [];
          final List<Map<String, dynamic>> stageIssues = _allIssues.where((i) => i['stageName'] == stageName).toList();

          return EsModal(
            title: "SZCZEGÓŁY ETAPU #$number",
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(stageName, style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 20))),
                    _statusTag(stage['status'] ?? 'W TRAKCIE'),
                  ],
                ),
                const SizedBox(height: 24),

                // Photos Section
                Row(
                  children: [
                    const Icon(Icons.photo_library_rounded, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Text("ZDJĘCIA Z TEGO ETAPU", style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 12),
                if (stage['photos'] == null || (stage['photos'] as List).isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Text("Brak zdjęć przypisanych do tego etapu.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.1), fontSize: 11)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: (stage['photos'] as List).length,
                        itemBuilder: (c, i) => GestureDetector(
                          onTap: () => _showPhotoPreview(_getImgUrl(stage['photos'][i])),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            width: 80,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05)),
                              image: DecorationImage(image: NetworkImage(_getImgUrl(stage['photos'][i])), fit: BoxFit.cover)
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Comments Section
                Row(
                  children: [
                    const Icon(Icons.history_rounded, color: Color(0xFF007BFF), size: 16),
                    const SizedBox(width: 8),
                    Text("KOMENTARZE I HISTORIA", style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (logs.isEmpty) 
                  Center(child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text("Brak wpisów w historii tego etapu.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.1), fontSize: 12, fontStyle: FontStyle.italic)),
                  ))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: logs.length,
                    itemBuilder: (c, i) {
                      final log = logs[i];
                      final String text = log['text'] ?? "";
                      
                      IconData icon = Icons.chat_bubble_outline_rounded;
                      Color iconCol = const Color(0xFF007BFF);
                      
                      if (text.contains("✅") || text.contains("ROZWIĄZANO")) { icon = Icons.check_circle_rounded; iconCol = Colors.green; }
                      else if (text.contains("🚀") || text.contains("MELDUNEK")) { icon = Icons.rocket_launch_rounded; iconCol = Colors.orange; }
                      else if (text.contains("🗓️")) { icon = Icons.calendar_month_rounded; iconCol = Colors.blue; }
                      else if (text.contains("⚠️") || text.contains("PROBLEM")) { icon = Icons.warning_amber_rounded; iconCol = Colors.redAccent; }
                      else if (text.contains("📁")) { icon = Icons.file_present_rounded; iconCol = Colors.indigoAccent; }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withOpacity(0.03), 
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05))
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(icon, size: 12, color: iconCol),
                                    const SizedBox(width: 8),
                                    Text(log['author'] ?? "SYSTEM", style: TextStyle(color: iconCol, fontWeight: FontWeight.w900, fontSize: 10)),
                                  ],
                                ),
                                Text(log['date'] ?? "", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 9)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(text, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13, height: 1.4)),
                          ],
                        ),
                      );
                    },
                  ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(),
                ),

                // Issues Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 8),
                        Text("ZGŁOSZONE PROBLEMY", style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1)),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: () => _reportIssueForStage(stageName), 
                      icon: const Icon(Icons.add_alert_rounded, size: 16, color: Colors.redAccent),
                      label: const Text("ZGŁOŚ NOWY", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (stageIssues.isEmpty) 
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text("Wszystko w porządku. Brak zgłoszonych problemów.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.1), fontSize: 11)),
                  )
                else
                  ...stageIssues.map((issue) => _issueMiniTile(issue)).toList(),
              ],
            ),
            footer: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentCtrl,
                    style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: "Dodaj wpis z budowy...",
                      hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 13),
                      filled: true, 
                      fillColor: theme.colorScheme.onSurface.withOpacity(0.03),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Material(
                  color: const Color(0xFF007BFF),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      final text = commentCtrl.text.trim();
                      if (text.isEmpty) return;
                      
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        final String? userEmail = prefs.getString(AppConstants.keyUserEmail);
                        final String? savedName = prefs.getString('user_name');
                        final String authorName = (userEmail == AppConstants.adminEmail) 
                            ? "Marcin (ES)" 
                            : (savedName ?? "INWESTOR");
                        
                        setState(() {
                          if (stage['logs'] == null) stage['logs'] = [];
                          (stage['logs'] as List).insert(0, {
                            'text': text,
                            'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
                            'author': authorName,
                          });
                        });
                        
                        commentCtrl.clear();
                        setS(() {}); // Refresh modal internal state
                        
                        await _saveOrderChanges();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dodano komentarz"), duration: Duration(seconds: 2)));
                      } catch (e) {
                        debugPrint("Add comment error: $e");
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Błąd zapisu: $e"), backgroundColor: Colors.red));
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        final String authorName = prefs.getString('user_name') ?? "Pracownik";
                        
                        setState(() {
                          if (stage['logs'] == null) stage['logs'] = [];
                          (stage['logs'] as List).insert(0, {
                            'text': "🚀 MELDUNEK: Rozpoczęto prace na budowie.",
                            'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
                            'author': authorName,
                          });
                        });
                        
                        setS(() {});
                        await _saveOrderChanges();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ZAMELDOWANO NA BUDOWIE"), backgroundColor: Colors.blue));
                      } catch (e) {
                        debugPrint("Meldunek error: $e");
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _pickAndUploadPhoto(stage),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickAndUploadPhoto(Map<String, dynamic> stage) async {
    try {
      final ImageSource? source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Icons.camera_alt), title: const Text("Aparat"), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
              ListTile(leading: const Icon(Icons.photo_library), title: const Text("Galeria"), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
            ],
          ),
        ),
      );

      if (source == null) return;

      final picker = ImagePicker();
      final XFile? img = await picker.pickImage(source: source, imageQuality: 50);
      
      if (img != null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Przesyłanie zdjęcia...")));
        
        final ref = FirebaseStorage.instance.ref().child("orders/${_order['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg");
        if (kIsWeb) {
          await ref.putData(await img.readAsBytes());
        } else {
          await ref.putFile(File(img.path));
        }
        
        final url = await ref.getDownloadURL();
        
        setState(() {
          if (stage['photos'] == null) stage['photos'] = [];
          (stage['photos'] as List).add(url);
          
          // Add a log entry about the photo
          if (stage['logs'] == null) stage['logs'] = [];
          (stage['logs'] as List).insert(0, {
            'text': "📸 Dodano nowe zdjęcie do etapu.",
            'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
            'author': _currentUserName ?? "Pracownik",
          });
        });
        
        await _saveOrderChanges();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Zdjęcie dodane pomyślnie!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint("Photo upload error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Błąd przesyłania zdjęcia: $e"), backgroundColor: Colors.red));
    }
  }

  Widget _issueMiniTile(Map<String, dynamic> issue) {
    final theme = Theme.of(context);
    final status = issue['status'] ?? 'NOWY';
    Color col = Colors.red;
    if (status == 'W TRAKCIE') col = Colors.orange;
    if (status == 'ROZWIĄZANO') col = Colors.green;
    if (status == 'ZAMKNIĘTY') col = Colors.grey;

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssuesScreen(isAdmin: false, currentUserEmail: _currentUserEmail ?? _order['id'], orderId: _order['id'], orderName: _order['name'], stages: _order['stages'] as List?))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: col.withOpacity(0.05), 
          borderRadius: BorderRadius.circular(12), 
          border: Border.all(color: col.withOpacity(0.2))
        ),
        child: Row(
          children: [
            Icon(Icons.report_problem_rounded, color: col, size: 16),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(issue['description'] ?? "Brak opisu", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text("$status | Priorytet: ${issue['priority'] ?? 'NORMALNY'}", style: TextStyle(color: col, fontSize: 8, fontWeight: FontWeight.w900)),
            ])),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurface.withOpacity(0.1), size: 16),
          ],
        ),
      ),
    );
  }

  void _reportIssueForStage(String stageName) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => IssuesScreen(
      isAdmin: false, 
      currentUserEmail: _currentUserEmail ?? _order['id'], 
      orderId: _order['id'], 
      orderName: _order['name'],
      stageName: stageName,
      stages: _order['stages'] as List?,
    )));
  }
  Widget _docRow(String t, String c, String p) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8), 
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(p)), 
        child: Row(children: [
          const Icon(Icons.description_outlined, color: Color(0xFF007BFF), size: 18), 
          const SizedBox(width: 12), 
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis), 
            Text(c.toUpperCase(), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 8))
          ])), 
          Icon(Icons.open_in_new, color: theme.colorScheme.onSurface.withOpacity(0.1), size: 14) 
        ])
      )
    );
  }
  Widget _weatherMeta(IconData i, String l, String v) {
    final theme = Theme.of(context);
    return Row(children: [
      Icon(i, color: const Color(0xFF007BFF), size: 14), 
      const SizedBox(width: 6), 
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 7)), 
        Text(v, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.bold))
      ])
    ]);
  }
  Widget _statusDetailRow(String l, String v, IconData i) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12), 
      child: Row(children: [
        Icon(i, color: const Color(0xFF007BFF), size: 18), 
        const SizedBox(width: 12), 
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 9)), 
          Text(v, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold))
        ])
      ])
    );
  }
  void _openChat() { setState(() => _selectedIndex = 6); }
  void _showFullGallery() { setState(() => _selectedIndex = 3); }
  void _showHistory() { setState(() => _selectedIndex = 2); }
  String _getImgUrl(dynamic p) { if (p is Map) return p['url'] ?? ""; return p.toString(); }
  void _showPhotoPreview(String url) { showDialog(context: context, builder: (ctx) => Dialog(backgroundColor: Colors.transparent, child: Column(mainAxisSize: MainAxisSize.min, children: [ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(url, fit: BoxFit.contain)), const SizedBox(height: 12), ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("ZAMKNIJ"))]))); }

}
