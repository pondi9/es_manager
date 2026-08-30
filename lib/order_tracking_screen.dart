import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/app_theme.dart';
import 'client_order_panel_screen.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _searchOrder() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Próba po ID dokumentu
      final snap = await FirebaseFirestore.instance.collection('orders').doc(code).get();
      
      if (snap.exists) {
        if (!mounted) return;
        Navigator.push(
          context, 
          MaterialPageRoute(builder: (_) => ClientOrderPanelScreen(order: {...snap.data()!, 'id': snap.id}))
        );
      } else {
        // 2. Próba po dedykowanym kodzie dostępu
        final query = await FirebaseFirestore.instance
            .collection('orders')
            .where('client_access_code', isEqualTo: code)
            .get();
        
        if (query.docs.isNotEmpty) {
          if (!mounted) return;
          final doc = query.docs.first;
          Navigator.push(
            context, 
            MaterialPageRoute(builder: (_) => ClientOrderPanelScreen(order: {...doc.data(), 'id': doc.id}))
          );
        } else {
          _showError("Nie znaleziono zlecenia o podanym kodzie.");
        }
      }
    } catch (e) {
      _showError("Błąd wyszukiwania: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712), // Ciemne tło ES CRM
      appBar: AppBar(
        title: const Text("ŚLEDZENIE POSTĘPÓW"),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            child: _buildSearchBox(),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return Card(
      color: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24), 
        side: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Icon(Icons.track_changes, size: 64, color: AppTheme.accentOrange),
            const SizedBox(height: 16),
            const Text("Wprowadź kod dostępu", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text("Kod otrzymasz od swojego instalatora po akceptacji zlecenia.", 
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "KOD ZLECENIA",
                labelStyle: const TextStyle(color: Colors.white38),
                hintText: "np. DPS2024",
                hintStyle: const TextStyle(color: Colors.white10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white10)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.accentBlue)),
                filled: true, fillColor: Colors.white.withOpacity(0.02),
              ),
              onSubmitted: (_) => _searchOrder(),
            ),
            const SizedBox(height: 24),
            if (_isLoading) 
              const CircularProgressIndicator(color: AppTheme.accentBlue)
            else
              ElevatedButton(
                onPressed: _searchOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("SPRAWDŹ POSTĘPY", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }
}
