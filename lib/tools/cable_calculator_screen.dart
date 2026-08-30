import 'dart:math';
import 'package:flutter/material.dart';

class CableCalculatorScreen extends StatefulWidget {
  const CableCalculatorScreen({super.key});

  @override
  State<CableCalculatorScreen> createState() => _CableCalculatorScreenState();
}

class _CableCalculatorScreenState extends State<CableCalculatorScreen> {
  final _powerController = TextEditingController();
  final _lengthController = TextEditingController();
  
  bool _isThreePhase = false;
  String _material = "CU"; // Cu - miedź, AL - aluminium
  double _cosPhi = 0.9;
  
  String _resultSection = "";
  double _resultDrop = 0.0;
  double _resultCurrent = 0.0;
  bool _calculated = false;

  void _calculate() {
    double? power = double.tryParse(_powerController.text.replaceAll(',', '.')); // kW
    double? length = double.tryParse(_lengthController.text.replaceAll(',', '.')); // m

    if (power == null || length == null || power <= 0 || length <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Podaj poprawne dane (liczby dodatnie)')),
      );
      return;
    }

    // 1. Oblicz natężenie prądu (A)
    double current;
    if (_isThreePhase) {
      // I = P / (sqrt(3) * U * cos phi)
      current = (power * 1000) / (sqrt(3) * 400 * _cosPhi);
    } else {
      // I = P / (U * cos phi)
      current = (power * 1000) / (230 * _cosPhi);
    }

    // 2. Wybierz bazowy przekrój na podstawie obciążalności długotrwałej (uproszczone dla Cu/Al)
    // Tabela uproszczona dla montażu pod tynkiem
    List<double> sections = [1.5, 2.5, 4, 6, 10, 16, 25, 35, 50, 70, 95, 120, 150, 185, 240];
    double gamma = (_material == "CU") ? 56.0 : 33.0; // konduktywność

    double selectedSection = sections[0];
    
    // Pętla szukająca przekroju spełniającego warunek spadku napięcia < 3%
    bool found = false;
    for (double s in sections) {
      double drop;
      if (_isThreePhase) {
        // dU% = (100 * sqrt(3) * L * I * cos phi) / (gamma * S * U)
        drop = (100 * sqrt(3) * length * current * _cosPhi) / (gamma * s * 400);
      } else {
        // dU% = (100 * 2 * L * I * cos phi) / (gamma * S * U)
        drop = (100 * 2 * length * current * _cosPhi) / (gamma * s * 230);
      }

      // Dodatkowy warunek obciążalności prądowej (uproszczony)
      // Cu: 1.5-14A, 2.5-18.5A, 4-25A, 6-34A, 10-46A, 16-62A
      double maxI = 0;
      if (_material == "CU") {
        if (s == 1.5) maxI = 14;
        else if (s == 2.5) maxI = 18.5;
        else if (s == 4.0) maxI = 25;
        else if (s == 6.0) maxI = 34;
        else if (s == 10.0) maxI = 46;
        else if (s == 16.0) maxI = 62;
        else maxI = s * 4; // zgrubne przybliżenie dla dużych przekrojów
      } else {
        maxI = (s * 3); // Aluminium ma mniejszą obciążalność
      }

      if (drop <= 3.0 && current <= maxI) {
        selectedSection = s;
        _resultDrop = drop;
        found = true;
        break;
      }
      
      // Zapamiętaj ostatni testowany jako wynik, jeśli nie znajdziemy idealnego
      selectedSection = s;
      _resultDrop = drop;
    }

    setState(() {
      _resultSection = "${selectedSection.toStringAsFixed(1)} mm²";
      _resultCurrent = current;
      _calculated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = const Color(0xFF455A64);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('DOBÓR KABLA I SPADEK U', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primaryColor.withOpacity(0.05), Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInputCard(colorScheme),
              const SizedBox(height: 24),
              if (_calculated) _buildResultCard(colorScheme),
              const SizedBox(height: 30),
              const Text(
                'Uwaga: Obliczenia mają charakter orientacyjny. Dobór docelowy powinien uwzględniać sposób ułożenia kabla, temperaturę otoczenia oraz pętlę zwarcia.',
                style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PARAMETRY LINII', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1, color: Colors.blueGrey)),
          const SizedBox(height: 20),
          TextField(
            controller: _powerController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecor('Moc odbiornika (kW)', Icons.bolt_outlined),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _lengthController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecor('Długość kabla (m)', Icons.straighten),
          ),
          const SizedBox(height: 20),
          const Text('RODZAJ ZASILANIA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _choiceChip('1 FAZA (230V)', !_isThreePhase, () => setState(() => _isThreePhase = false)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _choiceChip('3 FAZY (400V)', _isThreePhase, () => setState(() => _isThreePhase = true)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('MATERIAŁ ŻYŁY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _choiceChip('MIEDŹ (Cu)', _material == "CU", () => setState(() => _material = "CU")),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _choiceChip('ALUMINIUM (Al)', _material == "AL", () => setState(() => _material = "AL")),
              ),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _calculate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[800],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 5,
                shadowColor: Colors.amber.withOpacity(0.5),
              ),
              child: const Text('OBLICZ PARAMETRY', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blueGrey[800]!, Colors.blueGrey[900]!]),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          const Text('REKOMENDOWANY PRZEKRÓJ:', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 10),
          Text(
            _resultSection,
            style: const TextStyle(color: Colors.amber, fontSize: 42, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 10),
          _resultRow('Natężenie prądu:', '${_resultCurrent.toStringAsFixed(1)} A'),
          _resultRow('Spadek napięcia:', '${_resultDrop.toStringAsFixed(2)} %'),
          _resultRow('Dopuszczalny spadek:', '3.00 %'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _resultDrop <= 3.0 ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _resultDrop <= 3.0 ? 'NORMA SPEŁNIONA ✓' : 'PRZEKROCZONA NORMA ⚠',
              style: TextStyle(
                color: _resultDrop <= 3.0 ? Colors.greenAccent : Colors.redAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _choiceChip(String label, bool selected, VoidCallback onSelected) {
    return InkWell(
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF455A64) : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? const Color(0xFF455A64) : Colors.grey[300]!),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF455A64)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
      filled: true,
      fillColor: Colors.grey[50],
      labelStyle: const TextStyle(fontSize: 13),
    );
  }
}
