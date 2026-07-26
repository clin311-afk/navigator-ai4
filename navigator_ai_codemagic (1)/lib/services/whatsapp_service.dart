import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/voice_service.dart';

/// Service voor WhatsApp integratie - verstuur spraakberichten
class WhatsAppService {
  static final WhatsAppService _instance = WhatsAppService._internal();
  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  final VoiceService _voiceService = VoiceService();
  bool _isInitialized = false;

  // Contacts
  List<WhatsAppContact> _recentContacts = [];
  String? _defaultMessage;

  Future<void> initialize() async {
    await _voiceService.initialize();
    await _loadContacts();
    _isInitialized = true;
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = prefs.getStringList('whatsapp_contacts') ?? [];
    _recentContacts = contactsJson.map((c) => WhatsAppContact.fromJson(c)).toList();
    _defaultMessage = prefs.getString('whatsapp_default_message') ?? 'Ik ben er over {minutes} minuten 🚗';
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = _recentContacts.map((c) => c.toJson()).toList();
    await prefs.setStringList('whatsapp_contacts', contactsJson);
  }

  /// Verstuur "Ik ben er over X minuten" bericht
  Future<bool> sendEtaMessage({
    required String phoneNumber,
    required int minutes,
    String? customMessage,
  }) async {
    if (!_isInitialized) return false;

    final message = customMessage ?? _defaultMessage ?? 'Ik ben er over {minutes} minuten 🚗';
    final formattedMessage = message.replaceAll('{minutes}', minutes.toString());

    return await _openWhatsApp(phoneNumber, formattedMessage);
  }

  /// Verstuur custom bericht
  Future<bool> sendMessage({
    required String phoneNumber,
    required String message,
  }) async {
    if (!_isInitialized) return false;
    return await _openWhatsApp(phoneNumber, message);
  }

  /// Verstuur spraakbericht (gebruikt speech-to-text)
  Future<bool> sendVoiceMessage(String phoneNumber) async {
    if (!_isInitialized) return false;

    await _voiceService.speak('Dik wat je wilt versturen via WhatsApp');
    
    // In een echte implementatie zou je hier speech-to-text doen
    // Voor nu gebruiken we een standaard template
    final templates = [
      'Ik ben onderweg! 🚗',
      'Ik ben er over 10 minuten',
      'Ik rij nu, spreek je zo!',
      'File! Ik ben later dan verwacht',
      'Ik ben veilig aangekomen! ✅',
    ];

    // Laat gebruiker kiezen via voice
    return await _openWhatsApp(phoneNumber, templates[0]);
  }

  /// Open WhatsApp met bericht
  Future<bool> _openWhatsApp(String phoneNumber, String message) async {
    // Format phone number (remove spaces, add country code if needed)
    String formattedPhone = phoneNumber.replaceAll(RegExp(r'\s+'), '');
    if (!formattedPhone.startsWith('+')) {
      // Default to Netherlands
      formattedPhone = '+31${formattedPhone.replaceFirst(RegExp(r'^0'), '')}';
    }

    final encodedMessage = Uri.encodeComponent(message);
    
    // Try wa.me first
    final uri = Uri.parse('https://wa.me/$formattedPhone?text=$encodedMessage');
    
    // Try whatsapp:// scheme directly
    final directUri = Uri.parse('whatsapp://send?phone=$formattedPhone&text=$encodedMessage');

    try {
      // Try direct WhatsApp intent first
      try {
        await launchUrl(directUri, mode: LaunchMode.externalApplication);
        _addToRecentContacts(formattedPhone);
        return true;
      } catch (_) {
        // Fallback to web
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _addToRecentContacts(formattedPhone);
          return true;
        }
      }
    } catch (e) {
      print('WhatsApp launch error: $e');
    }

    return false;
  }

  void _addToRecentContacts(String phoneNumber) {
    // Remove if already exists
    _recentContacts.removeWhere((c) => c.phoneNumber == phoneNumber);
    
    // Add to beginning
    _recentContacts.insert(0, WhatsAppContact(
      phoneNumber: phoneNumber,
      lastUsed: DateTime.now(),
    ));

    // Keep only last 10
    if (_recentContacts.length > 10) {
      _recentContacts = _recentContacts.take(10).toList();
    }

    _saveContacts();
  }

  /// Snelle ETA templates
  List<QuickMessage> getQuickMessages({int? etaMinutes}) {
    return [
      QuickMessage(
        label: 'Onderweg!',
        message: 'Ik ben onderweg! 🚗',
        icon: Icons.directions_car,
      ),
      if (etaMinutes != null)
        QuickMessage(
          label: 'ETA: $etaMinutes min',
          message: 'Ik ben er over $etaMinutes minuten 🕐',
          icon: Icons.access_time,
        ),
      QuickMessage(
        label: 'Later',
        message: 'Ik ben later dan verwacht, file! 🚦',
        icon: Icons.traffic,
      ),
      QuickMessage(
        label: 'Aangekomen',
        message: 'Ik ben veilig aangekomen! ✅',
        icon: Icons.check_circle,
      ),
      QuickMessage(
        label: 'Bel me',
        message: 'Kan je bellen? 🔔',
        icon: Icons.phone,
      ),
    ];
  }

  /// Bereken ETA en stuur bericht
  Future<bool> sendCalculatedEta({
    required String phoneNumber,
    required double distanceKm,
    required double averageSpeedKmh,
  }) async {
    final minutes = ((distanceKm / averageSpeedKmh) * 60).round();
    return await sendEtaMessage(phoneNumber: phoneNumber, minutes: minutes);
  }

  /// Get recent contacts
  List<WhatsAppContact> get recentContacts => List.unmodifiable(_recentContacts);

  /// Add contact manually
  Future<void> addContact({required String phoneNumber, String? name}) async {
    _recentContacts.add(WhatsAppContact(
      phoneNumber: phoneNumber,
      name: name,
      lastUsed: DateTime.now(),
    ));
    await _saveContacts();
  }

  /// Set default message template
  Future<void> setDefaultMessage(String template) async {
    _defaultMessage = template;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('whatsapp_default_message', template);
  }

  void dispose() {
    _voiceService.dispose();
  }
}

class WhatsAppContact {
  final String phoneNumber;
  final String? name;
  final DateTime lastUsed;

  WhatsAppContact({
    required this.phoneNumber,
    this.name,
    required this.lastUsed,
  });

  String get displayName => name ?? phoneNumber;

  String toJson() => '$phoneNumber|$name|${lastUsed.toIso8601String()}';

  factory WhatsAppContact.fromJson(String json) {
    final parts = json.split('|');
    return WhatsAppContact(
      phoneNumber: parts[0],
      name: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
      lastUsed: DateTime.parse(parts.length > 2 ? parts[2] : DateTime.now().toIso8601String()),
    );
  }
}

class QuickMessage {
  final String label;
  final String message;
  final IconData icon;

  QuickMessage({
    required this.label,
    required this.message,
    required this.icon,
  });
}