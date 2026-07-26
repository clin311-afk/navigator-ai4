import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'screens/navigation_screen.dart';
import 'screens/camera_detection_screen.dart';
import 'screens/voice_assistant_screen.dart';
import 'utils/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: NavigatorAIApp(),
    ),
  );
}

class NavigatorAIApp extends StatelessWidget {
  const NavigatorAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navigator AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/navigate': (context) => const NavigationScreen(),
        '/camera': (context) => const CameraDetectionScreen(),
        '/assistant': (context) => const VoiceAssistantScreen(),
      },
    );
  }
}
