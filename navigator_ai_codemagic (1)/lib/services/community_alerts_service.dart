import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/voice_service.dart';
import '../config/api_config.dart';

/// Community-driven alerts service - users help each other
class CommunityAlertsService {
  static final CommunityAlertsService _instance = CommunityAlertsService._internal();
  factory CommunityAlertsService() => _instance;
  CommunityAlertsService._internal();

  final VoiceService _voiceService = VoiceService();
  bool _isInitialized = false;

  // Backend endpoint (using VPS backend)
  final String _apiBaseUrl = ApiConfig.apiBaseUrl;

  // Local cache
  List<CommunityAlert> _activeAlerts = [];
  DateTime? _lastSync;
  
  // User stats
  int _userReportCount = 0;
  int _userConfirmCount = 0;
  int _userPoints = 0;

  // Settings
  double _alertRadius = 5000; // meters
  bool _communityAlertsEnabled = true;

  Future<void> initialize() async {
    await _voiceService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _communityAlertsEnabled = prefs.getBool('community_alerts') ?? true;
    _userPoints = prefs.getInt('community_points') ?? 0;
    _userReportCount = prefs.getInt('community_reports') ?? 0;

    _isInitialized = true;
  }

  /// Sync alerts from community
  Future<void> syncAlerts(LatLng location) async {
    if (!_isInitialized || !_communityAlertsEnabled) return;

    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/community/alerts'
            '?lat=${location.latitude}'
            '&lng=${location.longitude}'
            '&radius=${_alertRadius.toInt()}'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final alerts = (data['alerts'] as List? ?? [])
            .map((a) => CommunityAlert.fromJson(a))
            .where((a) => a.isValid)
            .toList();

        _activeAlerts = alerts;
        _lastSync = DateTime.now();
      }
    } catch (e) {
      print('Community sync error: $e');
    }
  }

  /// Check for relevant alerts along route
  Future<List<CommunityAlert>> checkRouteAlerts(List<LatLng> route) async {
    if (!_isInitialized || !_communityAlertsEnabled) return [];

    final relevantAlerts = <CommunityAlert>[];
    final distance = Distance();

    for (final alert in _activeAlerts) {
      // Check if alert is near any point on route
      for (final point in route) {
        final dist = distance.as(LengthUnit.Meter, alert.location, point);
        if (dist < 500) { // Within 500m of route
          relevantAlerts.add(alert);
          break;
        }
      }
    }

    return relevantAlerts;
  }

  /// Report new alert to community
  Future<bool> reportAlert({
    required LatLng location,
    required AlertType type,
    required String description,
  }) async {
    if (!_isInitialized) return false;

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/community/alerts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'lat': location.latitude,
          'lng': location.longitude,
          'type': type.name,
          'description': description,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _userReportCount++;
        _userPoints += 10; // Points for reporting
        await _saveUserStats();
        return true;
      }
    } catch (e) {
      print('Report alert error: $e');
    }

    return false;
  }

  /// Confirm existing alert (validate)
  Future<bool> confirmAlert(String alertId) async {
    if (!_isInitialized) return false;

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/community/alerts/$alertId/confirm'),
      );

      if (response.statusCode == 200) {
        _userConfirmCount++;
        _userPoints += 5; // Points for confirming
        await _saveUserStats();
        return true;
      }
    } catch (e) {
      print('Confirm alert error: $e');
    }

    return false;
  }

  /// Dismiss alert (false positive)
  Future<bool> dismissAlert(String alertId) async {
    if (!_isInitialized) return false;

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/community/alerts/$alertId/dismiss'),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Dismiss alert error: $e');
    }

    return false;
  }

  /// Speak alert to user
  Future<void> speakAlert(CommunityAlert alert) async {
    String message;
    
    switch (alert.type) {
      case AlertType.accident:
        message = 'Community melding: Ongeval op je route ${_getDistanceText(alert)}.';
        break;
      case AlertType.trafficJam:
        message = 'Community melding: File op je route ${_getDistanceText(alert)}.';
        break;
      case AlertType.roadClosed:
        message = 'Community melding: Weg afgesloten ${_getDistanceText(alert)}.';
        break;
      case AlertType.police:
        message = 'Community melding: Politiecontrole ${_getDistanceText(alert)}.';
        break;
      case AlertType.speedCamera:
        message = 'Community melding: Flitspaal bevestigd ${_getDistanceText(alert)}.';
        break;
      case AlertType.obstacle:
        message = 'Community melding: Obstakel op weg ${_getDistanceText(alert)}.';
        break;
      case AlertType.weather:
        message = 'Community melding: Slecht weer op route ${_getDistanceText(alert)}.';
        break;
    }

    await _voiceService.speak(message);
  }

  String _getDistanceText(CommunityAlert alert) {
    if (alert.distanceToUser == null) return '';
    if (alert.distanceToUser! < 1000) {
      return 'over ${alert.distanceToUser!.toInt()} meter';
    } else {
      return 'over ${(alert.distanceToUser! / 1000).toStringAsFixed(1)} kilometer';
    }
  }

  /// Get quick report buttons for UI
  List<QuickReportOption> getQuickReportOptions() {
    return [
      QuickReportOption(type: AlertType.speedCamera, icon: Icons.camera_alt, label: 'Flitser'),
      QuickReportOption(type: AlertType.accident, icon: Icons.car_crash, label: 'Ongeval'),
      QuickReportOption(type: AlertType.trafficJam, icon: Icons.traffic, label: 'File'),
      QuickReportOption(type: AlertType.police, icon: Icons.local_police, label: 'Politie'),
      QuickReportOption(type: AlertType.obstacle, icon: Icons.warning, label: 'Obstakel'),
    ];
  }

  Future<void> _saveUserStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('community_points', _userPoints);
    await prefs.setInt('community_reports', _userReportCount);
  }

  /// Get user stats
  Map<String, dynamic> getUserStats() {
    return {
      'points': _userPoints,
      'reports': _userReportCount,
      'confirms': _userConfirmCount,
      'rank': _getRankName(),
    };
  }

  String _getRankName() {
    if (_userPoints >= 1000) return 'Legende';
    if (_userPoints >= 500) return 'Expert';
    if (_userPoints >= 200) return 'Helper';
    if (_userPoints >= 50) return 'Waarnemer';
    return 'Beginner';
  }

  /// Settings
  Future<void> setCommunityAlertsEnabled(bool enabled) async {
    _communityAlertsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('community_alerts', enabled);
  }

  bool get isCommunityAlertsEnabled => _communityAlertsEnabled;

  List<CommunityAlert> get activeAlerts => List.unmodifiable(_activeAlerts);

  void dispose() {
    _voiceService.dispose();
  }
}

