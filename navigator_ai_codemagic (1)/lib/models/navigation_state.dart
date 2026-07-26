import 'package:latlong2/latlong.dart';

class NavigationState {
  final bool isNavigating;
  final double currentSpeed;
  final LatLng? currentLocation;
  final LatLng? destination;
  final List<RouteStep> routeSteps;
  final int currentStepIndex;
  final List<NavigationAlert> alerts;

  NavigationState({
    required this.isNavigating,
    required this.currentSpeed,
    this.currentLocation,
    this.destination,
    required this.routeSteps,
    required this.currentStepIndex,
    required this.alerts,
  });

  String? get currentInstruction {
    if (routeSteps.isEmpty || currentStepIndex >= routeSteps.length) {
      return 'Ga verder';
    }
    return routeSteps[currentStepIndex].instruction;
  }

  double get distanceToNextStep {
    if (routeSteps.isEmpty || currentLocation == null) return 0;
    if (currentStepIndex >= routeSteps.length) return 0;
    
    return const Distance().as(
      LengthUnit.Meter,
      currentLocation!,
      routeSteps[currentStepIndex].location,
    );
  }

  NavigationState copyWith({
    bool? isNavigating,
    double? currentSpeed,
    LatLng? currentLocation,
    LatLng? destination,
    List<RouteStep>? routeSteps,
    int? currentStepIndex,
    List<NavigationAlert>? alerts,
  }) {
    return NavigationState(
      isNavigating: isNavigating ?? this.isNavigating,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      currentLocation: currentLocation ?? this.currentLocation,
      destination: destination ?? this.destination,
      routeSteps: routeSteps ?? this.routeSteps,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      alerts: alerts ?? this.alerts,
    );
  }
}

class RouteStep {
  final String instruction;
  final double distance;
  final double duration;
  final LatLng location;
  final String maneuver;

  RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.location,
    required this.maneuver,
  });
}

class NavigationAlert {
  final String type; // 'speed_camera', 'traffic', 'police', 'accident'
  final String message;
  final LatLng location;
  final DateTime timestamp;
  final int? speedLimit;

  NavigationAlert({
    required this.type,
    required this.message,
    required this.location,
    required this.timestamp,
    this.speedLimit,
  });
}
