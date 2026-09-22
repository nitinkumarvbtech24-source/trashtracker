import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:responsive_framework/responsive_framework.dart';

import 'dashboard_screen.dart';
import 'fleet_screen.dart';
import 'cleanliness_screen.dart';
import 'health_screen.dart';
import 'settings_screen.dart';
import 'roles_access_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/role_service.dart';
import '../../main.dart' as app_main;
import 'comnd_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 1; // Default to Fleets & Routes for this task
  bool _isSidebarOpen = true; // Open by default based on mockup
  String _userName = 'Loading...';
  String _userRole = '...';

  Future<void> _loadUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('userName') ?? 'Admin User';
        _userRole = prefs.getString('userRole') ?? 'Super Admin';
      });
      final userZone = prefs.getString('userZone');
      final userWard = prefs.getString('userWard');
      // Set initial user role in RoleService just in case
      RoleService.setCurrentUserRole(_userRole, zone: userZone, ward: userWard);
    }
  }
  
  void _onPermissionsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadUserSession();
    if (RoleService.globalRoles == null) {
      RoleService.initRoles([], []);
    }
    RoleService.currentUserPermissions.addListener(_onPermissionsChanged);
  }

  @override
  void dispose() {
    RoleService.currentUserPermissions.removeListener(_onPermissionsChanged);
    super.dispose();
  }

  final List<Widget> _screens = [
    const RolesAccessScreen(), // 0
    const DashboardScreen(), // 1
    const FleetScreen(), // 2
    const ComndScreen(), // 3
    const CleanlinessScreen(), // 4
    const HealthScreen(), // 5
    const Scaffold(body: Center(child: Text('Reports Screen'))), // 6
    const SettingsScreen(), // 7
  ];

  @override
  Widget build(BuildContext context) {
    // Automatically hide sidebar on mobile devices
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final showSidebar = !isMobile && _isSidebarOpen;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Row(
        children: [
          if (showSidebar) _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopAppBar(isMobile),
                Expanded(
                  child: _screens[_selectedIndex],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopAppBar(bool isMobile) {
    return Container(
      color: const Color(0xFF0F5132),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _isSidebarOpen = !_isSidebarOpen;
              });
            },
            icon: const Icon(LucideIcons.menu, color: Colors.white, size: 28),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          if (!isMobile) const Expanded(child: SizedBox()), // Spacer to center title
          if (isMobile) const SizedBox(width: 12),
          Expanded(
            child: Text(
              _getAppBarTitle().toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: isMobile ? 16 : 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
              textAlign: isMobile ? TextAlign.left : TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isMobile) const Expanded(child: SizedBox()), // Spacer to center title
          Stack(
            children: [
              const Icon(LucideIcons.bell, color: Colors.white, size: 24),
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            ],
          ),
          const SizedBox(width: 16),
          const Icon(LucideIcons.userCircle, color: Colors.white, size: 24),
        ],
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0: return 'Roles & Access';
      case 1: return 'Master Dashboard';
      case 2: return 'Fleets & Route Optimization';
      case 3: return 'COM&D';
      case 4: return 'Street Cleanliness AI';
      case 5: return 'Road Health Monitor AI';
      case 6: return 'Reports';
      case 7: return 'Settings';
      default: return 'Street AIQ';
    }
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: Colors.white,
      child: Stack(
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 350,
            child: Opacity(
              opacity: 0.15,
              child: Image.network(
                'https://upload.wikimedia.org/wikipedia/commons/thumb/4/41/Skyline_silhouette.svg/1280px-Skyline_silhouette.svg.png',
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
                color: const Color(0xFF4B7171),
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (context, error, stackTrace) => const SizedBox(),
              ),
            ),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 40, bottom: 24, left: 24, right: 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'STREET\nAIQ',
                          style: TextStyle(
                            color: Color(0xFF0F5132),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            height: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 1.5,
                      color: const Color(0xFF0F5132),
                      width: 100,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'URBAN INTELLIGENCE AS A SERVICE',
                      style: TextStyle(
                        color: Color(0xFF344054),
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildNavItem(0, 'Roles & Access', LucideIcons.users),
                    const SizedBox(height: 4),
                    _buildNavItem(1, 'Master Dashboard', LucideIcons.home),
                    const SizedBox(height: 4),
                    _buildNavItem(2, 'Fleets & Routes', LucideIcons.truck),
                    const SizedBox(height: 4),
                    _buildNavItem(3, 'COM&D', LucideIcons.messageSquare),
                    const SizedBox(height: 4),
                    _buildNavItem(4, 'Street Cleanliness AI', LucideIcons.sparkles),
                    const SizedBox(height: 4),
                    _buildNavItem(5, 'Road Health Monitor AI', LucideIcons.car),
                    const SizedBox(height: 4),
                    _buildNavItem(6, 'Reports', LucideIcons.fileText),
                    const SizedBox(height: 4),
                    _buildNavItem(7, 'Settings', LucideIcons.settings),
                  ],
                ),
              ),

              PopupMenuButton<String>(
                color: Colors.white,
                offset: const Offset(0, -100),
                onSelected: (val) async {
                  if (val == 'logout' || val == 'switch') {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('isLoggedIn', false);
                    if (!mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const app_main.AppRoot()),
                      (route) => false,
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'switch', child: Text('Switch Account', style: TextStyle(color: Colors.black))),
                  const PopupMenuItem(value: 'logout', child: Text('Logout', style: TextStyle(color: Colors.red))),
                ],
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD1E7DD)),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFFD1E7DD),
                        child: Icon(Icons.person, color: Color(0xFF0F5132)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _userName,
                              style: const TextStyle(
                                color: Color(0xFF0D1B2A),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _userRole,
                              style: const TextStyle(
                                color: Color(0xFF344054),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down, color: Color(0xFF344054)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String title, IconData icon) {
    if (_userRole != 'Super Admin') {
      final perms = RoleService.getRolePermissions(_userRole);
      if (perms != null && perms[title] != null) {
        if (perms[title]['enabled'] == false) return const SizedBox.shrink();
      } else if (title == 'Roles & Access') {
        // Fallback for roles that might not have this module yet but aren't Super Admin
        return const SizedBox.shrink();
      }
    }

    final isSelected = _selectedIndex == index;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F5132) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : const Color(0xFF344054),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF344054),
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


