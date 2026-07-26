import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/detection_result.dart';
import '../models/navigation_state.dart';

class ApiService {
  // VPS backend URL - update this with your actual server IP/domain
  static const String baseUrl = 'http://[2a02:4780:79:71d3::1]:3000/api/v1';
  static const String wsUrl = 'ws://[2a02:4780:79:71d3::1]:3000/ws';

  static final http.Client _client = http.Client();

  // ---- Speed Cameras ----

  static Future<List<Map<String, dynamic>>> getNearbyCameras({
    required double lat,
    required double lng,
    double radius = 2000,
    int limit = 50,
    List<String>? types,
  }) async {
    try {
      final queryParams = {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
        'limit': limit.toString(),
        if (types != null && types.isNotEmpty) 'types': types.join(','),
      };

      final url = Uri.parse('$baseUrl/cameras/nearby').replace(queryParameters: queryParams);
      final response = await _client.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data'] ?? []);
        }
      }
      return [];
    } catch (e) {
      print('API getNearbyCameras error: $e');
      return [];
    }
  }

  static Future<void> reportCamera({
    required double latitude,
    required double longitude,
    int? speedLimit,
    String cameraType = 'fixed',
    String? roadName,
    String? direction,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/cameras'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'speed_limit': speedLimit,
          'camera_type': cameraType,
          'road_name': roadName,
          'direction': direction,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        print('Camera reported successfully');
      }
    } catch (e) {
      print('API reportCamera error: $e');
    }
  }

  static Future<void> confirmCamera(String cameraId) async {
    try {
      await _client.post(
        Uri.parse('$baseUrl/cameras/$cameraId/confirm'),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      print('API confirmCamera error: $e');
    }
  }

  // ---- Community Alerts ----

  static Future<List<Map<String, dynamic>>> getNearbyAlerts({
    required double lat,
    required double lng,
    double radius = 5000,
    List<String>? types,
  }) async {
    try {
      final queryParams = {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
        if (types != null && types.isNotEmpty) 'types': types.join(','),
      };

      final url = Uri.parse('$baseUrl/alerts/nearby').replace(queryParameters: queryParams);
      final response = await _client.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data'] ?? []);
        }
      }
      return [];
    } catch (e) {
      print('API getNearbyAlerts error: $e');
      return [];
    }
  }

  static Future<void> reportAlert({
    required String type,
    required double latitude,
    required double longitude,
    String? description,
    String severity = 'medium',
    String? createdBy,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/alerts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': type,
          'latitude': latitude,
          'longitude': longitude,
          'description': description,
          'severity': severity,
          'created_by': createdBy ?? 'anonymous',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        print('Alert reported successfully');
      }
    } catch (e) {
      print('API reportAlert error: $e');
    }
  }

  static Future<void> voteOnAlert(String alertId, bool upvote) async {
    try {
      await _client.post(
        Uri.parse('$baseUrl/alerts/$alertId/vote'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'direction': upvote ? 'up' : 'down'}),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      print('API voteOnAlert error: $e');
    }
  }

  // ---- Convert API response to DetectionResult ----

  static DetectionResult cameraToDetectionResult(Map<String, dynamic> camera) {
    return DetectionResult(
      label: camera['camera_type'] == 'red_light' ? 'traffic_light' : 'speed_camera',
      confidence: 0.95,
      x: 0.5,
      y: 0.5,
      width: 0.1,
      height: 0.1,
    );
  }

  static NavigationAlert cameraToNavigationAlert(Map<String, dynamic> camera) {
    return NavigationAlert(
      type: 'speed_camera',
      message: '${camera['camera_type']} op ${camera['road_name'] ?? 'onbekende weg'}',
      location: const LatLng(0, 0), // Will be overridden by caller
      timestamp: DateTime.parse(camera['created_at'] ?? DateTime.now().toIso8601String()),
      speedLimit: camera['speed_limit'],
    );
  }

  static void dispose() {
    _client.close();
  }
}
