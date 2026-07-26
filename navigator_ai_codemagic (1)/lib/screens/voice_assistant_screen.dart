import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/voice_service.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';

class VoiceAssistantScreen extends ConsumerStatefulWidget {
  const VoiceAssistantScreen({super.key});

  @override
  ConsumerState<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends ConsumerState<VoiceAssistantScreen>
    with SingleTickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  final List<Map<String, dynamic>> _conversation = [];

  @override
  void initState() {
    super.initState();
    _voiceService.initialize();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Listen for transcripts
    _voiceService.transcriptStream.listen((transcript) {
      if (transcript.isNotEmpty) {
        setState(() {
          _conversation.add({
            'role': 'user',
            'text': transcript,
            'time': DateTime.now(),
          });
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isListening = ref.watch(voiceAssistantProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.cardBackground,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Navigator',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isListening ? AppTheme.primaryColor : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isListening ? 'Actief' : 'Standby',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Voice Visualizer
            Expanded(
              flex: 2,
              child: Center(
                child: GestureDetector(
                  onTap: _toggleListening,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Container(
                        width: isListening ? 200 * _pulseAnimation.value : 180,
                        height: isListening ? 200 * _pulseAnimation.value : 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [
                              AppTheme.primaryColor,
                              AppTheme.secondaryColor,
                            ],
                          ),
                          boxShadow: isListening
                            ? [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withOpacity( 0.4),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ]
                            : [],
                        ),
                        child: Icon(
                          isListening ? Icons.mic : Icons.mic_none,
                          size: 64,
                          color: Colors.black,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Status Text
            Text(
              isListening ? 'Luisteren...' : 'Tap om te praten',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 20,
              ),
            ),

            const SizedBox(height: 20),

            // Conversation History
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _conversation.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 48,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Start een gesprek',
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        reverse: true,
                        itemCount: _conversation.length,
                        itemBuilder: (context, index) {
                          final message = _conversation[_conversation.length - 1 - index];
                          final isUser = message['role'] == 'user';

                          return Align(
                            alignment: isUser 
                              ? Alignment.centerRight 
                              : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.7,
                              ),
                              decoration: BoxDecoration(
                                color: isUser 
                                  ? AppTheme.primaryColor 
                                  : Colors.grey[800],
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                                  bottomRight: Radius.circular(isUser ? 4 : 16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message['text'] ?? '',
                                    style: TextStyle(
                                      color: isUser ? Colors.black : Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTime(message['time'] as DateTime),
                                    style: TextStyle(
                                      color: isUser 
                                        ? Colors.black54 
                                        : Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),

            const SizedBox(height: 20),

            // Quick Commands
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Snelle commando\'s',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildQuickCommand('Navigeer naar huis', Icons.home),
                      _buildQuickCommand('Snelste route', Icons.timer),
                      _buildQuickCommand('Tankstations', Icons.local_gas_station),
                      _buildQuickCommand('Parkeergarages', Icons.local_parking),
                      _buildQuickCommand('Flitsers check', Icons.camera_alt),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCommand(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _conversation.add({
            'role': 'user',
            'text': label,
            'time': DateTime.now(),
          });
        });
        _processCommand(label);
      },
      child: Chip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        backgroundColor: AppTheme.cardBackground,
        side: const BorderSide(color: Colors.grey),
      ),
    );
  }

  void _toggleListening() async {
    final isListening = ref.read(voiceAssistantProvider);
    
    if (isListening) {
      await _voiceService.stopListening();
      ref.read(voiceAssistantProvider.notifier).state = false;
    } else {
      setState(() {
        _conversation.add({
          'role': 'user',
          'text': '...',
          'time': DateTime.now(),
        });
      });
      ref.read(voiceAssistantProvider.notifier).state = true;
      await _voiceService.startListening();
    }
  }

  void _processCommand(String command) async {
    // Simulate processing delay
    await Future.delayed(const Duration(seconds: 1));

    String response;
    final lowerCmd = command.toLowerCase();

    if (lowerCmd.contains('thuis') || lowerCmd.contains('huis')) {
      response = 'Ik bereken de route naar huis. Rijd veilig!';
    } else if (lowerCmd.contains('snelst') || lowerCmd.contains('route')) {
      response = 'De snelste route bespaart 5 minuten. Wil je deze nemen?';
    } else if (lowerCmd.contains('tank')) {
      response = 'Het dichtstbijzijnde tankstation is 2 km verderop.';
    } else if (lowerCmd.contains('parkeer')) {
      response = 'Ik zoek parkeergarages in de buurt van je bestemming.';
    } else if (lowerCmd.contains('flitser') || lowerCmd.contains('camera')) {
      response = 'Ik scan de weg voor flitspalen. Blijf alert!';
    } else {
      response = 'Ik begrijp je vraag. Laat me dat voor je uitzoeken.';
    }

    setState(() {
      _conversation.add({
        'role': 'assistant',
        'text': response,
        'time': DateTime.now(),
      });
    });

    await _voiceService.speak(response);
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _voiceService.dispose();
    super.dispose();
  }
}
