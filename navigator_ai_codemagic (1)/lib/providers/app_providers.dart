import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/navigation_state.dart';
import '../models/detection_result.dart';

// Navigation State Provider
final navigationProvider = StateProvider<NavigationState>((ref) {
  return NavigationState(
    isNavigating: false,
    currentSpeed: 0.0,
    currentLocation: null,
    destination: null,
    routeSteps: [],
    currentStepIndex: 0,
    alerts: [],
  );
});

// Detection Results Provider
final detectionProvider = StateProvider<List<DetectionResult>>((ref) {
  return [];
});

// Voice Assistant State
final voiceAssistantProvider = StateProvider<bool>((ref) => false);

// Camera Detection Active
final cameraActiveProvider = StateProvider<bool>((ref) => false);

// Speed Camera Alert Provider
final speedCameraAlertProvider = StateProvider<Map<String, dynamic>?>((ref) => null);
