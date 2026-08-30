import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'core/app_constants.dart';
import 'core/app_theme.dart';
import 'login_screen.dart';
import 'attendance_screen.dart';
import 'admin_panel_screen.dart';
import 'notifications_screen.dart';
import 'orders_screen.dart';
import 'storage_screen.dart';
import 'settings_screen.dart';
import 'fleet_screen.dart';
import 'expenses_screen.dart';
import 'clients_screen.dart';
import 'tools_screen.dart';
import 'protocols_screen.dart';
import 'helpful_apps_screen.dart';
import 'chat_screen.dart';
import 'knowledge_base_screen.dart';
import 'tools_map_screen.dart';
import 'tools/lan_labels_screen.dart';
import 'tools/flashlight_screen.dart';
import 'tools/lux_meter_screen.dart';
import 'tools/cable_calculator_screen.dart';
import 'tools/db_labels_screen.dart';
import 'tools/schematic_creator_screen.dart';
import 'tools/nfc_tag_screen.dart';
import 'tools/switchboard_visualizer_screen.dart';
import 'tools/label_designer_screen.dart';
import 'tools/installation_documentation_screen.dart';
import 'issues_screen.dart';
import 'important_files_screen.dart'; 
import 'estimations_screen.dart'; 
import 'client_leads_screen.dart';
import 'admin_command_center_screen.dart';
import 'hr_dashboard_screen.dart';
import 'procurement_dashboard_screen.dart';
import 'widgets/theme_switcher.dart';
import 'widgets/es_modal.dart';
import 'services/attendance_service.dart';
import 'services/cloud_sync_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

