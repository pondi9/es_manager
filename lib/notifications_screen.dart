import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'admin_panel_screen.dart';
import 'attendance_screen.dart';
import 'tools_screen.dart';

import 'orders_screen.dart';
import 'storage_screen.dart';
import 'chat_screen.dart';
import 'client_order_panel_screen.dart';
import 'issues_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/cloud_sync_service.dart';
import 'core/app_utils.dart';

class NotificationsScreen extends StatefulWidget {
  final bool isAdmin;
  final String currentUserEmail;
  const NotificationsScreen({super.key, required this.isAdmin, required this.currentUserEmail});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _employees = [];
  List<String> _groups = [];
  String _myGroup = "";
  
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _selectedTarget = 'all';

  final Set<Map<String, dynamic>> _selectedNotes = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // POBIERZ Z CHMURY PRZED WYŚWIETLENIEM
    try {
      await CloudSyncService().downloadNotifications(widget.currentUserEmail, widget.isAdmin, _myGroup).timeout(const Duration(seconds: 5));
    } catch (e) {}

    final String? noteData = prefs.getString('company_notifications_v2');
    if (noteData != null) {
      _notifications = List<Map<String, dynamic>>.from(json.decode(noteData));
    }

    // FRESH LOAD of employees
    try {
      final empSnap = await FirebaseFirestore.instance.collection('employees').get();
      if (empSnap.docs.isNotEmpty) {
        final List<Map<String, dynamic>> all = empSnap.docs.map((d) {
          var data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();
        
        _employees = all.where((e) {
          final String email = (e['email'] ?? e['id'] ?? '').toString().toLowerCase();
          final bool isActive = e['isActive'] == true;
          final bool isSpecial = email == 'admin' || email == 'ksiegowa' || email == 'b' || email == 'kierownik_zewn';
          return isActive && !isSpecial && email.isNotEmpty;
        }).toList();

        try {
          final me = all.firstWhere((e) => (e['email'] ?? e['id'] ?? '').toString().toLowerCase() == widget.currentUserEmail.toLowerCase());
          _myGroup = me['group'] ?? "";
        } catch (_) {}
      }
    } catch (_) {
      final String? empData = prefs.getString('user_permissions');
      if (empData != null) {
        final List<dynamic> decoded = json.decode(empData);
        _employees = decoded.where((e) {
          if (e == null || e is! Map) return false;
          final String email = (e['email'] ?? '').toString().toLowerCase();
          return e['isActive'] == true && email != 'admin' && email.isNotEmpty;
        }).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }

    final List<String>? storedGroups = prefs.getStringList('job_groups');
    if (storedGroups != null) { _groups = storedGroups; }

    for (var note in _notifications) {
      bool isForMe = note['target'] == 'all' || 
                    note['target'] == widget.currentUserEmail || 
                    (widget.isAdmin && note['target'] == 'admin') ||
                    (note['target'].toString() == 'group:$_myGroup');
      if (isForMe) { note['isRead'] = true; }
    }
    
    await _saveNotifications();
    
    // WYŚLIJ AKTUALIZACJĘ DO CHMURY (np. po oznaczeniu jako przeczytane)
    try {
      await CloudSyncService().uploadNotifications();
    } catch (e) {}

    setState(() {});
  }

  Future<void> _saveNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_notifications_v2', AppUtils.safeJsonEncode(_notifications));
    int unread = _notifications.where((n) {
      bool isForMe = n['target'] == 'all' || n['target'] == widget.currentUserEmail || (widget.isAdmin && n['target'] == 'admin') || (n['target'].toString() == 'group:$_myGroup');
      return isForMe && n['isRead'] == false && n['isArchived'] == false;
    }).length;
    await prefs.setInt('unread_count_${widget.currentUserEmail}', unread);
  }

  void _handleNotificationTap(Map<String, dynamic> note) async {
    String title = note['title'].toString().toUpperCase();
    String content = note['content'].toString();

    // Automatyczne usuwanie powiadomienia po kliknięciu
    setState(() {
      _notifications.remove(note);
    });
    await _saveNotifications();
    await CloudSyncService().deleteNotification(note);

    // Nawigacja do odpowiedniej sekcji
    if (title.contains('WIADOMOŚĆ') || title.contains('CZAT')) {
      // Jeśli to nowa wiadomość, przejdź do czatu
      // Wyciągamy email nadawcy z treści lub pola senderEmail jeśli istnieje
      String? senderEmail = note['senderEmail'];
      if (senderEmail != null) {
        Navigator.push(context, MaterialPageRoute(builder: (c) => ChatScreen(
          currentUserEmail: widget.currentUserEmail, 
          displayName: widget.isAdmin ? "ADMIN" : "KLIENT",
          initialTargetEmail: senderEmail,
        )));
        return;
      }
    }
    if (title.contains('REJESTRACJA') && widget.isAdmin) {
      Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminPanelScreen()));
      return;
    }

