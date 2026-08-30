import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'core/app_theme.dart';

class PublicRequestScreen extends StatefulWidget {
  const PublicRequestScreen({super.key});

  @override
  State<PublicRequestScreen> createState() => _PublicRequestScreenState();
}

class _PublicRequestScreenState extends State<PublicRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _descController = TextEditingController();
  bool _isSending = false;

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      final leadId = DateTime.now().millisecondsSinceEpoch.toString();
      final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

      final leadData = {
        'id': leadId,
        'clientName': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'description': _descController.text.trim(),
        'date': dateStr,
        'status': 'NOWE',
        'type': 'PUBLIC_LEAD'
      };

      // 1. Zapisz do kolekcji leadów
      await FirebaseFirestore.instance.collection('client_leads').doc(leadId).set(leadData);

      // 2. Dodaj powiadomienie dla administratora
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': 'NOWE ZAPYTANIE O WYCENĘ',
        'content': 'Klient: ${_nameController.text.trim()} prosi o wycenę. Tel: ${_phoneController.text.trim()}',
        'date': dateStr,
        'author': 'System Klienta',
        'target': 'admin',
        'isRead': false,
        'isArchived': false,
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("DZIĘKUJEMY!"),
            content: const Text("Twoje zapytanie zostało wysłane. Skontaktujemy się z Tobą najszybciej jak to możliwe."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text("OK"),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Błąd wysyłania: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: const Text("ZAPYTAJ O WYCENĘ"),
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Wypełnij poniższy formularz, a przygotujemy dla Ciebie ofertę.", 
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: "Imię i Nazwisko / Firma", prefixIcon: Icon(Icons.person)),
                    validator: (v) => v!.isEmpty ? "To pole jest wymagane" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: "Numer telefonu", prefixIcon: Icon(Icons.phone)),
                    keyboardType: TextInputType.phone,
                    validator: (v) => v!.isEmpty ? "To pole jest wymagane" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(labelText: "Adres zlecenia (Miasto, Ulica)", prefixIcon: Icon(Icons.location_on)),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(labelText: "Opis prac / Co jest do zrobienia?", alignLabelWithHint: true),
                    maxLines: 5,
                    validator: (v) => v!.isEmpty ? "Proszę opisać zlecenie" : null,
                  ),
                  const SizedBox(height: 32),
                  if (_isSending)
                    const Center(child: CircularProgressIndicator())
                  else
                    ElevatedButton(
                      onPressed: _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 60),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("WYŚLIJ ZAPYTANIE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