class DashboardScreen extends StatefulWidget {
  final String userEmail;
  final bool ignoreRedirect;
  const DashboardScreen({super.key, required this.userEmail, this.ignoreRedirect = false});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  bool _isAdmin = false;
  String _displayName = "";
  String? _avatarUrl;
  String? _userGroup;
  double _totalHours = 0;
  double _totalEarnings = 0;
  bool _hideAmounts = false;
  Map<String, double> _hoursByProject = {};
  bool _isLoading = true;
  bool _showTomorrow = false;
  bool _isHoursExpanded = false;
  Map<String, dynamic> _userPermissions = {};
  List<String> _tileOrder = [];
  Map<String, bool> _localVisibility = {};
  List<Map<String, dynamic>> _folders = [];
  List<dynamic> _recentAlerts = [];
  final Set<String> _shownNoteIds = {};
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _allEmployees = [];
  List<Map<String, dynamic>> _allOrders = [];
  int _unreadAlertCount = 0;
  int _unreadChatCount = 0;
  int _unreadWarehouseCount = 0;
  int _newLeadsCount = 0;
  int _activeIssuesCount = 0;
  StreamSubscription? _attSub, _assSub, _noteSub, _userSub, _leadSub, _issueSub;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _initDashboard(); }
  @override
  void dispose() { _setOnlineStatus(false); WidgetsBinding.instance.removeObserver(this); _attSub?.cancel(); _assSub?.cancel(); _noteSub?.cancel(); _userSub?.cancel(); _leadSub?.cancel(); _issueSub?.cancel(); super.dispose(); }

  Future<void> _initDashboard() async {
    final userEmail = widget.userEmail.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    
    // Upewnij się, że admin zawsze trafia do Centrum Dowodzenia
    final bool isSavedAdmin = prefs.getBool(AppConstants.keyIsAdmin) ?? false;
    _isAdmin = isSavedAdmin || userEmail == AppConstants.adminEmail;

    if (_isAdmin && !widget.ignoreRedirect && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminCommandCenterScreen(userEmail: widget.userEmail)),
      );
      return;
    }

    // POBIERZ ŚWIEŻE DANE Z FIRESTORE przed przekierowaniem, aby wyeliminować błędy cache'u SharedPreferences
    try {
      final userSnap = await FirebaseFirestore.instance.collection('employees').doc(userEmail).get();
      if (userSnap.exists && mounted && !widget.ignoreRedirect) {
        final userData = userSnap.data()!;
        final String pos = (userData['position'] ?? '').toString().toLowerCase();
        final bool isHr = (userData['permissions'] ?? {})['access_hr_pulpit'] == true || 
                          pos.contains('księgow') || pos.contains('kadry');
        final bool isProcurement = (userData['permissions'] ?? {})['access_procurement_pulpit'] == true ||
                                   pos.contains('zaopatrz');

        // Aktualizuj cache SharedPreferences
        await prefs.setBool('is_hr', isHr);
        await prefs.setBool('is_procurement', isProcurement);

        if (isProcurement) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProcurementDashboardScreen(userEmail: widget.userEmail)));
          return;
        } else if (isHr) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HrDashboardScreen(userEmail: widget.userEmail)));
          return;
        }
      }
    } catch (_) {}

    if (prefs.getBool('is_procurement') == true && !widget.ignoreRedirect && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ProcurementDashboardScreen(userEmail: widget.userEmail)),
      );
      return;
    }

    if (prefs.getBool('is_hr') == true && !widget.ignoreRedirect && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HrDashboardScreen(userEmail: widget.userEmail)),
      );
      return;
    }

    setState(() {
      _hideAmounts = prefs.getBool('hide_earnings_${widget.userEmail}') ?? false;
      _isLoading = true;
    });
    
    // Wstępne ładowanie słowników dla poprawnego wyświetlania nazw
    final empSnap = await FirebaseFirestore.instance.collection('employees').get();
    _allEmployees = empSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();

    _checkUpdates();
    _setupLiveStreams();
    _setOnlineStatus(true);
    setState(() => _isLoading = false);
  }

  void _checkUpdates() async {
    if (kIsWeb) return;
    final updateData = await CloudSyncService().checkLatestVersion();
    if (updateData != null) {
      final String latestVersion = updateData['version'] ?? AppConstants.appVersion;
      if (_isNewerVersion(latestVersion, AppConstants.appVersion)) {
        if (mounted) _showUpdateDialog(latestVersion, updateData['downloadUrl'] ?? "");
      }
    }
  }

  bool _isNewerVersion(String remote, String local) {
    try {
      List<int> vR = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> vL = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      for (int i = 0; i < vR.length && i < vL.length; i++) {
        if (vR[i] > vL[i]) return true;
        if (vR[i] < vL[i]) return false;
      }
      return vR.length > vL.length;
    } catch (_) { return remote != local; }
  }

  void _showUpdateDialog(String version, String url) {
    double progress = 0; bool downloading = false;
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => StatefulBuilder(builder: (context, setDS) => AlertDialog(
      title: const Text("AKTUALIZACJA"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("Dostępna wersja v$version"),
        if (downloading) LinearProgressIndicator(value: progress),
      ]),
      actions: [
        if (!downloading) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("PÓŹNIEJ")),
        ElevatedButton(onPressed: () async { setDS(() => downloading = true); await _downloadAndInstallAPK(url, (p) => setDS(() => progress = p)); }, child: const Text("AKTUALIZUJ")),
      ],
    )));
  }

  Future<void> _downloadAndInstallAPK(String url, Function(double) onProgress) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pobieranie aktualizacji...")));
      
      await Permission.requestInstallPackages.request();
      final dio = Dio();
      
      final Directory? dir = await getExternalCacheDirectories().then((ds) => ds?.first);
      final String path = "${dir?.path ?? (await getTemporaryDirectory()).path}/update.apk";
      final File file = File(path);
      
      if (await file.exists()) await file.delete();

      await dio.download(
        url, 
        path, 
        options: Options(headers: {"Cache-Control": "no-cache"}), 
        onReceiveProgress: (r, t) { if (t != -1) onProgress(r / t); }
      );

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Uruchamianie instalatora..."), backgroundColor: Colors.green));

      final result = await OpenFilex.open(path, type: "application/vnd.android.package-archive");
      
      if (result.type != ResultType.done) {
        throw result.message;
      }
    } catch (e) { 
      debugPrint("Update error: $e");
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _setOnlineStatus(bool online) async {
    try { await FirebaseFirestore.instance.collection('employees').doc(widget.userEmail.trim().toLowerCase()).update({'isOnline': online, 'lastSeen': FieldValue.serverTimestamp()}); } catch (_) {}
  }

  void _setupLiveStreams() {
    final attService = AttendanceService();
    final String userEmail = widget.userEmail.trim().toLowerCase();
    final String currentMonth = DateFormat('yyyy-MM').format(DateTime.now());

    _attSub = FirebaseFirestore.instance.collection('attendance').snapshots().listen((snap) {
      double sumH = 0; double sumCash = 0; Map<String, double> breakdown = {};
      for (var doc in snap.docs) {
        final data = doc.data(); final mail = data['email']?.toString().toLowerCase() ?? doc.id.toLowerCase();
        if (!_isAdmin && (mail != userEmail)) continue;
        final Map<String, dynamic> attMap = data['data'] ?? {};
        final emp = _allEmployees.firstWhere((e) => (e['email'] ?? '').toString().toLowerCase() == mail, orElse: () => {});
        final double rate = double.tryParse((emp['rate'] ?? 0).toString()) ?? 0;
        attMap.forEach((date, val) {
          if (date.startsWith(currentMonth)) {
            double h = attService.calculateHours(val['in'], val['out']);
            if (val['type'] == 'URLOP') h = 8.0; 
            if (h > 0) { 
              sumH += h; sumCash += (h * rate); 
              String p = val['orderName'] ?? "Inne"; 
              String key = _isAdmin ? "${emp['lastName'] ?? mail}: $p" : p; 
              breakdown[key] = (breakdown[key] ?? 0) + h; 
            }
          }
        });
      }
      if (mounted) setState(() { _totalHours = sumH; _totalEarnings = sumCash; _hoursByProject = breakdown; });
    });

    _assSub = FirebaseFirestore.instance.collection('assignments').snapshots().listen((snap) {
      if (mounted) setState(() { _assignments = snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList(); });
    });

    _noteSub = FirebaseFirestore.instance.collection('notifications').snapshots().listen((snap) {
      final String groupTarget = _userGroup != null ? 'group:$_userGroup' : 'NONE';
      final all = snap.docs.map((d) => d.data() as Map<String, dynamic>).where((n) {
        if (n['isRead'] == true) return false;
        final String target = (n['target'] ?? "").toString().toLowerCase();
        return target == 'all' || target == userEmail || target == groupTarget.toLowerCase() || (_isAdmin && target == 'admin');
      }).toList();
      
      if (mounted) setState(() { _recentAlerts = all; _unreadChatCount = all.where((n) => n['title'] == 'NOWA WIADOMOŚĆ' || n['title'] == 'WIADOMOŚĆ DLA EKIPY').length; _unreadAlertCount = all.length; });
    });

    _userSub = FirebaseFirestore.instance.collection('employees').doc(userEmail).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        final d = snap.data()!;
        setState(() { 
          _userPermissions = d['permissions'] ?? {}; 
          _displayName = "${d['firstName'] ?? ''} ${d['lastName'] ?? ''}".trim(); 
          _avatarUrl = d['avatarUrl']; 
          _userGroup = d['group'];
        });
      }
    });

    if (_isAdmin) {
      _leadSub = FirebaseFirestore.instance.collection('client_leads')
          .where('status', isEqualTo: 'NOWE')
          .snapshots().listen((snap) {
        if (mounted) setState(() => _newLeadsCount = snap.docs.length);
      });

      _issueSub = FirebaseFirestore.instance.collection('issues')
          .where('status', isEqualTo: 'NOWY')
          .snapshots().listen((snap) {
        if (mounted) setState(() => _activeIssuesCount = snap.docs.length);
      });
    }
  }

  void _handleAssignmentResponse(Map<String, dynamic> a, bool accept) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(accept ? "PRZYJĄĆ ZADANIE?" : "ODRZUCIĆ ZADANIE?"),
        content: Text("Czy na pewno chcesz zmienić status zadania '${a['orderName']}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("NIE")),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true), 
            style: ElevatedButton.styleFrom(backgroundColor: accept ? Colors.green : Colors.red),
            child: const Text("TAK")
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('assignments').doc(a['id']).update({
        'status': accept ? 'ACCEPTED' : 'REJECTED', 
        'updatedAt': FieldValue.serverTimestamp()
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("ES CRM PULPIT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          if (_isAdmin) IconButton(
            icon: const Icon(Icons.psychology_rounded, color: Colors.purpleAccent), 
            tooltip: "Centrum dowodzenia",
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AdminCommandCenterScreen(userEmail: widget.userEmail)))
          ),
          const ThemeSwitcher(),
          IconButton(icon: Icon(Icons.settings_rounded, color: isDark ? Colors.white70 : Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(isAdmin: _isAdmin, userEmail: widget.userEmail)))),
          IconButton(icon: Icon(Icons.logout, color: isDark ? Colors.white70 : Colors.white), onPressed: () async { final p = await SharedPreferences.getInstance(); await p.clear(); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }),
        ],
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
        _buildHeader(), const SizedBox(height: 20), _buildStatsRow(), const SizedBox(height: 20), _buildAssignmentsBox(), const SizedBox(height: 24), _buildMainBentoGrid(),
      ])),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ 
        Text("Witaj,", style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38)), 
        Text(_displayName.isEmpty ? widget.userEmail : _displayName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87)) 
      ]),
      CircleAvatar(radius: 22, backgroundColor: theme.colorScheme.primary, backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null, child: _avatarUrl == null ? const Icon(Icons.person, color: Colors.white) : null),
    ]);
  }

  Widget _buildStatsRow() => Row(children: [
    Expanded(flex: 5, child: InkWell(onTap: _showHoursDetailsDialog, child: _statCard(_isAdmin ? "EKIPA (H)" : "MOJE GODZINY", "${_totalHours.toStringAsFixed(1)}h", Colors.blue, icon: Icons.open_in_new))),
    const SizedBox(width: 12),
    Expanded(flex: 4, child: InkWell(onLongPress: () => setState(() => _hideAmounts = !_hideAmounts), child: _statCard(_isAdmin ? "KOSZT KADR" : "ZAROBEK", _hideAmounts ? "**** zł" : "${_totalEarnings.toStringAsFixed(0)} zł", Colors.green, icon: _hideAmounts ? Icons.visibility_off : Icons.account_balance_wallet))),
  ]);

  Widget _statCard(String t, String v, Color c, {IconData? icon}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16), 
      decoration: BoxDecoration(
        color: theme.cardTheme.color, 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white.withOpacity(0.05)),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
      ), 
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isDark ? Colors.white38 : Colors.black38)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ 
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: v.contains('*') ? Colors.grey : c)))), 
          if (icon != null) Icon(icon, size: 14, color: c.withOpacity(0.5)) 
        ]),
      ])
    );
  }

  void _showHoursDetailsDialog() {
    final list = _hoursByProject.entries.toList()..sort((a,b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showEsModal(
      context,
      title: "SZCZEGÓŁY GODZIN",
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16), 
            decoration: BoxDecoration(color: AppTheme.primaryNavy, borderRadius: BorderRadius.circular(16)), 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
              children: [ 
                const Text("SUMA MIESIĘCZNA:", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), 
                Text("${_totalHours.toStringAsFixed(1)}h", style: const TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.w900, fontSize: 22)) 
              ]
            )
          ),
          const SizedBox(height: 20),
          list.isEmpty 
            ? Center(child: Text("Brak wpisów.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3)))) 
            : ListView.separated(
                shrinkWrap: true, 
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length, 
                separatorBuilder: (_,__) => Divider(height: 1, color: theme.dividerTheme.color), 
                itemBuilder: (c, i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(list[i].key, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)), 
                  trailing: Text("${list[i].value.toStringAsFixed(1)}h", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w900, fontSize: 14))
                )
              ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context), 
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryNavy, foregroundColor: Colors.white),
          child: const Text("ZAMKNIJ")
        )
      ],
    );
  }


  Widget _buildAssignmentsBox() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final tomorrow = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));
    final date = _showTomorrow ? tomorrow : today;
    final list = _assignments.where((a) => a['date'] == date && (_isAdmin || a['empEmail'] == widget.userEmail)).toList();
    bool hasNewToday = _assignments.any((a) => a['date'] == today && a['status'] == 'PENDING' && (_isAdmin || a['empEmail'] == widget.userEmail));
    bool hasNewTom = _assignments.any((a) => a['date'] == tomorrow && a['status'] == 'PENDING' && (_isAdmin || a['empEmail'] == widget.userEmail));
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity, 
      padding: const EdgeInsets.all(16), 
      decoration: BoxDecoration(
        color: theme.cardTheme.color, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: theme.dividerTheme.color ?? Colors.white.withOpacity(0.05)),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]
      ), 
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [ 
            _tabBtnWithBadge("DZIŚ", !_showTomorrow, hasNewToday, () => setState(() => _showTomorrow = false)), 
            const SizedBox(width: 24), 
            _tabBtnWithBadge("JUTRO", _showTomorrow, hasNewTom, () => setState(() => _showTomorrow = true)) 
          ]),
          if (_isAdmin) IconButton(icon: Icon(Icons.add_task_rounded, color: theme.colorScheme.primary), onPressed: _showAddAssignmentDialog)
        ]),
        const Divider(height: 32),
        if (list.isEmpty) Padding(padding: const EdgeInsets.all(8.0), child: Text("Brak zaplanowanych zadań.", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: isDark ? Colors.white24 : Colors.black26))) 
        else ...list.map((a) => _assignmentTile(a)).toList(),
      ])
    );
  }

  Widget _assignmentTile(Map<String, dynamic> a) {
    bool isMe = a['empEmail'] == widget.userEmail;
    Color statusColor = a['status'] == 'ACCEPTED' ? Colors.green : (a['status'] == 'REJECTED' ? Colors.red : Colors.orange);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8), 
      padding: const EdgeInsets.all(12), 
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05), 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: statusColor.withOpacity(0.2))
      ), 
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text("${a['empName']}: ${a['orderName']}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : Colors.black87))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(a['status'], style: TextStyle(color: statusColor, fontSize: 8, fontWeight: FontWeight.bold))),
          if (_isAdmin) IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => FirebaseFirestore.instance.collection('assignments').doc(a['id']).delete()),
        ]),
        if (a['note'] != null && a['note'].isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(a['note'], style: TextStyle(fontSize: 10, color: isDark ? Colors.blueGrey[200] : Colors.blueGrey))),
        if (!_isAdmin && a['status'] == 'PENDING' && isMe) Padding(padding: const EdgeInsets.only(top: 12), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          ElevatedButton(onPressed: () => _handleAssignmentResponse(a, false), style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red, elevation: 0), child: const Text("ODRZUĆ", style: TextStyle(fontSize: 10))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: () => _handleAssignmentResponse(a, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, elevation: 0), child: const Text("PRZYJMIJ", style: TextStyle(fontSize: 10))),
        ]))
      ])
    );
  }

  Widget _tabBtnWithBadge(String label, bool active, bool hasNew, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(onTap: onTap, child: Stack(clipBehavior: Clip.none, children: [
      Column(children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: active ? (isDark ? Colors.white : Colors.black87) : (isDark ? Colors.white24 : Colors.black26))),
        if (active) Container(margin: const EdgeInsets.only(top: 4), width: 14, height: 3, decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(2))),
      ]),
      if (hasNew) Positioned(top: -8, right: -12, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Text("!", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))))
    ]));
  }

  Widget _buildMainBentoGrid() {
    return LayoutBuilder(builder: (context, constraints) {
      int cols = constraints.maxWidth > 1200 ? 6 : (constraints.maxWidth > 800 ? 4 : 2);
      
      bool hasP(String id) {
        if (_isAdmin) return true;
        return _userPermissions[id] == true;
      }
      
      final Map<String, Widget> allItems = {
        'attendance': hasP('attendance') ? _menuTile("LISTA OBECNOŚCI", Icons.calendar_today_rounded, Colors.blue, () => _openAttendance()) : const SizedBox(),
        'orders': hasP('orders') ? _menuTile("ZLECENIA", Icons.assignment_rounded, Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail, userPermissions: _userPermissions))), badge: _activeIssuesCount) : const SizedBox(),
        'issues': hasP('orders') ? _menuTile("PROBLEMY", Icons.report_problem_rounded, Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssuesScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail))), badge: _activeIssuesCount) : const SizedBox(),
        'chat': hasP('chat') ? _menuTile("KOMUNIKATOR", Icons.forum_rounded, Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(currentUserEmail: widget.userEmail, displayName: _displayName.isEmpty ? widget.userEmail : _displayName))), badge: _unreadChatCount) : const SizedBox(),
        'knowledge_base': hasP('knowledge_base') ? _menuTile("STANDARD", Icons.auto_stories_rounded, Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => KnowledgeBaseScreen(isAdmin: _isAdmin)))) : const SizedBox(),
        'expenses': hasP('expenses') ? _menuTile("KOSZTY", Icons.receipt_long_rounded, Colors.pink, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExpensesScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))) : const SizedBox(),
        'messages': hasP('messages') ? _menuTile("KOMUNIKATY", Icons.notifications_active_rounded, Colors.amber, () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail))), badge: _unreadAlertCount) : const SizedBox(),
        'tools': hasP('tools') ? _menuTile("SPRZĘT", Icons.construction_rounded, Colors.deepOrange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ToolsScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))) : const SizedBox(),
        'lan_labels': hasP('lan_labels') ? _menuTile("OPIS LAN", Icons.lan_rounded, Colors.cyan, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanLabelsScreen()))) : const SizedBox(),
        'fleet': hasP('fleet') ? _menuTile("FLOTA", Icons.local_shipping_rounded, Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => FleetScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))) : const SizedBox(),
        'clients': hasP('clients') ? _menuTile("KLIENCI", Icons.group_rounded, Colors.deepPurpleAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientsScreen(isAdmin: _isAdmin)))) : const SizedBox(),
        'storage': hasP('storage') ? _menuTile("MAGAZYN", Icons.inventory_2_rounded, Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => StorageScreen(isAdmin: _isAdmin, userEmail: widget.userEmail, userGroup: _userGroup ?? ""))), badge: _unreadWarehouseCount) : const SizedBox(),
        'protocols': hasP('protocols') ? _menuTile("PROTOKOŁY", Icons.fact_check_rounded, Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProtocolsScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))) : const SizedBox(),
        'helpful_apps': hasP('helpful_apps') ? _menuTile("NARZĘDZIA", Icons.apps_rounded, Colors.lightGreen, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpfulAppsScreen()))) : const SizedBox(),
        'important_files': hasP('important_files') ? _menuTile("PLIKI", Icons.file_present_rounded, Colors.brown, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImportantFilesScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))) : const SizedBox(),
        'estimations': hasP('estimations') ? _menuTile("WYCENY", Icons.calculate_rounded, Colors.indigoAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => EstimationsScreen(isAdmin: _isAdmin, currentUserEmail: widget.userEmail)))) : const SizedBox(),
        'tools_map': hasP('tools_map') ? _menuTile("MAPA SPRZĘTU", Icons.map_rounded, Colors.greenAccent[700]!, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolsMapScreen()))) : const SizedBox(),
        'flashlight': hasP('flashlight') ? _menuTile("LATARKA", Icons.flashlight_on, Colors.amber[800]!, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FlashlightScreen()))) : const SizedBox(),
        'lux_meter': hasP('lux_meter') ? _menuTile("LUKSOMIERZ", Icons.light_mode, Colors.blue[300]!, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LuxMeterScreen()))) : const SizedBox(),
        'cable_calc': hasP('cable_calc') ? _menuTile("KABLE", Icons.electrical_services, Colors.redAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CableCalculatorScreen()))) : const SizedBox(),
        'db_labels': hasP('db_labels') ? _menuTile("OPISY ROZDZ.", Icons.label_important_outline, Colors.brown[400]!, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DbLabelsScreen()))) : const SizedBox(),
        'schematic': hasP('schematic') ? _menuTile("SCHEMATY", Icons.schema_outlined, Colors.indigoAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SchematicCreatorScreen()))) : const SizedBox(),
        'nfc': hasP('nfc') ? _menuTile("NFC", Icons.nfc, Colors.deepPurple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NfcTagScreen()))) : const SizedBox(),
        'visualizer': hasP('visualizer') ? _menuTile("WIZUALIZACJA", Icons.view_quilt_rounded, Colors.blueGrey[700]!, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SwitchboardVisualizerScreen()))) : const SizedBox(),
        'label_printer': hasP('label_printer') ? _menuTile("DRUKARKA", Icons.print_rounded, Colors.grey[700]!, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabelDesignerScreen()))) : const SizedBox(),
        'installation_docs': hasP('installation_docs') ? _menuTile("ZDJĘCIA", Icons.photo_library_rounded, Colors.purple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InstallationDocumentationScreen()))) : const SizedBox(),
        
        'kadry': hasP('kadry') ? _menuTile("ZARZĄDZANIE KADRAMI", Icons.people_alt_rounded, Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()))) : const SizedBox(),
        'hr_pulpit': hasP('access_hr_pulpit') ? _menuTile("PULPIT HR / KADRY", Icons.admin_panel_settings_rounded, Colors.teal, () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HrDashboardScreen(userEmail: widget.userEmail)))) : const SizedBox(),
        'procurement_pulpit': hasP('access_procurement_pulpit') ? _menuTile("PULPIT ZAOPATRZENIA", Icons.shopping_cart_checkout_rounded, Colors.blueAccent, () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProcurementDashboardScreen(userEmail: widget.userEmail)))) : const SizedBox(),

        'leads': _isAdmin ? _menuTile("ZAPYTANIA", Icons.contact_page_rounded, Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientLeadsScreen())), badge: _newLeadsCount) : const SizedBox(),
      };

      final visibleItems = allItems.values.where((w) => w is! SizedBox).toList();

      return GridView.count(
        shrinkWrap: true, 
        physics: const NeverScrollableScrollPhysics(), 
        crossAxisCount: cols, 
        crossAxisSpacing: 16, 
        mainAxisSpacing: 16, 
        children: visibleItems
      );
    });
  }

  Widget _menuTile(String t, IconData i, Color c, VoidCallback onTap, {int badge = 0}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: theme.dividerTheme.color ?? Colors.black.withOpacity(0.05)),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)]
      ), 
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24), child: Stack(alignment: Alignment.center, children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [ 
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle), child: Icon(i, color: c, size: 28)), 
          const SizedBox(height: 12), 
          Text(t, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: theme.colorScheme.onSurface)) 
        ]),
        if (badge > 0) Positioned(top: 16, right: 16, child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: Text("$badge", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))),
      ]))
    );
  }

  void _showAddAssignmentDialog() {
    final eCtrl = TextEditingController(); 
    final oCtrl = TextEditingController(); 
    final nCtrl = TextEditingController();
    showEsModal(
      context,
      title: "DODAJ ZADANIE",
      content: Column(
        mainAxisSize: MainAxisSize.min, 
        children: [
          TextField(controller: eCtrl, style: const TextStyle(color: Colors.white), decoration: _inputDecoration("Email pracownika", Icons.email_outlined)),
          const SizedBox(height: 12),
          TextField(controller: oCtrl, style: const TextStyle(color: Colors.white), decoration: _inputDecoration("Nazwa budowy", Icons.apartment_rounded)),
          const SizedBox(height: 12),
          TextField(controller: nCtrl, style: const TextStyle(color: Colors.white), maxLines: 3, decoration: _inputDecoration("Uwagi / Opis zadania", Icons.note_alt_outlined)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANULUJ", style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          onPressed: () async {
            if (eCtrl.text.isEmpty || oCtrl.text.isEmpty) return;
            final String id = DateTime.now().millisecondsSinceEpoch.toString();
            await FirebaseFirestore.instance.collection('assignments').doc(id).set({
              'empEmail': eCtrl.text.trim().toLowerCase(), 'empName': eCtrl.text, 'orderName': oCtrl.text, 'note': nCtrl.text,
              'date': _showTomorrow ? DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1))) : DateFormat('yyyy-MM-dd').format(DateTime.now()),
              'status': 'PENDING', 'createdAt': FieldValue.serverTimestamp()
            });
            if (mounted) Navigator.pop(context);
          }, 
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryNavy, foregroundColor: Colors.white),
          child: const Text("DODAJ ZADANIE")
        )
      ],
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
    prefixIcon: Icon(icon, color: AppTheme.accentBlue, size: 20),
    filled: true, 
    fillColor: Colors.white.withOpacity(0.05),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );


  void _openAttendance() { 
    if (_isAdmin) _showEmployeeSelection(); 
    else Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen(userEmail: widget.userEmail, currentUserEmail: widget.userEmail))); 
  }

  void _showEmployeeSelection() async {
    final snapshot = await FirebaseFirestore.instance.collection('employees').get();
    if (!mounted) return;
    final List<Map<String, dynamic>> filteredEmps = snapshot.docs.map((d) => d.data() as Map<String, dynamic>).where((e) => e['isActive'] == true && !(e['position'] ?? '').toString().toLowerCase().contains('kierownik') && e['email'] != AppConstants.adminEmail).toList();
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))), builder: (context) => Container(padding: const EdgeInsets.all(24), child: Column(children: [ const Text("WYBIERZ PRACOWNIKA", style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 20), Expanded(child: ListView.builder(itemCount: filteredEmps.length, itemBuilder: (context, index) { final emp = filteredEmps[index]; return ListTile(leading: const Icon(Icons.person), title: Text("${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen(userEmail: emp['email'] ?? emp['id'], currentUserEmail: widget.userEmail, isAdminView: true))); }); })) ])));
  }
}
