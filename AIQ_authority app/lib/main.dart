import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:upgrader/upgrader.dart';

import 'package:responsive_framework/responsive_framework.dart';
import 'screens/main_layout.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'services/map_cache_service.dart';
import 'constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await MapCacheService.init();

  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('garbage_ai_url');
  if (savedUrl != null && savedUrl.isNotEmpty) {
    GARBAGE_AI_URL = savedUrl;
  }
  final savedUrlV2 = prefs.getString('garbage_ai_v2_url');
  if (savedUrlV2 != null && savedUrlV2.isNotEmpty) {
    GARBAGE_AI_V2_URL = savedUrlV2;
  }
  final savedUrlV3 = prefs.getString('garbage_ai_v3_url');
  if (savedUrlV3 != null && savedUrlV3.isNotEmpty) {
    GARBAGE_AI_V3_URL = savedUrlV3;
  }
  MODEL_VERSION = prefs.getInt('model_version') ?? (prefs.getBool('use_v2_model') == true ? 2 : 1);


  runApp(const StreetAIQApp());
}

class StreetAIQApp extends StatelessWidget {
  const StreetAIQApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Public URL hosted via Firebase Hosting
    final appcastURL = 'https://takemytrash.web.app/appcast_authority.xml';

    return MaterialApp(
      title: 'Street AIQ',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => ResponsiveBreakpoints.builder(
        child: child!,
        breakpoints: [
          const Breakpoint(start: 0, end: 480, name: MOBILE),
          const Breakpoint(start: 481, end: 800, name: TABLET),
          const Breakpoint(start: 801, end: 1920, name: DESKTOP),
          const Breakpoint(start: 1921, end: double.infinity, name: '4K'),
        ],
      ),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0F1C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF111827),
          error: Color(0xFFEF4444),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onError: Colors.white,
        ),
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
        ),
      ),
      home: UpgradeAlert(
        upgrader: Upgrader(
          storeController: UpgraderStoreController(
            onAndroid: () => UpgraderAppcastStore(appcastURL: appcastURL),
          ),
        ),
        child: const MainLayout(),
      ),
    );
  }
}
