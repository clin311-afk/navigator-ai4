import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../services/location_service.dart';
import '../services/navigation_service.dart';
import '../services/voice_service.dart';
import '../services/whatsapp_service.dart';
import '../models/navigation_state.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';

/// v22 - Fixed: auto-center, speed display, zoom level, reroute, side buttons
class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  final LocationService _locationService = LocationService();
  final NavigationService _navigationService = NavigationService();
  final VoiceService _voiceService = VoiceService();
  final WhatsAppService _whatsappService = WhatsAppService();
  final MapController _mapController = MapController();
  
  LatLng? _destination;
  List<LatLng> _stops = [];
  List<LatLng> _routePoints = [];
  LatLng? _currentLocation;
  double _currentHeading = 0.0;
  double _currentSpeed = 0.0;
  bool _isNavigating = false;
  bool _isPlanning = false;
  bool _optimizeStops = true;
  bool _isAddingStops = false;
  bool _autoCenter = true;
  
  // Navigation state
  String _currentInstruction = '';
  double _distanceToNext = 0;
  int _estimatedTime = 0;
  
  // Reroute detection
  DateTime? _lastRerouteTime;
  static const _rerouteCooldown = Duration(seconds: 10);
  static const _offRouteThreshold = 50.0; // meters

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _whatsappService.initialize();
    
    // Start GPS
    final hasPermission = await _locationService.requestPermission();
    if (hasPermission) {
      _locationService.startTracking();
      
      _locationService.locationStream.listen((location) {
        _navigationService.updateLocation(location);
        
        if (mounted) {
          setState(() {
            _currentLocation = location;
          });
          
          // ALWAYS center map when auto-center is enabled
          if (_autoCenter && _isNavigating) {
            _centerMapOnLocation(location);
          }
          
          // Check if off-route and needs reroute
          if (_isNavigating && _routePoints.isNotEmpty) {
            _checkAndReroute(location);
          }
        }
      });
      
      _locationService.speedStream.listen((speed) {
        if (mounted) {
          setState(() {
            // speedStream already emits km/h — don't convert again here
            _currentSpeed = speed;
          });
        }
      });
      
      _locationService.headingStream.listen((heading) {
        if (mounted) {
          setState(() {
            _currentHeading = heading;
          });
        }
      });
      
      // Get initial location
      final loc = await _locationService.getCurrentLocation();
      if (loc != null && mounted) {
        setState(() {
          _currentLocation = loc;
        });
        _mapController.move(loc, 17);
      }
    }
  }

  void _centerMapOnLocation(LatLng location) {
    try {
      _mapController.move(location, 18); // Zoom level 18 = close view
    } catch (e) {
      // Map might not be ready
    }
  }

  void _checkAndReroute(LatLng currentLocation) {
    // Check if we're off the route
    final distanceToRoute = _calculateDistanceToRoute(currentLocation);
    
    if (distanceToRoute > _offRouteThreshold) {
      // Check cooldown to avoid constant rerouting
      if (_lastRerouteTime == null || 
          DateTime.now().difference(_lastRerouteTime!) > _rerouteCooldown) {
        _lastRerouteTime = DateTime.now();
        _performReroute(currentLocation);
      }
    }
  }

  double _calculateDistanceToRoute(LatLng point) {
    if (_routePoints.isEmpty) return double.infinity;
    
    double minDistance = double.infinity;
    for (int i = 0; i < _routePoints.length - 1; i++) {
      final distance = _distanceToSegment(
        point, 
        _routePoints[i], 
        _routePoints[i + 1]
      );
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    final Distance distance = const Distance();
    final double segmentLength = distance(a, b);
    
    if (segmentLength == 0) return distance(p, a);
    
    double t = ((p.latitude - a.latitude) * (b.latitude - a.latitude) + 
                (p.longitude - a.longitude) * (b.longitude - a.longitude)) / 
               (segmentLength * segmentLength);
    
    t = t.clamp(0.0, 1.0);
    
    final LatLng projection = LatLng(
      a.latitude + t * (b.latitude - a.latitude),
      a.longitude + t * (b.longitude - a.longitude),
    );
    
    return distance(p, projection);
  }

  Future<void> _performReroute(LatLng currentLocation) async {
    if (_destination == null) return;
    
    // Show rerouting indicator
    _voiceService.speak('Route wordt herberekend');
    
    try {
      List<RouteStep> steps;
      if (_stops.isNotEmpty) {
        if (_optimizeStops) {
          steps = await _navigationService.getOptimizedRoute(currentLocation, _destination!, _stops);
        } else {
          steps = await _navigationService.getRouteWithStops(currentLocation, _destination!, _stops);
        }
      } else {
        steps = await _navigationService.getRoute(currentLocation, _destination!);
      }

      if (steps.isNotEmpty && mounted) {
        final routeGeometry = _navigationService.routeGeometry;
        
        setState(() {
          if (routeGeometry.isNotEmpty) {
            _routePoints = routeGeometry;
          }
          _currentInstruction = steps[0].instruction;
          _distanceToNext = steps[0].distance;
          _estimatedTime = (steps.fold<double>(0, (sum, s) => sum + s.duration) / 60).ceil();
        });

        _navigationService.updateRoute(steps);
        
        await _voiceService.speakNavigationInstruction(
          steps[0].instruction,
          distance: steps[0].distance,
        );
      }
    } catch (e) {
      // Reroute failed, continue with current route
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full screen map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(52.3676, 4.9041),
              initialZoom: 17,
              onTap: (_, latLng) {
                if (_isAddingStops) {
                  _addStop(latLng);
                } else if (!_isNavigating) {
                  _setDestination(latLng);
                }
              },
              onPositionChanged: (position, hasGesture) {
                // Disable auto-center if user manually moves map
                if (hasGesture && _autoCenter) {
                  setState(() {
                    _autoCenter = false;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.clin.navigator_ai',
              ),
              // Route line
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue,
                      strokeWidth: 8,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white,
                    ),
                  ],
                ),
              // Stops
              MarkerLayer(
                markers: _stops.asMap().entries.map((e) => Marker(
                  width: 40,
                  height: 40,
                  point: e.value,
                  child: GestureDetector(
                    onTap: () => _removeStop(e.key),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '${e.key + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                )).toList(),
              ),
              // Destination
              if (_destination != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 50,
                      height: 50,
                      point: _destination!,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              // CAR - Always show when we have location
              MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    Marker(
                      width: 60,
                      height: 60,
                      point: _currentLocation!,
                      child: Transform.rotate(
                        angle: _currentHeading * (math.pi / 180),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.directions_car,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // TOP BAR - Search (only when not navigating)
          if (!_isNavigating)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Zoek bestemming...',
                            hintStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none,
                            icon: Icon(Icons.search, color: Colors.white70),
                          ),
                          onSubmitted: (query) async {
                            if (query.isEmpty) return;
                            final location = await _navigationService.geocodeAddress(query);
                            if (location != null) {
                              _setDestination(location);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // TOP INSTRUCTION BANNER (when navigating)
          if (_isNavigating)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getTurnIcon(_currentInstruction),
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_distanceToNext.toInt()} m',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _currentInstruction,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // START BUTTON (when destination set but not navigating)
          if (_destination != null && !_isNavigating)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_destination!.latitude.toStringAsFixed(4)}, ${_destination!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    if (_stops.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${_stops.length} stop(s)',
                          style: const TextStyle(color: Colors.orange),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showStopsDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[700],
                            ),
                            icon: const Icon(Icons.add_location),
                            label: const Text('STOPS'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _isPlanning ? null : _startNavigation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: _isPlanning
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.navigation),
                            label: Text(
                              _isPlanning ? 'LADEN...' : 'START NAVIGATIE',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // LEFT SIDE BUTTONS (when navigating)
          if (_isNavigating)
            Positioned(
              left: 16,
              top: MediaQuery.of(context).padding.top + 150,
              child: Column(
                children: [
                  // Auto-center toggle
                  FloatingActionButton.small(
                    heroTag: 'recenter',
                    backgroundColor: _autoCenter ? Colors.blue : Colors.grey[700],
                    onPressed: () {
                      setState(() {
                        _autoCenter = !_autoCenter;
                      });
                      if (_autoCenter && _currentLocation != null) {
                        _centerMapOnLocation(_currentLocation!);
                      }
                    },
                    child: Icon(
                      Icons.my_location,
                      color: _autoCenter ? Colors.white : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Voice
                  FloatingActionButton.small(
                    heroTag: 'voice',
                    backgroundColor: Colors.white,
                    onPressed: () {
                      _voiceService.speak(_currentInstruction);
                    },
                    child: const Icon(Icons.volume_up, color: Colors.black),
                  ),
                  const SizedBox(height: 12),
                  // Camera
                  FloatingActionButton.small(
                    heroTag: 'camera',
                    backgroundColor: Colors.white,
                    onPressed: () {
                      Navigator.pushNamed(context, '/camera');
                    },
                    child: const Icon(Icons.camera_alt, color: Colors.black),
                  ),
                ],
              ),
            ),

          // RIGHT SIDE BUTTONS (when navigating)
          if (_isNavigating)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 150,
              child: Column(
                children: [
                  // Speed display
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentSpeed > 0 ? '${_currentSpeed.toInt()}' : '0',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'km/u',
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // WhatsApp
                  FloatingActionButton.small(
                    heroTag: 'whatsapp',
                    backgroundColor: Colors.green,
                    onPressed: _showWhatsAppDialog,
                    child: const Icon(Icons.chat, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  // Stop navigation
                  FloatingActionButton.small(
                    heroTag: 'stop',
                    backgroundColor: Colors.red,
                    onPressed: () {
                      _navigationService.stopNavigation();
                      setState(() {
                        _isNavigating = false;
                        _destination = null;
                        _stops.clear();
                        _routePoints.clear();
                        _currentInstruction = '';
                        _autoCenter = true;
                      });
                    },
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

          // BOTTOM BAR - Only ETA info (when navigating)
          if (_isNavigating)
            Positioned(
              bottom: 20,
              left: 80,
              right: 80,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.access_time, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      '$_estimatedTime min',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.straighten, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      '${(_routePoints.isNotEmpty ? _calculateRouteDistance() : 0).toStringAsFixed(1)} km',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // REROUTING INDICATOR
          if (_isNavigating && _lastRerouteTime != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 130,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Route herberekenen...',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _setDestination(LatLng location) {
    setState(() {
      _destination = location;
    });
    _mapController.move(location, 17);
  }

  void _addStop(LatLng location) {
    if (_stops.length >= 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximaal 15 stops toegestaan')),
      );
      return;
    }
    setState(() {
      _stops.add(location);
      _isAddingStops = false;
    });
  }

  void _removeStop(int index) {
    setState(() {
      _stops.removeAt(index);
    });
  }

  void _clearStops() {
    setState(() {
      _stops.clear();
    });
  }

  void _showStopsDialog() {
    setState(() {
      _isAddingStops = !_isAddingStops;
    });
  }

  Future<void> _startNavigation() async {
    if (_destination == null) return;

    setState(() => _isPlanning = true);

    try {
      final currentLoc = await _locationService.getCurrentLocation();
      if (currentLoc == null) {
        setState(() => _isPlanning = false);
        return;
      }

      List<RouteStep> steps;
      if (_stops.isNotEmpty) {
        if (_optimizeStops) {
          steps = await _navigationService.getOptimizedRoute(currentLoc, _destination!, _stops);
        } else {
          steps = await _navigationService.getRouteWithStops(currentLoc, _destination!, _stops);
        }
      } else {
        steps = await _navigationService.getRoute(currentLoc, _destination!);
      }

      if (steps.isNotEmpty && mounted) {
        final routeGeometry = _navigationService.routeGeometry;
        
        setState(() {
          _isNavigating = true;
          _isPlanning = false;
          _autoCenter = true;
          _currentInstruction = steps[0].instruction;
          _distanceToNext = steps[0].distance;
          _estimatedTime = (steps.fold<double>(0, (sum, s) => sum + s.duration) / 60).ceil();
          if (routeGeometry.isNotEmpty) {
            _routePoints = routeGeometry;
          } else {
            _routePoints = [currentLoc, _destination!];
          }
        });

        _navigationService.startNavigation(_destination!);
        
        // Center on location immediately
        _centerMapOnLocation(currentLoc);
        
        // Listen to updates
        _navigationService.navigationStream?.listen((state) {
          if (state.routeSteps.isNotEmpty && state.currentStepIndex < state.routeSteps.length) {
            setState(() {
              _currentInstruction = state.routeSteps[state.currentStepIndex].instruction;
              _distanceToNext = state.distanceToNextStep;
            });
          }
          ref.read(navigationProvider.notifier).state = state;
        });

        await _voiceService.speakNavigationInstruction(
          steps[0].instruction,
          distance: steps[0].distance,
        );
      }
    } catch (e) {
      setState(() => _isPlanning = false);
    }
  }

  double _calculateRouteDistance() {
    double total = 0;
    for (int i = 0; i < _routePoints.length - 1; i++) {
      total += const Distance().as(LengthUnit.Kilometer, _routePoints[i], _routePoints[i + 1]);
    }
    return total;
  }

  IconData _getTurnIcon(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('links')) return Icons.turn_left;
    if (lower.contains('rechts')) return Icons.turn_right;
    if (lower.contains('rotonde')) return Icons.roundabout_left;
    if (lower.contains('keer')) return Icons.u_turn_left;
    return Icons.arrow_upward;
  }

  void _showWhatsAppDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('WhatsApp', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ListTile(
              leading: const Icon(Icons.message, color: Colors.green),
              title: const Text('Ik ben onderweg!'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.access_time, color: Colors.green),
              title: Text('Ik ben er over $_estimatedTime min'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.green),
              title: const Text('Deel mijn locatie'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _locationService.stopTracking();
    _navigationService.dispose();
    super.dispose();
  }
}
