import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'core/app_theme.dart';

class ClientLeadsScreen extends StatefulWidget {
  const ClientLeadsScreen({super.key});

  @override
  State<ClientLeadsScreen> createState() => _ClientLeadsScreenState();
}

class _ClientLeadsScreenState extends State<ClientLeadsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _leads = [];

  @override
  void initState() {
    super.initState();
    _fetchLeads();
  }

  Future<void> _fetchLeads() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('client_leads')
          .orderBy('date', descending: true)
          .get();
      
      setState(() {
        _leads = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching leads: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    await FirebaseFirestore.instance.collection('client_leads').doc(id).update({'status': status});
    _fetchLeads();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("ZAPYTANIA O WYCENĘ"),
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchLeads),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)))
          : _leads.isEmpty
              ? Center(child: Text("Brak nowych zapytań.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3))))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _leads.length,
                  itemBuilder: (context, index) {
                    final lead = _leads[index];
                    final status = lead['status'] ?? 'NOWE';
                    Color statusColor = status == 'NOWE' ? Colors.blue : (status == 'W TRAKCIE' ? Colors.orange : Colors.green);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      color: theme.cardTheme.color,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: theme.dividerTheme.color ?? Colors.white10)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(lead['clientName'] ?? '-', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                  child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text("Data: ${lead['date'] ?? '-'}", style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.4))),
                            const Divider(height: 24),
                            _leadInfo(Icons.phone, lead['phone'] ?? '-', isPhone: true),
                            _leadInfo(Icons.location_on, lead['address'] ?? '-'),
                            const SizedBox(height: 12),
                            Text("OPIS ZLECENIA:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: theme.colorScheme.primary)),
                            const SizedBox(height: 4),
                            Text(lead['description'] ?? '-', style: TextStyle(fontSize: 13, height: 1.4, color: theme.colorScheme.onSurface)),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () async {
                                    final ok = await _confirmDelete();
                                    if (ok) {
                                      await FirebaseFirestore.instance.collection('client_leads').doc(lead['id']).delete();
                                      _fetchLeads();
                                    }
                                  },
                                ),
                                const Spacer(),
                                Theme(
                                  data: theme.copyWith(canvasColor: theme.cardTheme.color),
                                  child: DropdownButton<String>(
                                    value: status,
                                    dropdownColor: theme.cardTheme.color,
                                    style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12),
                                    underline: const SizedBox(),
                                    items: ['NOWE', 'W TRAKCIE', 'ZROBIONE'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                    onChanged: (v) => _updateStatus(lead['id'], v!),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _convertToOrder(lead),
                                  icon: const Icon(Icons.assignment_turned_in_rounded, size: 16),
                                  label: const Text("PRZEKSZTAŁĆ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF007BFF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _convertToOrder(Map<String, dynamic> lead) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("PRZEKSZTAŁCIĆ W ZLECENIE?"),
        content: Text("Czy chcesz utworzyć nowe zlecenie dla klienta ${lead['clientName']}? Zapytanie zostanie oznaczone jako ZROBIONE."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("NIE")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("TAK, UTWÓRZ")),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final String orderId = DateTime.now().millisecondsSinceEpoch.toString();
        
        // Domyślne etapy dla nowego zlecenia
        final List<Map<String, dynamic>> defaultStages = [
          {'name': 'Przygotowanie i projekt', 'status': 'W TRAKCIE', 'photos': [], 'logs': []},
          {'name': 'Montaż instalacji', 'status': 'OCZEKUJE', 'photos': [], 'logs': []},
          {'name': 'Pomiary i testy', 'status': 'OCZEKUJE', 'photos': [], 'logs': []},
          {'name': 'Odbiór i dokumentacja', 'status': 'OCZEKUJE', 'photos': [], 'logs': []},
        ];

        // Tworzenie zlecenia
        await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
          'id': orderId,
          'name': "Zlecenie: ${lead['clientName']}",
          'location': lead['address'] ?? 'Brak adresu',
          'client_name': lead['clientName'],
          'client_phone': lead['phone'],
          'client_email': lead['email'] ?? "", // Jeśli było podane
          'description': lead['description'],
          'status': 'W TRAKCIE',
          'startDate': DateFormat('dd.MM.yyyy').format(DateTime.now()),
          'stages': defaultStages,
          'client_access_code': lead['clientName'].toString().split(' ').last.toUpperCase() + DateTime.now().year.toString(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Aktualizacja zapytania
        await FirebaseFirestore.instance.collection('client_leads').doc(lead['id']).update({
          'status': 'ZROBIONE',
          'convertedToOrderId': orderId,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Zlecenie zostało utworzone pomyślnie!"),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: "ZOBACZ", 
                textColor: Colors.white,
                onPressed: () {
                  // Opcjonalnie można tu dodać nawigację do szczegółów zlecenia
                }
              ),
            ),
          );
        }
        _fetchLeads();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Błąd: $e"), backgroundColor: Colors.red));
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _leadInfo(IconData icon, String text, {bool isPhone = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: isPhone ? () => launchUrl(Uri.parse("tel:$text")) : null,
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF007BFF)),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: isPhone ? Colors.blue : theme.colorScheme.onSurface, decoration: isPhone ? TextDecoration.underline : null))),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete() async {
    return await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("USUŃ ZAPYTANIE?"),
        content: const Text("Czy na pewno chcesz trwale usunąć to zapytanie?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("NIE")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("TAK, USUŃ", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;
  }
}
