import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/detection_result.dart';

class ObjectDetectionService {
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isInitialized = false;
  
  // Model configuration
  static const int inputSize = 640;
  static const double confidenceThreshold = 0.5;
  static const double nmsThreshold = 0.45;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    try {
      // Load TFLite model
      final interpreterOptions = InterpreterOptions()
        ..threads = 4
        ..useNnApiForAndroid = true;

      _interpreter = await Interpreter.fromAsset(
        'assets/models/yolov8n.tflite',
        options: interpreterOptions,
      );

      // Load labels
      final labelData = await File('assets/models/labels.txt').readAsString();
      _labels = labelData.split('\n').where((l) => l.isNotEmpty).toList();

      _isInitialized = true;
    } catch (e) {
      print('Error initializing object detection: $e');
      _isInitialized = false;
    }
  }

  Future<List<DetectionResult>> detectObjects(CameraImage cameraImage) async {
    if (!_isInitialized || _interpreter == null) {
      return [];
    }

    try {
      // Convert CameraImage to model input
      final input = _preprocessImage(cameraImage);
      
      // Run inference
      final output = List.generate(
        1,
        (_) => List.generate(
          84,
          (_) => List.generate(8400, (_) => 0.0),
        ),
      );

      _interpreter!.run(input, output);

      // Post-process results
      return _postprocessOutput(output[0]);
    } catch (e) {
      print('Detection error: $e');
      return [];
    }
  }

  /// Detect objects from an image file (for camera captured images)
  Future<List<DetectionResult>> detectFromFile(String imagePath) async {
    if (!_isInitialized || _interpreter == null) {
      return [];
    }

    try {
      // Load image from file
      final imageData = await File(imagePath).readAsBytes();
      final image = img.decodeImage(imageData);
      
      if (image == null) return [];

      // Preprocess
      final resized = img.copyResize(
        image,
        width: inputSize,
        height: inputSize,
      );

      // Normalize to [0, 1] and flatten
      final List<double> input = [];
      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          input.add(pixel.r / 255.0);
          input.add(pixel.g / 255.0);
          input.add(pixel.b / 255.0);
        }
      }

      // Run inference
      final output = List.generate(
        1,
        (_) => List.generate(
          84,
          (_) => List.generate(8400, (_) => 0.0),
        ),
      );

      _interpreter!.run([input], output);

      // Post-process results
      return _postprocessOutput(output[0]);
    } catch (e) {
      print('File detection error: $e');
      return [];
    }
  }

  List<double> _preprocessImage(CameraImage cameraImage) {
    // Convert YUV to RGB and resize to 640x640
    final img.Image? image = _convertYUV420ToImage(cameraImage);
    if (image == null) return [];

    final resized = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
    );

    // Normalize to [0, 1] and flatten
    final List<double> input = [];
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        input.add(pixel.r / 255.0);
        input.add(pixel.g / 255.0);
        input.add(pixel.b / 255.0);
      }
    }

    return input;
  }

  img.Image? _convertYUV420ToImage(CameraImage cameraImage) {
    try {
      final width = cameraImage.planes[0].bytesPerRow;
      final height = cameraImage.height;
      
      final img.Image image = img.Image(width: width, height: height);
      
      final uvRowStride = cameraImage.planes[1].bytesPerRow;
      final uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y * cameraImage.planes[0].bytesPerRow + x;
          final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

          final yp = cameraImage.planes[0].bytes[yIndex];
          final up = cameraImage.planes[1].bytes[uvIndex];
          final vp = cameraImage.planes[2].bytes[uvIndex];

          int r = (yp + 1.370705 * (vp - 128)).toInt();
          int g = (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128)).toInt();
          int b = (yp + 1.732446 * (up - 128)).toInt();

          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return image;
    } catch (e) {
      return null;
    }
  }

  List<DetectionResult> _postprocessOutput(List<List<double>> output) {
    final List<DetectionResult> results = [];
    
    // YOLOv8 output format: [x_center, y_center, width, height, confidence, class_scores...]
    for (int i = 0; i < 8400; i++) {
      final confidence = output[4][i];
      
      if (confidence < confidenceThreshold) continue;

      // Find best class
      double maxScore = 0;
      int classId = 0;
      
      for (int c = 0; c < 80; c++) {
        final score = output[5 + c][i];
        if (score > maxScore) {
          maxScore = score;
          classId = c;
        }
      }

      final finalScore = confidence * maxScore;
      if (finalScore < confidenceThreshold) continue;

      results.add(DetectionResult(
        label: _labels?[classId] ?? 'unknown',
        confidence: finalScore,
        x: output[0][i],
        y: output[1][i],
        width: output[2][i],
        height: output[3][i],
      ));
    }

    // Apply NMS (Non-Maximum Suppression)
    return _nms(results);
  }

  List<DetectionResult> _nms(List<DetectionResult> boxes) {
    // Sort by confidence
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
    
    final List<DetectionResult> selected = [];
    final List<bool> suppressed = List.filled(boxes.length, false);

    for (int i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;
      
      selected.add(boxes[i]);
      
      for (int j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;
        
        final iou = _calculateIoU(boxes[i], boxes[j]);
        if (iou > nmsThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return selected;
  }

  double _calculateIoU(DetectionResult a, DetectionResult b) {
    final x1 = (a.x - a.width / 2).clamp(0.0, 1.0);
    final y1 = (a.y - a.height / 2).clamp(0.0, 1.0);
    final x2 = (a.x + a.width / 2).clamp(0.0, 1.0);
    final y2 = (a.y + a.height / 2).clamp(0.0, 1.0);

    final x3 = (b.x - b.width / 2).clamp(0.0, 1.0);
    final y3 = (b.y - b.height / 2).clamp(0.0, 1.0);
    final x4 = (b.x + b.width / 2).clamp(0.0, 1.0);
    final y4 = (b.y + b.height / 2).clamp(0.0, 1.0);

    final xi1 = x1 > x3 ? x1 : x3;
    final yi1 = y1 > y3 ? y1 : y3;
    final xi2 = x2 < x4 ? x2 : x4;
    final yi2 = y2 < y4 ? y2 : y4;

    final interArea = (xi2 - xi1).clamp(0.0, 1.0) * (yi2 - yi1).clamp(0.0, 1.0);
    final boxAArea = (x2 - x1) * (y2 - y1);
    final boxBArea = (x4 - x3) * (y4 - y3);

    return interArea / (boxAArea + boxBArea - interArea + 1e-6);
  }

  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }
}
