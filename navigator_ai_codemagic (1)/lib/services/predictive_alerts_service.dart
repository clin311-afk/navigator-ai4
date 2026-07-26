import 'dart:async';
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/voice_service.dart';
import '../services/favorites_service.dart';
import '../services/location_service.dart';

/// Service voor predictive alerts gebaseerd op weer, verkeer, en patronen
class PredictiveAlertsService {
  static final PredictiveAlertsService _instance = PredictiveAlertsService._internal();
  factory PredictiveAlertsService() => _instance;
  PredictiveAlertsService._internal();

  final VoiceService _voiceService = VoiceService();
  final FavoritesService _favoritesService = FavoritesService();
  final LocationService _locationService = LocationService();
  
  Timer? _checkTimer;
  bool _isInitialized = false;
  
  // Cache
  Map<String, dynamic>? _weatherCache;
  Map<String, dynamic>? _trafficCache;
  DateTime? _lastWeatherCheck;
  DateTime? _lastTrafficCheck;
  
  // Settings
  bool _enableWeatherAlerts = true;
  bool _enableTrafficAlerts = true;
  bool _enablePatternAlerts = true;

  Future<void> initialize() async {
    await _voiceService.initialize();
    await _favoritesService.initialize();
    
    final prefs = await SharedPreferences.getInstance();
    _enableWeatherAlerts = prefs.getBool('weather_alerts') ?? true;
    _enableTrafficAlerts = prefs.getBool('traffic_alerts') ?? true;
    _enablePatternAlerts = prefs.getBool('pattern_alerts') ?? true;
    
    _isInitialized = true;
  }

