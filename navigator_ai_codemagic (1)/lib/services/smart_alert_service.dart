import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'voice_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

/// Slimme alert service die proactief waarschuwt gebaseerd op situatie
class SmartAlertService {
  static final SmartAlertService _instance = SmartAlertService._internal();
  factory SmartAlertService() => _instance;
  SmartAlertService._internal();

  final VoiceService _voiceService = VoiceService();
  
  Timer? _alertTimer;
  Timer? _speedCheckTimer;
  
  // Status tracking
  LatLng? _lastLocation;
  double _currentSpeed = 0; // km/h
  DateTime? _lastCameraAlert;
  DateTime? _lastSpeedAlert;
  DateTime? _lastApproachAlert;
  
  // Camera's in de buurt
  List<Map<String, dynamic>> _activeCameras = [];
  Map<String, dynamic>? _closestCamera;
  
  // Preferences
  int _speedWarningThreshold = 5; // km/h over limiet voordat we waarschuwen
  int _cameraAlertDistance = 300; // meters
  int _approachAlertDistance = 1000; // meters
  
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    await _voiceService.initialize();
    
    final prefs = await SharedPreferences.getInstance();
    _speedWarningThreshold = prefs.getInt('speed_warning_threshold') ?? 5;
    _cameraAlertDistance = prefs.getInt('camera_alert_distance') ?? 300;
    
