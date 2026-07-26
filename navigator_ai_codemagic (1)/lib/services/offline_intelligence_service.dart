import 'dart:async';
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/navigation_state.dart';

/// Service voor offline navigatie op bekende routes
class OfflineIntelligenceService {
  static final OfflineIntelligenceService _instance = OfflineIntelligenceService._internal();
  factory OfflineIntelligenceService() => _instance;
  OfflineIntelligenceService._internal();

  bool _isInitialized = false;
  Map<String, CachedRoute> _routeCache = {};
  Map<String, KnownLocation> _knownLocations = {};
  
  // Settings
  bool _offlineModeEnabled = true;
  int _maxCachedRoutes = 20;

  Future<void> initialize() async {
    await _loadCache();
    _isInitialized = true;
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load cached routes
    final routesJson = prefs.getString('cached_routes');
    if (routesJson != null) {
      final routes = jsonDecode(routesJson) as Map;
      _routeCache = routes.map((key, value) => 
        MapEntry(key.toString(), CachedRoute.fromJson(value)));
    }
    
    // Load known locations
    final locationsJson = prefs.getString('known_locations');
    if (locationsJson != null) {
      final locations = jsonDecode(locationsJson) as Map;
      _knownLocations = locations.map((key, value) =>
        MapEntry(key.toString(), KnownLocation.fromJson(value)));
    }
    
    _offlineModeEnabled = prefs.getBool('offline_mode') ?? true;
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    
    final routesJson = jsonEncode(
      _routeCache.map((key, value) => MapEntry(key, value.toJson()))
    );
    await prefs.setString('cached_routes', routesJson);
    
    final locationsJson = jsonEncode(
      _knownLocations.map((key, value) => MapEntry(key, value.toJson()))
    );
    await prefs.setString('known_locations', locationsJson);
  }

  /// Cache een route voor offline gebruik
  Future<void> cacheRoute(String routeKey, List<RouteStep> steps, {
    required LatLng from,
    required LatLng to,
    required String destinationName,
  }) async {
    if (!_offlineModeEnabled) return;
    
    final cachedRoute = CachedRoute(
      key: routeKey,
      steps: steps,
      from: from,
      to: to,
      destinationName: destinationName,
      cachedAt: DateTime.now(),
      useCount: 1,
    );
    
    _routeCache[routeKey] = cachedRoute;
    
    // Prune old routes if over limit
    if (_routeCache.length > _maxCachedRoutes) {
      _pruneOldRoutes();
    }
    
    // Add to known locations
    _addKnownLocation(destinationName, to);
    
    await _saveCache();
  }

  void _pruneOldRoutes() {
    // Sort by use count and date, remove least used
    final sorted = _routeCache.entries.toList()
      ..sort((a, b) {
        if (a.value.useCount != b.value.useCount) {
          return a.value.useCount.compareTo(b.value.useCount);
        }
        return a.value.cachedAt.compareTo(b.value.cachedAt);
      });
    
    // Remove oldest 20%
    final toRemove = (sorted.length * 0.2).ceil();
    for (var i = 0; i < toRemove; i++) {
      _routeCache.remove(sorted[i].key);
    }
  }

  void _addKnownLocation(String name, LatLng location) {
    final key = '${location.latitude.toStringAsFixed(4)}_${location.longitude.toStringAsFixed(4)}';
    
    if (_knownLocations.containsKey(key)) {
      final existing = _knownLocations[key]!;
      _knownLocations[key] = KnownLocation(
        name: name,
        location: location,
        visitCount: existing.visitCount + 1,
        lastVisited: DateTime.now(),
      );
    } else {
      _knownLocations[key] = KnownLocation(
        name: name,
        location: location,
        visitCount: 1,
        lastVisited: DateTime.now(),
      );
    }
  }

  /// Zoek gecachte route
  CachedRoute? getCachedRoute(LatLng from, LatLng to, {double toleranceMeters = 500}) {
    if (!_offlineModeEnabled) return null;
    
    final distance = Distance();
    
    for (final entry in _routeCache.entries) {
      final route = entry.value;
      
      // Check if start and end are close enough
      final fromDist = distance.as(LengthUnit.Meter, from, route.from);
      final toDist = distance.as(LengthUnit.Meter, to, route.to);
      
      if (fromDist < toleranceMeters && toDist < toleranceMeters) {
        // Update use count
        _incrementRouteUse(entry.key);
        return route;
      }
    }
    
    return null;
  }

  Future<void> _incrementRouteUse(String key) async {
    if (_routeCache.containsKey(key)) {
      final route = _routeCache[key]!;
      _routeCache[key] = CachedRoute(
        key: route.key,
        steps: route.steps,
        from: route.from,
        to: route.to,
        destinationName: route.destinationName,
        cachedAt: route.cachedAt,
        useCount: route.useCount + 1,
        lastUsed: DateTime.now(),
      );
      await _saveCache();
    }
  }

