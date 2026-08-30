import 'package:flutter/material.dart';
import 'package:torch_light/torch_light.dart';

class FlashlightScreen extends StatefulWidget {
  const FlashlightScreen({super.key});

  @override
  State<FlashlightScreen> createState() => _FlashlightScreenState();
}

class _FlashlightScreenState extends State<FlashlightScreen> {
  bool _isTorchOn = false;

  @override
  void dispose() {
    if (_isTorchOn) {
      _toggleTorch(false);
    }
    super.dispose();
  }

  Future<void> _toggleTorch(bool turnOn) async {
    try {
      if (turnOn) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
      setState(() {
        _isTorchOn = turnOn;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Błąd latarki: Brak wsparcia lub brak uprawnień')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('LATARKA'),
        backgroundColor: const Color(0xFF455A64),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => _toggleTorch(!_isTorchOn),
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: _isTorchOn ? Colors.amber[100] : Colors.grey[100],
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (_isTorchOn)
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                  ],
                ),
                child: Icon(
                  _isTorchOn ? Icons.flashlight_on : Icons.flashlight_off,
                  size: 100,
                  color: _isTorchOn ? Colors.amber[800] : Colors.grey[400],
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              _isTorchOn ? "LATARKA WŁĄCZONA" : "KLIKNIJ, ABY WŁĄCZYĆ",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _isTorchOn ? Colors.amber[900] : Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 10),
            Switch(
              value: _isTorchOn,
              activeColor: Colors.amber,
              onChanged: (val) => _toggleTorch(val),
            ),
          ],
        ),
      ),
    );
  }
}
