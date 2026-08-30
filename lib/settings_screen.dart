import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // DODANE
import 'package:flutter/foundation.dart' show kIsWeb; // DODANE
import 'dart:convert';
import 'package:es_manager/core/app_constants.dart';
import 'package:es_manager/services/cloud_sync_service.dart';
import 'package:es_manager/services/email_service.dart'; // DODANE
import 'admin_panel_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool isAdmin;
  final String userEmail;
  const SettingsScreen({super.key, required this.isAdmin, required this.userEmail});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showFinancials = true;
  final _companyNameController = TextEditingController();
  final _companyNipController = TextEditingController();
  final _companyAddressController = TextEditingController();
  final _companyBankController = TextEditingController();
  
  // SMTP Settings
  final _smtpServerController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _smtpUserController = TextEditingController();
  final _smtpPassController = TextEditingController();
  
  // Pełna lista kafelków z DashboardScreen
  List<Map<String, dynamic>> _tiles = [
    {'id': 'attendance', 'label': 'Lista obecności', 'visible': true, 'icon': Icons.calendar_today},
    {'id': 'orders', 'label': 'Zlecenia', 'visible': true, 'icon': Icons.assignment},
    {'id': 'chat', 'label': 'Komunikator', 'visible': true, 'icon': Icons.chat_bubble_outline},
    {'id': 'expenses', 'label': 'Koszty i Paragony', 'visible': true, 'icon': Icons.shopping_bag},
    {'id': 'knowledge_base', 'label': 'Standard Firmowy', 'visible': true, 'icon': Icons.menu_book},
    {'id': 'kadry', 'label': 'Zarządzanie kadrami', 'visible': true, 'icon': Icons.people_alt},
    {'id': 'messages', 'label': 'Komunikaty', 'visible': true, 'icon': Icons.notifications_active},
    {'id': 'tools', 'label': 'Narzędzia (Baza)', 'visible': true, 'icon': Icons.build_circle},
    {'id': 'fleet', 'label': 'Flota / Pojazdy', 'visible': true, 'icon': Icons.directions_car},
    {'id': 'lan_labels', 'label': 'Opis LAN', 'visible': true, 'icon': Icons.lan},
    {'id': 'clients', 'label': 'Klienci', 'visible': true, 'icon': Icons.contact_phone},
    {'id': 'storage', 'label': 'Magazyn / Zamówienia', 'visible': true, 'icon': Icons.inventory},
    {'id': 'protocols', 'label': 'Protokoły / Pomiary', 'visible': true, 'icon': Icons.assignment_turned_in},
    {'id': 'tools_map', 'label': 'Mapa Sprzętu', 'visible': true, 'icon': Icons.map},
    {'id': 'helpful_apps', 'label': 'Grupa: Pomocne Narzędzia', 'visible': true, 'icon': Icons.construction},
    
    // NOWE INDYWIDUALNE NARZĘDZIA
    {'id': 'flashlight', 'label': 'Latarka', 'visible': true, 'icon': Icons.flashlight_on},
    {'id': 'lux_meter', 'label': 'Luksomierz', 'visible': true, 'icon': Icons.light_mode},
    {'id': 'cable_calc', 'label': 'Dobór przewodu', 'visible': true, 'icon': Icons.electrical_services},
    {'id': 'db_labels', 'label': 'Opisy rozdzielni', 'visible': true, 'icon': Icons.label_important_outline},
    {'id': 'schematic', 'label': 'Kreator schematów', 'visible': true, 'icon': Icons.schema_outlined},
    {'id': 'nfc', 'label': 'Czytnik NFC', 'visible': true, 'icon': Icons.nfc},
    {'id': 'visualizer', 'label': 'Wizualizacja rozdzielni', 'visible': true, 'icon': Icons.view_quilt_outlined},
    {'id': 'label_printer', 'label': 'Drukarka etykiet', 'visible': true, 'icon': Icons.print_outlined},
    {'id': 'installation_docs', 'label': 'Zdjęcia podtynkowe', 'visible': true, 'icon': Icons.photo_library_outlined},
    
    {'id': 'settings', 'label': 'Ustawienia', 'visible': true, 'icon': Icons.settings},
  ];

  List<Map<String, dynamic>> _folders = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _showFinancials = prefs.getBool('show_financials_global') ?? true;

    // Load from Cloud first if Admin
    if (widget.isAdmin) {
      await CloudSyncService().downloadCompanySettings();
    }

    _companyNameController.text = prefs.getString('comp_name') ?? 'ES CRM - USŁUGI ELEKTRYCZNE';
    _companyNipController.text = prefs.getString('comp_nip') ?? '';
    _companyAddressController.text = prefs.getString('comp_address') ?? '';
    _companyBankController.text = prefs.getString('comp_bank') ?? '';

    // Load SMTP Settings
    final String? smtpJson = prefs.getString('smtp_settings');
    if (smtpJson != null) {
      final s = json.decode(smtpJson);
      _smtpServerController.text = s['server'] ?? '';
      _smtpPortController.text = s['port']?.toString() ?? '465';
      _smtpUserController.text = s['user'] ?? '';
      _smtpPassController.text = s['pass'] ?? '';
    }

    final List<String>? savedOrder = prefs.getStringList('tile_order_${widget.userEmail}');
    if (savedOrder != null) {
      List<Map<String, dynamic>> sortedTiles = [];
      for (String id in savedOrder) {
        final tileIdx = _tiles.indexWhere((t) => t['id'] == id);
        if (tileIdx != -1) {
          sortedTiles.add(_tiles[tileIdx]);
        }
      }
      // Dodaj brakujące kafelki (jeśli doszły nowe w aktualizacji)
      for (var tile in _tiles) {
        if (!savedOrder.contains(tile['id'])) {
          sortedTiles.add(tile);
        }
      }
      _tiles = sortedTiles;
    }

    // Załaduj widoczność dla każdego kafelka
    for (var tile in _tiles) {
      tile['visible'] = prefs.getBool('tile_visible_${tile['id']}_${widget.userEmail}') ?? true;
    }

    final String? folderData = prefs.getString('custom_folders_${widget.userEmail}');
    if (folderData != null) {
      _folders = List<Map<String, dynamic>>.from(json.decode(folderData));
    }

    setState(() {});
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_folders_${widget.userEmail}', json.encode(_folders));
    await CloudSyncService().uploadDashboardSettings(widget.userEmail, folders: _folders);
  }

  void _manageFolder({Map<String, dynamic>? folder}) {
    final nameController = TextEditingController(text: folder?['name'] ?? '');
    List<String> selectedIds = List<String>.from(folder?['childIds'] ?? []);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDS) => AlertDialog(
        title: Text(folder == null ? 'NOWA GRUPA' : 'EDYTUJ GRUPĘ'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nazwa grupy (np. POMIARY)')),
              const SizedBox(height: 20),
              const Text('Wybierz zawartość grupy:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: _tiles.where((t) => t['id'] != 'settings').map((t) {
                    bool isChecked = selectedIds.contains(t['id']);
                    return CheckboxListTile(
                      title: Text(t['label'], style: const TextStyle(fontSize: 12)),
                      secondary: Icon(t['icon'], size: 18),
                      value: isChecked,
                      onChanged: (val) {
                        setDS(() {
                          if (val == true) selectedIds.add(t['id']); else selectedIds.remove(t['id']);
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (folder != null) TextButton(onPressed: () {
            setState(() => _folders.remove(folder));
            _saveFolders();
            Navigator.pop(context);
          }, child: const Text('USUŃ', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
          ElevatedButton(onPressed: () {
            if (nameController.text.isNotEmpty) {
              final newFolder = {
                'id': folder?['id'] ?? 'folder_${DateTime.now().millisecondsSinceEpoch}',
                'name': nameController.text,
                'childIds': selectedIds,
              };
              setState(() {
                if (folder != null) {
                  int idx = _folders.indexOf(folder);
                  _folders[idx] = newFolder;
                } else {
                  _folders.add(newFolder);
                }
              });
              _saveFolders();
              Navigator.pop(context);
            }
          }, child: const Text('ZAPISZ')),
        ],
      )),
    );
  }

  Future<void> _saveCompanyData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final name = _companyNameController.text.trim();
    final nip = _companyNipController.text.trim();
    final addr = _companyAddressController.text.trim();
    final bank = _companyBankController.text.trim();
    
    await prefs.setString('comp_name', name);
    await prefs.setString('comp_nip', nip);
    await prefs.setString('comp_address', addr);
    await prefs.setString('comp_bank', bank);
    
    // Save SMTP with trimming
    final smtp = {
      'server': _smtpServerController.text.trim(),
      'port': int.tryParse(_smtpPortController.text.trim()) ?? 465,
      'user': _smtpUserController.text.trim(),
      'pass': _smtpPassController.text.trim(),
    };
    await prefs.setString('smtp_settings', json.encode(smtp));

    // Upload to Cloud (Firestore)
    if (widget.isAdmin) {
      await CloudSyncService().uploadCompanySettings({
        'name': name,
        'nip': nip,
        'address': addr,
        'bank': bank,
        'smtp': smtp,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dane firmy i poczty zapisane w chmurze!')));
  }

  Future<void> _saveOrder() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> order = _tiles.map((t) => t['id'] as String).toList();
    await prefs.setStringList('tile_order_${widget.userEmail}', order);
    await CloudSyncService().uploadDashboardSettings(widget.userEmail, tileOrder: order);
  }

  Future<void> _updateFinancials(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _showFinancials = value);
    await prefs.setBool('show_financials_global', value);
  }

  Future<void> _updateTileVisibility(int index, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _tiles[index]['visible'] = value);
    final String tileId = _tiles[index]['id'];
    await prefs.setBool('tile_visible_${tileId}_${widget.userEmail}', value);
    
    // Prepare map of visibility for cloud sync
    Map<String, bool> visibilityMap = {};
    for (var tile in _tiles) {
      visibilityMap[tile['id']] = tile['visible'];
    }
    await CloudSyncService().uploadDashboardSettings(widget.userEmail, visibility: visibilityMap);
  }

  void _showUpdateAdminDialog() {
    final vCtrl = TextEditingController(text: AppConstants.appVersion);
    final urlCtrl = TextEditingController(text: "https://es-manager-crm.web.app/app-debug.apk");
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ZARZĄDZANIE AKTUALIZACJĄ"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: vCtrl, decoration: const InputDecoration(labelText: "Wersja do ogłoszenia")),
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: "Link do pobrania APK")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANULUJ")),
          ElevatedButton(onPressed: () async {
             await CloudSyncService().updateRemoteVersion(vCtrl.text, urlCtrl.text);
             Navigator.pop(context);
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wersja zdalna zaktualizowana!")));
          }, child: const Text("USTAW DLA WSZYSTKICH"))
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('USTAWIENIA'),
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminPanelScreen())),
              tooltip: 'Zarządzanie kadrami',
            ),
        ],
      ),
      body: ListView(
        children: [
          if (widget.isAdmin) ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('DANE FIRMY (DO PDF)', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                TextField(controller: _companyNameController, style: TextStyle(color: theme.colorScheme.onSurface), decoration: _inputDecoration('Nazwa firmy')),
                const SizedBox(height: 8),
                TextField(controller: _companyNipController, style: TextStyle(color: theme.colorScheme.onSurface), decoration: _inputDecoration('NIP')),
                const SizedBox(height: 8),
                TextField(controller: _companyAddressController, style: TextStyle(color: theme.colorScheme.onSurface), decoration: _inputDecoration('Adres')),
                const SizedBox(height: 8),
                TextField(controller: _companyBankController, style: TextStyle(color: theme.colorScheme.onSurface), decoration: _inputDecoration('Nr konta bankowego')),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveCompanyData, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007BFF), foregroundColor: Colors.white), child: const Text('ZAPISZ DANE FIRMY'))),
                const Divider(height: 40),
                Text('USTAWIENIA POCZTY (SMTP)', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12)),
                Text('Pozwala wysyłać PDF bezpośrednio z Twojego konta.', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.3))),
                const SizedBox(height: 12),
                TextField(controller: _smtpServerController, style: TextStyle(color: theme.colorScheme.onSurface), decoration: _inputDecoration('Serwer SMTP (np. smtp.gmail.com)')),
                const SizedBox(height: 8),
                TextField(controller: _smtpPortController, style: TextStyle(color: theme.colorScheme.onSurface), decoration: _inputDecoration('Port (np. 465 lub 587)'), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(controller: _smtpUserController, style: TextStyle(color: theme.colorScheme.onSurface), decoration: _inputDecoration('Twój e-mail')),
                const SizedBox(height: 8),
                TextField(controller: _smtpPassController, style: TextStyle(color: theme.colorScheme.onSurface), decoration: _inputDecoration('Hasło aplikacji (nie zwykłe hasło!)'), obscureText: true),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: ElevatedButton(onPressed: _saveCompanyData, style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1), foregroundColor: theme.colorScheme.onSurface), child: const Text('ZAPISZ POCZTĘ'))),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final smtp = {
                          'server': _smtpServerController.text.trim(),
                          'port': int.tryParse(_smtpPortController.text.trim()) ?? 465,
                          'user': _smtpUserController.text.trim(),
                          'pass': _smtpPassController.text.trim(),
                        };
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('smtp_settings', json.encode(smtp));
                        
                        if (kIsWeb) {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("FUNKCJA NIEDOSTĘPNA"),
                              content: const Text("Wysyłanie e-maili przez SMTP jest zablokowane w przeglądarce ze względów bezpieczeństwa."),
                              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ROZUMIEM"))],
                            ),
                          );
                          return;
                        }

                        if (!mounted) return;
                        showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
                        final EmailResult result = await EmailService.sendTestEmail();
                        if (!mounted) return;
                        Navigator.pop(context);

                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: theme.cardTheme.color,
                            title: Text(result.success ? "SUKCES!" : "BŁĄD", style: TextStyle(color: theme.colorScheme.onSurface)),
                            content: Text(result.success 
                              ? "Testowa wiadomość została wysłana na adres: ${_smtpUserController.text}." 
                              : "Nie udało się wysłać wiadomości.\n\nSzczegóły błędu:\n${result.message}", style: TextStyle(color: theme.colorScheme.onSurface)),
                            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
                          ),
                        );
                      }, 
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text('TEST', style: TextStyle(color: Colors.white))
                    ),
                  ],
                ),
              ]),
            ),
            const Divider(),
          ],
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('GRUPY I FOLDERY', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
          ),
          ..._folders.map((f) => ListTile(
            leading: const Icon(Icons.folder_open, color: Colors.orange),
            title: Text(f['name'], style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            subtitle: Text('Elementy: ${f['childIds']?.length ?? 0}', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.4))),
            trailing: Icon(Icons.edit, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.3)),
            onTap: () => _manageFolder(folder: f),
          )).toList(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () => _manageFolder(), 
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('STWÓRZ NOWĄ GRUPĘ'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.withOpacity(0.1), foregroundColor: Colors.orange, elevation: 0),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('OGÓLNE', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
          ),
          SwitchListTile(
            title: Text('Widoczność finansów', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
            subtitle: Text('Pokazuj sumy i wynagrodzenia w aplikacji', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
            value: _showFinancials,
            onChanged: _updateFinancials,
            activeColor: const Color(0xFF007BFF),
          ),
          ListTile(
            leading: Icon(Icons.password_rounded, color: theme.colorScheme.onSurface.withOpacity(0.5)),
            title: Text('Zmień swoje hasło', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
            subtitle: Text('Ustaw nowe hasło do logowania', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
            trailing: Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.2)),
            onTap: () {
              final newPass = TextEditingController();
              showDialog(context: context, builder: (ctx) => AlertDialog(
                backgroundColor: theme.cardTheme.color,
                title: Text("ZMIANA HASŁA", style: TextStyle(color: theme.colorScheme.onSurface)),
                content: TextField(controller: newPass, obscureText: true, style: TextStyle(color: theme.colorScheme.onSurface), decoration: const InputDecoration(labelText: "Nowe hasło")),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANULUJ")),
                  ElevatedButton(onPressed: () async {
                    if (newPass.text.length < 4) return;
                    await FirebaseFirestore.instance.collection('employees').doc(widget.userEmail.toLowerCase()).update({'password': newPass.text, 'forcePasswordReset': false});
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hasło zmienione!")));
                  }, child: const Text("ZAPISZ"))
                ],
              ));
            },
          ),
          if (widget.isAdmin)
            ListTile(
              leading: const Icon(Icons.system_update, color: Colors.orange),
              title: Text('Powiadomienie o aktualizacji', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
              subtitle: Text('Ustaw nową wersję dla wszystkich użytkowników', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
              trailing: Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.2)),
              onTap: _showUpdateAdminDialog,
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('SORTOWANIE I WIDOCZNOŚĆ MENU', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text('Przytrzymaj i przesuń kafelki, aby zmienić ich kolejność na ekranie głównym. Użyj przełączników, aby ukryć nieużywane moduły.', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.3))),
          ),
          const SizedBox(height: 10),
          _buildReorderableList(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 13),
      filled: true,
      fillColor: theme.colorScheme.onSurface.withOpacity(0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      isDense: true,
    );
  }

  Widget _buildReorderableList() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _tiles.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _tiles.removeAt(oldIndex);
          _tiles.insert(newIndex, item);
        });
        _saveOrder();
      },
      itemBuilder: (context, index) {
        final tile = _tiles[index];
        if (tile['id'] == 'kadry' && !widget.isAdmin) return SizedBox(key: ValueKey(tile['id']));

        return Card(
          key: ValueKey(tile['id']),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: theme.cardTheme.color,
          elevation: isDark ? 0 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), 
            side: BorderSide(color: theme.dividerTheme.color ?? Colors.white10)
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 8, right: 16),
            leading: ReorderableDragStartListener(
              index: index,
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.reorder_rounded, color: theme.colorScheme.onSurface.withOpacity(0.3)),
              ),
            ),
            title: Row(
              children: [
                Icon(tile['icon'], size: 20, color: const Color(0xFF007BFF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tile['label'], style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            trailing: tile['id'] == 'settings' 
              ? Icon(Icons.lock_outline, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.1))
              : Switch(
                  value: tile['visible'],
                  onChanged: (val) => _updateTileVisibility(index, val),
                  activeColor: const Color(0xFF007BFF),
                ),
          ),
        );
      },
    );
  }
}