    // 2. Kalendarz / Godziny / Badania / Umowa -> Lista obecności
    if (title.contains('GODZIN') || title.contains('BADANIA') || title.contains('UMOWA')) {
      Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceScreen(userEmail: widget.currentUserEmail, isAdminView: widget.isAdmin)));
      return;
    }

    // 3. Zlecenia / Budowy -> Moduł Zlecenia
    if (title.contains('ZLECENIE') || title.contains('WPIS') || title.contains('ZDJĘCIE') || title.contains('BUDOWA') || title.contains('STATUSU ETAPU') || title.contains('ETAPU') || title.contains('KOMENTARZ')) {
      // Jeśli to klient, otwórz panel zlecenia
      if (!widget.isAdmin) {
         // Na klient-id jest przypisany currentUserEmail (id zlecenia)
         final orderSnap = await FirebaseFirestore.instance.collection('orders').doc(widget.currentUserEmail).get();
         if (orderSnap.exists) {
           Navigator.push(context, MaterialPageRoute(builder: (c) => ClientOrderPanelScreen(order: {...orderSnap.data()!, 'id': orderSnap.id})));
           return;
         }
      }
      Navigator.push(context, MaterialPageRoute(builder: (c) => OrdersScreen(isAdmin: widget.isAdmin, currentUserEmail: widget.currentUserEmail)));
      return;
    }

    // 3b. PROBLEMY -> Ekran Problemów
    if (title.contains('PROBLEM') || title.contains('PILNE')) {
      Navigator.push(context, MaterialPageRoute(builder: (c) => IssuesScreen(isAdmin: widget.isAdmin, currentUserEmail: widget.currentUserEmail)));
      return;
    }

    // 4. Sprzęt / Narzędzia / Awaria -> Moduł Narzędzia
    if (title.contains('SPRZĘT') || title.contains('NARZĘDZIA') || title.startsWith('RE:')) {
      Navigator.push(context, MaterialPageRoute(builder: (c) => ToolsScreen(isAdmin: widget.isAdmin, currentUserEmail: widget.currentUserEmail)));
      return;
    }

    // 5. Magazyn / Zamówienia -> Moduł Magazyn
    if (title.contains('ZAMÓWIENIA') || title.contains('MATERIAŁ')) {
      Navigator.push(context, MaterialPageRoute(builder: (c) => StorageScreen(
        isAdmin: widget.isAdmin, 
        userEmail: widget.currentUserEmail, 
        userGroup: _myGroup
      )));
      return;
    }

    // 6. Domyślny powrót
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Brak powiązanej akcji dla tego komunikatu.')));
  }

  void _addNotification() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: const Text('NOWY KOMUNIKAT'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedTarget,
                  decoration: const InputDecoration(labelText: 'Adresat'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('WSZYSCY')),
                    ..._groups.map((g) => DropdownMenuItem(value: 'group:$g', child: Text('GRUPA: ${g.toUpperCase()}'))),
                    ..._employees.map((e) => DropdownMenuItem(value: e['email'], child: Text(e['displayName']?.isNotEmpty == true ? e['displayName'] : e['email']))),
                  ],
                  onChanged: (val) => setDS(() => _selectedTarget = val!),
                ),
                TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Tytuł')),
                TextField(controller: _contentController, decoration: const InputDecoration(labelText: 'Treść'), maxLines: 3),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
            ElevatedButton(
              onPressed: () {
                if (_titleController.text.isNotEmpty) {
                  setState(() {
                    _notifications.insert(0, {
                      'title': _titleController.text, 'content': _contentController.text,
                      'date': DateFormat('dd.MM HH:mm').format(DateTime.now()), 
                      'timestamp': DateTime.now().toIso8601String(),
                      'target': _selectedTarget,
                      'isRead': false, 'isArchived': false, 'author': widget.currentUserEmail,
                    });
                  });
                  _saveNotifications();
                  // WYŚLIJ DO CHMURY NATYCHMIAST
                  CloudSyncService().uploadNotifications();
                  
                  _titleController.clear(); _contentController.clear();
                  Navigator.pop(context);
                }
              },
              child: const Text('WYŚLIJ'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleArchive(int index) async {
    setState(() { _notifications[index]['isArchived'] = !(_notifications[index]['isArchived'] ?? false); });
    await _saveNotifications();
    await CloudSyncService().uploadNotifications();
  }

  Future<void> _bulkDelete() async {
    if (_selectedNotes.isEmpty) return;
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('USUŃ WYBRANE?'),
        content: Text('Czy na pewno chcesz trwale usunąć ${_selectedNotes.length} powiadomień?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NIE')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('TAK, USUŃ')),
        ],
      ),
    );

    if (confirm == true) {
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
      try {
        for (var note in _selectedNotes) {
          await CloudSyncService().deleteNotification(note);
          _notifications.remove(note);
        }
        setState(() {
          _selectedNotes.clear();
          _isSelectionMode = false;
        });
        await _saveNotifications();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usunięto wybrane powiadomienia.')));
      } catch (e) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd podczas usuwania: $e')));
      }
    }
  }

  void _toggleSelectAll(List<Map<String, dynamic>> visibleNotes) {
    setState(() {
      bool allSelected = visibleNotes.isNotEmpty && visibleNotes.every((n) => _selectedNotes.contains(n));
      if (allSelected) {
        for (var n in visibleNotes) {
          _selectedNotes.remove(n);
        }
        if (_selectedNotes.isEmpty) _isSelectionMode = false;
      } else {
        _selectedNotes.addAll(visibleNotes);
        _isSelectionMode = true;
      }
    });
  }

  void _deleteNotification(Map<String, dynamic> note) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('USUŃ POWIADOMIENIE?'),
        content: const Text('Czy na pewno chcesz trwale usunąć to powiadomienie?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NIE')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('TAK, USUŃ')),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _notifications.remove(note);
      });
      await _saveNotifications();
      // USUŃ Z CHMURY
      await CloudSyncService().deleteNotification(note);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Powiadomienie zostało usunięte.')));
    }
  }

  String _getName(String? email) {
    if (email == null || email.isEmpty || email == 'all') return email == 'all' ? 'WSZYSCY' : "-";
    final String sMail = email.trim().toLowerCase();
    if (sMail == 'admin') return "Marcin Kiczek";
    try {
      final emp = _employees.firstWhere(
        (e) => (e['email'] ?? '').toString().toLowerCase() == sMail || (e['id'] ?? '').toString().toLowerCase() == sMail, 
        orElse: () => {}
      );
      if (emp.isEmpty) return email;
      String fn = "${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}".trim();
      if (fn.isNotEmpty) return fn;
      if (emp['displayName'] != null && emp['displayName'].toString().isNotEmpty) return emp['displayName'];
      return email;
    } catch (_) { return email; }
  }

  @override
  Widget build(BuildContext context) {
    final myMessages = _notifications.where((n) {
      bool isForMe = n['target'] == 'all' || n['target'] == widget.currentUserEmail || (widget.isAdmin && n['target'] == 'admin') || (n['target'].toString() == 'group:$_myGroup');
      return isForMe || widget.isAdmin;
    }).toList();
    final activeNotes = myMessages.where((n) => n['isArchived'] == false).toList();
    final archivedNotes = myMessages.where((n) => n['isArchived'] == true).toList();
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        final int tabIndex = DefaultTabController.of(context).index;
        final currentVisibleNotes = tabIndex == 0 ? activeNotes : archivedNotes;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: _isSelectionMode 
              ? Text('Wybrano: ${_selectedNotes.length}') 
              : const Text('KOMUNIKATY'),
            backgroundColor: _isSelectionMode 
              ? (isDark ? Colors.blueGrey[900] : Colors.blueGrey[100]) 
              : theme.appBarTheme.backgroundColor, 
            foregroundColor: _isSelectionMode 
              ? (isDark ? Colors.white : Colors.black87) 
              : theme.appBarTheme.foregroundColor,
            leading: _isSelectionMode ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() { _selectedNotes.clear(); _isSelectionMode = false; }),
            ) : null,
            actions: [
              if (widget.isAdmin)
                IconButton(
                  icon: const Icon(Icons.done_all),
                  onPressed: () async {
                    setState(() {
                      for (var n in _notifications) {
                        n['isRead'] = true;
                      }
                    });
                    await _saveNotifications();
                    await CloudSyncService().uploadNotifications();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wszystkie powiadomienia oznaczono jako przeczytane.')));
                  },
                  tooltip: 'Oznacz wszystkie jako przeczytane',
                ),
              if (_isSelectionMode) ...[
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: () => _toggleSelectAll(currentVisibleNotes),
                  tooltip: 'Zaznacz wszystkie',
                ),
                IconButton(
                  icon: Icon(tabIndex == 0 ? Icons.archive : Icons.unarchive),
                  onPressed: () {
                    if (_selectedNotes.isEmpty) return;
                    setState(() {
                      for (var note in _selectedNotes) {
                        note['isArchived'] = tabIndex == 0;
                      }
                      _selectedNotes.clear();
                      _isSelectionMode = false;
                    });
                    _saveNotifications();
                    CloudSyncService().uploadNotifications();
                  },
                  tooltip: tabIndex == 0 ? 'Archiwizuj zaznaczone' : 'Przywróć zaznaczone',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _bulkDelete,
                  tooltip: 'Usuń zaznaczone',
                ),
              ]
            ],
            bottom: TabBar(
              onTap: (index) => setState(() { _selectedNotes.clear(); _isSelectionMode = false; }),
              tabs: const [Tab(text: 'AKTYWNE'), Tab(text: 'ARCHIWUM')], 
              labelColor: Colors.white, 
              unselectedLabelColor: Colors.white70
            ),
          ),
          body: TabBarView(
            children: [ _buildList(activeNotes, false), _buildList(archivedNotes, true) ],
          ),
          floatingActionButton: (widget.isAdmin && !_isSelectionMode) ? FloatingActionButton(
            backgroundColor: theme.colorScheme.primary, 
            onPressed: _addNotification,
            child: const Icon(Icons.send, color: Colors.white),
          ) : null,
        );
      }),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> notes, bool isArchivedTab) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final List<Map<String, dynamic>> filteredNotes = widget.isAdmin 
      ? notes 
      : notes.where((n) {
          String target = n['target']?.toString() ?? "";
          return target == widget.currentUserEmail || target == 'all';
        }).toList();

    if (filteredNotes.isEmpty) return Center(child: Text('Brak komunikatów.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3))));
    return ListView.builder(
      itemCount: filteredNotes.length,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemBuilder: (context, index) {
        final note = filteredNotes[index];
        final bool isGroup = note['target'].toString().startsWith('group:');
        String targetLabel = note['target'] == 'all' ? 'WSZYSCY' : (isGroup ? note['target'].toString().replaceAll('group:', 'GRUPA: ') : _getName(note['target']));
        bool isSelected = _selectedNotes.contains(note);
        bool unread = note['isRead'] == false;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          elevation: unread ? 4 : 1,
          color: isSelected 
            ? theme.colorScheme.primary.withOpacity(0.1) 
            : theme.cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: unread ? theme.colorScheme.primary.withOpacity(0.5) : Colors.white.withOpacity(0.05),
              width: unread ? 1.5 : 1,
            )
          ),
          child: ListTile(
            onTap: () {
              if (_isSelectionMode) {
                setState(() {
                  if (isSelected) {
                    _selectedNotes.remove(note);
                    if (_selectedNotes.isEmpty) _isSelectionMode = false;
                  } else {
                    _selectedNotes.add(note);
                  }
                });
              } else {
                _handleNotificationTap(note);
              }
            },
            onLongPress: () {
              setState(() {
                _isSelectionMode = true;
                _selectedNotes.add(note);
              });
            },
            leading: _isSelectionMode 
              ? Checkbox(
                  value: isSelected, 
                  onChanged: (v) {
                    setState(() {
                      if (v!) _selectedNotes.add(note);
                      else {
                        _selectedNotes.remove(note);
                        if (_selectedNotes.isEmpty) _isSelectionMode = false;
                      }
                    });
                  }
                )
              : Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isGroup ? Colors.blue : (note['target'] == 'all' ? Colors.orange : Colors.blueGrey)).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    note['title'] == 'Nowa rejestracja' ? Icons.person_add : (isGroup ? Icons.groups : (note['target'] == 'all' ? Icons.campaign : Icons.person_pin)),
                    color: isGroup ? Colors.blue : (note['target'] == 'all' ? Colors.orange : Colors.blueGrey),
                    size: 20,
                  ),
                ),
            title: Text(
              note['title'], 
              style: TextStyle(
                fontWeight: unread ? FontWeight.w900 : FontWeight.bold,
                color: unread ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
              )
            ),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 4),
              Text(
                note['content'],
                style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 10, color: theme.colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(width: 4),
                  Text('${note['date']} • Adresat: $targetLabel', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.2), fontWeight: FontWeight.bold)),
                ],
              ),
            ]),
            trailing: _isSelectionMode ? null : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(isArchivedTab ? Icons.unarchive : Icons.archive_outlined, color: theme.colorScheme.onSurface.withOpacity(0.3), size: 18),
                  onPressed: () { int originalIndex = _notifications.indexOf(note); _toggleArchive(originalIndex); },
                  tooltip: isArchivedTab ? 'Przywróć' : 'Archiwizuj',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                  onPressed: () => _deleteNotification(note),
                  tooltip: 'Usuń na stałe',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
