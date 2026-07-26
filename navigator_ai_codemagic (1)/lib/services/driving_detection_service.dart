import 'dart:async';
import 'dart:math' show sqrt;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/voice_service.dart';
import '../services/favorites_service.dart';

/// Service die automatisch detecteert wanneer de gebruiker aan het rijden is
class DrivingDetectionService {
  static final DrivingDetectionService _instance = DrivingDetectionService._internal();
  factory DrivingDetectionService() => _instance;
  DrivingDetectionService._internal();

  final VoiceService _voiceService = VoiceService();
  final FavoritesService _favoritesService = FavoritesService();
  
  // Sensors
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  
  // Status
  bool _isDriving = false;
  bool _isMonitoring = false;
  bool _autoStartSuggested = false;
  
  // Movement detection
  List<double> _recentSpeeds = [];
  List<AccelerometerData> _recentAccelData = [];
  DateTime? _movementStartTime;
  
  // Thresholds
  static const double _drivingSpeedThreshold = 15.0; // km/h
  static const double _accelerationThreshold = 2.0; // m/s²
  static const int _minDrivingDurationSeconds = 30;
  static const int _maxWalkingSpeed = 10; // km/h
  
  // Timers
  Timer? _speedCheckTimer;
  Timer? _autoSuggestTimer;
  
  bool get isDriving => _isDriving;
  bool get isMonitoring => _isMonitoring;

  Future<void> initialize() async {
    await _voiceService.initialize();
    await _favoritesService.initialize();
  }

  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    
    // Monitor accelerometer voor beweging
    _accelSubscription = accelerometerEvents.listen(_onAccelerometerEvent);
    
    // Monitor gyroscoop voor rotatie (auto draait, niet wandelaar)
    _gyroSubscription = gyroscopeEvents.listen(_onGyroscopeEvent);
    
    // Check snelheid elke 10 seconden
    _speedCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkDrivingStatus();
    });
    
    // Auto-suggest timer voor "Wil je naar huis?"
    _autoSuggestTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkForSmartSuggestions();
    });
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _speedCheckTimer?.cancel();
    _autoSuggestTimer?.cancel();
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    
    _recentAccelData.add(AccelerometerData(
      magnitude: magnitude,
      timestamp: DateTime.now(),
    ));
    
    // Keep only last 30 seconds
    _recentAccelData.removeWhere((d) => 
      DateTime.now().difference(d.timestamp).inSeconds > 30);
  }

  void _onGyroscopeEvent(GyroscopeEvent event) {
    // Gyroscope detects rotation - cars turn smoothly, people turn erratically
    // This helps distinguish walking from driving
  }

  Future<void> _checkDrivingStatus() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      
      final speedKmh = position.speed * 3.6;
      
      _recentSpeeds.add(speedKmh);
      if (_recentSpeeds.length > 6) {
        _recentSpeeds.removeAt(0);
      }
      
      // Calculate average speed
      final avgSpeed = _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length;
      
      // Check if driving conditions are met
      final isConsistentSpeed = _recentSpeeds.every((s) => s > _maxWalkingSpeed);
      final hasEnoughData = _recentSpeeds.length >= 3;
      
      if (avgSpeed > _drivingSpeedThreshold && isConsistentSpeed && hasEnoughData) {
        if (!_isDriving) {
          _startDrivingDetected();
        }
      } else if (avgSpeed < _maxWalkingSpeed && _recentSpeeds.length >= 3) {
        if (_isDriving) {
          _stopDrivingDetected();
        }
      }
    } catch (e) {
      print('Error checking driving status: $e');
    }
  }

  void _startDrivingDetected() {
    _isDriving = true;
    _movementStartTime = DateTime.now();
    
    // Notify listeners
    _onDrivingStarted();
  }

  void _stopDrivingDetected() {
    _isDriving = false;
    _movementStartTime = null;
    _autoStartSuggested = false;
    
    _onDrivingStopped();
  }

  Future<void> _onDrivingStarted() async {
    print('🚗 RIJDEN GEDETECTEERD!');
    
    // Check if we should auto-suggest navigation
    if (!_autoStartSuggested) {
      _autoStartSuggested = true;
      await _suggestNavigation();
    }
  }

  void _onDrivingStopped() {
    print('🛑 RIJDEN GESTOPT');
  }

  Future<void> _suggestNavigation() async {
    final hour = DateTime.now().hour;
    final home = _favoritesService.home;
    final work = _favoritesService.work;
    
    String? suggestion;
    FavoriteDestination? destination;
    
    // Morning (6-10): suggest work
    if (hour >= 6 && hour <= 10 && work != null) {
      suggestion = 'Goedemorgen! Wil je naar je werk navigeren?';
      destination = work;
    }
    // Evening (16-20): suggest home
    else if (hour >= 16 && hour <= 20 && home != null) {
      suggestion = 'Goedenavond! Wil je naar huis navigeren?';
      destination = home;
    }
    // Other times: suggest most frequent destination
    else {
      final recent = _favoritesService.recentRoutes;
      if (recent.isNotEmpty) {
        final lastRoute = recent.first;
        suggestion = 'Wil je naar ${lastRoute.destinationName} navigeren?';
        destination = FavoriteDestination(
          name: lastRoute.destinationName,
          address: lastRoute.destinationAddress,
          location: lastRoute.destinationLocation,
          type: 'recent',
          icon: 'history',
        );
      }
    }
    
    if (suggestion != null) {
      await _voiceService.speak(suggestion);
      // Store suggestion for UI to pick up
      _pendingSuggestion = destination;
    }
  }
  
  FavoriteDestination? _pendingSuggestion;
  FavoriteDestination? get pendingSuggestion => _pendingSuggestion;
  void clearPendingSuggestion() => _pendingSuggestion = null;

  Future<void> _checkForSmartSuggestions() async {
    if (!_isDriving) return;
    
    // Check for traffic delays on current route
    // This would integrate with traffic API in full version
  }

  /// Check if user is likely to be driving based on time and recent patterns
  Future<bool> shouldSuggestDrivingMode() async {
    final hour = DateTime.now().hour;
    
    // Common driving times
    final isMorningCommute = hour >= 7 && hour <= 9;
    final isEveningCommute = hour >= 17 && hour <= 19;
    
    if (isMorningCommute || isEveningCommute) {
      // Check if user has routes during these times
      final recent = _favoritesService.recentRoutes;
      final hasCommutePattern = recent.any((r) {
        final routeHour = r.timestamp.hour;
        return (routeHour >= 7 && routeHour <= 9) || (routeHour >= 17 && routeHour <= 19);
      });
      
      return hasCommutePattern;
    }
    
    return false;
  }

  void dispose() {
    stopMonitoring();
    _voiceService.dispose();
  }
}

class AccelerometerData {
  final double magnitude;
  final DateTime timestamp;

  AccelerometerData({
    required this.magnitude,
    required this.timestamp,
  });
}