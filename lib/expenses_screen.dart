import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'core/app_utils.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'services/cloud_sync_service.dart';

class ExpensesScreen extends StatefulWidget {
  final bool isAdmin;
  final String currentUserEmail;
  const ExpensesScreen({super.key, required this.isAdmin, required this.currentUserEmail});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  bool _isUploading = false;
  final Color primaryColor = const Color(0xFF263238);
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    try {
      await CloudSyncService().downloadExpenses().timeout(const Duration(seconds: 5));
      await CloudSyncService().downloadOrders().timeout(const Duration(seconds: 5));
      await CloudSyncService().downloadEmployees().timeout(const Duration(seconds: 5));
    } catch (e) {}

    final String? expData = prefs.getString('company_expenses_v1');
    if (expData != null) _expenses = List<Map<String, dynamic>>.from(json.decode(expData));
    
    final String? ordersData = prefs.getString('company_orders_v2');
    if (ordersData != null) _orders = List<Map<String, dynamic>>.from(json.decode(ordersData));

    // FRESH LOAD of employees
    try {
      final empSnap = await FirebaseFirestore.instance.collection('employees').get();
      if (empSnap.docs.isNotEmpty) {
        _employees = empSnap.docs.map((d) {
          var data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();
      }
    } catch (_) {
      final String? empData = prefs.getString('user_permissions');
      if (empData != null) _employees = List<Map<String, dynamic>>.from(json.decode(empData));
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_expenses_v1', AppUtils.safeJsonEncode(_expenses));
    try { await CloudSyncService().uploadExpenses(); } catch (e) {}
  }

  void _addExpenseDialog({Map<String, dynamic>? expense, int? index}) {
    final titleController = TextEditingController(text: expense?['title'] ?? '');
    final amountController = TextEditingController(text: expense?['amount']?.toString() ?? '');
    String? selectedOrderId = expense?['orderId'];
    String? photoUrl = expense?['photoUrl'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: Text(expense == null ? 'DODAJ WYDATEK' : 'EDYTUJ WYDATEK'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Co kupiono?')),
                const SizedBox(height: 10),
                TextField(controller: amountController, decoration: const InputDecoration(labelText: 'Kwota (zł)', prefixText: 'PLN '), keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: selectedOrderId,
                  decoration: const InputDecoration(labelText: 'Powiąż z budową'),
                  items: _orders.map((o) => DropdownMenuItem(value: o['id'].toString(), child: Text(o['name']))).toList(),
                  onChanged: (val) => selectedOrderId = val,
                ),
                const SizedBox(height: 20),
                if (_isUploading) 
                  const CircularProgressIndicator()
                else if (photoUrl != null)
                  Column(children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const Text('Zdjęcie dodane', style: TextStyle(fontSize: 10)),
                    TextButton(onPressed: () => setDS(() => photoUrl = null), child: const Text('Usuń zdjęcie', style: TextStyle(color: Colors.red, fontSize: 10)))
                  ])
                else
                  ElevatedButton.icon(
                    onPressed: () async {
                      showModalBottomSheet(
                        context: context,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (c) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const ListTile(title: Text('Skąd pobrać zdjęcie paragonu?', style: TextStyle(fontWeight: FontWeight.bold))),
                              ListTile(
                                leading: const Icon(Icons.camera_alt),
                                title: const Text('Aparat'),
                                onTap: () async {
                                  Navigator.pop(c);
                                  final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 40);
                                  if (image != null) {
                                    setDS(() => _isUploading = true);
                                    try {
                                      final fileName = 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                      final ref = FirebaseStorage.instance.ref().child('receipts/$fileName');
                                      if (kIsWeb) await ref.putData(await image.readAsBytes()); else await ref.putFile(File(image.path));
                                      photoUrl = await ref.getDownloadURL();
                                    } catch (e) {}
                                    setDS(() => _isUploading = false);
                                  }
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.image),
                                title: const Text('Galeria (Pamięć telefonu)'),
                                onTap: () async {
                                  Navigator.pop(c);
                                  final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
                                  if (image != null) {
                                    setDS(() => _isUploading = true);
                                    try {
                                      final fileName = 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                      final ref = FirebaseStorage.instance.ref().child('receipts/$fileName');
                                      if (kIsWeb) await ref.putData(await image.readAsBytes()); else await ref.putFile(File(image.path));
                                      photoUrl = await ref.getDownloadURL();
                                    } catch (e) {}
                                    setDS(() => _isUploading = false);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('ZDJĘCIE PARAGONU'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                  ),
              ],
            ),
          ),
          actions: [
            if (expense != null && widget.isAdmin)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                   _deleteExpense(index!);
                   Navigator.pop(context);
                },
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANULUJ')),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.isNotEmpty && amountController.text.isNotEmpty) {
                  setState(() {
                    final data = {
                      'id': expense?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
                      'title': titleController.text,
                      'amount': double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0.0,
                      'orderId': selectedOrderId,
                      'orderName': _orders.firstWhere((o) => o['id'].toString() == selectedOrderId, orElse: () => {'name': 'Brak'})['name'],
                      'date': expense?['date'] ?? DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
                      'author': expense?['author'] ?? widget.currentUserEmail,
                      'photoUrl': photoUrl,
                    };
                    if (index == null) _expenses.insert(0, data); else _expenses[index] = data;
                  });
                  _saveExpenses();
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

  void _deleteExpense(int index) async {
    final exp = _expenses[index];
    final String id = exp['id'].toString();
    
    // 1. Najpierw usuń lokalnie dla efektu natychmiastowego
    setState(() => _expenses.removeAt(index));
    
    // 2. Zapisz stan lokalny
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_expenses_v1', AppUtils.safeJsonEncode(_expenses));
    
    // 3. Usuń trwale z chmury
    try { 
      await CloudSyncService().deleteExpense(id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wydatek usunięty trwale.')));
    } catch (e) {
      debugPrint("Błąd usuwania z chmury: $e");
    }
  }

  String _getName(String? email) {
    if (email == null || email.isEmpty) return "-";
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filteredExpenses = widget.isAdmin 
        ? _expenses 
        : _expenses.where((e) => e['author'] == widget.currentUserEmail).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('KOSZTY I PARAGONY'),
        backgroundColor: const Color(0xFF001A2C), 
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)))
        : filteredExpenses.isEmpty
          ? Center(child: Text('Brak zarejestrowanych wydatków.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3))))
          : ListView.builder(
              itemCount: filteredExpenses.length,
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemBuilder: (context, index) {
                final exp = filteredExpenses[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: theme.cardTheme.color,
                  elevation: isDark ? 0 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15), 
                    side: BorderSide(color: theme.dividerTheme.color ?? Colors.white10)
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.withOpacity(0.1),
                      child: const Icon(Icons.receipt, color: Colors.green),
                    ),
                    title: Text(exp['title'], style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    subtitle: Text(
                      'Budowa: ${exp['orderName']}\nData: ${exp['date']} | Kupujący: ${_getName(exp['author'])}',
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 11),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${exp['amount'].toStringAsFixed(2)} zł', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.redAccent, fontSize: 14)),
                            if (exp['photoUrl'] != null) Icon(Icons.image, size: 14, color: theme.colorScheme.primary.withOpacity(0.5)),
                          ],
                        ),
                        if (widget.isAdmin) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.edit, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                            onPressed: () => _addExpenseDialog(expense: exp, index: _expenses.indexOf(exp)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                            onPressed: () => _deleteExpense(index),
                          ),
                        ]
                      ],
                    ),
                    onTap: () {
                      if (exp['photoUrl'] != null) {
                        showDialog(context: context, builder: (c) => Dialog(
                          backgroundColor: theme.cardTheme.color,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Image.network(
                            kIsWeb ? 'https://images.weserv.nl/?url=${Uri.encodeComponent(exp['photoUrl'])}&w=600' : exp['photoUrl'],
                            loadingBuilder: (c, w, p) => p == null ? w : const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
                            errorBuilder: (c, e, s) => const Center(child: Padding(padding: EdgeInsets.all(20), child: Icon(Icons.broken_image, size: 40, color: Colors.grey))),
                          ),
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('ZAMKNIJ'))
                        ])));
                      }
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addExpenseDialog,
        backgroundColor: Colors.green[700],
        child: const Icon(Icons.add_shopping_cart, color: Colors.white),
      ),
    );
  }
}