  void startMonitoring() {
    _checkTimer?.cancel();
    // Check elke 10 minuten
    _checkTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _runPredictiveChecks();
    });
    
    // Direct eerste check
    _runPredictiveChecks();
  }

  void stopMonitoring() {
    _checkTimer?.cancel();
  }

  Future<void> _runPredictiveChecks() async {
    if (!_isInitialized) return;
    
    final now = DateTime.now();
    final hour = now.hour;
    
    // Alleen checken tijdens actieve uren (6-23)
    if (hour < 6 || hour > 23) return;
    
    // Check voor verschillende alert types
    if (_enablePatternAlerts) {
      await _checkForDepartureSuggestion();
    }
    
    if (_enableWeatherAlerts) {
      await _checkForWeatherAlerts();
    }
    
    if (_enableTrafficAlerts) {
      await _checkForTrafficAlerts();
    }
  }

  /// Suggereer vertrek gebaseerd op patronen
  Future<void> _checkForDepartureSuggestion() async {
    final now = DateTime.now();
    final hour = now.hour;
    final weekday = now.weekday; // 1 = maandag, 7 = zondag
    
    // Check of het een werkdag is
    if (weekday > 5) return; // Weekend
    
    // Ochtend routine check (7-9 uur)
    if (hour >= 7 && hour <= 9) {
      final work = _favoritesService.work;
      if (work != null) {
        // Check of we al recent naar werk zijn genavigeerd
        final recent = _favoritesService.recentRoutes;
        final alreadyNavigatedToday = recent.any((r) {
          return r.destinationName == work.name &&
                 r.timestamp.day == now.day &&
                 r.timestamp.month == now.month;
        });
        
        if (!alreadyNavigatedToday) {
          // Check weer voor suggestie
          final weather = await _getWeatherForecast();
          if (weather != null && weather['rainExpected']) {
            await _voiceService.speak(
              'Goedemorgen! Het gaat straks regenen. Wil je nu naar je werk vertrekken om droog te blijven?'
            );
          }
        }
      }
    }
  }

  /// Check weer voor alerts
  Future<void> _checkForWeatherAlerts() async {
    // Cooldown check (niet te vaak)
    if (_lastWeatherCheck != null) {
      if (DateTime.now().difference(_lastWeatherCheck!) < const Duration(hours: 1)) {
        return;
      }
    }
    
    try {
      final position = await _locationService.getCurrentLocation();
      if (position == null) return;
      
      final weather = await _fetchWeather(position.latitude, position.longitude);
      _weatherCache = weather;
      _lastWeatherCheck = DateTime.now();
      
      if (weather != null) {
        // Check voor slecht weer
        final condition = weather['weather']?[0]?['main']?.toString().toLowerCase() ?? '';
        final rainExpected = condition.contains('rain') || condition.contains('drizzle');
        final snowExpected = condition.contains('snow');
        final thunderstorm = condition.contains('thunder');
        
        if (thunderstorm) {
          await _voiceService.speak(
            'Let op! Er is onweer voorspeld in de komende uren. Rij voorzichtig.'
          );
        } else if (snowExpected) {
          await _voiceService.speak(
            'Waarschuwing: sneeuw voorspeld. Pas je rijstijl aan en houd afstand.'
          );
        } else if (rainExpected) {
          // Alleen waarschuwen als het nu droog is
          final currentWeather = await _fetchCurrentWeather(position.latitude, position.longitude);
          if (currentWeather != null && !currentWeather.toLowerCase().contains('rain')) {
            await _voiceService.speak(
              'Het gaat over ongeveer 30 minuten regenen. Zet je ruitenwissers op tijd aan.'
            );
          }
        }
      }
    } catch (e) {
      print('Weather check error: $e');
    }
  }

  /// Check verkeer voor alerts
  Future<void> _checkForTrafficAlerts() async {
    if (_lastTrafficCheck != null) {
      if (DateTime.now().difference(_lastTrafficCheck!) < const Duration(minutes: 15)) {
        return;
      }
    }
    
    try {
      final position = await _locationService.getCurrentLocation();
      if (position == null) return;
      
      // Simuleer traffic check (in productie zou dit echt traffic API gebruiken)
      final currentHour = DateTime.now().hour;
      
      // Rush hour detectie
      final isRushHour = (currentHour >= 7 && currentHour <= 9) || 
                         (currentHour >= 16 && currentHour <= 19);
      
      if (isRushHour) {
        // Check of gebruiker recentelijk heeft gereden
        final recent = _favoritesService.recentRoutes;
        if (recent.isNotEmpty) {
          final lastRoute = recent.first;
          final timeSince = DateTime.now().difference(lastRoute.timestamp);
          
          // Als laatste route meer dan 2 uur geleden was
          if (timeSince.inHours >= 2) {
            await _voiceService.speak(
              'Het is spits. Verwacht extra reistijd door drukte op de weg.'
            );
          }
        }
      }
      
      _lastTrafficCheck = DateTime.now();
    } catch (e) {
      print('Traffic check error: $e');
    }
  }

  Future<Map<String, dynamic>?> _fetchWeather(double lat, double lng) async {
    try {
      // OpenWeatherMap API (gratis tier)
      // Je zou hier je eigen API key gebruiken
      // Voor nu simuleren we
      return {
        'weather': [{'main': 'Clear'}],
        'main': {'temp': 20},
      };
    } catch (e) {
      return null;
    }
  }

  Future<String> _fetchCurrentWeather(double lat, double lng) async {
    return 'Clear';
  }

  Future<Map<String, dynamic>?> _getWeatherForecast() async {
    return _weatherCache;
  }

  /// Check route voor problemen voordat we starten
  Future<String?> checkRouteBeforeStart(LatLng destination) async {
    final alerts = <String>[];
    
    // Check weer
    if (_weatherCache != null) {
      final condition = _weatherCache!['weather']?[0]?['main']?.toString().toLowerCase() ?? '';
      if (condition.contains('rain')) {
        alerts.add('regen verwacht op route');
      }
    }
    
    // Check tijd
    final hour = DateTime.now().hour;
    if ((hour >= 7 && hour <= 9) || (hour >= 16 && hour <= 19)) {
      alerts.add('spitsuur, extra reistijd verwacht');
    }
    
    if (alerts.isEmpty) return null;
    return 'Let op: ${alerts.join(', ')}.';
  }

  /// Settings
  Future<void> setWeatherAlerts(bool enabled) async {
    _enableWeatherAlerts = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weather_alerts', enabled);
  }

  Future<void> setTrafficAlerts(bool enabled) async {
    _enableTrafficAlerts = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('traffic_alerts', enabled);
  }

  Future<void> setPatternAlerts(bool enabled) async {
    _enablePatternAlerts = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pattern_alerts', enabled);
  }

  void dispose() {
    stopMonitoring();
    _voiceService.dispose();
  }
}