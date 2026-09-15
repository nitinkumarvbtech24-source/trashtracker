import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/auth_service.dart';
import '../services/telemetry_service.dart';
import 'map_screen.dart';
import 'reports_screen.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import 'dart:ui';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isInitializingPermissions = true;

  final List<Widget> _screens = [
    const MapScreen(),
    const ReportsScreen(),
    const CameraScreen(),
    const GalleryScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initializePermissions();
  }

  Future<void> _initializePermissions() async {
    if (!kIsWeb) {
      [
        Permission.camera,
        Permission.microphone,
      ].request().catchError((e) {
        debugPrint("Permission error: $e");
        return <Permission, PermissionStatus>{};
      });
    }

    // 2. GPS Location Permissions
    TelemetryService().initialize().catchError((e) {
      debugPrint("Error initializing telemetry: $e");
    });

    if (mounted) {
      setState(() {
        _isInitializingPermissions = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializingPermissions) {
      return Scaffold(
        backgroundColor: const Color(0xFF020617),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.blueAccent),
              const SizedBox(height: 24),
              Text(
                'Securing Connection & GPS...',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16),
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F172A), Colors.transparent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tipper Dashboard', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 0.5)),
            Consumer<AuthService>(
              builder: (context, auth, _) => Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.greenAccent, blurRadius: 4)]),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Vehicle: ${auth.vehicleNumber ?? "Unknown"}',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.blueAccent, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      extendBody: true, // Allows body to extend under the floating dock
      body: Stack(
        children: [
          // Background subtle gradients
          Positioned(
            top: -100, right: -100,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent.withOpacity(0.05)),
            ),
          ),
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),

        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.7),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: BottomNavigationBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  type: BottomNavigationBarType.fixed,
                  currentIndex: _currentIndex,
                  selectedItemColor: Colors.blueAccent,
                  unselectedItemColor: Colors.white54,
                  selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11),
                  unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11),
                  showUnselectedLabels: false,
                  onTap: (index) => setState(() => _currentIndex = index),
                  items: [
                    _buildNavItem(Icons.map_rounded, 'Route', 0),
                    _buildNavItem(Icons.history_rounded, 'Reports', 1),
                    _buildNavItem(Icons.video_library_rounded, 'Cam', 2),
                    _buildNavItem(Icons.flag_rounded, 'Flags', 3),
                    _buildNavItem(Icons.settings_rounded, 'Settings', 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    return BottomNavigationBarItem(
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, size: isSelected ? 28 : 24),
      ),
      label: label,
    );
  }
}
