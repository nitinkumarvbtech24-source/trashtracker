import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:responsive_framework/responsive_framework.dart';

import 'dashboard_screen.dart';
import 'fleet_screen.dart';
import 'cleanliness_screen.dart';
import 'health_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'roles_access_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/role_service.dart';
import '../services/trash_spots_service.dart';
import '../../main.dart' as app_main;
import 'comnd_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 1; // Default to Fleets & Routes for this task
  bool _isSidebarOpen = true; // Open by default based on mockup
  String _userName = 'Loading...';
  String _userRole = '...';

  // Real-time Area-Scoped Notifications State
  StreamSubscription? _trashSpotsSub;
  StreamSubscription? _complaintsSub;
  List<Map<String, dynamic>> _areaNotifications = [];
  int _unreadCount = 0;

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
      _processNotifications();
    }
  }
  
  void _onPermissionsChanged() {
    if (mounted) {
      setState(() {});
      _processNotifications();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUserSession();
    if (RoleService.globalRoles == null) {
      RoleService.initRoles([], []);
    }
    RoleService.currentUserPermissions.addListener(_onPermissionsChanged);
    _startAreaNotificationListener();
  }

  void _startAreaNotificationListener() {
    _trashSpotsSub = FirebaseFirestore.instance
        .collection('trash_spots')
        .snapshots()
        .listen((snap) {
      _processNotifications();
    });

    TrashSpotsService.instance.flagsNotifier.addListener(_processNotifications);

    _complaintsSub = FirebaseFirestore.instance
        .collection('user_complaints')
        .snapshots()
        .listen((snap) {
      _processNotifications();
    });
  }

  Future<void> _processNotifications() async {
    if (!mounted) return;
    try {
      final List<Map<String, dynamic>> alerts = [];

      // A. Trash Spots
      final spotsSnap = await FirebaseFirestore.instance.collection('trash_spots').limit(40).get();
      for (var doc in spotsSnap.docs) {
        final d = doc.data();
        final lat = ((d['lat'] ?? 0.0) as num).toDouble();
        final lng = ((d['lng'] ?? 0.0) as num).toDouble();
        final z = (d['zone'] ?? '').toString();
        final w = (d['ward'] ?? '').toString();

        // Area-scoping check: ONLY notify if spot is allowed for user's assigned area!
        if (!RoleService.isSpotAllowed(lat, lng, z, w, 'COM&D')) continue;

        final isCleaned = d['status'] == 'Deflagged';
        final roadStatus = (d['road_status'] ?? 'Trash Detected').toString();
        final vehicle = (d['vehicle_number'] ?? 'Fleet').toString();

        DateTime dt = DateTime.now();
        if (d['timestamp'] is Timestamp) {
          dt = (d['timestamp'] as Timestamp).toDate();
        }

        alerts.add({
          'id': doc.id,
          'type': isCleaned ? 'cleaned' : 'trash',
          'title': isCleaned ? 'Spot Cleared: $w' : 'Trash Detected: $roadStatus',
          'subtitle': isCleaned 
              ? 'Cleaned & deflagged in $w, $z' 
              : 'Flagged by vehicle $vehicle in $w ($z)',
          'time': dt,
          'timeAgo': _formatTimeAgo(dt),
          'isUnread': !isCleaned,
        });
      }

      // B. User Complaints
      final compSnap = await FirebaseFirestore.instance.collection('user_complaints').limit(20).get();
      for (var doc in compSnap.docs) {
        final d = doc.data();
        final lat = ((d['lat'] ?? 0.0) as num).toDouble();
        final lng = ((d['lng'] ?? 0.0) as num).toDouble();
        final z = (d['zone'] ?? '').toString();
        final w = (d['ward'] ?? '').toString();

        if (!RoleService.isSpotAllowed(lat, lng, z, w, 'COM&D')) continue;

        DateTime dt = DateTime.now();
        if (d['created_at'] is Timestamp) {
          dt = (d['created_at'] as Timestamp).toDate();
        }

        alerts.add({
          'id': doc.id,
          'type': 'complaint',
          'title': 'Citizen Report: ${d['category'] ?? 'Complaint'}',
          'subtitle': '${d['comment'] ?? 'User complaint'} in $w',
          'time': dt,
          'timeAgo': _formatTimeAgo(dt),
          'isUnread': d['status'] != 'Resolved',
        });
      }

      alerts.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));

      if (mounted) {
        setState(() {
          _areaNotifications = alerts.take(25).toList();
          _unreadCount = _areaNotifications.where((a) => a['isUnread'] == true).length;
        });
      }
    } catch (e) {
      debugPrint("Error processing notifications: $e");
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void dispose() {
    RoleService.currentUserPermissions.removeListener(_onPermissionsChanged);
    TrashSpotsService.instance.flagsNotifier.removeListener(_processNotifications);
    _trashSpotsSub?.cancel();
    _complaintsSub?.cancel();
    super.dispose();
  }

  final List<Widget> _screens = [
    const RolesAccessScreen(), // 0
    const DashboardScreen(), // 1
    const FleetScreen(), // 2
    const ComndScreen(), // 3
    const CleanlinessScreen(), // 4
    const HealthScreen(), // 5
    const ReportsScreen(), // 6
    const SettingsScreen(), // 7
  ];

  @override
  Widget build(BuildContext context) {
    // Automatically hide sidebar on mobile devices
    final isMobile = ResponsiveBreakpoints.of(context).smallerOrEqualTo(TABLET) || MediaQuery.of(context).size.width < 800;
    final showSidebar = !isMobile && _isSidebarOpen;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FA),
      drawer: isMobile ? Drawer(child: _buildSidebar(isDrawer: true)) : null,
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
    final titleWidget = Text(
      _getAppBarTitle().toUpperCase(),
      style: TextStyle(
        color: Colors.white,
        fontSize: isMobile ? 16 : 20,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
      textAlign: isMobile ? TextAlign.left : TextAlign.center,
      overflow: TextOverflow.ellipsis,
    );

    return Container(
      color: const Color(0xFF0F5132),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 14),
      child: isMobile
          ? Row(
              children: [
                IconButton(
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  icon: const Icon(LucideIcons.menu, color: Colors.white, size: 28),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                Expanded(child: titleWidget),
                _buildTopAppBarActions(),
              ],
            )
          : Stack(
              alignment: Alignment.center,
              children: [
                // Centered Screen Heading
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 160),
                    child: titleWidget,
                  ),
                ),
                // Left & Right Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    _buildTopAppBarActions(),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildTopAppBarActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'AI Model Settings',
          onPressed: _showAISettingsDialog,
          icon: const Icon(LucideIcons.sliders, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Area Notifications',
          onPressed: _showNotificationsSheet,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(LucideIcons.bell, color: Colors.white, size: 24),
              if (_unreadCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      _unreadCount > 9 ? '9+' : '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(LucideIcons.userCircle, color: Colors.white, size: 24),
      ],
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

  void _showNotificationsSheet() {
    final userWard = RoleService.currentUserWard;
    final userZone = RoleService.currentUserZone;
    final scopeLabel = (userWard != null && userWard.isNotEmpty && userWard != 'All Wards')
        ? userWard
        : (userZone != null && userZone.isNotEmpty && userZone != 'All Zones')
            ? userZone
            : 'Citywide Jurisdiction';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.bellRing, color: Color(0xFF0F5132), size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Area Notifications',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Scoped to $scopeLabel • Only your jurisdiction',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(LucideIcons.x, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Alerts List
            Expanded(
              child: _areaNotifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.bellOff, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text('No active notifications for $scopeLabel',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                          const SizedBox(height: 4),
                          const Text('Real-time alerts detected in your area will appear here',
                              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _areaNotifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final alert = _areaNotifications[index];
                        final type = alert['type'];
                        final isCleaned = type == 'cleaned';
                        final isComplaint = type == 'complaint';
                        final isUnread = alert['isUnread'] == true;

                        return Container(
                          decoration: BoxDecoration(
                            color: isUnread ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isUnread ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
                              width: isUnread ? 1.5 : 1,
                            ),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isCleaned
                                    ? const Color(0xFFD1FAE5)
                                    : isComplaint
                                        ? const Color(0xFFFEF3C7)
                                        : const Color(0xFFFEE2E2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isCleaned
                                    ? LucideIcons.checkCheck
                                    : isComplaint
                                        ? LucideIcons.messageSquare
                                        : LucideIcons.alertTriangle,
                                color: isCleaned
                                    ? const Color(0xFF059669)
                                    : isComplaint
                                        ? const Color(0xFFD97706)
                                        : const Color(0xFFDC2626),
                                size: 18,
                              ),
                            ),
                            title: Text(
                              alert['title'],
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(alert['subtitle'], style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                                const SizedBox(height: 4),
                                Text(alert['timeAgo'], style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                              ],
                            ),
                            trailing: const Icon(LucideIcons.chevronRight, size: 16, color: Color(0xFF94A3B8)),
                            onTap: () {
                              Navigator.pop(ctx);
                              // Switch directly to COM&D tab
                              setState(() {
                                _selectedIndex = 3;
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar({bool isDrawer = false}) {
    return Container(
      width: isDrawer ? null : 260,
      color: Colors.white,
      child: SafeArea(
        top: isDrawer,
        bottom: isDrawer,
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
                  padding: EdgeInsets.only(top: isDrawer ? 20 : 40, bottom: 24, left: 24, right: 24),
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
                      _buildNavItem(0, 'Roles & Access', LucideIcons.users, isDrawer: isDrawer),
                      const SizedBox(height: 4),
                      _buildNavItem(1, 'Master Dashboard', LucideIcons.home, isDrawer: isDrawer),
                      const SizedBox(height: 4),
                      _buildNavItem(2, 'Fleets & Routes', LucideIcons.truck, isDrawer: isDrawer),
                      const SizedBox(height: 4),
                      _buildNavItem(3, 'COM&D', LucideIcons.messageSquare, isDrawer: isDrawer),
                      const SizedBox(height: 4),
                      _buildNavItem(4, 'Street Cleanliness AI', LucideIcons.sparkles, isDrawer: isDrawer),
                      const SizedBox(height: 4),
                      _buildNavItem(5, 'Road Health Monitor AI', LucideIcons.car, isDrawer: isDrawer),
                      const SizedBox(height: 4),
                      _buildNavItem(6, 'Reports', LucideIcons.fileText, isDrawer: isDrawer),
                      const SizedBox(height: 4),
                      _buildNavItem(7, 'Settings', LucideIcons.settings, isDrawer: isDrawer),
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
    ),
  );
}

  Widget _buildNavItem(int index, String title, IconData icon, {bool isDrawer = false}) {
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
        if (isDrawer) {
          Navigator.of(context).pop();
        }
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

  void _showAISettingsDialog() async {
    final baseUrl = activeGarbageAiUrl;
    
    double currentThreshold = 0.25;
    double veryDirtyThreshold = 0.50;
    bool isLoading = true;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (isLoading) {
              http.get(Uri.parse('$baseUrl/api/settings')).then((res) {
                if (res.statusCode == 200) {
                  final data = json.decode(res.body);
                  setDialogState(() {
                    currentThreshold = (data['confidence_threshold'] as num?)?.toDouble() ?? 0.25;
                    veryDirtyThreshold = (data['very_dirty_threshold'] as num?)?.toDouble() ?? 0.50;
                    isLoading = false;
                  });
                } else {
                  setDialogState(() => isLoading = false);
                }
              }).catchError((e) {
                setDialogState(() => isLoading = false);
              });
            }
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F5132).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(LucideIcons.sliders, color: Color(0xFF0F5132), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('AI Model Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: isLoading 
                ? const SizedBox(height: 140, child: Center(child: CircularProgressIndicator(color: Color(0xFF0F5132))))
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section 1: Very Dirty Road Confidence Level Setter (MobileNetV3)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red),
                                      SizedBox(width: 6),
                                      Text('Very Dirty Road Confidence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text('${(veryDirtyThreshold * 100).toInt()}%', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Slider(
                                value: veryDirtyThreshold,
                                min: 0.20,
                                max: 0.95,
                                divisions: 15,
                                activeColor: Colors.redAccent,
                                label: '${(veryDirtyThreshold * 100).toInt()}%',
                                onChanged: (val) {
                                  setDialogState(() => veryDirtyThreshold = val);
                                },
                              ),
                              Wrap(
                                spacing: 6,
                                children: [0.35, 0.50, 0.70, 0.85].map((preset) {
                                  final isSel = (veryDirtyThreshold - preset).abs() < 0.03;
                                  return ChoiceChip(
                                    label: Text('${(preset * 100).toInt()}%', style: TextStyle(fontSize: 11, color: isSel ? Colors.white : Colors.black87)),
                                    selected: isSel,
                                    selectedColor: Colors.redAccent,
                                    backgroundColor: Colors.white,
                                    onSelected: (_) => setDialogState(() => veryDirtyThreshold = preset),
                                    visualDensity: VisualDensity.compact,
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 6),
                              const Text('MobileNetV3 classifier threshold required to escalate trash-detected road frames to "VERY DIRTY ROAD" (red alert).', style: TextStyle(fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Section 2: YOLO Detection Confidence
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F5132).withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF0F5132).withOpacity(0.15)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('YOLO Detection Confidence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F5132))),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F5132).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text('${(currentThreshold * 100).toInt()}%', style: const TextStyle(color: Color(0xFF0F5132), fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Slider(
                                value: currentThreshold,
                                min: 0.1,
                                max: 0.9,
                                divisions: 16,
                                activeColor: const Color(0xFF0F5132),
                                label: '${(currentThreshold * 100).toInt()}%',
                                onChanged: (val) {
                                  setDialogState(() => currentThreshold = val);
                                },
                              ),
                              Wrap(
                                spacing: 6,
                                children: [0.15, 0.25, 0.40, 0.60].map((preset) {
                                  final isSel = (currentThreshold - preset).abs() < 0.03;
                                  return ChoiceChip(
                                    label: Text('${(preset * 100).toInt()}%', style: TextStyle(fontSize: 11, color: isSel ? Colors.white : Colors.black87)),
                                    selected: isSel,
                                    selectedColor: const Color(0xFF0F5132),
                                    backgroundColor: Colors.white,
                                    onSelected: (_) => setDialogState(() => currentThreshold = preset),
                                    visualDensity: VisualDensity.compact,
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 6),
                              const Text('Initial candidate threshold: Lower = more detections, higher false positives; Higher = strictly visible trash.', style: TextStyle(fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    setDialogState(() => isLoading = true);
                    try {
                      await http.post(
                        Uri.parse('$baseUrl/api/settings'),
                        headers: {'Content-Type': 'application/json'},
                        body: json.encode({
                          'confidence_threshold': currentThreshold,
                          'very_dirty_threshold': veryDirtyThreshold,
                        }),
                      );
                    } catch (e) {}
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
                  child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }
}


