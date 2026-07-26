import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Whisper Speech-to-Text via VPS API
/// Uploads recorded audio to VPS Whisper server, gets transcription back
class WhisperService {
  static const String _whisperUrl = 'http://[2a02:4780:79:71d3::1]:8000';
  static final http.Client _client = http.Client();

  /// Transcribe audio file to text
  /// Returns empty string on error
  static Future<String> transcribeFile(File audioFile) async {
    try {
      final uri = Uri.parse('$_whisperUrl/transcribe/stream');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath(
        'audio',
        audioFile.path,
        contentType: MediaType('audio', _getAudioExtension(audioFile.path)),
      ));

      request.fields['language'] = 'nl';

      final response = await request.send().timeout(const Duration(seconds: 15));
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        return data['text'] as String? ?? '';
      }
    } catch (e) {
      print('Whisper transcribe error: $e');
    }
    return '';
  }

  /// Transcribe raw audio bytes (for in-memory recording)
  static Future<String> transcribeBytes(List<int> audioBytes, {String format = 'wav'}) async {
    try {
      final uri = Uri.parse('$_whisperUrl/transcribe/stream');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(http.MultipartFile.fromBytes(
        'audio',
        audioBytes,
        filename: 'recording.$format',
        contentType: MediaType('audio', format),
      ));

      request.fields['language'] = 'nl';

      final response = await request.send().timeout(const Duration(seconds: 15));
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        return data['text'] as String? ?? '';
      }
    } catch (e) {
      print('Whisper bytes transcribe error: $e');
    }
    return '';
  }

  /// Check if Whisper server is available
  static Future<bool> isAvailable() async {
    try {
      final response = await _client
          .get(Uri.parse('$_whisperUrl/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static String _getAudioExtension(String path) {
    final ext = path.split('.').last.toLowerCase();
    const map = {'mp3': 'mpeg', 'm4a': 'mp4', 'ogg': 'ogg', 'webm': 'webm', 'wav': 'wav'};
    return map[ext] ?? 'wav';
  }

  static void dispose() {
    _client.close();
  }
}
