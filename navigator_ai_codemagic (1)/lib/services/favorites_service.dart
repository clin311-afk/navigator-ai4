import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service voor het opslaan en beheren van favoriete routes en bestemmingen
class FavoritesService {
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  static const String _favoritesKey = 'favorite_destinations';
  static const String _recentRoutesKey = 'recent_routes';
  static const String _homeKey = 'home_location';
  static const String _workKey = 'work_location';

  List<FavoriteDestination> _favorites = [];
  List<RecentRoute> _recentRoutes = [];
  FavoriteDestination? _home;
  FavoriteDestination? _work;

  bool _isLoaded = false;

  Future<void> initialize() async {
    if (_isLoaded) return;
    await _loadData();
    _isLoaded = true;
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load favorites
    final favoritesJson = prefs.getStringList(_favoritesKey) ?? [];
    _favorites = favoritesJson
        .map((json) => FavoriteDestination.fromJson(jsonDecode(json)))
        .toList();

    // Load recent routes
    final recentJson = prefs.getStringList(_recentRoutesKey) ?? [];
    _recentRoutes = recentJson
        .map((json) => RecentRoute.fromJson(jsonDecode(json)))
        .take(10) // Max 10 recent
        .toList();

    // Load home and work
    final homeJson = prefs.getString(_homeKey);
    if (homeJson != null) {
      _home = FavoriteDestination.fromJson(jsonDecode(homeJson));
    }

    final workJson = prefs.getString(_workKey);
    if (workJson != null) {
      _work = FavoriteDestination.fromJson(jsonDecode(workJson));
    }
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _favorites.map((f) => jsonEncode(f.toJson())).toList();
    await prefs.setStringList(_favoritesKey, jsonList);
  }

  Future<void> _saveRecentRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _recentRoutes.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_recentRoutesKey, jsonList);
  }

  // Favorites management
  List<FavoriteDestination> get favorites => List.unmodifiable(_favorites);

  Future<void> addFavorite(FavoriteDestination dest) async {
    // Check if already exists
    final existingIndex = _favorites.indexWhere((f) =>
        (f.name.toLowerCase() == dest.name.toLowerCase()) ||
        (_distanceBetween(f.location, dest.location) < 100));

    if (existingIndex >= 0) {
      // Update existing
      _favorites[existingIndex] = dest;
    } else {
      _favorites.add(dest);
    }

    await _saveFavorites();
  }

  Future<void> removeFavorite(String name) async {
    _favorites.removeWhere((f) => f.name == name);
    await _saveFavorites();
  }

  // Home/Work shortcuts
  FavoriteDestination? get home => _home;
  FavoriteDestination? get work => _work;

  Future<void> setHome(FavoriteDestination dest) async {
    _home = dest;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_homeKey, jsonEncode(dest.toJson()));
    await addFavorite(dest);
  }

  Future<void> setWork(FavoriteDestination dest) async {
    _work = dest;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_workKey, jsonEncode(dest.toJson()));
    await addFavorite(dest);
  }

  Future<void> clearHome() async {
    _home = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeKey);
  }

  Future<void> clearWork() async {
    _work = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_workKey);
  }

  // Recent routes
  List<RecentRoute> get recentRoutes => List.unmodifiable(_recentRoutes);

  Future<void> addRecentRoute(RecentRoute route) async {
    // Remove if same route already exists
    _recentRoutes.removeWhere((r) =>
        r.destinationName == route.destinationName ||
        (_distanceBetween(r.destinationLocation, route.destinationLocation) < 100));

    // Add to beginning
    _recentRoutes.insert(0, route);

    // Keep only 10
    if (_recentRoutes.length > 10) {
      _recentRoutes = _recentRoutes.take(10).toList();
    }

    await _saveRecentRoutes();

    // Also add as favorite if used frequently
    await _checkAndPromoteToFavorite(route);
  }

  Future<void> _checkAndPromoteToFavorite(RecentRoute route) async {
    // Count how many times this destination appears in recent routes
    final count = _recentRoutes
        .where((r) => r.destinationName == route.destinationName)
        .length;

    if (count >= 3) {
      // Used 3+ times, suggest as favorite
      final existing = _favorites.indexWhere((f) => f.name == route.destinationName);
      if (existing < 0) {
        await addFavorite(FavoriteDestination(
          name: route.destinationName,
          address: route.destinationAddress,
          location: route.destinationLocation,
          type: 'auto',
          icon: _suggestIcon(route.destinationName),
        ));
      }
    }
  }

  String _suggestIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('huis') || lower.contains('thuis')) return 'home';
    if (lower.contains('werk') || lower.contains('kantoor')) return 'work';
    if (lower.contains('school')) return 'school';
    if (lower.contains('winkel') || lower.contains('shop')) return 'shopping';
    if (lower.contains('restaurant') || lower.contains('eten')) return 'restaurant';
    if (lower.contains('sport') || lower.contains('gym')) return 'sports';
    return 'place';
  }

  Future<void> clearRecentRoutes() async {
    _recentRoutes.clear();
    await _saveRecentRoutes();
  }

  // Smart suggestions based on time
  List<FavoriteDestination> getSmartSuggestions() {
    final hour = DateTime.now().hour;
    final suggestions = <FavoriteDestination>[];

    // Morning (6-9): suggest work
    if (hour >= 6 && hour <= 9 && _work != null) {
      suggestions.add(_work!);
    }

    // Evening (17-20): suggest home
    if (hour >= 17 && hour <= 20 && _home != null) {
      suggestions.add(_home!);
    }

    // Add frequently used favorites
    suggestions.addAll(_favorites.take(3));

    // Add recent routes
    for (final route in _recentRoutes.take(2)) {
      if (!suggestions.any((s) => s.name == route.destinationName)) {
        suggestions.add(FavoriteDestination(
          name: route.destinationName,
          address: route.destinationAddress,
          location: route.destinationLocation,
          type: 'recent',
          icon: 'history',
        ));
      }
    }

    return suggestions.take(5).toList();
  }

  double _distanceBetween(LatLng a, LatLng b) {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, a, b);
  }
}

