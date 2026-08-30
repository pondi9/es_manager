import 'dart:async';
import 'package:flutter/material.dart';
import 'package:light/light.dart';

class LuxMeterScreen extends StatefulWidget {
  const LuxMeterScreen({super.key});

  @override
  State<LuxMeterScreen> createState() => _LuxMeterScreenState();
}

class _LuxMeterScreenState extends State<LuxMeterScreen> {
  bool _isLuxMeterOn = false;
  Light? _light;
  StreamSubscription? _lightSubscription;
  int _luxValue = 0;

  @override
  void initState() {
    super.initState();
    try {
      _light = Light();
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopLightSensor();
    super.dispose();
  }

  void _toggleLuxMeter(bool turnOn) {
    if (turnOn) {
      _initLightSensor();
    } else {
      _stopLightSensor();
    }
    setState(() {
      _isLuxMeterOn = turnOn;
      if (!turnOn) _luxValue = 0;
    });
  }

  void _initLightSensor() {
    if (_light == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Błąd czujnika światła: Brak wsparcia')),
      );
      return;
    }
    try {
      _lightSubscription = _light!.lightSensorStream.listen((lux) {
        setState(() {
          _luxValue = lux.toInt();
        });
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Błąd czujnika światła: Brak wsparcia')),
      );
    }
  }

  void _stopLightSensor() {
    _lightSubscription?.cancel();
    _lightSubscription = null;
  }

  String _getLightAdvice(int lux) {
    if (lux < 20) return "Bardzo ciemno";
    if (lux < 200) return "Słabe oświetlenie";
    if (lux < 500) return "Oświetlenie biurowe / pokojowe";
    if (lux < 1000) return "Dobre oświetlenie do pracy";
    return "Bardzo jasne światło / Światło słoneczne";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('LUKSOMIERZ'),
        backgroundColor: const Color(0xFF455A64),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$_luxValue',
              style: TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.w900,
                color: _isLuxMeterOn ? Colors.blue : Colors.grey[300],
              ),
            ),
            Text(
              'LUX',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _isLuxMeterOn ? Colors.blueGrey : Colors.grey[300],
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: LinearProgressIndicator(
                value: (_luxValue / 1000).clamp(0.0, 1.0),
                backgroundColor: Colors.blue[50],
                color: _isLuxMeterOn ? Colors.blue : Colors.grey[300],
                minHeight: 15,
              ),
            ),
            const SizedBox(height: 20),
            if (_isLuxMeterOn)
              Text(
                _getLightAdvice(_luxValue),
                style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
              ),
            const SizedBox(height: 50),
            SwitchListTile(
              title: const Text('POMIAR NATĘŻENIA ŚWIATŁA', style: TextStyle(fontWeight: FontWeight.bold)),
              value: _isLuxMeterOn,
              activeColor: Colors.blue,
              onChanged: (val) => _toggleLuxMeter(val),
            ),
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                "Narzędzie wykorzystuje wbudowany czujnik światła otoczenia.\nWyniki zależą od modelu telefonu.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
