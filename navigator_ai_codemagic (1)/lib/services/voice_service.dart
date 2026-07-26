import 'dart:async';
import 'dart:io';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'whisper_service.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  
  bool _isListening = false;
  bool _isSpeaking = false;
  String _lastWords = '';

  // Stream controllers
  final StreamController<String> _transcriptController = StreamController<String>.broadcast();
  final StreamController<bool> _listeningController = StreamController<bool>.broadcast();

  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<bool> get listeningStream => _listeningController.stream;

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  String get lastWords => _lastWords;

  Future<bool> initialize() async {
    // Initialize Text-to-Speech
    await _flutterTts.setLanguage('nl-NL');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
    });

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    // Initialize Speech-to-Text
    final available = await _speechToText.initialize(
      onError: (error) => print('Speech error: $error'),
      onStatus: (status) {
        if (status == 'notListening') {
          _isListening = false;
          _listeningController.add(false);
        }
      },
    );

    return available;
  }

  Future<void> startListening() async {
    if (!_speechToText.isAvailable) {
      await initialize();
    }

    _isListening = true;
    _listeningController.add(true);
    _lastWords = '';

    await _speechToText.listen(
      onResult: (result) {
        _lastWords = result.recognizedWords;
        _transcriptController.add(_lastWords);
        
        if (result.finalResult) {
          _processVoiceCommand(_lastWords);
        }
      },
      localeId: 'nl-NL',
    );
  }

  Future<void> stopListening() async {
    _isListening = false;
    _listeningController.add(false);
    await _speechToText.stop();
  }

  /// Transcribe using Whisper API if local STT fails or for better accuracy
  Future<String> transcribeWithWhisper(File audioFile) async {
    if (await WhisperService.isAvailable()) {
      return await WhisperService.transcribeFile(audioFile);
    }
    return '';
  }

  void _processVoiceCommand(String command) async {
    final lowerCommand = command.toLowerCase();
    
    if (lowerCommand.contains('navigeer') || lowerCommand.contains('route') || lowerCommand.contains('ga naar')) {
      // Extract destination from command
      final destination = _extractDestination(command);
      if (destination != null) {
        await speak('Ik navigeer naar $destination');
      } else {
        await speak('Waar wil je naartoe? Noem een adres of plaats.');
      }
    } else if (lowerCommand.contains('stop') || lowerCommand.contains('halt') || lowerCommand.contains('annuleer')) {
      await speak('Navigatie gestopt.');
    } else if (lowerCommand.contains('flitser') || lowerCommand.contains('camera') || lowerCommand.contains('flitspaal')) {
      await speak('Let op, ik scan naar flitspalen in de buurt.');
    } else if (lowerCommand.contains('thuis') || lowerCommand.contains('huis')) {
      await speak('Ik navigeer naar huis.');
    } else if (lowerCommand.contains('werk') || lowerCommand.contains('kantoor') || lowerCommand.contains('werken')) {
      await speak('Ik navigeer naar je werk.');
    } else if (lowerCommand.contains('file') || lowerCommand.contains('verkeer') || lowerCommand.contains('drukte')) {
      await speak('Ik check het verkeer rondom je locatie. Even geduld.');
    } else if (lowerCommand.contains('snelheid') || lowerCommand.contains('hoe hard')) {
      await speak('Je huidige snelheid wordt weergegeven op het scherm.');
    } else if (lowerCommand.contains('tanken') || lowerCommand.contains('benzine') || lowerCommand.contains('diesel')) {
      await speak('Ik zoek tankstations in de buurt.');
    } else if (lowerCommand.contains('tijd') || lowerCommand.contains('hoelang') || lowerCommand.contains('wanneer')) {
      await speak('Ik bereken de verwachte aankomsttijd.');
    } else if (lowerCommand.contains('alternatief') || lowerCommand.contains('andere route')) {
      await speak('Ik zoek een alternatieve route voor je.');
    } else if (lowerCommand.contains('waarschuwing') || lowerCommand.contains('alert')) {
      await speak('Waarschuwingen worden nu gecontroleerd.');
    } else {
      await _processWithAI(command);
    }
  }
  
  String? _extractDestination(String command) {
    // Common patterns in Dutch
    final patterns = [
      RegExp(r'naar\s+(.+?)(?:\s|$)'),
      RegExp(r'ga\s+naar\s+(.+?)(?:\s|$)'),
      RegExp(r'navigeer\s+naar\s+(.+?)(?:\s|$)'),
      RegExp(r'route\s+naar\s+(.+?)(?:\s|$)'),
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(command.toLowerCase());
      if (match != null) {
        return match.group(1)?.trim();
      }
    }
    return null;
  }

  Future<void> _processWithAI(String command) async {
    try {
      // Fallback: simple response
      await speak('Ik heb je gevraag begrepen: $command');
    } catch (e) {
      print('AI processing error: $e');
      await speak('Sorry, ik kon je verzoek niet verwerken.');
    }
  }

  Future<void> speak(String text) async {
    if (_isSpeaking) {
      await _flutterTts.stop();
    }
    await _flutterTts.speak(text);
  }

  Future<void> speakNavigationInstruction(String instruction, {double? distance}) async {
    String text = instruction;
    if (distance != null) {
      if (distance < 1000) {
        text += ' over ${distance.toInt()} meter';
      } else {
        text += ' over ${(distance / 1000).toStringAsFixed(1)} kilometer';
      }
    }
    await speak(text);
  }

  Future<void> speakSpeedCameraAlert(int? speedLimit) async {
    if (speedLimit != null) {
      await speak('Let op! Flitspaal vooruit. Snelheidslimiet $speedLimit kilometer per uur.');
    } else {
      await speak('Let op! Flitspaal gedetecteerd vooruit.');
    }
  }

  Future<void> setLanguage(String language) async {
    await _flutterTts.setLanguage(language);
  }

  Future<void> stopSpeaking() async {
    await _flutterTts.stop();
    _isSpeaking = false;
  }

  void dispose() {
    _transcriptController.close();
    _listeningController.close();
    _flutterTts.stop();
    _speechToText.cancel();
  }
}