    _isInitialized = true;
  }

  /// Start slimme monitoring
  void startMonitoring() {
    _alertTimer?.cancel();
    _speedCheckTimer?.cancel();
    
    // Check elke 5 seconden voor camera's
    _alertTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkForCameraAlerts();
    });
    
    // Check elke 3 seconden snelheid
    _speedCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkSpeedAndAlert();
    });
    
    _voiceService.speak('Slimme waarschuwingen actief.');
  }

  void stopMonitoring() {
    _alertTimer?.cancel();
    _speedCheckTimer?.cancel();
  }

  /// Update huidige locatie en snelheid
  Future<void> updateLocation(LatLng location, double speedKmh) async {
    _lastLocation = location;
    _currentSpeed = speedKmh;
    
    // Haal camera's op als we ver genoeg zijn verplaatst
    if (_shouldRefreshCameras(location)) {
      await _fetchNearbyCameras(location);
    }
  }

  bool _shouldRefreshCameras(LatLng newLocation) {
    if (_lastLocation == null) return true;
    if (_activeCameras.isEmpty) return true;
    
    final distance = const Distance().as(LengthUnit.Meter, _lastLocation!, newLocation);
    return distance > 200; // Ververs elke 200m
  }

  Future<void> _fetchNearbyCameras(LatLng location) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.camerasNearby}'
            '?lat=${location.latitude}'
            '&lng=${location.longitude}'
            '&radius=5000'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _activeCameras = (data['data'] as List).cast<Map<String, dynamic>>();
        
        // Vind dichtstbijzijnde camera
        if (_activeCameras.isNotEmpty) {
          _activeCameras.sort((a, b) {
            final distA = (a['distance_meters'] as num?)?.toInt() ?? 99999;
            final distB = (b['distance_meters'] as num?)?.toInt() ?? 99999;
            return distA.compareTo(distB);
          });
          _closestCamera = _activeCameras.first;
        }
      }
    } catch (e) {
      print('Error fetching cameras: $e');
    }
  }

  /// Check of we moeten waarschuwen voor camera
  void _checkForCameraAlerts() {
    if (_closestCamera == null || _lastLocation == null) return;
    
    final distance = (_closestCamera!['distance_meters'] as num?)?.toInt() ?? 99999;
    final speedLimit = _closestCamera!['speed_limit'] as int? ?? 50;
    final roadName = _closestCamera!['road_name'] ?? 'deze weg';
    final cameraType = _closestCamera!['camera_type'] ?? 'fixed';
    
    // Cooldown check
    if (_lastCameraAlert != null) {
      final timeSince = DateTime.now().difference(_lastCameraAlert!);
      if (timeSince < const Duration(seconds: 30)) return;
    }
    
    // Check 1: We zijn DICHTBIJ en rijden te hard
    if (distance < _cameraAlertDistance && _currentSpeed > speedLimit + _speedWarningThreshold) {
      _lastCameraAlert = DateTime.now();
      _alertUserOfSpeedingCamera(distance, speedLimit, roadName, _currentSpeed);
      return;
    }
    
    // Check 2: We naderen een camera (1km)
    if (distance < _approachAlertDistance && distance > _cameraAlertDistance) {
      if (_lastApproachAlert != null) {
        final timeSince = DateTime.now().difference(_lastApproachAlert!);
        if (timeSince < const Duration(seconds: 45)) return;
      }
      
      _lastApproachAlert = DateTime.now();
      _alertUserOfApproachingCamera(distance, speedLimit, roadName);
      return;
    }
    
    // Check 3: Camera net gepasseerd, herstel snelheid
    if (distance < 50 && _currentSpeed < speedLimit - 10) {
      // Camera gepasseerd, je mag weer harder
      _voiceService.speak('Flitspaal gepasseerd. Snelheidslimiet weer $speedLimit kilometer per uur.');
      _closestCamera = null; // Reset
    }
  }

  /// Check snelheid en waarschuw indien nodig
  void _checkSpeedAndAlert() {
    if (_closestCamera == null || _lastLocation == null) return;
    
    final distance = (_closestCamera!['distance_meters'] as num?)?.toInt() ?? 99999;
    final speedLimit = _closestCamera!['speed_limit'] as int? ?? 50;
    final roadName = _closestCamera!['road_name'] ?? 'deze weg';
    
    // Alleen checken als we redelijk dichtbij zijn
    if (distance > _cameraAlertDistance * 2) return;
    
    // Check of we te hard rijden
    if (_currentSpeed > speedLimit + _speedWarningThreshold) {
      if (_lastSpeedAlert != null) {
        final timeSince = DateTime.now().difference(_lastSpeedAlert!);
        if (timeSince < const Duration(seconds: 10)) return; // Niet te vaak
      }
      
      _lastSpeedAlert = DateTime.now();
      
      final overSpeed = (_currentSpeed - speedLimit).toInt();
      _voiceService.speak(
        'Let op! Je rijdt $overSpeed kilometer te hard. Vertraag naar $speedLimit kilometer per uur.'
      );
    }
  }

  void _alertUserOfSpeedingCamera(int distance, int speedLimit, String roadName, double currentSpeed) {
    final overSpeed = (currentSpeed - speedLimit).toInt();
    
    if (distance < 100) {
      // HEEL DICHTBIJ - DRINGEND
      _voiceService.speak(
        'PAS OP! Flitspaal over $distance meter op $roadName. Je rijdt $overSpeed kilometer te hard! Vertraag NU naar $speedLimit!'
      );
    } else {
      // Dichtbij maar nog tijd
      _voiceService.speak(
        'Let op! Over $distance meter flitspaal op $roadName. Je rijdt $overSpeed kilometer te hard. Vertraag naar $speedLimit.'
      );
    }
  }

  void _alertUserOfApproachingCamera(int distance, int speedLimit, String roadName) {
    if (distance < 500) {
      _voiceService.speak(
        'Flitspaal over $distance meter op $roadName. Limiet $speedLimit kilometer per uur.'
      );
    } else {
      final km = (distance / 1000).toStringAsFixed(1);
      _voiceService.speak(
        'Over $km kilometer flitspaal op $roadName. Limiet $speedLimit kilometer per uur.'
      );
    }
  }

  /// Handmatige waarschuwing trigger
  Future<void> triggerCameraWarning(Map<String, dynamic> camera) async {
    final distance = (camera['distance_meters'] as num?)?.toInt() ?? 500;
    final speedLimit = camera['speed_limit'] as int? ?? 50;
    final roadName = camera['road_name'] ?? 'deze weg';
    
    if (_currentSpeed > speedLimit) {
      _alertUserOfSpeedingCamera(distance, speedLimit, roadName, _currentSpeed);
    } else {
      _alertUserOfApproachingCamera(distance, speedLimit, roadName);
    }
  }

  /// Update settings
  Future<void> setSpeedWarningThreshold(int kmh) async {
    _speedWarningThreshold = kmh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('speed_warning_threshold', kmh);
  }

  Future<void> setCameraAlertDistance(int meters) async {
    _cameraAlertDistance = meters;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('camera_alert_distance', meters);
  }

  void dispose() {
    stopMonitoring();
    _voiceService.dispose();
  }
}