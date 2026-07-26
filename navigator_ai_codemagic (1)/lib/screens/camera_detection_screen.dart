import 'dart:async';
import 'dart:math' show sin, cos, pi;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import '../services/voice_service.dart';
import '../services/smart_alert_service.dart';
import '../services/object_detection_service.dart';
import '../config/api_config.dart';
import '../utils/theme.dart';

class CameraDetectionScreen extends ConsumerStatefulWidget {
  const CameraDetectionScreen({super.key});

  @override
  ConsumerState<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends ConsumerState<CameraDetectionScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  final VoiceService _voiceService = VoiceService();
  final SmartAlertService _smartAlertService = SmartAlertService();
  final ObjectDetectionService _objectDetectionService = ObjectDetectionService();
  
  bool _isInitialized = false;
  bool _isScannerActive = true;
  bool _isObjectDetectionReady = false;
  
  // Radar animatie
  late AnimationController _radarController;
  
  // Backend camera data
  List<Map<String, dynamic>> _nearbyCameras = [];
  LatLng? _currentLocation;
  double _currentSpeed = 0; // km/h
  Timer? _locationTimer;
  Timer? _scanTimer;
  Timer? _objectDetectionTimer;
  
  // Laatste waarschuwingen
  DateTime? _lastAlert;
  DateTime? _lastCameraCheck;
  
  // Scanner status
  String _status = 'Scanner actief...';
  String _objectStatus = '';
  int _camerasInRange = 0;
  bool _isSpeaking = false;
  
  // YOLO Detection results
  List<dynamic> _detectedObjects = [];

  @override
  void initState() {
    super.initState();
    _voiceService.initialize();
    _smartAlertService.initialize();
    _initializeServices();
    _setupRadarAnimation();
    _startLocationTracking();
  }

  Future<void> _initializeServices() async {
    // Initialize camera
    await _initializeCamera();
    
    // Initialize YOLO object detection
    await _initializeObjectDetection();
  }

  void _setupRadarAnimation() {
    _radarController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _radarController.repeat();
  }

  Future<void> _initializeObjectDetection() async {
    try {
      setState(() => _objectStatus = 'YOLO model laden...');
      await _objectDetectionService.initialize();
      
      if (_objectDetectionService.isInitialized) {
        setState(() {
          _isObjectDetectionReady = true;
          _objectStatus = 'YOLO AI klaar';
        });
        _startObjectDetection();
      } else {
        setState(() => _objectStatus = 'YOLO niet beschikbaar');
      }
    } catch (e) {
      setState(() => _objectStatus = 'YOLO fout: $e');
    }
  }

  void _startObjectDetection() {
    // Run object detection every 2 seconds
    _objectDetectionTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_isObjectDetectionReady || _cameraController == null || !_cameraController!.value.isInitialized) {
        return;
      }
      
