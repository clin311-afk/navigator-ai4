import 'dart:async';
import 'dart:convert';
import 'dart:math' show sqrt, pow;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/navigation_state.dart';

/// Machine Learning service die rijstijl en route voorkeuren leert
class MLRouteLearningService {
  static final MLRouteLearningService _instance = MLRouteLearningService._internal();
  factory MLRouteLearningService() => _instance;
  MLRouteLearningService._internal();

  bool _isInitialized = false;
  Map<String, UserRouteProfile> _routeProfiles = {};
  List<RouteChoice> _routeChoices = [];
  DrivingStyleProfile _drivingStyle = DrivingStyleProfile();

  Future<void> initialize() async {
    await _loadData();
    _isInitialized = true;
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final profilesJson = prefs.getString('ml_route_profiles');
    if (profilesJson != null) {
      final profiles = jsonDecode(profilesJson) as Map;
      _routeProfiles = profiles.map((key, value) =>
        MapEntry(key.toString(), UserRouteProfile.fromJson(value)));
    }

    final choicesJson = prefs.getString('ml_route_choices');
    if (choicesJson != null) {
      final choices = jsonDecode(choicesJson) as List;
      _routeChoices = choices.map((c) => RouteChoice.fromJson(c)).toList();
    }

    final styleJson = prefs.getString('ml_driving_style');
    if (styleJson != null) {
      _drivingStyle = DrivingStyleProfile.fromJson(jsonDecode(styleJson));
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setString('ml_route_profiles', jsonEncode(
      _routeProfiles.map((k, v) => MapEntry(k, v.toJson()))
    ));
    
    await prefs.setString('ml_route_choices', jsonEncode(
      _routeChoices.map((c) => c.toJson()).toList()
    ));
    
    await prefs.setString('ml_driving_style', jsonEncode(_drivingStyle.toJson()));
  }

  /// Registreer welke route de gebruiker kiest
  Future<void> recordRouteChoice({
    required String from,
    required String to,
    required String routeId,
    required List<LatLng> path,
    required int duration,
    required double distance,
  }) async {
    final choice = RouteChoice(
      from: from,
      to: to,
      routeId: routeId,
      path: path,
      duration: duration,
      distance: distance,
      timestamp: DateTime.now(),
    );

    _routeChoices.add(choice);
    
    // Update route profile
    final key = '${from}_$to';
    if (_routeProfiles.containsKey(key)) {
      final profile = _routeProfiles[key]!;
      _routeProfiles[key] = profile.incrementChoice(routeId);
    } else {
      _routeProfiles[key] = UserRouteProfile(
        from: from,
        to: to,
        routePreferences: {routeId: 1},
      );
    }

    // Update driving style
    _updateDrivingStyle(path, duration);

    // Prune old choices
    if (_routeChoices.length > 100) {
      _routeChoices = _routeChoices.skip(_routeChoices.length - 50).toList();
    }

    await _saveData();
  }

  void _updateDrivingStyle(List<LatLng> path, int duration) {
    // Analyseer of gebruiker snelweg of stad prefereert
    // En of ze snel of rustig rijden
    
    final avgSpeed = (duration > 0) ? (calculatePathDistance(path) / (duration / 3600)) : 0;
    
    if (avgSpeed > 80) {
      _drivingStyle = _drivingStyle.copyWith(
        highwayPreference: (_drivingStyle.highwayPreference * 9 + 1) / 10,
      );
    } else if (avgSpeed < 50) {
      _drivingStyle = _drivingStyle.copyWith(
        cityPreference: (_drivingStyle.cityPreference * 9 + 1) / 10,
      );
    }
  }

  double calculatePathDistance(List<LatLng> path) {
    double total = 0;
    for (int i = 0; i < path.length - 1; i++) {
      total += const Distance().as(LengthUnit.Kilometer, path[i], path[i + 1]);
    }
    return total;
  }

  /// Krijg route aanbeveling gebaseerd op historie
  String? getRecommendedRoute(String from, String to, List<String> availableRoutes) {
    final key = '${from}_$to';
    final profile = _routeProfiles[key];
    
    if (profile == null) return null;
    
    // Vind meest gekozen route die beschikbaar is
    String? bestRoute;
    int bestCount = 0;
    
    for (final routeId in availableRoutes) {
      final count = profile.routePreferences[routeId] ?? 0;
      if (count > bestCount) {
        bestCount = count;
        bestRoute = routeId;
      }
    }
    
    return bestRoute;
  }

  /// Check of gebruiker consistente voorkeur heeft
  bool hasStrongPreference(String from, String to) {
    final key = '${from}_$to';
    final profile = _routeProfiles[key];
    
    if (profile == null) return false;
    
    final total = profile.routePreferences.values.fold(0, (a, b) => a + b);
    if (total < 3) return false; // Minimaal 3 keer gereden
    
    final max = profile.routePreferences.values.reduce((a, b) => a > b ? a : b);
    return (max / total) > 0.7; // 70% van tijd zelfde route
  }

  /// Get driving style insights
  Map<String, dynamic> getDrivingInsights() {
    return {
      'highway_lover': _drivingStyle.highwayPreference > 0.6,
      'city_driver': _drivingStyle.cityPreference > 0.6,
      'speed_preference': _drivingStyle.averageSpeed > 0,
      'routes_learned': _routeProfiles.length,
      'total_choices': _routeChoices.length,
    };
  }

  /// Suggest route type based on learned preferences
  String suggestRouteType() {
    if (_drivingStyle.highwayPreference > 0.7) return 'Snelweg route';
    if (_drivingStyle.cityPreference > 0.7) return 'Stads route';
    if (_drivingStyle.averageSpeed > 100) return 'Snelste route';
    return 'Standaard route';
  }

  void dispose() {}
}

class UserRouteProfile {
  final String from;
  final String to;
  final Map<String, int> routePreferences;