  /// Check of we een route offline kunnen doen
  bool canNavigateOffline(LatLng to, {double toleranceMeters = 500}) {
    if (!_offlineModeEnabled) return false;
    
    final distance = Distance();
    
    for (final route in _routeCache.values) {
      final toDist = distance.as(LengthUnit.Meter, to, route.to);
      if (toDist < toleranceMeters) {
        return true;
      }
    }
    
    return false;
  }

  /// Get offline route suggestion
  List<String> getOfflineRouteSuggestions() {
    if (!_offlineModeEnabled) return [];
    
    // Return most used routes
    final sorted = _routeCache.values.toList()
      ..sort((a, b) => b.useCount.compareTo(a.useCount));
    
    return sorted.take(5).map((r) => r.destinationName).toList();
  }

  /// Check of locatie bekend is
  KnownLocation? getKnownLocation(String name) {
    final lowerName = name.toLowerCase();
    
    for (final location in _knownLocations.values) {
      if (location.name.toLowerCase().contains(lowerName)) {
        return location;
      }
    }
    
    return null;
  }

  /// Get stats
  Map<String, dynamic> getStats() {
    return {
      'cached_routes': _routeCache.length,
      'known_locations': _knownLocations.length,
      'offline_mode': _offlineModeEnabled,
      'most_used_route': _routeCache.isNotEmpty
          ? _routeCache.values.reduce((a, b) => a.useCount > b.useCount ? a : b).destinationName
          : null,
    };
  }

  /// Clear cache
  Future<void> clearCache() async {
    _routeCache.clear();
    _knownLocations.clear();
    await _saveCache();
  }

  /// Settings
  Future<void> setOfflineMode(bool enabled) async {
    _offlineModeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offline_mode', enabled);
  }

  bool get isOfflineModeEnabled => _offlineModeEnabled;

  void dispose() {
    // Nothing to dispose yet
  }
}

class CachedRoute {
  final String key;
  final List<RouteStep> steps;
  final LatLng from;
  final LatLng to;
  final String destinationName;
  final DateTime cachedAt;
  final int useCount;
  final DateTime? lastUsed;

  CachedRoute({
    required this.key,
    required this.steps,
    required this.from,
    required this.to,
    required this.destinationName,
    required this.cachedAt,
    this.useCount = 0,
    this.lastUsed,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'steps': steps.map((s) => {
      'instruction': s.instruction,
      'distance': s.distance,
      'duration': s.duration,
      'location': {'lat': s.location.latitude, 'lng': s.location.longitude},
    }).toList(),
    'from': {'lat': from.latitude, 'lng': from.longitude},
    'to': {'lat': to.latitude, 'lng': to.longitude},
    'destinationName': destinationName,
    'cachedAt': cachedAt.toIso8601String(),
    'useCount': useCount,
    'lastUsed': lastUsed?.toIso8601String(),
  };

  factory CachedRoute.fromJson(Map<String, dynamic> json) {
    return CachedRoute(
      key: json['key'] ?? '',
      steps: (json['steps'] as List? ?? []).map((s) => RouteStep(
        instruction: s['instruction'] ?? '',
        distance: s['distance']?.toDouble() ?? 0,
        duration: s['duration']?.toDouble() ?? 0,
        location: LatLng(
          s['location']?['lat'] ?? 0.0,
          s['location']?['lng'] ?? 0.0,
        ),
        maneuver: s['maneuver'] ?? 'continue',
      )).toList(),
      from: LatLng(
        json['from']?['lat'] ?? 0.0,
        json['from']?['lng'] ?? 0.0,
      ),
      to: LatLng(
        json['to']?['lat'] ?? 0.0,
        json['to']?['lng'] ?? 0.0,
      ),
      destinationName: json['destinationName'] ?? 'Onbekend',
      cachedAt: DateTime.parse(json['cachedAt'] ?? DateTime.now().toIso8601String()),
      useCount: json['useCount'] ?? 0,
      lastUsed: json['lastUsed'] != null ? DateTime.parse(json['lastUsed']) : null,
    );
  }
}

class KnownLocation {
  final String name;
  final LatLng location;
  final int visitCount;
  final DateTime lastVisited;

  KnownLocation({
    required this.name,
    required this.location,
    this.visitCount = 0,
    required this.lastVisited,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': location.latitude,
    'lng': location.longitude,
    'visitCount': visitCount,
    'lastVisited': lastVisited.toIso8601String(),
  };

  factory KnownLocation.fromJson(Map<String, dynamic> json) {
    return KnownLocation(
      name: json['name'] ?? 'Onbekend',
      location: LatLng(json['lat'] ?? 0.0, json['lng'] ?? 0.0),
      visitCount: json['visitCount'] ?? 0,
      lastVisited: DateTime.parse(json['lastVisited'] ?? DateTime.now().toIso8601String()),
    );
  }
}