import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('company_orders_v2');
    if (data != null) {
      _orders = List<Map<String, dynamic>>.from(json.decode(data));
    }
    setState(() => _isLoading = false);
  }

  // BARDZO AGRESYWNE SZUKANIE WSPÓŁRZĘDNYCH
  LatLng? _getCoords(String? location) {
    if (location == null || location.isEmpty) return null;
    try {
      // Szukamy dowolnego ciągu cyfr typu "50.123, 21.456" (nawet w środku linku)
      final regExp = RegExp(r'([-+]?\d{1,3}\.\d+),\s*([-+]?\d{1,3}\.\d+)');
      final match = regExp.firstMatch(location);
      if (match != null) {
        double lat = double.parse(match.group(1)!);
        double lng = double.parse(match.group(2)!);
        // Podstawowa walidacja zakresu dla Polski i okolic
        if (lat > 30 && lat < 70 && lng > 10 && lng < 40) {
          return LatLng(lat, lng);
        }
      }
    } catch (_) {}
    return null;
  }

  double _calculateProgress(Map<String, dynamic> order) {
    List stages = order['stages'] as List? ?? [];
    if (stages.isEmpty) return 0;
    int done = stages.where((s) => s['status'] == 'ZAKOŃCZONO').length;
    return done / stages.length;
  }

  @override
  Widget build(BuildContext context) {
    List<Marker> markers = [];
    for (var order in _orders) {
      LatLng? coords = _getCoords(order['location']);
      if (coords != null) {
        markers.add(Marker(
          point: coords,
          width: 120,
          height: 80,
          child: GestureDetector(
            onTap: () => _showOrderInfo(order),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    border: Border.all(color: Colors.red, width: 1.5),
                  ),
                  child: Text(
                    order['name'],
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.location_on, color: Colors.red, size: 38),
              ],
            ),
          ),
        ));
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('MAPA TWOICH BUDÓW'),
        backgroundColor: const Color(0xFF263238),
        foregroundColor: Colors.white,
        actions: [
           if(!_isLoading) Padding(
             padding: const EdgeInsets.only(right: 16),
             child: Center(child: Text('Pinezki: ${markers.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber))),
           )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: markers.isNotEmpty ? markers.first.point : const LatLng(52.237, 21.017), 
                  initialZoom: 7.5,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.esmanager.app',
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
              if (markers.isEmpty) 
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(30),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.withOpacity(0.5))),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map, size: 50, color: Colors.red),
                        SizedBox(height: 15),
                        Text('BRAK BUDÓW NA MAPIE', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 10),
                        Text(
                          'Mapa nie widzi budów, bo linki w zleceniach są puste lub za krótkie.\n\nWSKAZÓWKA: Wklejaj bezpośrednie współrzędne (np. 50.123, 21.456), aby mieć pewność, że pinezka się pojawi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
    );
  }

  void _showOrderInfo(Map<String, dynamic> order) {
    double progress = _calculateProgress(order);
    List assigned = order['assigned_employees'] ?? [];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(order['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 10),
            Text(order['location'] ?? 'Brak adresu', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Divider(height: 30),
            const Text('POSTĘP PRAC:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.blueGrey)),
            const SizedBox(height: 16),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 6,
                      backgroundColor: Colors.green.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  ),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('EKIPA:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.blueGrey)),
            const SizedBox(height: 5),
            Text(assigned.isEmpty ? 'Brak przypisanych osób' : assigned.join(', '), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: () {
                  final loc = order['location'].toString();
                  final url = loc.startsWith('http') ? Uri.parse(loc) : Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(loc)}");
                  launchUrl(url, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.navigation),
                label: const Text('NAWIGUJ DO BUDOWY', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[800], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
