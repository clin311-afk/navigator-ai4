import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/navigation_state.dart';

class NavigationService {
  // OSRM (Open Source Routing Machine) - free, self-hostable
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';
  
  // Alternative: Mapbox Directions API
  // static const String _mapboxUrl = 'https://api.mapbox.com/directions/v5/mapbox/driving';

  StreamController<NavigationState>? _navigationController;
  Timer? _routeUpdateTimer;
  LatLng? _currentLocation;
  LatLng? _destination;
  List<RouteStep> _currentRoute = [];
  List<LatLng> _routeGeometry = []; // Volledige route lijn punten
  int _currentStepIndex = 0;

  Stream<NavigationState>? get navigationStream => _navigationController?.stream;
  List<LatLng> get routeGeometry => _routeGeometry;

  // Geocode address to coordinates using Nominatim (OpenStreetMap)
  Future<LatLng?> geocodeAddress(String address) async {
    try {
      final encodedAddress = Uri.encodeComponent(address);
      final url = 'https://nominatim.openstreetmap.org/search?q=$encodedAddress&format=json&limit=1';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'NavigatorAI/1.0'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        if (data.isNotEmpty) {
          final result = data[0];
          final lat = double.parse(result['lat']);
          final lon = double.parse(result['lon']);
          return LatLng(lat, lon);
        }
      }
      return null;
    } catch (e) {
      print('Geocoding error: $e');
      return null;
    }
  }

  Future<List<RouteStep>> getRoute(LatLng from, LatLng to) async {
    try {
      final url = 
        '$_osrmBaseUrl/route/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson&steps=true';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List;
        
        if (routes.isEmpty) return [];

        final route = routes[0];
        
        // Extract full route geometry for drawing the line
        final geometry = route['geometry'];
        if (geometry != null && geometry['coordinates'] != null) {
          final coords = geometry['coordinates'] as List;
          _routeGeometry = coords.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
        }
        
        final legs = route['legs'] as List;
        final steps = <RouteStep>[];

        for (final leg in legs) {
          final legSteps = leg['steps'] as List;
          for (final step in legSteps) {
            final maneuver = step['maneuver'];
            final location = maneuver['location'] as List;
            
            steps.add(RouteStep(
              instruction: _parseInstruction(
                maneuver['type'],
                step['name'] ?? 'de weg',
              ),
              distance: (step['distance'] as num).toDouble(),
              duration: (step['duration'] as num).toDouble(),
              location: LatLng(location[1], location[0]),
              maneuver: maneuver['type'] ?? 'straight',
            ));
          }
        }

        _currentRoute = steps;
        return steps;
      }
    } catch (e) {
      print('Route error: $e');
    }
    return [];
  }

  String _parseInstruction(String? maneuver, String roadName) {
    switch (maneuver) {
      case 'turn':
        return 'Sla af naar $roadName';
      case 'new name':
        return 'Ga verder op $roadName';
      case 'depart':
        return 'Vertrek richting $roadName';
      case 'arrive':
        return 'Je bent bij je bestemming';
      case 'uturn':
        return 'Keer om';
      case 'roundabout':
        return 'Neem de rotonde';
      case 'exit roundabout':
        return 'Verlaat de rotonde';
      default:
        return 'Ga verder op $roadName';
    }
  }

  void startNavigation(LatLng destination) {
    _destination = destination;
    _navigationController = StreamController<NavigationState>.broadcast();
    
    _routeUpdateTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updateNavigation(),
    );
  }

  void updateLocation(LatLng location) {
    _currentLocation = location;
  }

  void _updateNavigation() async {
    if (_currentLocation == null || _destination == null) return;

    // Check if we need to reroute
    if (_currentRoute.isEmpty || _isOffRoute()) {
      _currentRoute = await getRoute(_currentLocation!, _destination!);
      _currentStepIndex = 0;
    }

    // Check if we reached destination
    if (_currentLocation != null && _destination != null) {
      final distance = const Distance().as(
        LengthUnit.Meter,
        _currentLocation!,
        _destination!,
      );

      if (distance < 50) {
        _navigationController?.add(NavigationState(
          isNavigating: false,
          currentSpeed: 0,
          currentLocation: _currentLocation,
          destination: _destination,
          routeSteps: _currentRoute,
          currentStepIndex: _currentStepIndex,
          alerts: [NavigationAlert(
            type: 'arrived',
            message: 'Je bent bij je bestemming!',
            location: _destination!,
            timestamp: DateTime.now(),
          )],
        ));
        stopNavigation();
        return;
      }
    }

    // Update current step
    _updateCurrentStep();

    _navigationController?.add(NavigationState(
      isNavigating: true,
      currentSpeed: 0,
      currentLocation: _currentLocation,
      destination: _destination,
      routeSteps: _currentRoute,
      currentStepIndex: _currentStepIndex,
      alerts: [],
    ));
  }

  bool _isOffRoute() {
    if (_currentRoute.isEmpty || _currentLocation == null) return false;
    
    final currentStep = _currentRoute[_currentStepIndex];
    final distanceToStep = const Distance().as(
      LengthUnit.Meter,
      _currentLocation!,
      currentStep.location,
    );

    // If we're more than 100m from the current step, we're off route
    return distanceToStep > 100;
  }

  void _updateCurrentStep() {
    if (_currentRoute.isEmpty || _currentLocation == null) return;

    // Check if we've passed the current step
    if (_currentStepIndex < _currentRoute.length - 1) {
      final nextStep = _currentRoute[_currentStepIndex + 1];
      final distanceToNext = const Distance().as(
        LengthUnit.Meter,
        _currentLocation!,
        nextStep.location,
      );

      if (distanceToNext < 30) {
        _currentStepIndex++;
      }
    }
  }

  String getCurrentInstruction() {
    if (_currentRoute.isEmpty || _currentStepIndex >= _currentRoute.length) {
      return 'Ga verder';
    }
    return _currentRoute[_currentStepIndex].instruction;
  }

  double getDistanceToNextStep() {
    if (_currentRoute.isEmpty || _currentLocation == null) return 0;
    if (_currentStepIndex >= _currentRoute.length) return 0;
    
    return const Distance().as(
      LengthUnit.Meter,
      _currentLocation!,
      _currentRoute[_currentStepIndex].location,
    );
  }

  void stopNavigation() {
    _routeUpdateTimer?.cancel();
    _routeUpdateTimer = null;
    _navigationController?.close();
    _navigationController = null;
    _currentRoute = [];
    _currentStepIndex = 0;
  }

  // Update route during navigation (for rerouting)
  void updateRoute(List<RouteStep> newRoute) {
    _currentRoute = newRoute;
    _currentStepIndex = 0;
  }

  // Speed camera database (mock - replace with real data)
  List<Map<String, dynamic>> _speedCameras = [];

  // Route met stops in opgegeven volgorde
  Future<List<RouteStep>> getRouteWithStops(LatLng from, LatLng to, List<LatLng> stops) async {
    List<RouteStep> allSteps = [];
    LatLng current = from;
    
    for (final stop in stops) {
      final steps = await getRoute(current, stop);
      allSteps.addAll(steps);
      current = stop;
    }
    
    final finalSteps = await getRoute(current, to);
    allSteps.addAll(finalSteps);
    
    return allSteps;
  }

  // Route met stops geoptimaliseerd (kortste pad via nearest neighbor)
  Future<List<RouteStep>> getOptimizedRoute(LatLng from, LatLng to, List<LatLng> stops) async {
    List<LatLng> optimizedStops = List.from(stops);
    LatLng current = from;
    List<RouteStep> allSteps = [];
    
    while (optimizedStops.isNotEmpty) {
      // Vind dichtste stop
      LatLng? nearest;
      double minDist = double.infinity;
      
      for (final stop in optimizedStops) {
        final dist = const Distance().as(LengthUnit.Meter, current, stop);
        if (dist < minDist) {
          minDist = dist;
          nearest = stop;
        }
      }
      
      if (nearest != null) {
        final steps = await getRoute(current, nearest);
        allSteps.addAll(steps);
        current = nearest;
        optimizedStops.remove(nearest);
      }
    }
    
    // Route naar bestemming
    final finalSteps = await getRoute(current, to);
    allSteps.addAll(finalSteps);
    
    return allSteps;
  }

  void loadSpeedCameras(List<Map<String, dynamic>> cameras) {
    _speedCameras = cameras;
  }

  List<Map<String, dynamic>> checkNearbySpeedCameras(LatLng location, double radiusKm) {
    final nearby = <Map<String, dynamic>>[];
    
    for (final camera in _speedCameras) {
      final camLat = camera['lat'] as double;
      final camLng = camera['lng'] as double;
      final cameraLocation = LatLng(camLat, camLng);
      
      final distance = const Distance().as(LengthUnit.Kilometer, location, cameraLocation);
      
      if (distance < radiusKm) {
        nearby.add({
          ...camera,
          'distance': distance,
        });
      }
    }
    
    return nearby..sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
  }

  void dispose() {
    stopNavigation();
  }
}
