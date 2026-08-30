import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'core/app_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/cloud_sync_service.dart';

class ClientsScreen extends StatefulWidget {
  final bool isAdmin;
  const ClientsScreen({super.key, required this.isAdmin});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _filteredClients = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  final _nameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _nipController = TextEditingController();
  final _addressController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  List<Map<String, String>> _contacts = [];
  final List<String> _roleOptions = ['Właściciel', 'Kierownik', 'Administracja'];

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await CloudSyncService().downloadClients().timeout(const Duration(seconds: 5));
    } catch (e) {}

    final String? data = prefs.getString('company_clients');
    if (data != null) {
      setState(() {
        _clients = List<Map<String, dynamic>>.from(json.decode(data));
        _sortClients();
      });
    }
    setState(() => _isLoading = false);
  }

  void _sortClients() {
    // Upewniamy się, że każdy klient ma ID
    for (var c in _clients) {
      if (c['id'] == null) {
        c['id'] = "client_${c['name'].toString().replaceAll(" ", "_")}_${DateTime.now().millisecondsSinceEpoch}";
      }
    }
    _clients.sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));
    _filteredClients = List.from(_clients);
  }

  Future<void> _saveClients() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_clients', AppUtils.safeJsonEncode(_clients));
    try {
      await CloudSyncService().uploadClients();
    } catch (e) {}
  }

  void _filterClients(String query) {
    setState(() {
      _filteredClients = _clients.where((c) {
        final n = (c['name'] ?? '').toString().toLowerCase();
        final fn = (c['fullName'] ?? '').toString().toLowerCase();
        final a = (c['address'] ?? '').toString().toLowerCase();
        final nip = (c['nip'] ?? '').toString().toLowerCase();
        final q = query.toLowerCase();
        return n.contains(q) || fn.contains(q) || a.contains(q) || nip.contains(q);
      }).toList();
    });
  }

  void _showClientDialog({int? index}) {
    String? currentId;
    if (index != null) {
      final c = _clients[index];
      currentId = c['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
      _nameController.text = c['name'] ?? '';
      _fullNameController.text = c['fullName'] ?? '';
      _addressController.text = c['address'] ?? '';
      _postalCodeController.text = c['postalCode'] ?? '';
      _cityController.text = c['city'] ?? '';
      _nipController.text = c['nip'] ?? '';
      _phoneController.text = c['phone'] ?? '';
      _notesController.text = c['notes'] ?? '';
      _contacts = List<Map<String, String>>.from(
        (c['contacts'] as List? ?? []).map((e) => {
          'name': e['name']?.toString() ?? '',
          'phone': e['phone']?.toString() ?? '',
          'role': e['role']?.toString() ?? 'Właściciel',
        })
      );
    } else {
      currentId = DateTime.now().millisecondsSinceEpoch.toString();
      _nameController.clear();
      _fullNameController.clear();
      _addressController.clear();
      _postalCodeController.clear();
      _cityController.clear();
      _nipController.clear();
      _phoneController.clear();
      _notesController.clear();
      _contacts = [];
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: Text(index == null ? 'DODAJ KLIENTA' : 'EDYTUJ KLIENTA'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPopupField(_nameController, 'Nazwa skrócona (ID)', Icons.business_center),
                  _buildPopupField(_fullNameController, 'Pełna nazwa / Dane do faktury', Icons.description),
                  _buildPopupField(_nipController, 'NIP', Icons.numbers),
                  _buildPopupField(_addressController, 'Ulica i nr', Icons.location_city),
                  Row(children: [
                    Expanded(child: _buildPopupField(_postalCodeController, 'Kod', Icons.map)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildPopupField(_cityController, 'Miasto', null)),
                  ]),
                  _buildPopupField(_phoneController, 'Główny Telefon', Icons.phone, type: TextInputType.phone),
                  const SizedBox(height: 20),
                  const Text('OSOBY KONTAKTOWE:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.blueGrey)),
                  const Divider(),
                  ..._contacts.asMap().entries.map((entry) {
                    int i = entry.key;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blueGrey[50], borderRadius: BorderRadius.circular(15)),
                      child: Column(children: [
                        Row(children: [
                          Expanded(child: TextField(
                            decoration: const InputDecoration(labelText: 'Imię i Nazwisko', isDense: true, border: InputBorder.none),
                            onChanged: (v) => _contacts[i]['name'] = v,
                            controller: TextEditingController(text: _contacts[i]['name'])..selection = TextSelection.collapsed(offset: _contacts[i]['name']!.length),
                          )),
                          IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20), onPressed: () => setDS(() => _contacts.removeAt(i)))
                        ]),
                        Row(children: [
                          Expanded(child: TextField(
                            decoration: const InputDecoration(labelText: 'Telefon', isDense: true, border: InputBorder.none),
                            onChanged: (v) => _contacts[i]['phone'] = v,
                            controller: TextEditingController(text: _contacts[i]['phone'])..selection = TextSelection.collapsed(offset: _contacts[i]['phone']!.length),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: DropdownButtonFormField<String>(
                            value: _roleOptions.contains(_contacts[i]['role']) ? _contacts[i]['role'] : _roleOptions[0],
                            decoration: const InputDecoration(labelText: 'Rola', isDense: true, border: InputBorder.none),
                            items: _roleOptions.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 11)))).toList(),
                            onChanged: (v) => setDS(() => _contacts[i]['role'] = v ?? _roleOptions[0]),
                          )),
                        ]),
                      ]),
                    );
                  }).toList(),
                  TextButton.icon(
                    onPressed: () => setDS(() => _contacts.add({'name': '', 'phone': '', 'role': 'Właściciel'})),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('DODAJ OSOBĘ KONTAKTOWĄ'),
                  ),
                  const Divider(),
                  TextField(controller: _notesController, decoration: const InputDecoration(labelText: 'Uwagi ogólne', border: OutlineInputBorder()), maxLines: 2),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
            ElevatedButton(
              onPressed: () {
                if (_nameController.text.isNotEmpty) {
                  setState(() {
                    final clientData = {
                      'id': currentId,
                      'name': _nameController.text,
                      'fullName': _fullNameController.text,
                      'nip': _nipController.text,
                      'address': _addressController.text,
                      'postalCode': _postalCodeController.text,
                      'city': _cityController.text,
                      'phone': _phoneController.text,
                      'notes': _notesController.text,
                      'contacts': _contacts,
                    };
                    if (index == null) { _clients.add(clientData); } else { _clients[index] = clientData; }
                    _sortClients();
                  });
                  _saveClients();
                  Navigator.pop(context);
                }
              },
              child: const Text('ZAPISZ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopupField(TextEditingController ctrl, String label, IconData? icon, {TextInputType type = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        decoration: InputDecoration(labelText: label, prefixIcon: icon != null ? Icon(icon, size: 20) : null, isDense: true),
      ),
    );
  }

  void _deleteClient(int index) async {
    final client = _clients[index];
    final String clientId = client['id'].toString();
    setState(() {
      _clients.removeAt(index);
      _sortClients();
    });
    _saveClients();
    try { await CloudSyncService().deleteClient(clientId); } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('BAZA KLIENTÓW'),
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
                boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Szukaj klienta...',
                  hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3)),
                  prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onChanged: _filterClients,
              ),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)))
              : _filteredClients.isEmpty 
                ? Center(child: Text('Brak klientów.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3))))
                : ListView.builder(
                    itemCount: _filteredClients.length,
                    itemBuilder: (context, index) {
                      final client = _filteredClients[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        elevation: isDark ? 0 : 2,
                        color: theme.cardTheme.color,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: theme.dividerTheme.color ?? Colors.white10)),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: theme.colorScheme.onSurface.withOpacity(0.05), child: Icon(Icons.business, color: theme.colorScheme.primary)),
                          title: Text(client['name'] ?? '-', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                          subtitle: Text("${client['city'] ?? ''}\nNIP: ${client['nip'] ?? '-'}", style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                          onTap: () => _showClientDetails(client),
                          trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurface.withOpacity(0.2)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: widget.isAdmin ? FloatingActionButton(
        backgroundColor: const Color(0xFF001A2C),
        onPressed: () => _showClientDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  void _showClientDetails(Map<String, dynamic> client) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardTheme.color,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        expand: false,
        builder: (c, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(client['name'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
                  if (widget.isAdmin)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Color(0xFF007BFF)), 
                          onPressed: () { 
                            Navigator.pop(context); 
                            int originalIndex = _clients.indexWhere((c) => c['id'].toString() == client['id'].toString());
                            _showClientDialog(index: originalIndex); 
                          }
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent), 
                          onPressed: () { 
                            showDialog(context: context, builder: (c2) => AlertDialog(
                              backgroundColor: theme.cardTheme.color,
                              title: Text('USUŃ KLIENTA?', style: TextStyle(color: theme.colorScheme.onSurface)),
                              content: Text('Usunąć klienta ${client['name']}?', style: TextStyle(color: theme.colorScheme.onSurface)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c2), child: const Text('NIE')),
                                TextButton(onPressed: () { 
                                  Navigator.pop(c2); Navigator.pop(context); 
                                  int originalIndex = _clients.indexWhere((c) => c['id'].toString() == client['id'].toString());
                                  _deleteClient(originalIndex); 
                                }, child: const Text('TAK, USUŃ', style: TextStyle(color: Colors.redAccent))),
                              ],
                            ));
                          }
                        ),
                      ],
                    ),
                ],
              ),
              const Divider(),
              _detailRow(Icons.business, 'Pełna nazwa', client['fullName']),
              _detailRow(Icons.numbers, 'NIP', client['nip']),
              _detailRow(Icons.location_on, 'Adres', "${client['postalCode'] ?? ''} ${client['city'] ?? ''}, ${client['address'] ?? ''}"),
              _detailRow(Icons.phone, 'Główny Telefon', client['phone']),
              const SizedBox(height: 20),
              Text('OSOBY KONTAKTOWE:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
              const Divider(),
              ... (client['contacts'] as List? ?? []).map((contact) => ListTile(
                title: Text("${contact['name'] ?? '-'}", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
                subtitle: Text("${contact['role'] ?? 'Właściciel'} | ${contact['phone'] ?? '-'}", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
                trailing: IconButton(
                  icon: const Icon(Icons.call, color: Colors.green),
                  onPressed: () => launchUrl(Uri.parse("tel:${contact['phone']}")),
                ),
              )),
              const SizedBox(height: 15),
              _detailRow(Icons.note, 'Uwagi', client['notes']),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary.withOpacity(0.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.bold)),
                Text(value != null && value.isNotEmpty ? value : '-', style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
