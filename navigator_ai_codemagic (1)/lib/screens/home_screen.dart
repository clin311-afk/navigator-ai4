import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../providers/app_providers.dart';
import '../services/location_service.dart';
import '../services/voice_service.dart';
import '../services/favorites_service.dart';
import '../services/driving_detection_service.dart';
import '../services/predictive_alerts_service.dart';
import '../services/offline_intelligence_service.dart';
import '../services/ml_route_learning_service.dart';
import '../services/smart_parking_service.dart';
import '../services/community_alerts_service.dart';
import '../widgets/audio_waveform.dart';
import '../utils/theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final LocationService _locationService = LocationService();
  final VoiceService _voiceService = VoiceService();
  final FavoritesService _favoritesService = FavoritesService();
  final DrivingDetectionService _drivingService = DrivingDetectionService();
  final PredictiveAlertsService _predictiveService = PredictiveAlertsService();
  final OfflineIntelligenceService _offlineService = OfflineIntelligenceService();
  final MLRouteLearningService _mlRouteService = MLRouteLearningService();
  final SmartParkingService _parkingService = SmartParkingService();
  final CommunityAlertsService _communityService = CommunityAlertsService();
  
  List<FavoriteDestination> _smartSuggestions = [];
  bool _favoritesLoaded = false;
  bool _isDriving = false;
  FavoriteDestination? _drivingSuggestion;
  String? _predictiveAlert;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _locationService.requestPermission();
    await _voiceService.initialize();
    await _favoritesService.initialize();
    await _drivingService.initialize();
    await _predictiveService.initialize();
    await _offlineService.initialize();
    await _mlRouteService.initialize();
    await _parkingService.initialize();
    await _communityService.initialize();
    
    // Start monitoring services
    _drivingService.startMonitoring();
    _predictiveService.startMonitoring();
    
    // Check for suggestions periodically
    Timer.periodic(const Duration(seconds: 5), (_) {
      _checkDrivingSuggestions();
    });
    
    setState(() {
      _smartSuggestions = _favoritesService.getSmartSuggestions();
      _favoritesLoaded = true;
    });
  }
  
  void _checkDrivingSuggestions() {
    if (!mounted) return;
    
    // Check driving detection
    if (_drivingService.pendingSuggestion != null && _drivingSuggestion == null) {
      setState(() {
        _drivingSuggestion = _drivingService.pendingSuggestion;
      });
    }
    
    // Update driving status
    if (_drivingService.isDriving != _isDriving) {
      setState(() {
        _isDriving = _drivingService.isDriving;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigationState = ref.watch(navigationProvider);
    final isAssistantActive = ref.watch(voiceAssistantProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Navigator AI',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          if (_isDriving) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'RIJMODUS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'Intelligente navigatie',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      _showSettingsDialog(context);
                    },
                  ),
                ],
              ),
            ),

            // Auto-suggest banner voor rijden
            if (_drivingSuggestion != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blueAccent, width: 2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_car, color: Colors.white, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Rijden gedetecteerd!',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Wil je naar ${_drivingSuggestion!.name} navigeren?',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/navigate',
                          arguments: {
                            'destination': _drivingSuggestion!.location,
                            'address': _drivingSuggestion!.address,
                          },
                        );
                        setState(() {
                          _drivingSuggestion = null;
                        });
                        _drivingService.clearPendingSuggestion();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                      ),
                      child: const Text('GA'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () {
                        setState(() {
                          _drivingSuggestion = null;
                        });
                        _drivingService.clearPendingSuggestion();
                      },
                    ),
                  ],
                ),
              ),

            // Speed Display
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Text(
                    'HUIDIGE SNELHEID',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${navigationState.currentSpeed.toInt()}',
                        style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'km/h',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Slimme Suggesties / Favorieten
            if (_favoritesLoaded && _smartSuggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: AppTheme.accentColor, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Slimme Suggesties',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 90,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _smartSuggestions.length,
                        itemBuilder: (context, index) {
                          final dest = _smartSuggestions[index];
                          return _buildSuggestionCard(dest);
                        },
                      ),
                    ),
                  ],
                ),
              ),

            if (_favoritesLoaded && _smartSuggestions.isNotEmpty)
              const SizedBox(height: 20),

            // Main Actions
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                padding: const EdgeInsets.all(20),
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                children: [
                  _buildActionCard(
                    icon: Icons.navigation,
                    label: 'Navigeren',
                    color: AppTheme.primaryColor,
                    onTap: () => Navigator.pushNamed(context, '/navigate'),
                  ),
                  _buildActionCard(
                    icon: Icons.camera_alt,
                    label: 'Flitscamera',
                    color: AppTheme.warningColor,
                    onTap: () => Navigator.pushNamed(context, '/camera'),
                  ),
                  _buildActionCard(
                    icon: Icons.mic,
                    label: 'AI Assistant',
                    color: AppTheme.secondaryColor,
                    onTap: () => Navigator.pushNamed(context, '/assistant'),
                  ),
                  _buildActionCard(
                    icon: Icons.map,
                    label: 'Verkeer',
                    color: Colors.purple,
                    onTap: () {
                      _voiceService.speak('Verkeersinformatie wordt geladen');
                    },
                  ),
                ],
              ),
            ),

            // Voice Assistant Button
            GestureDetector(
              onTap: _toggleVoiceAssistant,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: isAssistantActive ? AppTheme.primaryColor : AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isAssistantActive ? AppTheme.primaryColor : Colors.grey,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isAssistantActive ? Icons.mic : Icons.mic_none,
                          size: 32,
                          color: isAssistantActive ? Colors.black : Colors.white,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isAssistantActive ? 'Luisteren...' : 'Tap om te praten',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isAssistantActive ? Colors.black : Colors.white,
                          ),
                        ),
                      ],
                    ),
                    if (isAssistantActive) ...[
                      const SizedBox(height: 10),
                      const AudioWaveform(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(FavoriteDestination dest) {
    IconData icon = Icons.place;
    Color color = AppTheme.accentColor;
    
    switch (dest.icon) {
      case 'home':
        icon = Icons.home;
        color = Colors.green;
        break;
      case 'work':
        icon = Icons.work;
        color = Colors.blue;
        break;
      case 'school':
        icon = Icons.school;
        color = Colors.orange;
        break;
      case 'shopping':
        icon = Icons.shopping_bag;
        color = Colors.pink;
        break;
      case 'restaurant':
        icon = Icons.restaurant;
        color = Colors.red;
        break;
      case 'sports':
        icon = Icons.sports;
        color = Colors.teal;
        break;
      case 'history':
        icon = Icons.history;
        color = Colors.grey;
        break;
    }
    
    String label = dest.name;
    if (label.length > 12) {
      label = '${label.substring(0, 12)}...';
    }
    
    return GestureDetector(
      onTap: () {
        // Navigate to this destination
        Navigator.pushNamed(
          context,
          '/navigate',
          arguments: {
            'destination': dest.location,
            'address': dest.address,
          },
        );
      },
      child: Container(
        width: 110,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (dest.type == 'recent')
              Text(
                (dest as dynamic).timeAgo ?? '',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity( 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleVoiceAssistant() async {
    final isActive = ref.read(voiceAssistantProvider);
    
    if (isActive) {
      await _voiceService.stopListening();
      ref.read(voiceAssistantProvider.notifier).state = false;
    } else {
      ref.read(voiceAssistantProvider.notifier).state = true;
      await _voiceService.startListening();
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: const Text('Instellingen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Navigator AI v1.0'),
            const SizedBox(height: 10),
            const Text('Backend: http://76.13.137.117:3000'),
            const SizedBox(height: 20),
            const Text('Stem assistant: Nederlands'),
            const SizedBox(height: 10),
            const Text('Kaart: OpenStreetMap'),
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

  @override
  void dispose() {
    _locationService.stopTracking();
    _drivingService.stopMonitoring();
    _predictiveService.stopMonitoring();
    _drivingService.dispose();
    _predictiveService.dispose();
    _offlineService.dispose();
    _mlRouteService.dispose();
    _parkingService.dispose();
    _communityService.dispose();
    super.dispose();
  }
}
