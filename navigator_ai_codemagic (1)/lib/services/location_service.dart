import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _headingStream;
  final StreamController<LatLng> _locationController = StreamController<LatLng>.broadcast();
  final StreamController<double> _speedController = StreamController<double>.broadcast();
  final StreamController<double> _headingController = StreamController<double>.broadcast();

  Stream<LatLng> get locationStream => _locationController.stream;
  Stream<double> get speedStream => _speedController.stream;
  Stream<double> get headingStream => _headingController.stream;

  Future<bool> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  void startTracking() {
    // High accuracy for smooth car tracking
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3, // Update every 3 meters for smooth movement
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      final latLng = LatLng(position.latitude, position.longitude);
      final speedKmh = position.speed * 3.6; // Convert m/s to km/h
      
      _locationController.add(latLng);
      _speedController.add(speedKmh);
      
      // Use heading from GPS (more accurate than compass when moving)
      if (position.heading != 0) {
        _headingController.add(position.heading);
      }
    });
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  Future<LatLng?> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      return null;
    }
  }

  double calculateDistance(LatLng from, LatLng to) {
    const distance = Distance();
    return distance.as(LengthUnit.Kilometer, from, to);
  }

  void dispose() {
    stopTracking();
    _headingStream?.cancel();
    _locationController.close();
    _speedController.close();
    _headingController.close();
  }
}
