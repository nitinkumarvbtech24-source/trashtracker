import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:upgrader/upgrader.dart';

import 'package:responsive_framework/responsive_framework.dart';
import 'services/camera_service.dart';
import 'services/telemetry_service.dart';
import 'services/sync_service.dart';
import 'services/auth_service.dart';
import 'ui/login_screen.dart';
import 'ui/main_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock the app to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('garbage_ai_url');
  // if (savedUrl != null && savedUrl.isNotEmpty) {
  //   GARBAGE_AI_URL = savedUrl;
  // }
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => CameraService()),
        ChangeNotifierProvider(create: (_) => TelemetryService()),
        ChangeNotifierProvider(create: (_) => SyncService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Public URL hosted via Firebase Hosting
    final appcastURL = 'https://takemytrash.web.app/appcast_fleet.xml';
    final storeController = UpgraderStoreController(
      onAndroid: () => UpgraderAppcastStore(appcastURL: appcastURL),
    );

    return MaterialApp(
      title: 'Street AIQ Tipper',
      builder: (context, child) => ResponsiveBreakpoints.builder(
        child: Builder(
          builder: (context) {
            return ResponsiveScaledBox(
              width: ResponsiveValue<double?>(
                context,
                defaultValue: null,
                conditionalValues: [
                  const Condition.equals(name: MOBILE, value: 411),
                ],
              ).value,
              child: child!,
            );
          },
        ),
        breakpoints: [
          const Breakpoint(start: 0, end: 480, name: MOBILE),
          const Breakpoint(start: 481, end: 800, name: TABLET),
          const Breakpoint(start: 801, end: 1920, name: DESKTOP),
          const Breakpoint(start: 1921, end: double.infinity, name: '4K'),
        ],
      ),
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
      ),
      home: UpgradeAlert(
        upgrader: Upgrader(storeController: storeController),
        child: Consumer<AuthService>(
          builder: (context, auth, child) {
            if (!auth.isInitialized) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return auth.isLoggedIn ? const MainScreen() : const LoginScreen();
          },
        ),
      ),
    );
  }
}
