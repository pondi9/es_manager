import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import 'core/app_theme.dart';
import 'services/cloud_sync_service.dart';

class ToolsMapScreen extends StatefulWidget {
  const ToolsMapScreen({super.key});

  @override
  State<ToolsMapScreen> createState() => _ToolsMapScreenState();
}

class _ToolsMapScreenState extends State<ToolsMapScreen> {
  List<Map<String, dynamic>> _toolsWithGps = [];
  bool _isLoading = true;
  String _companyAddress = "";

  double _getVNum(dynamic val) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  @override
  void initState() {
    super.initState();
    _loadTools();
  }

  Future<void> _loadTools() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _companyAddress = prefs.getString('comp_address') ?? "";

    try {
      await CloudSyncService().downloadTools().timeout(const Duration(seconds: 8));
    } catch (_) {}

    final String? toolsData = prefs.getString('company_tools_v1');
    if (toolsData != null) {
      final List<dynamic> all = json.decode(toolsData);
      final random = Random();
      setState(() {
        _toolsWithGps = all.map((t) {
          var tool = Map<String, dynamic>.from(t);
          // DEFAULT: If no GPS, set to Warehouse
          if (tool['lastLat'] == null || tool['lastLng'] == null) {
            tool['lastLat'] = 50.0121107;
            tool['lastLng'] = 21.9540645;
            if (tool['manualLocation'] == null || tool['manualLocation'].isEmpty) {
              tool['manualLocation'] = "MAGAZYN GŁÓWNY (Domyślnie)";
            }
          }
          
          // ADD JITTER to avoid perfect overlap at warehouse
          if (_getVNum(tool['lastLat']) == 50.0121107 && _getVNum(tool['lastLng']) == 21.9540645) {
             tool['lastLat'] = 50.0121107 + (random.nextDouble() - 0.5) * 0.001;
             tool['lastLng'] = 21.9540645 + (random.nextDouble() - 0.5) * 0.001;
          }

          return tool;
        }).toList();
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MAPA ROZSTAWIENIA SPRZĘTU"),
        backgroundColor: AppTheme.primaryNavy,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _loadTools,
            tooltip: "Odśwież dane",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _toolsWithGps.isEmpty
              ? const Center(child: Text("Brak sprzętu w bazie."))
              : FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(
                      _getVNum(_toolsWithGps.isNotEmpty ? _toolsWithGps.first['lastLat'] : 50.0121107), 
                      _getVNum(_toolsWithGps.isNotEmpty ? _toolsWithGps.first['lastLng'] : 21.9540645)
                    ),
                    initialZoom: 11.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.esmanager.app',
                    ),
                    MarkerLayer(
                      markers: _toolsWithGps.map((t) {
                        return Marker(
                          point: LatLng(_getVNum(t['lastLat']), _getVNum(t['lastLng'])),
                          width: 80,
                          height: 80,
                          child: GestureDetector(
                            onTap: () => _showToolInfo(t),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                                  child: Text(t['name'], style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                                ),
                                const Icon(Icons.location_on, color: Colors.red, size: 30),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
    );
  }

  void _showToolInfo(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      builder: (c) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("${t['brand']} ${t['model']}"),
            const Divider(),
            Text("Ostatnia lokalizacja: ${t['lastLocDate'] ?? 'Nieznana'}"),
            Builder(builder: (context) {
              String loc = t['manualLocation'] ?? "";
              if (loc.isEmpty && (t['owner'] == 'magazyn' || t['owner'] == null)) {
                loc = "Adres Firmy: $_companyAddress";
              }
              if (loc.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text("Miejsce: $loc", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                );
              }
              return const SizedBox();
            }),
            Text("Właściciel: ${t['owner']}"),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
