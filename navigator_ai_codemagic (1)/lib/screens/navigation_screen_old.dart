import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/location_service.dart';
import '../services/navigation_service.dart';
import '../services/voice_service.dart';
import '../services/whatsapp_service.dart';
import '../models/navigation_state.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';

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
  List<LatLng> _routePoints = []; // Route line points
  LatLng? _currentLocation;
  double _currentHeading = 0.0;
  bool _isNavigating = false;
  bool _isPlanning = false;
  bool _optimizeStops = true;
  bool _isAddingStops = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _locationService.startTracking();
    
    _locationService.locationStream.listen((location) {
      _navigationService.updateLocation(location);
      if (mounted) {
        setState(() {
          _currentLocation = location;
        });
        
        // Auto-center map on car when navigating (like Waze)
        if (_isNavigating) {
          _mapController.move(location, 17);
        }
      }
    });
    
    // Track heading for car rotation
    _locationService.headingStream?.listen((heading) {
      setState(() {
        _currentHeading = heading;
      });
    });
  }

  Future<void> _initializeServices() async {
    await _whatsappService.initialize();
    
    // Request GPS permission and start tracking immediately
    final hasPermission = await _locationService.requestPermission();
    if (hasPermission) {
      _locationService.startTracking();
      
      // Direct locatie ophalen bij startup
      try {
        final loc = await _locationService.getCurrentLocation();
        if (loc != null && mounted) {
          setState(() {
            _currentLocation = loc;
          });
          _mapController.move(loc, 15);
        }
      } catch (e) {
        print('Initial location error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(52.3676, 4.9041), // Amsterdam
              initialZoom: 12,
              onTap: (_, latLng) {
                if (_isAddingStops) {
                  _addStop(latLng);
                } else {
                  _setDestination(latLng);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.clin.navigator_ai',
              ),
              // Route line - ALWAYS show something if we have destination
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue,
                      strokeWidth: 6,
                    ),
                  ],
                )
              else if (_destination != null && _currentLocation != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_currentLocation!, _destination!],
                      color: Colors.grey.withOpacity(0.7),
                      strokeWidth: 4,
                    ),
                  ],
                ),
              // Stops markers
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
              // Current location - Car marker with heading (ALWAYS show if navigating)
              MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    Marker(
                      width: 60,
                      height: 60,
                      point: _currentLocation!,
                      child: Transform.rotate(
                        angle: (_currentHeading) * (3.14159 / 180),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
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
              // Destination marker
              if (_destination != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 50,
                      height: 50,
                      point: _destination!,
                      child: const Icon(
                        Icons.location_on,
                        color: AppTheme.dangerColor,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Top Bar
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
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Adres zoeken...')),
                          );
                          
                          final location = await _navigationService.geocodeAddress(query);
                          
                          if (location != null) {
                            _setDestination(location);
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Bestemming: $query')),
                            );
                          } else {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Adres niet gevonden')),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top: Bestemming info + Start Navigatie knop (hide when navigating)
          if (_destination != null && !_isNavigating)
            Positioned(
              top: 130,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: AppTheme.primaryColor,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bestemming',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${_destination!.latitude.toStringAsFixed(4)}, ${_destination!.longitude.toStringAsFixed(4)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Stops info
                    if (_stops.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.flag, color: Colors.orange, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '${_stops.length} stop${_stops.length == 1 ? '' : 's'} toegevoegd',
                              style: const TextStyle(color: Colors.orange, fontSize: 12),
                            ),
                            const Spacer(),
                            if (_stops.isNotEmpty)
                              TextButton(
                                onPressed: _clearStops,
                                child: const Text('WIS', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                      ),
                    // Buttons row
                    Row(
                      children: [
                        // Stops button
                        ElevatedButton.icon(
                          onPressed: _showStopsDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isAddingStops ? Colors.orange : Colors.grey[800],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Badge(
                            label: Text('${_stops.length}'),
                            isLabelVisible: _stops.isNotEmpty,
                            child: Icon(_isAddingStops ? Icons.edit_location : Icons.add_location),
                          ),
                          label: Text(_isAddingStops ? 'KLAAR' : 'STOPS'),
                        ),
                        const SizedBox(width: 8),
                        // Start Navigation button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isPlanning ? null : _startNavigation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _isPlanning
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.navigation),
                            label: Text(
                              _isPlanning ? 'LADEN...' : 'START',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Bottom hint
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isAddingStops
                        ? 'Tik op de kaart om stops toe te voegen'
                        : _destination == null 
                          ? 'Tik op de kaart of zoek een adres'
                          : _stops.isEmpty
                            ? 'Klik START om te beginnen'
                            : 'Klik STOPS om volgorde te wijzigen',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _setDestination(LatLng latLng) {
    setState(() {
      _destination = latLng;
    });
    _mapController.move(latLng, 15);
  }

  void _addStop(LatLng latLng) {
    if (_stops.length >= 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximaal 15 stops')),
      );
      return;
    }
    setState(() {
      _stops.add(latLng);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Stop ${_stops.length} toegevoegd')),
    );
  }

  void _removeStop(int index) {
    setState(() {
      _stops.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stop verwijderd')),
    );
  }

  void _clearStops() {
    setState(() {
      _stops.clear();
      _isAddingStops = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alle stops verwijderd')),
    );
  }

  void _showStopsDialog() {
    if (_isAddingStops) {
      setState(() => _isAddingStops = false);
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: const Text('Stops Toevoegen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stops: ${_stops.length}/15'),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text('Route optimaliseren'),
              subtitle: const Text('Automatisch kortste pad'),
              value: _optimizeStops,
              onChanged: (v) => setState(() => _optimizeStops = v),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _isAddingStops = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tik op de kaart om stops toe te voegen')),
                );
              },
              icon: const Icon(Icons.add_location),
              label: const Text('Stop toevoegen op kaart'),
            ),
            if (_stops.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Huidige stops:', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._stops.asMap().entries.map((e) => ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                title: Text('Stop ${e.key + 1}', style: const TextStyle(fontSize: 14)),
                subtitle: Text('${e.value.latitude.toStringAsFixed(3)}, ${e.value.longitude.toStringAsFixed(3)}', style: const TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: AppTheme.dangerColor, size: 20),
                  onPressed: () {
                    _removeStop(e.key);
                    Navigator.pop(context);
                    _showStopsDialog();
                  },
                ),
              )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    );
  }

  Future<void> _startNavigation() async {
    if (_destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Klik eerst op de kaart of zoek een adres')),
      );
      return;
    }

    setState(() => _isPlanning = true);

    try {
      print('DEBUG: Start navigatie...');
      
      // Vraag GPS permissie expliciet
      final hasPermission = await _locationService.requestPermission();
      print('DEBUG: GPS permissie: $hasPermission');
      
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('GPS toestemming nodig. Ga naar Instellingen > Apps > Navigator AI > Permissies.')),
          );
        }
        return;
      }

      // Probeer locatie te krijgen
      LatLng? currentLoc;
      for (int i = 0; i < 3; i++) {
        currentLoc = await _locationService.getCurrentLocation();
        if (currentLoc != null) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      
      print('DEBUG: Locatie: $currentLoc');
      
      // Fallback als GPS niet werkt
      currentLoc ??= const LatLng(52.3676, 4.9041);

      print('DEBUG: Route ophalen...');
      
      List<RouteStep> steps;
      if (_stops.isNotEmpty) {
        if (_optimizeStops) {
          print('DEBUG: Geoptimaliseerde route met ${_stops.length} stops');
          steps = await _navigationService.getOptimizedRoute(currentLoc, _destination!, _stops);
        } else {
          print('DEBUG: Route met ${_stops.length} stops (eigen volgorde)');
          steps = await _navigationService.getRouteWithStops(currentLoc, _destination!, _stops);
        }
      } else {
        steps = await _navigationService.getRoute(currentLoc, _destination!);
      }
      
      print('DEBUG: Stappen: ${steps.length}');
      
      if (steps.isNotEmpty) {
        setState(() {
          _isNavigating = true;
        });
        
        // Get real route geometry from OSRM (actual road path)
        final routeGeometry = _navigationService.routeGeometry;
        if (routeGeometry.isNotEmpty) {
          setState(() {
            _routePoints = routeGeometry;
          });
        } else {
          final loc = currentLoc;
          if (loc != null) {
            setState(() {
              _routePoints = [loc, _destination!];
            });
          }
        }
        
        _navigationService.startNavigation(_destination!);
        
        // Listen to navigation updates
        _navigationService.navigationStream?.listen((state) {
          ref.read(navigationProvider.notifier).state = state;
        });

        // Speak first instruction
        await _voiceService.speakNavigationInstruction(
          steps[0].instruction,
          distance: steps[0].distance,
        );

        // Show navigation overlay
        _showNavigationOverlay();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Geen route gevonden. Probeer een andere bestemming.')),
          );
        }
      }
    } catch (e, stackTrace) {
      print('DEBUG ERROR: $e');
      print('DEBUG STACK: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e')),
        );
      }
    } finally {
      setState(() => _isPlanning = false);
    }
  }

  void _showNavigationOverlay() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => NavigationOverlay(
        navigationService: _navigationService,
        voiceService: _voiceService,
        whatsAppService: _whatsappService,
        onStop: () {
          _navigationService.stopNavigation();
          setState(() {
            _isNavigating = false;
          });
          Navigator.pop(context);
        },
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

class NavigationOverlay extends StatelessWidget {
  final NavigationService navigationService;
  final VoiceService voiceService;
  final WhatsAppService whatsAppService;
  final VoidCallback onStop;

  const NavigationOverlay({
    super.key,
    required this.navigationService,
    required this.voiceService,
    required this.whatsAppService,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: navigationService.navigationStream,
      builder: (context, snapshot) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.darkBackground.withOpacity( 0.98),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Instruction
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity( 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity( 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.arrow_upward,
                        size: 48,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        navigationService.getCurrentInstruction(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(navigationService.getDistanceToNextStep()).toInt()} m',
                        style: const TextStyle(
                          fontSize: 18,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Controls
                Row(
                  children: [
                    Expanded(
                      child: _buildControlButton(
                        icon: Icons.volume_up,
                        label: 'Herhaal',
                        onTap: () {
                          voiceService.speakNavigationInstruction(
                            navigationService.getCurrentInstruction(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildControlButton(
                        icon: Icons.camera_alt,
                        label: 'Camera',
                        onTap: () {
                          Navigator.pushNamed(context, '/camera');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildControlButton(
                        icon: Icons.chat,
                        label: 'WhatsApp',
                        color: Colors.green,
                        onTap: () => _showWhatsAppDialog(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildControlButton(
                        icon: Icons.close,
                        label: 'Stop',
                        color: AppTheme.dangerColor,
                        onTap: onStop,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showWhatsAppDialog(BuildContext context) {
    final quickMessages = whatsAppService.getQuickMessages(etaMinutes: 10);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Verstuur via WhatsApp',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...quickMessages.map((msg) => ListTile(
              leading: Icon(msg.icon, color: Colors.green),
              title: Text(msg.label),
              subtitle: Text(msg.message, style: const TextStyle(fontSize: 12)),
              onTap: () async {
                Navigator.pop(context);
                // Show contact picker dialog
                _showContactPickerDialog(context, msg.message);
              },
            )),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Eigen bericht'),
              onTap: () {
                Navigator.pop(context);
                _showCustomMessageDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showContactPickerDialog(BuildContext context, String message) {
    final recentContacts = whatsAppService.recentContacts;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: const Text('Kies contact'),
        content: SizedBox(
          width: double.maxFinite,
          child: recentContacts.isEmpty
              ? const Text('Geen recente contacten. Voeg een contact toe.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: recentContacts.length,
                  itemBuilder: (context, index) {
                    final contact = recentContacts[index];
                    return ListTile(
                      leading: const Icon(Icons.person, color: Colors.green),
                      title: Text(contact.displayName),
                      subtitle: Text(contact.phoneNumber),
                      onTap: () async {
                        Navigator.pop(context);
                        final success = await whatsAppService.sendMessage(
                          phoneNumber: contact.phoneNumber,
                          message: message,
                        );
                        if (success) {
                          voiceService.speak('WhatsApp bericht geopend');
                        }
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => _showAddContactDialog(context, message),
            child: const Text('Nieuw contact'),
          ),
        ],
      ),
    );
  }

  void _showAddContactDialog(BuildContext context, String message) {
    final phoneController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: const Text('Telefoonnummer'),
        content: TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: '06...',
            labelText: 'Telefoonnummer',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () async {
              final phone = phoneController.text.trim();
              if (phone.isNotEmpty) {
                Navigator.pop(context);
                final success = await whatsAppService.sendMessage(
                  phoneNumber: phone,
                  message: message,
                );
                if (success) {
                  voiceService.speak('WhatsApp bericht geopend');
                }
              }
            },
            child: const Text('Versturen'),
          ),
        ],
      ),
    );
  }

  void _showCustomMessageDialog(BuildContext context) {
    final messageController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: const Text('Eigen bericht'),
        content: TextField(
          controller: messageController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Typ je bericht...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () {
              final message = messageController.text.trim();
              if (message.isNotEmpty) {
                Navigator.pop(context);
                _showContactPickerDialog(context, message);
              }
            },
            child: const Text('Doorgaan'),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: (color ?? Colors.grey).withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color ?? Colors.white),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color ?? Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
