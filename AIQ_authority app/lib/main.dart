import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:upgrader/upgrader.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'screens/main_layout.dart';
import 'screens/login_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'services/map_cache_service.dart';
import 'services/role_service.dart';
import 'services/ward_zone_service.dart';
import 'services/trash_spots_service.dart';
import 'constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await MapCacheService.init();
  WardZoneService.instance.init();
  TrashSpotsService.instance.init();

  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('garbage_ai_url');
  if (savedUrl != null && savedUrl.isNotEmpty) {
    if (savedUrl.contains("ngrok") || savedUrl.contains("knowledgestorm")) {
      await prefs.remove("garbage_ai_url");
    } else {
      GARBAGE_AI_URL = savedUrl;
    }
  }
  final savedUrlV2 = prefs.getString('garbage_ai_v2_url');
  if (savedUrlV2 != null && savedUrlV2.isNotEmpty) {
    GARBAGE_AI_V2_URL = savedUrlV2;
  }
  final savedUrlV3 = prefs.getString('garbage_ai_v3_url');
  if (savedUrlV3 != null && savedUrlV3.isNotEmpty) {
    GARBAGE_AI_V3_URL = savedUrlV3;
  }
  final savedUrlV4 = prefs.getString('garbage_ai_v5_url');
  if (savedUrlV4 != null && savedUrlV4.isNotEmpty) {
    if (savedUrlV4.contains('pointer-staff-prodigy-v5') || savedUrlV4.contains('grumbling-tattling-schilling') || savedUrlV4.contains('disprove-chop-regalia')) {
      await prefs.remove('garbage_ai_v5_url');
    } else {
      GARBAGE_AI_V5_URL = savedUrlV4;
    }
  }
  final savedUrlV7 = prefs.getString('garbage_ai_v7_url');
  if (savedUrlV7 != null && savedUrlV7.isNotEmpty) {
    if (savedUrlV7.contains('pointer-staff-prodigy') ||
        savedUrlV7.contains('ngrok') ||
        savedUrlV7.contains('knowledgestorm') ||
        savedUrlV7.contains('copper-labs') ||
        savedUrlV7.contains('frankfurt-tour')) {
      await prefs.remove('garbage_ai_v7_url');
    } else {
      updateBackendUrl(savedUrlV7);
    }
  }
  MODEL_VERSION = 7; // Set to V7

  // Real-time Firestore sync: Any phone or web app instantly auto-syncs with live Cloudflare tunnel
  try {
    FirebaseFirestore.instance.collection('settings').doc('server_config').snapshots().listen((doc) {
      if (doc.exists && doc.data() != null) {
        final remoteUrl = doc.data()!['active_backend_url'] as String?;
        if (remoteUrl != null && remoteUrl.isNotEmpty && remoteUrl.startsWith('http')) {
          updateBackendUrl(remoteUrl);
          debugPrint('🌐 [Auto-Sync] Live Backend URL synced from Firestore: $remoteUrl');
        }
      }
    }, onError: (e) {
      debugPrint('Firestore server_config sync error: $e');
    });
  } catch (e) {
    debugPrint('Failed to attach server_config listener: $e');
  }


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
      home: kIsWeb
          ? const AppRoot()
          : UpgradeAlert(
              upgrader: Upgrader(
                storeController: UpgraderStoreController(
                  onAndroid: () => UpgraderAppcastStore(appcastURL: appcastURL),
                ),
              ),
              child: const AppRoot(),
            ),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _isLoading = true;
  bool _showLogin = false;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (isLoggedIn) {
      final role = prefs.getString('userRole');
      final zone = prefs.getString('userZone');
      final ward = prefs.getString('userWard');
      if (role != null) {
        RoleService.setCurrentUserRole(role, zone: zone, ward: ward);
      }
    }

    // Initialize RoleService (it will pull from Firestore)
    RoleService.initRoles([], []);

    setState(() {
      _showLogin = !isLoggedIn;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0F5132))),
      );
    }

    if (_showLogin) {
      return const LoginScreen();
    }

    return const MainLayout();
  }
}
