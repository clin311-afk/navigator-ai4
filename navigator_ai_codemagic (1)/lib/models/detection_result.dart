class DetectionResult {
  final String label;
  final double confidence;
  final double x;
  final double y;
  final double width;
  final double height;

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory DetectionResult.fromMap(Map<String, dynamic> map) {
    return DetectionResult(
      label: map['label'] ?? '',
      confidence: map['confidence'] ?? 0.0,
      x: map['x'] ?? 0.0,
      y: map['y'] ?? 0.0,
      width: map['width'] ?? 0.0,
      height: map['height'] ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'confidence': confidence,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }

  String get displayLabel {
    switch (label) {
      case 'speed_camera':
        return '📸 Flitspaal';
      case 'speed_limit':
        return '🚫 Snelheidslimiet';
      case 'traffic_light':
        return '🚦 Verkeerslicht';
      case 'stop_sign':
        return '🛑 Stopbord';
      default:
        return label;
    }
  }

  bool get isSpeedCamera => label == 'speed_camera';
  bool get isSpeedLimit => label == 'speed_limit';
}
