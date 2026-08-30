import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class WeatherService {
  final _dio = Dio();

  Future<Map<String, dynamic>?> getWeatherByAddress(String address) async {
    try {
      // 1. Geocoding (Address to Lat/Lon) using Nominatim (OpenStreetMap)
      final geoRes = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': address,
          'format': 'json',
          'limit': 1,
        },
      );

      if (geoRes.data == null || (geoRes.data as List).isEmpty) {
        return null;
      }

      final double lat = double.parse(geoRes.data[0]['lat']);
      final double lon = double.parse(geoRes.data[0]['display_name'].contains('Poland') ? geoRes.data[0]['lon'] : geoRes.data[0]['lon']);

      // 2. Weather using Open-Meteo
      final weatherRes = await _dio.get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': lat,
          'longitude': lon,
          'current_weather': true,
          'timezone': 'auto',
        },
      );

      if (weatherRes.data != null && weatherRes.data['current_weather'] != null) {
        final current = weatherRes.data['current_weather'];
        return {
          'temp': current['temperature'],
          'wind': current['windspeed'],
          'code': current['weathercode'], // WMO Weather interpretation codes
          'isDay': current['is_day'] == 1,
          'city': geoRes.data[0]['display_name'].split(',')[0],
        };
      }
    } catch (e) {
      debugPrint("Weather fetch error: $e");
    }
    return null;
  }

  String getWeatherIcon(int code) {
    // Basic WMO Weather interpretation codes mapping
    if (code == 0) return "☀️"; // Clear sky
    if (code >= 1 && code <= 3) return "⛅"; // Partly cloudy
    if (code >= 45 && code <= 48) return "🌫️"; // Fog
    if (code >= 51 && code <= 67) return "🌧️"; // Rain
    if (code >= 71 && code <= 77) return "❄️"; // Snow
    if (code >= 80 && code <= 82) return "🌦️"; // Showers
    if (code >= 95) return "⛈️"; // Thunderstorm
    return "🌡️";
  }
  
  String getWeatherDesc(int code) {
    if (code == 0) return "Czyste niebo";
    if (code >= 1 && code <= 3) return "Częściowe zachmurzenie";
    if (code >= 45 && code <= 48) return "Mgła";
    if (code >= 51 && code <= 67) return "Opady deszczu";
    if (code >= 71 && code <= 77) return "Opady śniegu";
    if (code >= 80 && code <= 82) return "Przelotne opady";
    if (code >= 95) return "Burza";
    return "Pochmurno";
  }
}