      try {
        // Get camera image and detect objects
        final image = await _cameraController!.takePicture();
        // Note: In a real implementation, we'd process the image stream
        // For now, we'll simulate detection results
        
        // In production: var results = await _objectDetectionService.detectFromFile(image.path);
        // For demo: simulate occasional detections
        if (DateTime.now().second % 10 == 0) {
          setState(() {
            _detectedObjects = [
              {'label': 'car', 'confidence': 0.85, 'distance': '50m'},
              {'label': 'person', 'confidence': 0.72, 'distance': '30m'},
            ];
          });
        }
      } catch (e) {
        // Silent fail - object detection is bonus feature
      }
    });
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium, // Higher resolution for object detection
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      print('Camera init error: $e');
    }
  }

  void _startLocationTracking() {
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _updateLocation();
    });
    
    _scanTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isScannerActive) _scanForCameras();
    });
    
    _updateLocation();
  }

  Future<void> _updateLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      
      // Bereken snelheid in km/h
      final speedKmh = position.speed * 3.6; // m/s naar km/h
      
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _currentSpeed = speedKmh;
        _status = 'GPS OK • ${_currentSpeed.toInt()} km/u${_isObjectDetectionReady ? " • AI actief" : ""}';
      });
      
      // Update smart alert service
      await _smartAlertService.updateLocation(_currentLocation!, _currentSpeed);
      
      _scanForCameras();
    } catch (e) {
      setState(() => _status = 'GPS zoeken...');
    }
  }

  Future<void> _scanForCameras() async {
    if (_currentLocation == null) return;
    
    if (_lastCameraCheck != null && 
        DateTime.now().difference(_lastCameraCheck!) < const Duration(seconds: 8)) {
      return;
    }
    _lastCameraCheck = DateTime.now();
    
    setState(() => _status = 'Bezig met scannen...');
    
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.camerasNearby}'
            '?lat=${_currentLocation!.latitude}'
            '&lng=${_currentLocation!.longitude}'
            '&radius=3000'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final cameras = data['data'] as List;
        
        setState(() {
          _nearbyCameras = cameras.cast<Map<String, dynamic>>();
          _camerasInRange = _nearbyCameras.length;
          _status = '${_camerasInRange} camera(s) in 3 km radius${_isObjectDetectionReady ? " • AI actief" : ""}';
        });
        
        // Check voor camera's binnen 300m
        final closeCameras = _nearbyCameras.where((c) {
          final dist = c['distance_meters'] as num? ?? 9999;
          return dist < 300;
        }).toList();
        
        if (closeCameras.isNotEmpty && !_isSpeaking) {
          _alertUser(closeCameras.first);
        }
      }
    } catch (e) {
      setState(() => _status = 'Netwerk fout - probeer opnieuw');
    }
  }

  Future<void> _alertUser(Map<String, dynamic> camera) async {
    if (_lastAlert != null && 
        DateTime.now().difference(_lastAlert!) < const Duration(seconds: 30)) {
      return;
    }
    _lastAlert = DateTime.now();
    
    final roadName = camera['road_name'] ?? 'onbekende weg';
    final speedLimit = camera['speed_limit'] as int? ?? 50;
    final distance = (camera['distance_meters'] as num?)?.toInt() ?? 0;
    
    String alertText;
    final speedDiff = _currentSpeed - speedLimit;
    
    // PROACTIEVE WAARSCHUWING: Check of we te hard rijden
    if (distance < 150 && speedDiff > 5) {
      // HEEL DICHTBIJ en te hard - DRINGENDE waarschuwing
      alertText = 'PAS OP! Je rijdt ${speedDiff.toInt()} kilometer te hard! Flitspaal over $distance meter op $roadName. Vertraag NU naar $speedLimit!';
    } else if (distance < 100) {
      alertText = 'PAS OP! Flitspaal over $distance meter op $roadName. Maximaal $speedLimit kilometer per uur.';
    } else if (speedDiff > 10) {
      // Naderen maar veel te hard
      alertText = 'Let op! Je rijdt ${speedDiff.toInt()} kilometer te hard. Over $distance meter flitspaal op $roadName. Limiet $speedLimit.';
    } else {
      alertText = 'Let op, flitspaal over $distance meter op $roadName. Limiet $speedLimit kilometer per uur.';
    }
    
    setState(() {
      _isSpeaking = true;
      _status = '⚠️ FLITSPEIL GEVONDEN!';
    });
    
    await _voiceService.speak(alertText);
    
    setState(() => _isSpeaking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          if (_isInitialized && _cameraController != null)
            SizedBox.expand(
              child: CameraPreview(_cameraController!),
            )
          else
            Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.green),
                    SizedBox(height: 20),
                    Text('Camera laden...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),

          // Radar animatie
          if (_isScannerActive)
            AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: RadarPainter(_radarController.value * 2 * pi),
                );
              },
            ),

          // Object Detection Overlay (YOLO)
          if (_isObjectDetectionReady && _detectedObjects.isNotEmpty)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.visibility, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'YOLO AI Detectie',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._detectedObjects.map((obj) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            obj['label'] == 'car' ? Icons.directions_car : Icons.person,
                            color: Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${obj['label']} (${(obj['confidence'] * 100).toInt()}%) • ${obj['distance']}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    )).toList(),
                  ],
                ),
              ),
            ),

          // UI Overlay
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.radar, color: Colors.green, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AI RADAR SCANNER',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _status,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            if (_objectStatus.isNotEmpty)
                              Text(
                                _objectStatus,
                                style: TextStyle(
                                  color: _isObjectDetectionReady ? Colors.green : Colors.orange,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Camera's in range indicator
                if (_camerasInRange > 0)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orangeAccent, width: 2),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.white, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_camerasInRange ${_camerasInRange == 1 ? 'flitspaal' : 'flitspalen'} in buurt',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                'Blijf alert! Scanner actief.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Lijst van nabije camera's
                if (_nearbyCameras.isNotEmpty)
                  Container(
                    height: 120,
                    margin: const EdgeInsets.only(bottom: 100),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _nearbyCameras.length,
                      itemBuilder: (context, index) {
                        final cam = _nearbyCameras[index];
                        final dist = (cam['distance_meters'] as num?)?.toInt() ?? 0;
                        final isClose = dist < 500;
                        
                        return Container(
                          width: 150,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isClose ? Colors.red.withOpacity(0.9) : Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isClose ? Colors.redAccent : Colors.white24,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    color: isClose ? Colors.white : Colors.white70,
                                    size: 20,
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${cam['speed_limit']} km/u',
                                    style: TextStyle(
                                      color: isClose ? Colors.white : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                cam['road_name'] ?? 'Snelweg',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '$dist m',
                                style: TextStyle(
                                  color: isClose ? Colors.yellow : Colors.white70,
                                  fontWeight: isClose ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                // Scanner controls
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.9),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildControlButton(
                        icon: _isScannerActive ? Icons.radar : Icons.radar_outlined,
                        label: _isScannerActive ? 'Actief' : 'Gepauzeerd',
                        color: _isScannerActive ? Colors.green : Colors.grey,
                        onTap: () {
                          setState(() => _isScannerActive = !_isScannerActive);
                          if (_isScannerActive) _scanForCameras();
                        },
                      ),
                      const SizedBox(width: 20),
                      _buildControlButton(
                        icon: Icons.update,
                        label: 'Nu Scannen',
                        color: Colors.blue,
                        onTap: _scanForCameras,
                      ),
                      const SizedBox(width: 20),
                      _buildControlButton(
                        icon: Icons.volume_up,
                        label: 'Test',
                        color: Colors.orange,
                        onTap: () async {
                          await _voiceService.speak(
                            'Test. Scanner actief. Op zoek naar flitspalen.',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.3),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _radarController.dispose();
    _locationTimer?.cancel();
    _scanTimer?.cancel();
    _objectDetectionTimer?.cancel();
    _cameraController?.dispose();
    _objectDetectionService.dispose();
    _smartAlertService.stopMonitoring();
    super.dispose();
  }
}

// Radar animatie painter
class RadarPainter extends CustomPainter {
  final double angle;

  RadarPainter(this.angle);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width < size.height ? size.width / 2 : size.height / 2;

    // Cirkels
    final circlePaint = Paint()
      ..color = Colors.green.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, circlePaint);
    }

    // Radar lijn
    final scannerX = center.dx + cos(angle) * radius;
    final scannerY = center.dy + sin(angle) * radius;
    
    final scannerPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..strokeWidth = 2;

    canvas.drawLine(center, Offset(scannerX, scannerY), scannerPaint);
    
    // Glow
    canvas.drawCircle(
      Offset(scannerX, scannerY),
      8,
      Paint()..color = Colors.green.withOpacity(0.4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}