  UserRouteProfile({
    required this.from,
    required this.to,
    required this.routePreferences,
  });

  UserRouteProfile incrementChoice(String routeId) {
    final updated = Map<String, int>.from(routePreferences);
    updated[routeId] = (updated[routeId] ?? 0) + 1;
    return UserRouteProfile(
      from: from,
      to: to,
      routePreferences: updated,
    );
  }

  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'routePreferences': routePreferences,
  };

  factory UserRouteProfile.fromJson(Map<String, dynamic> json) {
    return UserRouteProfile(
      from: json['from'] ?? '',
      to: json['to'] ?? '',
      routePreferences: Map<String, int>.from(json['routePreferences'] ?? {}),
    );
  }
}

class RouteChoice {
  final String from;
  final String to;
  final String routeId;
  final List<LatLng> path;
  final int duration;
  final double distance;
  final DateTime timestamp;

  RouteChoice({
    required this.from,
    required this.to,
    required this.routeId,
    required this.path,
    required this.duration,
    required this.distance,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'routeId': routeId,
    'path': path.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    'duration': duration,
    'distance': distance,
    'timestamp': timestamp.toIso8601String(),
  };

  factory RouteChoice.fromJson(Map<String, dynamic> json) {
    return RouteChoice(
      from: json['from'] ?? '',
      to: json['to'] ?? '',
      routeId: json['routeId'] ?? '',
      path: (json['path'] as List? ?? []).map((p) => 
        LatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0)).toList(),
      duration: json['duration'] ?? 0,
      distance: json['distance']?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class DrivingStyleProfile {
  final double highwayPreference;
  final double cityPreference;
  final double averageSpeed;

  DrivingStyleProfile({
    this.highwayPreference = 0.5,
    this.cityPreference = 0.5,
    this.averageSpeed = 0,
  });

  DrivingStyleProfile copyWith({
    double? highwayPreference,
    double? cityPreference,
    double? averageSpeed,
  }) {
    return DrivingStyleProfile(
      highwayPreference: highwayPreference ?? this.highwayPreference,
      cityPreference: cityPreference ?? this.cityPreference,
      averageSpeed: averageSpeed ?? this.averageSpeed,
    );
  }

  Map<String, dynamic> toJson() => {
    'highwayPreference': highwayPreference,
    'cityPreference': cityPreference,
    'averageSpeed': averageSpeed,
  };

  factory DrivingStyleProfile.fromJson(Map<String, dynamic> json) {
    return DrivingStyleProfile(
      highwayPreference: json['highwayPreference']?.toDouble() ?? 0.5,
      cityPreference: json['cityPreference']?.toDouble() ?? 0.5,
      averageSpeed: json['averageSpeed']?.toDouble() ?? 0,
    );
  }
}