class CommunityAlert {
  final String id;
  final LatLng location;
  final AlertType type;
  final String description;
  final DateTime timestamp;
  final int confirmations;
  final int dismissals;
  final double? distanceToUser;

  CommunityAlert({
    required this.id,
    required this.location,
    required this.type,
    required this.description,
    required this.timestamp,
    this.confirmations = 0,
    this.dismissals = 0,
    this.distanceToUser,
  });

  bool get isValid {
    // Alert is valid if not too old and has more confirms than dismissals
    final age = DateTime.now().difference(timestamp);
    if (age > const Duration(hours: 2)) return false;
    return confirmations >= dismissals;
  }

  bool get isConfirmed => confirmations >= 3;

  double get reliability {
    final total = confirmations + dismissals;
    if (total == 0) return 0.5;
    return confirmations / total;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'lat': location.latitude,
    'lng': location.longitude,
    'type': type.name,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
    'confirmations': confirmations,
    'dismissals': dismissals,
  };

  factory CommunityAlert.fromJson(Map<String, dynamic> json) {
    return CommunityAlert(
      id: json['id'] ?? '',
      location: LatLng(
        json['lat'] ?? 0.0,
        json['lng'] ?? 0.0,
      ),
      type: AlertType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AlertType.obstacle,
      ),
      description: json['description'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      confirmations: json['confirmations'] ?? 0,
      dismissals: json['dismissals'] ?? 0,
    );
  }

  CommunityAlert copyWith({double? distanceToUser}) {
    return CommunityAlert(
      id: id,
      location: location,
      type: type,
      description: description,
      timestamp: timestamp,
      confirmations: confirmations,
      dismissals: dismissals,
      distanceToUser: distanceToUser ?? this.distanceToUser,
    );
  }
}

enum AlertType {
  accident,
  trafficJam,
  roadClosed,
  police,
  speedCamera,
  obstacle,
  weather,
}

class QuickReportOption {
  final AlertType type;
  final IconData icon;
  final String label;

  QuickReportOption({
    required this.type,
    required this.icon,
    required this.label,
  });
}