class FavoriteDestination {
  final String name;
  final String address;
  final LatLng location;
  final String type; // 'home', 'work', 'favorite', 'auto', 'recent'
  final String icon;
  final DateTime? lastUsed;

  FavoriteDestination({
    required this.name,
    required this.address,
    required this.location,
    this.type = 'favorite',
    this.icon = 'place',
    this.lastUsed,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'lat': location.latitude,
        'lng': location.longitude,
        'type': type,
        'icon': icon,
        'lastUsed': lastUsed?.toIso8601String(),
      };

  factory FavoriteDestination.fromJson(Map<String, dynamic> json) {
    return FavoriteDestination(
      name: json['name'] ?? 'Onbekend',
      address: json['address'] ?? '',
      location: LatLng(json['lat'] ?? 0.0, json['lng'] ?? 0.0),
      type: json['type'] ?? 'favorite',
      icon: json['icon'] ?? 'place',
      lastUsed: json['lastUsed'] != null
          ? DateTime.parse(json['lastUsed'])
          : null,
    );
  }
}

class RecentRoute {
  final String destinationName;
  final String destinationAddress;
  final LatLng destinationLocation;
  final DateTime timestamp;
  final double? distance;
  final int? durationMinutes;

  RecentRoute({
    required this.destinationName,
    required this.destinationAddress,
    required this.destinationLocation,
    required this.timestamp,
    this.distance,
    this.durationMinutes,
  });

  Map<String, dynamic> toJson() => {
        'destinationName': destinationName,
        'destinationAddress': destinationAddress,
        'lat': destinationLocation.latitude,
        'lng': destinationLocation.longitude,
        'timestamp': timestamp.toIso8601String(),
        'distance': distance,
        'durationMinutes': durationMinutes,
      };

  factory RecentRoute.fromJson(Map<String, dynamic> json) {
    return RecentRoute(
      destinationName: json['destinationName'] ?? 'Onbekend',
      destinationAddress: json['destinationAddress'] ?? '',
      destinationLocation: LatLng(
        json['lat'] ?? 0.0,
        json['lng'] ?? 0.0,
      ),
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      distance: json['distance']?.toDouble(),
      durationMinutes: json['durationMinutes'],
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m geleden';
    if (diff.inHours < 24) return '${diff.inHours}u geleden';
    return '${diff.inDays}d geleden';
  }
}