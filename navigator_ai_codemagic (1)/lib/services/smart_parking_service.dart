import 'dart:async';
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/voice_service.dart';

/// Service voor slim parkeren - zoekt parkeerplekken voor aankomst
class SmartParkingService {
  static final SmartParkingService _instance = SmartParkingService._internal();
  factory SmartParkingService() => _instance;
  SmartParkingService._internal();

  final VoiceService _voiceService = VoiceService();
  bool _isInitialized = false;

  // Cache
  List<ParkingLocation> _nearbyParkings = [];
  DateTime? _lastParkingSearch;

  // Settings
  double _searchRadius = 500; // meters
  bool _autoSuggestParking = true;
  int _minFreeSpotsThreshold = 3;

  Future<void> initialize() async {
    await _voiceService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _autoSuggestParking = prefs.getBool('auto_suggest_parking') ?? true;
    _searchRadius = prefs.getDouble('parking_search_radius') ?? 500;

    _isInitialized = true;
  }

  /// Zoek parkeerplekken dichtbij bestemming
  Future<List<ParkingLocation>> findParkingNear(LatLng destination) async {
    if (!_isInitialized) return [];

    // Gebruik OpenStreetMap Overpass API voor parkeerdata
    try {
      final parkings = await _fetchParkingFromOverpass(destination);
      _nearbyParkings = parkings;
      _lastParkingSearch = DateTime.now();
      return parkings;
    } catch (e) {
      print('Parking search error: $e');
      return [];
    }
  }

  Future<List<ParkingLocation>> _fetchParkingFromOverpass(LatLng dest) async {
    // Overpass API query voor parkeerplaatsen
    final query = '''
      [out:json];
      (
        node["amenity"="parking"](around:${_searchRadius},${dest.latitude},${dest.longitude});
        way["amenity"="parking"](around:${_searchRadius},${dest.latitude},${dest.longitude});
      );
      out center;
    ''';

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final elements = data['elements'] as List? ?? [];

        return elements.map((e) {
          final lat = e['lat'] ?? e['center']?['lat'] ?? dest.latitude;
          final lng = e['lon'] ?? e['center']?['lon'] ?? dest.longitude;
          final tags = e['tags'] ?? {};

          return ParkingLocation(
            id: e['id'].toString(),
            name: tags['name'] ?? 'Parkeerplaats',
            location: LatLng(lat, lng),
            capacity: int.tryParse(tags['capacity'] ?? '0') ?? 0,
            fee: tags['fee'] == 'yes',
            covered: tags['covered'] == 'yes',
            access: tags['access'] ?? 'yes',
          );
        }).toList();
      }
    } catch (e) {
      print('Overpass error: $e');
    }

    return [];
  }

  /// Check of we parkeeradvies moeten geven
  Future<void> checkAndSuggestParking(LatLng currentLocation, LatLng destination, double distanceToDestination) async {
    if (!_autoSuggestParking) return;

    // Alleen als we dichtbij komen (binnen 1km)
    if (distanceToDestination > 1000) return;

    // Zoek parkeerplekken
    final parkings = await findParkingNear(destination);
    if (parkings.isEmpty) return;

    // Filter op beschikbaarheid (simuleer - in echt zou dit live data zijn)
    final bestOptions = parkings
        .where((p) => p.capacity >= _minFreeSpotsThreshold)
        .take(3)
        .toList();

    if (bestOptions.isNotEmpty) {
      final closest = bestOptions.first;
      final distance = const Distance().as(LengthUnit.Meter, destination, closest.location);

      String message;
      if (distance < 100) {
        message = 'Je bent er bijna! Er is parkeergelegenheid bij je bestemming.';
      } else {
        message = 'Er zijn ${bestOptions.length} parkeeropties bij je bestemming. De dichtstbijzijnde is $distance meter lopen.';
      }

      await _voiceService.speak(message);
    }
  }

  /// Vind beste parkeerplek gebaseerd op voorkeuren
  ParkingLocation? findBestParking(List<ParkingLocation> options, {bool preferCovered = false, bool preferFree = false}) {
    if (options.isEmpty) return null;

    var scored = options.map((p) {
      double score = 0;

      // Dichtbij bestemming is goed
      score += 100;

      // Bedekte parkeerplaats
      if (preferCovered && p.covered) score += 50;

      // Gratis is beter
      if (preferFree && !p.fee) score += 30;

      // Grote capaciteit = waarschijnlijker plek
      score += p.capacity * 0.1;

      return MapEntry(p, score);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.first.key;
  }

  /// Simuleer beschikbare plekken (in productie: echte data)
  int estimateAvailableSpots(ParkingLocation parking) {
    // Simulatie gebaseerd op tijd van dag
    final hour = DateTime.now().hour;

    // Spits = minder plekken
    if ((hour >= 8 && hour <= 10) || (hour >= 17 && hour <= 19)) {
      return (parking.capacity * 0.2).toInt(); // 20% beschikbaar
    }

    // Normale uren
    if (hour >= 6 && hour <= 22) {
      return (parking.capacity * 0.6).toInt(); // 60% beschikbaar
    }

    // Nacht
    return (parking.capacity * 0.9).toInt(); // 90% beschikbaar
  }

  /// Settings
  Future<void> setAutoSuggest(bool enabled) async {
    _autoSuggestParking = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_suggest_parking', enabled);
  }

  Future<void> setSearchRadius(double meters) async {
    _searchRadius = meters;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('parking_search_radius', meters);
  }

  void dispose() {
    _voiceService.dispose();
  }
}

class ParkingLocation {
  final String id;
  final String name;
  final LatLng location;
  final int capacity;
  final bool fee;
  final bool covered;
  final String access;

  ParkingLocation({
    required this.id,
    required this.name,
    required this.location,
    required this.capacity,
    required this.fee,
    required this.covered,
    required this.access,
  });

  bool get isAccessible => access == 'yes' || access == 'public';
  bool get isPrivate => access == 'private' || access == 'customers';

  String get accessText {
    switch (access) {
      case 'private':
        return 'Privé';
      case 'customers':
        return 'Alleen voor klanten';
      case 'yes':
      case 'public':
      default:
        return 'Publiek';
    }
  }

  String get feeText => fee ? 'Betaald' : 'Gratis';
}