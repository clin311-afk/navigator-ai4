/// Centrale API configuratie
class ApiConfig {
  // Backend API - gebruik IPv6 (betrouwbaarder op deze VPS)
  static const String backendUrl = 'http://[2a02:4780:79:71d3::1]:3000';
  static const String apiBaseUrl = '$backendUrl/api/v1';
  
  // Fallback naar IPv4 als IPv6 faalt
  static const String backendUrlV4 = 'http://76.13.137.117:3000';
  static const String apiBaseUrlV4 = '$backendUrlV4/api/v1';
  
  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
  
  /// Probeer IPv6 eerst, fallback naar IPv4
  static String get camerasNearby => '$apiBaseUrl/cameras/nearby';
  static String get camerasAll => '$apiBaseUrl/cameras';
  static String get communityAlerts => '$apiBaseUrl/community/alerts';
}
