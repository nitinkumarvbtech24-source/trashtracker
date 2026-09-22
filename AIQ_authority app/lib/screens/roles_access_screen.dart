import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../models/ward.dart';
import '../models/zone.dart';
import '../services/role_service.dart';
import 'officers_list_screen.dart';

enum ResourceMapMode { view, drawWard, drawZone }

class RolesAccessScreen extends StatefulWidget {
  const RolesAccessScreen({super.key});

  @override
  State<RolesAccessScreen> createState() => _RolesAccessScreenState();
}

class _RolesAccessScreenState extends State<RolesAccessScreen> {
  int _selectedTabIndex = 0; // 0 for Role Management, 1 for User Management
  int _selectedRoleIndex = 2; // Default select Zone Officer

  // List of all available modules in the permissions section
  final List<String> _modules = [
    'Master Dashboard',
    'Fleets & Routes',
    'COM&D',
    'Street Cleanliness AI',
    'Road Health Monitor AI',
    'Reports',
    'Roles & Access',
    'Settings'
  ];

  List<String> _allZones = [];
  List<String> _allWards = [];
  List<Zone> _zoneModels = [];
  List<Ward> _wardModels = [];
  StreamSubscription<QuerySnapshot>? _wardsSub;
  StreamSubscription<QuerySnapshot>? _zonesSub;

  bool _isWardInZone(Ward ward, Zone zone) {
    if (ward.boundary.isEmpty || zone.boundary.isEmpty) return true; // Fallback for dummy data without bounds
    double cLat = 0, cLng = 0;
    for(var p in ward.boundary) { cLat += p.latitude; cLng += p.longitude; }
    LatLng centroid = LatLng(cLat / ward.boundary.length, cLng / ward.boundary.length);

    int intersectCount = 0;
    for (int j = 0; j < zone.boundary.length - 1; j++) {
      if (_rayCastIntersect(centroid, zone.boundary[j], zone.boundary[j + 1])) {
        intersectCount++;
      }
    }
    if (_rayCastIntersect(centroid, zone.boundary.last, zone.boundary.first)) intersectCount++;
    return (intersectCount % 2) == 1;
  }

  bool _rayCastIntersect(LatLng point, LatLng vertA, LatLng vertB) {
    double aY = vertA.latitude, bY = vertB.latitude;
    double aX = vertA.longitude, bX = vertB.longitude;
    double pY = point.latitude, pX = point.longitude;
    if ((aY > pY && bY > pY) || (aY < pY && bY < pY) || (aX < pX && bX < pX)) return false;
    if (aY == bY) return false;
    double m = (aX - bX) / (aY - bY);
    double x = aX + m * (pY - aY);
    return x > pX;
  }

  // Helper methods removed; moved to RoleService

  late List<Map<String, dynamic>> _roles;

  // Expansion panel states for modules
  final List<bool> _moduleExpanded = [true, false, false, false, false, false, false, false];

  // User Management State
  List<Map<String, dynamic>> _users = [];
  StreamSubscription<QuerySnapshot>? _usersSub;
  String _searchQuery = '';
  String _filterRole = 'All Roles';
  String _filterStatus = 'All Status';
  
  // User Form State
  int? _editingUserIndex;
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _userEmailController = TextEditingController();
  final TextEditingController _userPhoneController = TextEditingController();
  final TextEditingController _userPasswordController = TextEditingController();
  final TextEditingController _userConfirmPasswordController = TextEditingController();
  String? _selectedFormRole;
  String? _selectedFormZone;
  String? _selectedFormWard;
  bool _isUserFormVisible = false;

  // Resource Management State
  List<Map<String, dynamic>> _vehicles = [];
  StreamSubscription<QuerySnapshot>? _vehiclesSub;
  String _searchResourceQuery = '';
  String _filterResourceStatus = 'All Status';
  bool _isResourceFormVisible = false;
  int? _editingResourceIndex;

  int _resourceNavIndex = 0; // 0: Vehicles, 1: Maps
  ResourceMapMode _currentMapMode = ResourceMapMode.view;
  List<LatLng> _drawingPoints = [];
  Zone? _selectedZoneForMap;
  Ward? _selectedWardForMap;
  bool _showSidebars = true;
  bool _showDirectoryPanel = false;
  Zone? _dashboardSelectedZone;
  Ward? _dashboardSelectedWard;
  String? _editingRegionId;
  String? _editingRegionName;
  final MapController _mapController = MapController();

  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _vehicleDriverNameController = TextEditingController();
  final TextEditingController _vehiclePhoneController = TextEditingController();
  final TextEditingController _vehiclePasswordController = TextEditingController();
  String? _selectedResourceZone;
  String? _selectedResourceWard;

  void _onRolesUpdated() {
    if (mounted) {
      setState(() {
        _roles = RoleService.globalRoles ?? [];
        if (_selectedRoleIndex >= _roles.length) {
          _selectedRoleIndex = _roles.isEmpty ? -1 : 0;
        }
      });
    }
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _vehiclesSub?.cancel();
    _wardsSub?.cancel();
    _zonesSub?.cancel();
    _mapController.dispose();
    _userNameController.dispose();
    _userEmailController.dispose();
    _userPhoneController.dispose();
    _userPasswordController.dispose();
    _userConfirmPasswordController.dispose();
    _vehicleNumberController.dispose();
    _vehicleDriverNameController.dispose();
    _vehiclePhoneController.dispose();
    _vehiclePasswordController.dispose();
    RoleService.rolesUpdated.removeListener(_onRolesUpdated);
    super.dispose();
  }

  void _fetchZonesAndWards() {
    _zonesSub = FirebaseFirestore.instance.collection('zones').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _zoneModels = snapshot.docs.map((doc) => Zone.fromJson(doc.id, doc.data())).toList();
        _allZones = _zoneModels.map((z) => z.name).toList();
      });
    });

    _wardsSub = FirebaseFirestore.instance.collection('wards').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _wardModels = snapshot.docs.map((doc) => Ward.fromJson(doc.id, doc.data())).toList();
        _allWards = _wardModels.map((w) => w.name).toList();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchZonesAndWards();
    
    RoleService.initRoles(_allZones, _allWards);
    _roles = RoleService.globalRoles ?? [];
    RoleService.rolesUpdated.addListener(_onRolesUpdated);

    _usersSub = FirebaseFirestore.instance.collection('authority_users').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _users = snapshot.docs.map((doc) {
          var data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      });
    });

    _vehiclesSub = FirebaseFirestore.instance.collection('vehicles').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _vehicles = snapshot.docs.map((doc) {
          var data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      });
    });
  }

  void _showCreateEditRoleDialog({int? editIndex}) {
    final isEditing = editIndex != null;
    final role = isEditing ? _roles[editIndex] : null;

    final titleController = TextEditingController(text: role?['title'] ?? '');
    final subtitleController = TextEditingController(text: role?['subtitle'] ?? '');

    // For simplicity in this mock, assign a random color/icon for new roles
    final iconColor = role?['color'] ?? const Color(0xFF06B6D4);
    final bgColor = role?['bgColor'] ?? const Color(0xFFCFFAFE);
    final icon = role?['icon'] ?? LucideIcons.userPlus;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(isEditing ? 'Edit Role' : 'Create New Role', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    labelText: 'Role Name',
                    labelStyle: TextStyle(color: Colors.black54),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.black26)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF0F5132))),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: subtitleController,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    labelText: 'Subtitle Description',
                    labelStyle: TextStyle(color: Colors.black54),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.black26)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF0F5132))),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.black)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
              onPressed: () async {
                if (titleController.text.trim().isEmpty) return;
                
                final newRole = isEditing 
                    ? Map<String, dynamic>.from(_roles[editIndex])
                    : {
                        'title': titleController.text,
                        'subtitle': subtitleController.text,
                        'icon': icon,
                        'users': 0,
                        'isSystem': false,
                        'color': iconColor,
                        'bgColor': bgColor,
                        'permissions': RoleService.generateDefaultPermissionsForNewRole(),
                      };
                
                if (isEditing) {
                  newRole['title'] = titleController.text;
                  newRole['subtitle'] = subtitleController.text;
                }
                
                // Show loading indicator or handle state if needed
                await RoleService.saveRole(newRole);
                
                if (mounted) Navigator.pop(context);
              },
              child: Text(isEditing ? 'Save Changes' : 'Create Role', style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(int index) {
    if (_roles[index]['isSystem']) return; // Cannot delete system role
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Delete Role', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          content: Text('Are you sure you want to delete the role "${_roles[index]['title']}"? This action cannot be undone.', style: const TextStyle(color: Colors.black87)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.black)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC3545)),
              onPressed: () async {
                final roleTitle = _roles[index]['title'];
                await RoleService.deleteRole(roleTitle);
                
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTabs(),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _selectedTabIndex == 0
                  ? [ _buildDashboardTab() ]
                  : _selectedTabIndex == 1
                    ? [
                        _buildLeftColumn(),
                        const SizedBox(width: 24),
                        _buildRightColumn(),
                      ]
                    : _selectedTabIndex == 2
                      ? [
                          _buildUserManagementLeftColumn(),
                          if (_isUserFormVisible) const SizedBox(width: 24),
                          if (_isUserFormVisible) _buildUserManagementRightColumn(),
                        ]
                      : [
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  child: _resourceNavIndex == 0
                                    ? Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildResourceManagementLeftColumn(),
                                          if (_isResourceFormVisible) const SizedBox(width: 24),
                                          if (_isResourceFormVisible) _buildResourceManagementRightColumn(),
                                        ],
                                      )
                                    : _buildResourceMapMode(),
                                ),
                                _buildResourceBottomNav(),
                              ],
                            ),
                          )
                        ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _buildTabItem('Region Dashboard', 0),
          const SizedBox(width: 32),
          _buildTabItem('Role Management', 1),
          const SizedBox(width: 32),
          _buildTabItem('User Management', 2),
          const SizedBox(width: 32),
          _buildTabItem('Resource Management', 3),
        ],
      ),
    );
  }

  Widget _buildTabItem(String title, int index) {
    bool isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? const Color(0xFF0F5132) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? const Color(0xFF0F5132) : const Color(0xFF64748B),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildLeftColumn() {
    return Expanded(
      flex: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Roles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  SizedBox(height: 4),
                  Text('Manage system roles and permissions', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _showCreateEditRoleDialog,
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('Create Role', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F5132),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const TextField(
              style: TextStyle(color: Colors.black),
              decoration: InputDecoration(
                icon: Icon(LucideIcons.search, color: Color(0xFF94A3B8), size: 18),
                hintText: 'Search roles...',
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: _roles.isEmpty 
              ? const Center(child: Text('No roles found.')) 
              : ListView.separated(
                  itemCount: _roles.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  itemBuilder: (context, index) {
                    return _buildRoleCard(index, _roles[index]);
                  },
                ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCard(int index, Map<String, dynamic> role) {
    bool isSelected = index == _selectedRoleIndex;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedRoleIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0FDF4) : Colors.transparent, // Very light green when selected
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: role['bgColor'],
                shape: BoxShape.circle,
              ),
              child: Icon(role['icon'], color: role['color'], size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(role['title'], style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), fontSize: 14)),
                      if (role['isSystem']) const SizedBox(width: 8),
                      if (role['isSystem'])
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('System Role', style: TextStyle(color: Color(0xFF16A34A), fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(role['subtitle'], style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Users', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                Text('${_users.where((u) => u['role'] == role['title']).length}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), fontSize: 14)),
              ],
            ),
            const SizedBox(width: 16),
            // Actions menu
            PopupMenuButton<String>(
              color: Colors.white,
              icon: const Icon(LucideIcons.moreVertical, color: Color(0xFF94A3B8), size: 18),
              onSelected: (val) {
                if (val == 'edit') {
                  _showCreateEditRoleDialog(editIndex: index);
                } else if (val == 'delete') {
                  _showDeleteConfirmationDialog(index);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit Role', style: TextStyle(color: Colors.black))),
                if (!role['isSystem']) const PopupMenuItem(value: 'delete', child: Text('Delete Role', style: TextStyle(color: Colors.red))),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRightColumn() {
    if (_roles.isEmpty) return const Expanded(flex: 5, child: SizedBox());

    final currentRole = _roles[_selectedRoleIndex];

    return Expanded(
      flex: 5,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Role Permissions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    SizedBox(height: 4),
                    Text('Configure detailed permissions for the selected role', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
                Row(
                  children: [
                    const Text('Select Role', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          dropdownColor: Colors.white,
                          value: _selectedRoleIndex,
                          icon: const Icon(LucideIcons.chevronDown, size: 14, color: Color(0xFF64748B)),
                          items: List.generate(_roles.length, (index) {
                            return DropdownMenuItem(
                              value: index,
                              child: Text(_roles[index]['title'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black)),
                            );
                          }),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedRoleIndex = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: [
                  _buildModulePanel('Master Dashboard', LucideIcons.home, 0, currentRole),
                  const SizedBox(height: 12),
                  _buildModulePanel('Fleets & Routes', LucideIcons.truck, 1, currentRole),
                  const SizedBox(height: 12),
                  _buildModulePanel('COM&D', LucideIcons.messageSquare, 2, currentRole),
                  const SizedBox(height: 12),
                  _buildModulePanel('Street Cleanliness AI', LucideIcons.sparkles, 3, currentRole),
                  const SizedBox(height: 12),
                  _buildModulePanel('Road Health Monitor AI', LucideIcons.car, 4, currentRole),
                  const SizedBox(height: 12),
                  _buildModulePanel('Reports', LucideIcons.fileText, 5, currentRole, isExport: true),
                  const SizedBox(height: 12),
                  _buildModulePanel('Roles & Access', LucideIcons.users, 6, currentRole),
                  const SizedBox(height: 12),
                  _buildModulePanel('Settings', LucideIcons.settings, 7, currentRole, isSettings: true),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await RoleService.saveRole(currentRole);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Permissions saved successfully!'),
                              backgroundColor: Color(0xFF0F5132),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(LucideIcons.save, size: 16, color: Colors.white),
                      label: const Text('Save Permissions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5132),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyPermissionsToAllModules(String sourceModuleName) {
    if (_selectedRoleIndex < 0 || _selectedRoleIndex >= _roles.length) return;
    
    final role = _roles[_selectedRoleIndex];
    final perms = role['permissions'] as Map<String, dynamic>;
    final sourcePerms = perms[sourceModuleName] as Map<String, dynamic>;
    
    setState(() {
      for (String mod in _modules) {
        if (mod == sourceModuleName) continue;
        
        final targetPerms = perms[mod] as Map<String, dynamic>;
        
        targetPerms['enabled'] = sourcePerms['enabled'] ?? (sourcePerms['actions']?['view'] ?? false);
        targetPerms['viewAccess'] = sourcePerms['viewAccess'];
        targetPerms['zones'] = List<String>.from(sourcePerms['zones']);
        targetPerms['wards'] = List<String>.from(sourcePerms['wards']);
        
        if (sourcePerms['actions'] != null && targetPerms['actions'] != null) {
          targetPerms['actions'] = Map<String, dynamic>.from(sourcePerms['actions']);
        }
        
        if (sourcePerms.containsKey('export') && targetPerms.containsKey('export')) {
          targetPerms['export'] = sourcePerms['export'];
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Permissions applied to all modules successfully.'),
        backgroundColor: Color(0xFF0F5132),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildModulePanel(String moduleName, IconData icon, int index, Map<String, dynamic> currentRole, {bool isExport = false, bool isSettings = false}) {
    Map<String, dynamic> perms = currentRole['permissions'][moduleName];
    bool isEnabled = perms['enabled'] ?? (perms['actions']?['view'] ?? false);
    bool isExpanded = _moduleExpanded[index];
    List<String> selectedZones = List<String>.from(perms['zones'] ?? []);
    List<String> selectedWards = List<String>.from(perms['wards'] ?? []);

    List<String> allZonesOptions = ['All Zones', ..._allZones];
    List<String> availableZones = allZonesOptions.where((z) => !selectedZones.contains(z)).toList();
    List<String> allWardsOptions = ['All Wards', ..._allWards];
    List<String> validWards = allWardsOptions;
    
    if (selectedZones.isNotEmpty && !selectedZones.contains('All Zones')) {
      validWards = _wardModels.where((w) {
        if (w.boundary.isEmpty) return false;
        bool inAnyZone = false;
        for (String zoneName in selectedZones) {
          try {
            final z = _zoneModels.firstWhere((zm) => zm.name == zoneName);
            if (_isWardInZone(w, z)) {
              inAnyZone = true;
              break;
            }
          } catch (_) {}
        }
        return inAnyZone;
      }).map((w) => w.name).toList();
      validWards.insert(0, 'All Wards');
      
      // Fallback: If spatial logic filtered out EVERYTHING (e.g. dummy data without polygons),
      // just show all wards so the user isn't stuck with an empty dropdown.
      if (validWards.length == 1 && validWards.first == 'All Wards') {
        validWards = List<String>.from(allWardsOptions);
      }
    }
    List<String> availableWards = validWards.where((w) => !selectedWards.contains(w)).toList();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header (Clickable to expand/collapse)
          InkWell(
            onTap: () {
              setState(() {
                _moduleExpanded[index] = !_moduleExpanded[index];
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: isExpanded ? const Color(0xFFE2E8F0) : Colors.transparent)),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: isEnabled,
                    activeColor: const Color(0xFF0F5132),
                    onChanged: (val) {
                      setState(() {
                        perms['enabled'] = val ?? false;
                      });
                    },
                  ),
                  Icon(icon, size: 18, color: isEnabled ? const Color(0xFF64748B) : Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Expanded(child: Text(moduleName, style: TextStyle(fontWeight: FontWeight.bold, color: isEnabled ? const Color(0xFF1E293B) : Colors.grey.shade400))),
                  if (isExpanded) ...[
                    TextButton.icon(
                      onPressed: () => _applyPermissionsToAllModules(moduleName),
                      icon: const Icon(LucideIcons.copy, size: 14, color: Color(0xFF0F5132)),
                      label: const Text('Apply to All', style: TextStyle(color: Color(0xFF0F5132), fontSize: 12, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        backgroundColor: const Color(0xFF0F5132).withOpacity(0.05),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (!isExpanded) ...[
                    _buildCollapsedSummary(perms, isExport, isSettings),
                    const SizedBox(width: 24),
                  ],
                  Icon(isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronRight, size: 18, color: const Color(0xFF64748B)),
                ],
              ),
            ),
          ),
          // Expanded Content
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('View Access', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                            const SizedBox(height: 4),
                            Text('Define what data this role can view on the $moduleName.', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                            const SizedBox(height: 16),
                            _buildRadioButton('All Data (All Zones & Wards)', 'Can view data of all zones and wards', perms, moduleName),
                            const SizedBox(height: 12),
                            _buildRadioButton('Zone Based Access', 'Can view data only for assigned zones', perms, moduleName),
                            const SizedBox(height: 12),
                            _buildRadioButton('Ward Based Access', 'Can view data only for assigned wards', perms, moduleName),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Zone Control', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                              const SizedBox(height: 4),
                              const Text('Select zones this role can access', style: TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: selectedZones.map((z) => _buildChip(z, () {
                                          setState(() {
                                            selectedZones.remove(z);
                                            perms['zones'] = selectedZones;
                                          });
                                        })).toList(),
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      color: Colors.white,
                                      icon: const Icon(LucideIcons.chevronDown, size: 14, color: Color(0xFF64748B)),
                                      onSelected: (val) {
                                        setState(() {
                                          selectedZones.add(val);
                                          perms['zones'] = selectedZones;
                                        });
                                      },
                                      itemBuilder: (context) {
                                        return availableZones.map((z) {
                                          return PopupMenuItem<String>(
                                            value: z,
                                            child: Text(z, style: const TextStyle(color: Colors.black)),
                                          );
                                        }).toList();
                                      }
                                    )
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text('Ward Control', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                              const SizedBox(height: 4),
                              const Text('Select wards within the selected zones', style: TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          ...selectedWards.take(4).map((w) => _buildChip(w, () {
                                            setState(() {
                                              selectedWards.remove(w);
                                              perms['wards'] = selectedWards;
                                            });
                                          })),
                                          if (selectedWards.length > 4)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text('+${selectedWards.length - 4} more', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                                            ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      color: Colors.white,
                                      icon: const Icon(LucideIcons.chevronDown, size: 14, color: Color(0xFF64748B)),
                                      onSelected: (val) {
                                        setState(() {
                                          selectedWards.add(val);
                                          perms['wards'] = selectedWards;
                                        });
                                      },
                                      itemBuilder: (context) {
                                        return availableWards.map((w) {
                                          return PopupMenuItem<String>(
                                            value: w,
                                            child: Text(w, style: const TextStyle(color: Colors.black)),
                                          );
                                        }).toList();
                                      }
                                    )
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 16),
                  const Text('Module Actions', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 4),
                  Text('Choose what actions this role can perform in $moduleName.', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildCheckboxItem('View', 'Allow viewing dashboard and analytics', perms, moduleName, 'view')),
                      if (!isSettings) Expanded(child: _buildCheckboxItem('Add / Create', 'Allow creating new records', perms, moduleName, 'add')),
                      if (!isSettings && !isExport) Expanded(child: _buildCheckboxItem('Edit', 'Allow editing existing records', perms, moduleName, 'edit')),
                      if (!isSettings && !isExport) Expanded(child: _buildCheckboxItem('Delete', 'Allow deleting records', perms, moduleName, 'delete')),
                      if (isExport) Expanded(child: _buildCheckboxItem('Export', 'Allow exporting reports', perms, moduleName, 'export', isExportField: true)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCollapsedSummary(Map<String, dynamic> perms, bool isExport, bool isSettings) {
    String viewVal = perms['viewAccess'] == 'Zone Based Access' ? 'Zone Based' : perms['viewAccess'] == 'Ward Based Access' ? 'Ward Based' : 'All Data';
    
    if (isSettings) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('View: $viewVal   |   ', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          const Text('Access: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          Icon(perms['actions']['view'] ? LucideIcons.checkSquare : LucideIcons.x, size: 12, color: perms['actions']['view'] ? const Color(0xFF198754) : const Color(0xFFDC3545)),
        ],
      );
    } else if (isExport) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('View: $viewVal   |   ', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          const Text('Export: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          Icon(perms['export'] ? LucideIcons.checkSquare : LucideIcons.x, size: 12, color: perms['export'] ? const Color(0xFF198754) : const Color(0xFFDC3545)),
        ],
      );
    } else {
      bool add = perms['actions']['add'];
      bool edit = perms['actions']['edit'];
      bool del = perms['actions']['delete'];
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('View: $viewVal   |   ', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          const Text('Add: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          Icon(add ? LucideIcons.checkSquare : LucideIcons.x, size: 12, color: add ? const Color(0xFF198754) : const Color(0xFFDC3545)),
          const Text('   Edit: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          Icon(edit ? LucideIcons.checkSquare : LucideIcons.x, size: 12, color: edit ? const Color(0xFF198754) : const Color(0xFFDC3545)),
          const Text('   Delete: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          Icon(del ? LucideIcons.checkSquare : LucideIcons.x, size: 12, color: del ? const Color(0xFF198754) : const Color(0xFFDC3545)),
        ],
      );
    }
  }

  Widget _buildRadioButton(String title, String subtitle, Map<String, dynamic> perms, String moduleName) {
    bool isSelected = perms['viewAccess'] == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          perms['viewAccess'] = title;
        });
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: isSelected ? const Color(0xFF0F5132) : const Color(0xFFCBD5E1)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B), fontSize: 12)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxItem(String title, String subtitle, Map<String, dynamic> perms, String moduleName, String actionKey, {bool isExportField = false}) {
    bool isChecked = isExportField ? perms['export'] : perms['actions'][actionKey];
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isExportField) {
            perms['export'] = !perms['export'];
          } else {
            perms['actions'][actionKey] = !perms['actions'][actionKey];
          }
        });
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: isChecked ? const Color(0xFF0F5132) : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isChecked ? const Color(0xFF0F5132) : const Color(0xFFCBD5E1)),
            ),
            child: isChecked ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B), fontSize: 12)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, VoidCallback onDeleted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF334155))),
          const SizedBox(width: 4),
          InkWell(
            onTap: onDeleted,
            child: const Icon(LucideIcons.x, size: 10, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildUserManagementLeftColumn() {
    List<Map<String, dynamic>> filteredUsers = _users.where((user) {
      if (_searchQuery.isNotEmpty && !user['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_filterRole != 'All Roles' && user['role'] != _filterRole) {
        return false;
      }
      if (_filterStatus != 'All Status' && user['status'] != _filterStatus) {
        return false;
      }
      return true;
    }).toList();

    return Expanded(
      flex: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Users', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    SizedBox(height: 4),
                    Text('Manage and assign roles to users', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(LucideIcons.upload, size: 14, color: Color(0xFF1E293B)),
                    label: const Text('Export', style: TextStyle(color: Color(0xFF1E293B))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isUserFormVisible = true;
                        _editingUserIndex = null;
                        _userNameController.clear();
                        _userEmailController.clear();
                        _userPhoneController.clear();
                        _userPasswordController.clear();
                        _userConfirmPasswordController.clear();
                        _selectedFormRole = null;
                        _selectedFormZone = null;
                        _selectedFormWard = null;
                      });
                    },
                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                    label: const Text('Add User', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F5132),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 24),
          // Role Navigation Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All Roles', ..._roles.map((r) => r['title'].toString())].map((r) {
                bool isSelected = _filterRole == r;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _filterRole = r;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF0F5132) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? const Color(0xFF0F5132) : const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        r,
                        style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF64748B),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    style: const TextStyle(color: Colors.black, fontSize: 14),
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: const InputDecoration(
                      hintText: 'Search users...',
                      hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                      prefixIcon: Icon(LucideIcons.search, color: Color(0xFF94A3B8), size: 16),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: Colors.white,
                    value: _filterStatus,
                    icon: const Icon(LucideIcons.chevronDown, size: 14, color: Color(0xFF64748B)),
                    items: const [
                      DropdownMenuItem(value: 'All Status', child: Text('All Status', style: TextStyle(fontSize: 14, color: Colors.black))),
                      DropdownMenuItem(value: 'Active', child: Text('Active', style: TextStyle(fontSize: 14, color: Colors.black))),
                      DropdownMenuItem(value: 'Inactive', child: Text('Inactive', style: TextStyle(fontSize: 14, color: Colors.black))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _filterStatus = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: [
                        const Expanded(flex: 2, child: Text('User Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        const Expanded(flex: 2, child: Text('Email', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        const Expanded(flex: 1, child: Text('Role', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        if (!_isUserFormVisible) const Expanded(flex: 1, child: Text('Zone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        if (!_isUserFormVisible) const Expanded(flex: 1, child: Text('Ward', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        const Expanded(flex: 1, child: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        const Expanded(flex: 1, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        const SizedBox(width: 60, child: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredUsers.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      itemBuilder: (context, index) {
                        final user = filteredUsers[index];
                        final rawIndex = _users.indexOf(user);
                        
                        // Determine badge styling based on role
                        Color badgeBg = const Color(0xFFDBEAFE);
                        Color badgeText = const Color(0xFF3B82F6);
                        try {
                          final roleObj = _roles.firstWhere((r) => r['title'] == user['role']);
                          badgeBg = roleObj['bgColor'];
                          badgeText = roleObj['color'];
                        } catch (e) {}
                        
                        String initials = user['name'].toString().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase();

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: const Color(0xFFDCFCE7),
                                      child: Text(initials, style: const TextStyle(fontSize: 10, color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(user['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF1E293B))),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(user['email'], style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ),
                              Expanded(
                                flex: 1,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(4)),
                                    child: Text(user['role'], style: TextStyle(fontSize: 10, color: badgeText, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                              if (!_isUserFormVisible) Expanded(
                                flex: 1,
                                child: Text(user['zone']?.toString() ?? 'N/A', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ),
                              if (!_isUserFormVisible) Expanded(
                                flex: 1,
                                child: Text(user['ward']?.toString() ?? 'N/A', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(user['phone'], style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ),
                              Expanded(
                                flex: 1,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: user['status'] == 'Active' ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(4)
                                    ),
                                    child: Text(user['status'], style: TextStyle(fontSize: 10, color: user['status'] == 'Active' ? const Color(0xFF16A34A) : const Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 60,
                                child: Row(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _isUserFormVisible = true;
                                          _editingUserIndex = rawIndex;
                                          _userNameController.text = user['name'] ?? '';
                                          _userEmailController.text = user['email'] ?? '';
                                          _userPhoneController.text = user['phone'] ?? '';
                                          _selectedFormRole = user['role'];
                                          _selectedFormZone = user['zone'];
                                          _selectedFormWard = user['ward'];
                                          _userPasswordController.clear();
                                          _userConfirmPasswordController.clear();
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Icon(LucideIcons.edit2, size: 12, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () async {
                                        await FirebaseFirestore.instance.collection('authority_users').doc(user['id']).delete();
                                        if (_editingUserIndex == rawIndex) {
                                          setState(() {
                                            _isUserFormVisible = false;
                                            _editingUserIndex = null;
                                            _userNameController.clear();
                                            _userEmailController.clear();
                                            _userPhoneController.clear();
                                            _userPasswordController.clear();
                                            _userConfirmPasswordController.clear();
                                            _selectedFormRole = null;
                                            _selectedFormZone = null;
                                            _selectedFormWard = null;
                                          });
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Icon(LucideIcons.trash2, size: 12, color: Color(0xFFDC2626)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Showing 1 to ${filteredUsers.length} of ${filteredUsers.length} users', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(4)),
                    child: const Icon(LucideIcons.chevronLeft, size: 14, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF0F5132)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('1', style: TextStyle(color: Color(0xFF0F5132), fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(4)),
                    child: const Icon(LucideIcons.chevronRight, size: 14, color: Color(0xFF94A3B8)),
                  ),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Future<bool> _showDuplicateWarning(String entityType, String nameInUse) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Warning', style: TextStyle(color: Colors.red)),
          content: Text('A $entityType is already assigned to this region ($nameInUse).\nDo you want to proceed and add another?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.black87)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add Another', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Widget _buildUserManagementRightColumn() {
    bool isEditing = _editingUserIndex != null;

    bool hasAllAccess = false;
    List<String> allowedZones = [];
    List<String> allowedWards = [];

    if (_selectedFormRole != null) {
      try {
        final role = _roles.firstWhere((r) => r['title'] == _selectedFormRole);
        final perms = role['permissions'] as Map<String, dynamic>;
        
        for (var module in perms.values) {
          if (module['viewAccess'] == 'All Data (All Zones & Wards)') {
            hasAllAccess = true;
            break;
          }
          final zones = List<String>.from(module['zones'] ?? []);
          if (zones.contains('All Zones')) {
            hasAllAccess = true;
            break;
          }
          allowedZones.addAll(zones);
          allowedWards.addAll(List<String>.from(module['wards'] ?? []));
        }
      } catch (_) {}
    }
    allowedZones = allowedZones.toSet().toList();
    allowedWards = allowedWards.toSet().toList();

    return Expanded(
      flex: 3,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditing ? 'Edit User' : 'Add User', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 4),
            Text(isEditing ? 'Modify user details and role' : 'Create a new user and assign role', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: [
                  const Text('Role *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        dropdownColor: Colors.white,
                        isExpanded: true,
                        hint: const Text('Select Role', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                        value: _selectedFormRole,
                        icon: const Icon(LucideIcons.chevronDown, size: 16, color: Color(0xFF64748B)),
                        items: _roles.map((r) => r['title'].toString()).map((r) {
                          return DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 14, color: Colors.black)));
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedFormRole = val;
                            _selectedFormZone = null;
                            _selectedFormWard = null;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Zone *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        dropdownColor: Colors.white,
                        isExpanded: true,
                        hint: const Text('Select Zone', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                        value: _selectedFormZone,
                        icon: const Icon(LucideIcons.chevronDown, size: 16, color: Color(0xFF64748B)),
                        items: (() {
                          List<String> zItems = (hasAllAccess ? _allZones : allowedZones).toList();
                          if (zItems.length > 1 && !zItems.contains('All Zones')) {
                            zItems.insert(0, 'All Zones');
                          } else if (zItems.isEmpty) {
                            return <DropdownMenuItem<String>>[];
                          }
                          return zItems.map((z) {
                            return DropdownMenuItem(value: z, child: Text(z, style: const TextStyle(fontSize: 14, color: Colors.black)));
                          }).toList();
                        })(),
                        onChanged: (val) {
                          setState(() {
                            _selectedFormZone = val;
                            _selectedFormWard = null; // Reset ward when zone changes
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Ward *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        dropdownColor: Colors.white,
                        isExpanded: true,
                        hint: const Text('Select Ward', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                        value: _selectedFormWard,
                        icon: const Icon(LucideIcons.chevronDown, size: 16, color: Color(0xFF64748B)),
                        items: (() {
                          if ((hasAllAccess ? _allWards : allowedWards).isEmpty) return <DropdownMenuItem<String>>[];
                          List<String> wItems = _wardModels.where((w) {
                            if (!hasAllAccess && !allowedWards.contains('All Wards') && !allowedWards.contains(w.name)) return false;
                            if (_selectedFormZone == null || _selectedFormZone == 'All Zones') return true;
                            try {
                              final z = _zoneModels.firstWhere((zm) => zm.name == _selectedFormZone);
                              return _isWardInZone(w, z);
                            } catch (_) { return false; }
                          }).map((w) => w.name).toList();
                          
                          if (wItems.length > 1 && !wItems.contains('All Wards')) {
                            wItems.insert(0, 'All Wards');
                          }
                          if (_selectedFormWard != null && !wItems.contains(_selectedFormWard)) {
                            wItems.add(_selectedFormWard!);
                          }
                          return wItems.map((w) {
                            return DropdownMenuItem(value: w, child: Text(w, style: const TextStyle(fontSize: 14, color: Colors.black)));
                          }).toList();
                        })(),
                        onChanged: (val) {
                          setState(() {
                            _selectedFormWard = val;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildUserFormTextField('Full Name *', 'Enter full name', _userNameController),
                  const SizedBox(height: 16),
                  _buildUserFormTextField('Phone Number *', 'Enter phone number', _userPhoneController, prefixIcon: LucideIcons.phone),
                  const SizedBox(height: 16),
                  _buildUserFormTextField('Email Address *', 'Enter email address', _userEmailController, prefixIcon: LucideIcons.mail),
                  const SizedBox(height: 16),
                  _buildUserFormTextField('Password *', 'Enter password', _userPasswordController, suffixIcon: LucideIcons.eyeOff, obscureText: true),
                  const SizedBox(height: 16),
                  _buildUserFormTextField('Confirm Password *', 'Confirm password', _userConfirmPasswordController, suffixIcon: LucideIcons.eyeOff, obscureText: true),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isUserFormVisible = false;
                      _editingUserIndex = null;
                      _userNameController.clear();
                      _userEmailController.clear();
                      _userPhoneController.clear();
                      _userPasswordController.clear();
                      _userConfirmPasswordController.clear();
                      _selectedFormRole = null;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    String finalZone = hasAllAccess ? 'All Zones' : (_selectedFormZone ?? '');
                    String finalWard = hasAllAccess ? 'All Wards' : (_selectedFormWard ?? '');
                    
                    if (_userNameController.text.isEmpty || _selectedFormRole == null || _userEmailController.text.isEmpty || finalZone.isEmpty || finalWard.isEmpty) return;
                    
                    final existingUsers = _users.where((u) {
                      if (isEditing && u['id'] == _users[_editingUserIndex!]['id']) return false;
                      return u['zone'] == finalZone && u['ward'] == finalWard && u['role'] == _selectedFormRole;
                    }).toList();
                    
                    if (existingUsers.isNotEmpty) {
                      bool proceed = await _showDuplicateWarning('User', existingUsers.first['name'] ?? 'Unknown');
                      if (!proceed) return;
                    }

                    final userData = {
                      'name': _userNameController.text,
                      'email': _userEmailController.text,
                      'password': _userPasswordController.text,
                      'role': _selectedFormRole,
                      'zone': finalZone,
                      'ward': finalWard,
                      'phone': _userPhoneController.text,
                    };

                    if (isEditing) {
                      final docId = _users[_editingUserIndex!]['id'];
                      userData['status'] = _users[_editingUserIndex!]['status'] ?? 'Active';
                      await FirebaseFirestore.instance.collection('authority_users').doc(docId).update(userData);
                    } else {
                      userData['status'] = 'Active';
                      await FirebaseFirestore.instance.collection('authority_users').add(userData);
                    }

                    setState(() {
                      _isUserFormVisible = false;
                      _editingUserIndex = null;
                      _userNameController.clear();
                      _userEmailController.clear();
                      _userPhoneController.clear();
                      _userPasswordController.clear();
                      _userConfirmPasswordController.clear();
                      _selectedFormRole = null;
                      _selectedFormZone = null;
                      _selectedFormWard = null;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F5132),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                  child: Text(isEditing ? 'Save Changes' : 'Create User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildUserFormTextField(String label, String hint, TextEditingController controller, {IconData? prefixIcon, IconData? suffixIcon, bool obscureText = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 16, color: const Color(0xFF94A3B8)) : null,
            suffixIcon: suffixIcon != null ? Icon(suffixIcon, size: 16, color: const Color(0xFF94A3B8)) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(6)),
            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF0F5132)), borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ],
    );
  }

  Widget _buildResourceManagementLeftColumn() {
    List<Map<String, dynamic>> filteredVehicles = _vehicles.where((vehicle) {
      if (_searchResourceQuery.isNotEmpty && !(vehicle['vehicleNumber']?.toString().toLowerCase().contains(_searchResourceQuery.toLowerCase()) ?? false) && !(vehicle['driverName']?.toString().toLowerCase().contains(_searchResourceQuery.toLowerCase()) ?? false)) {
        return false;
      }
      String statusText = (vehicle['isActive'] == true) ? 'Active' : 'Inactive';
      if (_filterResourceStatus != 'All Status' && statusText != _filterResourceStatus) {
        return false;
      }
      return true;
    }).toList();

    return Expanded(
      flex: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Resources (Vehicles)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    SizedBox(height: 4),
                    Text('Manage and register vehicles', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(LucideIcons.upload, size: 14, color: Color(0xFF1E293B)),
                    label: const Text('Export', style: TextStyle(color: Color(0xFF1E293B))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isResourceFormVisible = true;
                        _editingResourceIndex = null;
                        _vehicleNumberController.clear();
                        _vehicleDriverNameController.clear();
                        _vehiclePhoneController.clear();
                        _vehiclePasswordController.clear();
                        _selectedResourceZone = null;
                        _selectedResourceWard = null;
                      });
                    },
                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                    label: const Text('Add Vehicle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F5132),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    style: const TextStyle(color: Colors.black, fontSize: 14),
                    onChanged: (val) => setState(() => _searchResourceQuery = val),
                    decoration: const InputDecoration(
                      hintText: 'Search vehicles...',
                      hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                      prefixIcon: Icon(LucideIcons.search, color: Color(0xFF94A3B8), size: 16),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: Colors.white,
                    value: _filterResourceStatus,
                    icon: const Icon(LucideIcons.chevronDown, size: 14, color: Color(0xFF64748B)),
                    items: const [
                      DropdownMenuItem(value: 'All Status', child: Text('All Status', style: TextStyle(fontSize: 14, color: Colors.black))),
                      DropdownMenuItem(value: 'Active', child: Text('Active', style: TextStyle(fontSize: 14, color: Colors.black))),
                      DropdownMenuItem(value: 'Inactive', child: Text('Inactive', style: TextStyle(fontSize: 14, color: Colors.black))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _filterResourceStatus = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: [
                        const Expanded(flex: 2, child: Text('Vehicle Number', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        const Expanded(flex: 2, child: Text('Driver Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        if (!_isResourceFormVisible) const Expanded(flex: 1, child: Text('Zone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        if (!_isResourceFormVisible) const Expanded(flex: 1, child: Text('Ward', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        const Expanded(flex: 1, child: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        const Expanded(flex: 1, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        const SizedBox(width: 60, child: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredVehicles.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      itemBuilder: (context, index) {
                        final vehicle = filteredVehicles[index];
                        final rawIndex = _vehicles.indexOf(vehicle);
                        
                        String statusText = (vehicle['isActive'] == true) ? 'Active' : 'Inactive';
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(vehicle['vehicleNumber'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF1E293B))),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(vehicle['driverName'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ),
                              if (!_isResourceFormVisible) Expanded(
                                flex: 1,
                                child: Text(vehicle['zone']?.toString() ?? 'N/A', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ),
                              if (!_isResourceFormVisible) Expanded(
                                flex: 1,
                                child: Text(vehicle['assignedWard']?.toString() ?? 'N/A', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(vehicle['phoneNumber'] ?? 'N/A', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ),
                              Expanded(
                                flex: 1,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusText == 'Active' ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(4)
                                    ),
                                    child: Text(statusText, style: TextStyle(fontSize: 10, color: statusText == 'Active' ? const Color(0xFF16A34A) : const Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 60,
                                child: Row(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _isResourceFormVisible = true;
                                          _editingResourceIndex = rawIndex;
                                          _vehicleNumberController.text = vehicle['vehicleNumber'] ?? '';
                                          _vehicleDriverNameController.text = vehicle['driverName'] ?? '';
                                          _vehiclePhoneController.text = vehicle['phoneNumber'] ?? '';
                                          _selectedResourceZone = vehicle['zone'];
                                          _selectedResourceWard = vehicle['assignedWard'];
                                          _vehiclePasswordController.clear();
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Icon(LucideIcons.edit2, size: 12, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () async {
                                        await FirebaseFirestore.instance.collection('vehicles').doc(vehicle['id']).delete();
                                        if (_editingResourceIndex == rawIndex) {
                                          setState(() {
                                            _isResourceFormVisible = false;
                                            _editingResourceIndex = null;
                                            _vehicleNumberController.clear();
                                            _vehicleDriverNameController.clear();
                                            _vehiclePhoneController.clear();
                                            _vehiclePasswordController.clear();
                                            _selectedResourceZone = null;
                                            _selectedResourceWard = null;
                                          });
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Icon(LucideIcons.trash2, size: 12, color: Color(0xFFDC2626)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Showing 1 to ${filteredVehicles.length} of ${filteredVehicles.length} vehicles', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(4)),
                    child: const Icon(LucideIcons.chevronLeft, size: 14, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF0F5132)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('1', style: TextStyle(color: Color(0xFF0F5132), fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(4)),
                    child: const Icon(LucideIcons.chevronRight, size: 14, color: Color(0xFF94A3B8)),
                  ),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildResourceManagementRightColumn() {
    bool isEditing = _editingResourceIndex != null;

    List<String> allowedZones = _allZones; 
    List<String> allowedWards = _allWards;

    return Expanded(
      flex: 3,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditing ? 'Edit Vehicle' : 'Add Vehicle', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 4),
            Text(isEditing ? 'Modify vehicle details' : 'Register a new vehicle', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: [
                  const Text('Zone *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        dropdownColor: Colors.white,
                        isExpanded: true,
                        hint: const Text('Select Zone', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                        value: _selectedResourceZone,
                        icon: const Icon(LucideIcons.chevronDown, size: 16, color: Color(0xFF64748B)),
                        items: ['All Zones', ...allowedZones].map((z) {
                          return DropdownMenuItem(value: z, child: Text(z, style: const TextStyle(fontSize: 14, color: Colors.black)));
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedResourceZone = val;
                            _selectedResourceWard = null; 
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Ward *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        dropdownColor: Colors.white,
                        isExpanded: true,
                        hint: const Text('Select Ward', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                        value: _selectedResourceWard,
                        icon: const Icon(LucideIcons.chevronDown, size: 16, color: Color(0xFF64748B)),
                        items: (() {
                          List<String> wItems = _wardModels.where((w) {
                            if (_selectedResourceZone == null || _selectedResourceZone == 'All Zones') return true;
                            try {
                              final z = _zoneModels.firstWhere((zm) => zm.name == _selectedResourceZone);
                              return _isWardInZone(w, z);
                            } catch (_) { return false; }
                          }).map((w) => w.name).toList();
                          
                          if (wItems.length > 1 && !wItems.contains('All Wards')) {
                            wItems.insert(0, 'All Wards');
                          }
                          if (_selectedResourceWard != null && !wItems.contains(_selectedResourceWard)) {
                            wItems.add(_selectedResourceWard!);
                          }
                          return wItems.map((w) {
                            return DropdownMenuItem(value: w, child: Text(w, style: const TextStyle(fontSize: 14, color: Colors.black)));
                          }).toList();
                        })(),
                        onChanged: (val) {
                          setState(() {
                            _selectedResourceWard = val;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildUserFormTextField('Vehicle Number *', 'Enter vehicle number (e.g., AB 12 CD 3456)', _vehicleNumberController),
                  const SizedBox(height: 16),
                  _buildUserFormTextField('Driver Name *', 'Enter driver name', _vehicleDriverNameController),
                  const SizedBox(height: 16),
                  _buildUserFormTextField('Phone Number', 'Enter driver phone number', _vehiclePhoneController, prefixIcon: LucideIcons.phone),
                  const SizedBox(height: 16),
                  _buildUserFormTextField('Password (Optional)', 'Enter password for driver login', _vehiclePasswordController, suffixIcon: LucideIcons.eyeOff, obscureText: true),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isResourceFormVisible = false;
                      _editingResourceIndex = null;
                      _vehicleNumberController.clear();
                      _vehicleDriverNameController.clear();
                      _vehiclePhoneController.clear();
                      _vehiclePasswordController.clear();
                      _selectedResourceZone = null;
                      _selectedResourceWard = null;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    String finalZone = _selectedResourceZone ?? '';
                    String finalWard = _selectedResourceWard ?? '';
                    
                    if (_vehicleNumberController.text.isEmpty || _vehicleDriverNameController.text.isEmpty || finalZone.isEmpty || finalWard.isEmpty) return;
                    
                    final existingVehicles = _vehicles.where((v) {
                      if (isEditing && v['id'] == _vehicles[_editingResourceIndex!]['id']) return false;
                      return v['zone'] == finalZone && (v['ward'] == finalWard || v['assignedWard'] == finalWard);
                    }).toList();

                    if (existingVehicles.isNotEmpty) {
                      bool proceed = await _showDuplicateWarning('Vehicle', existingVehicles.first['vehicleNumber'] ?? 'Unknown');
                      if (!proceed) return;
                    }

                    final Map<String, dynamic> vehicleData = {
                      'vehicleNumber': _vehicleNumberController.text,
                      'driverName': _vehicleDriverNameController.text,
                      'phoneNumber': _vehiclePhoneController.text,
                      'password': _vehiclePasswordController.text,
                      'zone': finalZone,
                      'assignedWard': finalWard,
                    };

                    if (isEditing) {
                      final docId = _vehicles[_editingResourceIndex!]['id'];
                      await FirebaseFirestore.instance.collection('vehicles').doc(docId).update(vehicleData);
                    } else {
                      vehicleData['isActive'] = true;
                      await FirebaseFirestore.instance.collection('vehicles').add(vehicleData);
                    }

                    setState(() {
                      _isResourceFormVisible = false;
                      _editingResourceIndex = null;
                      _vehicleNumberController.clear();
                      _vehicleDriverNameController.clear();
                      _vehiclePhoneController.clear();
                      _vehiclePasswordController.clear();
                      _selectedResourceZone = null;
                      _selectedResourceWard = null;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F5132),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                  child: Text(isEditing ? 'Save Changes' : 'Register Vehicle', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildResourceBottomNav() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: BottomNavigationBar(
        currentIndex: _resourceNavIndex,
        onTap: (index) {
          setState(() {
            _resourceNavIndex = index;
          });
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: const Color(0xFF0F5132),
        unselectedItemColor: const Color(0xFF64748B),
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.truck), label: 'Vehicles'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.map), label: 'Maps (Zones/Wards)'),
        ],
      ),
    );
  }

  Widget _buildResourceMapMode() {
    bool isDrawing = _currentMapMode != ResourceMapMode.view;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isDrawing && _showSidebars) ...[
          // Zones Column
          Container(
            width: 250,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Zones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 20, color: Colors.grey),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() => _showSidebars = false),
                      ),
                    ],
                  ),
                ),
                if (_zoneModels.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('No zones available', style: TextStyle(color: Colors.grey))),
                Expanded(
                  child: ListView.builder(
                    itemCount: _zoneModels.length,
                    itemBuilder: (context, index) {
                      final z = _zoneModels[index];
                      final isSelected = _selectedZoneForMap?.id == z.id;
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: Colors.blue.withOpacity(0.05),
                        title: Text(z.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.blue.shade800 : Colors.black87)),
                        onTap: () {
                          setState(() {
                            _selectedZoneForMap = z;
                            _selectedWardForMap = null; 
                          });
                          if (z.boundary.isNotEmpty) {
                             double cLat = 0, cLng = 0;
                             for (var p in z.boundary) { cLat += p.latitude; cLng += p.longitude; }
                             _mapController.move(LatLng(cLat / z.boundary.length, cLng / z.boundary.length), 13.0);
                          }
                        },
                        trailing: IconButton(
                          icon: const Icon(LucideIcons.edit, size: 16, color: Colors.blue),
                          onPressed: () {
                            setState(() {
                              _currentMapMode = ResourceMapMode.drawZone;
                              _drawingPoints = List.from(z.boundary);
                              _editingRegionId = z.id;
                              _editingRegionName = z.name;
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
          
          // Wards Column
          if (_selectedZoneForMap != null)
            Container(
              width: 250,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${_selectedZoneForMap!.name} Wards', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                        IconButton(
                          icon: const Icon(LucideIcons.x, size: 18, color: Colors.grey),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _selectedZoneForMap = null;
                              _selectedWardForMap = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final zoneWards = _wardModels.where((w) => _isWardInZone(w, _selectedZoneForMap!)).toList();
                        if (zoneWards.isEmpty) {
                          return const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('No wards found', style: TextStyle(color: Colors.grey)));
                        }
                        return ListView.builder(
                          itemCount: zoneWards.length,
                          itemBuilder: (context, index) {
                            final w = zoneWards[index];
                            final isSelected = _selectedWardForMap?.id == w.id;
                            return ListTile(
                              selected: isSelected,
                              selectedTileColor: Colors.blue.withOpacity(0.1),
                              title: Text(w.name, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.blue.shade900 : Colors.black87)),
                              onTap: () {
                                setState(() {
                                  _selectedWardForMap = w;
                                });
                                if (w.boundary.isNotEmpty) {
                                   double cLat = 0, cLng = 0;
                                   for (var p in w.boundary) { cLat += p.latitude; cLng += p.longitude; }
                                   _mapController.move(LatLng(cLat / w.boundary.length, cLng / w.boundary.length), 14.5);
                                }
                              },
                              trailing: IconButton(
                                icon: const Icon(LucideIcons.edit, size: 16, color: Colors.blue),
                                onPressed: () {
                                  setState(() {
                                    _currentMapMode = ResourceMapMode.drawWard;
                                    _drawingPoints = List.from(w.boundary);
                                    _editingRegionId = w.id;
                                    _editingRegionName = w.name;
                                    _selectedWardForMap = w;
                                  });
                                },
                              ),
                            );
                          },
                        );
                      }
                    ),
                  ),
                ],
              ),
            ),
        ],

        // Map Area
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: isDrawing ? BorderRadius.circular(12) : const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(12.9716, 77.5946),
                    initialZoom: 12.0,
                    onTap: (tapPosition, point) {
                      if (_currentMapMode != ResourceMapMode.view) {
                        setState(() {
                          _drawingPoints.add(point);
                        });
                      } else {
                        // Check if tapped inside any ward
                        final camera = _mapController.camera;
                        final showWards = camera.zoom >= 13.5;
                        
                        Ward? tappedWard;
                        if (showWards || _selectedZoneForMap != null) {
                          for (var w in _wardModels) {
                            if (_isPointInPolygon(point, w.boundary)) {
                              tappedWard = w;
                              break;
                            }
                          }
                        }

                        if (tappedWard != null) {
                          // Find its parent zone
                          Zone? parentZone;
                          for (var z in _zoneModels) {
                            if (_isWardInZone(tappedWard, z)) {
                              parentZone = z;
                              break;
                            }
                          }
                          setState(() {
                            _showSidebars = true;
                            _selectedZoneForMap = parentZone;
                            _selectedWardForMap = tappedWard;
                          });
                          return;
                        }

                        // Check if tapped inside any zone
                        Zone? tappedZone;
                        for (var z in _zoneModels) {
                          if (_isPointInPolygon(point, z.boundary)) {
                            tappedZone = z;
                            break;
                          }
                        }

                        if (tappedZone != null) {
                          setState(() {
                            _showSidebars = true;
                            _selectedZoneForMap = tappedZone;
                            _selectedWardForMap = null;
                          });
                        }
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app',
                    ),
                    Builder(
                      builder: (context) {
                        final camera = MapCamera.of(context);
                        final zoom = camera.zoom;
                        final showWards = zoom >= 13.5;
                        
                        return PolygonLayer(
                          polygons: [
                            // Existing Zones (always show boundary)
                            ..._zoneModels.where((z) => z.boundary.isNotEmpty).map((z) => Polygon(
                              points: z.boundary,
                              color: (_selectedZoneForMap?.id == z.id) ? Colors.green.withOpacity(0.3) : Colors.green.withOpacity(0.15),
                              borderColor: Colors.green,
                              borderStrokeWidth: (_selectedZoneForMap?.id == z.id) ? 3 : 1.5,
                            )),
                            // Existing Wards
                            if (showWards || _selectedZoneForMap != null)
                              ..._wardModels.where((w) => w.boundary.isNotEmpty).map((w) => Polygon(
                                points: w.boundary,
                                color: (_selectedWardForMap?.id == w.id) ? Colors.blue.withOpacity(0.4) : Colors.blue.withOpacity(0.2),
                                borderColor: Colors.blue,
                                borderStrokeWidth: (_selectedWardForMap?.id == w.id) ? 3 : 1.5,
                              )),
                            // Currently drawing polygon
                            if (_drawingPoints.isNotEmpty)
                              Polygon(
                                points: _drawingPoints,
                                color: _currentMapMode == ResourceMapMode.drawWard 
                                    ? Colors.blue.withOpacity(0.4) 
                                    : Colors.green.withOpacity(0.4),
                                borderColor: _currentMapMode == ResourceMapMode.drawWard ? Colors.blue : Colors.green,
                                borderStrokeWidth: 3,
                              ),
                          ],
                        );
                      }
                    ),
                    Builder(
                      builder: (context) {
                        final camera = MapCamera.of(context);
                        final zoom = camera.zoom;
                        final showWards = zoom >= 13.5;
                        
                        final List<Marker> labels = [];
                        if (showWards || _selectedZoneForMap != null) {
                          for (var w in _wardModels.where((w) => w.boundary.isNotEmpty)) {
                            if (_selectedZoneForMap != null && !_isWardInZone(w, _selectedZoneForMap!)) continue;
                            
                            double cLat = 0, cLng = 0;
                            for (var p in w.boundary) { cLat += p.latitude; cLng += p.longitude; }
                            labels.add(Marker(
                              point: LatLng(cLat / w.boundary.length, cLng / w.boundary.length),
                              width: 120,
                              height: 40,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.blue.shade700, width: 1),
                                  ),
                                  child: Text(
                                    w.name,
                                    style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 11),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ));
                          }
                        }
                        
                        if (!showWards) {
                          for (var z in _zoneModels.where((z) => z.boundary.isNotEmpty)) {
                            double cLat = 0, cLng = 0;
                            for (var p in z.boundary) { cLat += p.latitude; cLng += p.longitude; }
                            labels.add(Marker(
                              point: LatLng(cLat / z.boundary.length, cLng / z.boundary.length),
                              width: 140,
                              height: 40,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.green.shade700, width: 1.5),
                                  ),
                                  child: Text(
                                    z.name,
                                    style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ));
                          }
                        }

                        return MarkerLayer(
                          markers: [
                            ...labels,
                            ..._drawingPoints.map((p) => Marker(
                              point: p,
                              width: 12,
                              height: 12,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            )).toList(),
                          ],
                        );
                      }
                    ),
                  ],
                ),
                
                // Action Bar
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)
                      ]
                    ),
                    child: Row(
                      children: [
                        if (_currentMapMode == ResourceMapMode.view) ...[
                          if (!_showSidebars) ...[
                            ElevatedButton.icon(
                              onPressed: () => setState(() => _showSidebars = true),
                              icon: const Icon(LucideIcons.list, size: 16, color: Colors.black87),
                              label: const Text('Show Regions', style: TextStyle(color: Colors.black87)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade200),
                            ),
                            const SizedBox(width: 8),
                          ],
                          ElevatedButton.icon(
                            onPressed: () => setState(() => _currentMapMode = ResourceMapMode.drawZone),
                            icon: const Icon(LucideIcons.penTool, size: 16, color: Colors.white),
                            label: const Text('Draw Zone', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => setState(() => _currentMapMode = ResourceMapMode.drawWard),
                            icon: const Icon(LucideIcons.penTool, size: 16, color: Colors.white),
                            label: const Text('Draw Ward', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
                          ),
                        ] else ...[
                          Text('${_editingRegionId != null ? 'Editing' : 'Drawing'} ${_currentMapMode == ResourceMapMode.drawZone ? 'Zone' : 'Ward'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 16),
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _drawingPoints.clear();
                              });
                            },
                            child: const Text('Clear'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _currentMapMode = ResourceMapMode.view;
                                _drawingPoints.clear();
                                _editingRegionId = null;
                                _editingRegionName = null;
                              });
                            },
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _drawingPoints.length >= 3 ? () => _showSavePolygonDialog() : null,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
                            child: const Text('Save', style: TextStyle(color: Colors.white)),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
                
                // Bottom Analytics Panel
                if (_selectedWardForMap != null && _currentMapMode == ResourceMapMode.view)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildWardAnalyticsPanel(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSavePolygonDialog() {
    final nameController = TextEditingController(text: _editingRegionName ?? '');
    final isZone = _currentMapMode == ResourceMapMode.drawZone;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('${_editingRegionId != null ? 'Update' : 'Save'} ${isZone ? 'Zone' : 'Ward'}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            labelText: '${isZone ? 'Zone' : 'Ward'} Name',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.black))),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              
              if (isZone) {
                final newZone = Zone(
                  id: _editingRegionId ?? 'zone_${DateTime.now().millisecondsSinceEpoch}',
                  name: nameController.text,
                  boundary: List.from(_drawingPoints),
                );
                await FirebaseFirestore.instance.collection('zones').doc(newZone.id).set(newZone.toJson());
              } else {
                final newWard = Ward(
                  id: _editingRegionId ?? 'ward_${DateTime.now().millisecondsSinceEpoch}',
                  name: nameController.text,
                  boundary: List.from(_drawingPoints),
                );
                await FirebaseFirestore.instance.collection('wards').doc(newWard.id).set(newWard.toJson());
              }
              
              if (mounted) {
                setState(() {
                  _currentMapMode = ResourceMapMode.view;
                  _drawingPoints.clear();
                  _editingRegionId = null;
                  _editingRegionName = null;
                });
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildWardAnalyticsPanel() {
    final assignedVehicles = _vehicles.where((v) {
      final wardName = v['ward']?.toString().toLowerCase() ?? '';
      return wardName.contains(_selectedWardForMap!.name.toLowerCase()) || 
             _selectedWardForMap!.name.toLowerCase().contains(wardName);
    }).toList();
    
    final authorities = _users.where((u) {
       final r = u['role']?.toString().toLowerCase() ?? '';
       final w = u['ward']?.toString().toLowerCase() ?? '';
       return r.contains('ward') && (w.contains(_selectedWardForMap!.name.toLowerCase()) || _selectedWardForMap!.name.toLowerCase().contains(w));
    }).toList();
    
    final authorityName = authorities.isNotEmpty ? authorities.first['name'] : 'Unassigned';

    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, -2))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_selectedWardForMap!.name} Analytics', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 20, color: Colors.grey),
                        onPressed: () => setState(() => _selectedWardForMap = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildAnalyticStat(LucideIcons.truck, 'Vehicles', '${assignedVehicles.length}'),
                      const SizedBox(width: 24),
                      _buildAnalyticStat(LucideIcons.user, 'Authority', authorityName.toString()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Drivers:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                  Expanded(
                    child: assignedVehicles.isEmpty 
                        ? const Text('No drivers assigned', style: TextStyle(color: Colors.grey, fontSize: 12))
                        : ListView.builder(
                            itemCount: assignedVehicles.length,
                            itemBuilder: (context, idx) => Text('• ${assignedVehicles[idx]['driverName'] ?? 'Unknown'} (${assignedVehicles[idx]['vehicleNumber'] ?? ''})', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                          ),
                  )
                ],
              ),
            ),
          ),
          Container(width: 1, color: Colors.grey.shade200, margin: const EdgeInsets.symmetric(vertical: 20)),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Collection Efficiency (Last 7 Days)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true, reservedSize: 22, interval: 1, getTitlesWidget: _bottomTitleWidgets),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true, interval: 20, reservedSize: 28, getTitlesWidget: _leftTitleWidgets),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        minX: 0,
                        maxX: 6,
                        minY: 0,
                        maxY: 100,
                        lineBarsData: [
                          LineChartBarData(
                            spots: const [
                              FlSpot(0, 85),
                              FlSpot(1, 92),
                              FlSpot(2, 78),
                              FlSpot(3, 88),
                              FlSpot(4, 95),
                              FlSpot(5, 91),
                              FlSpot(6, 98),
                            ],
                            isCurved: true,
                            color: Colors.green.shade600,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(show: true, color: const Color(0x334CAF50)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  static Widget _bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(color: Colors.grey, fontSize: 10);
    Widget text;
    switch (value.toInt()) {
      case 0: text = const Text('Mon', style: style); break;
      case 1: text = const Text('Tue', style: style); break;
      case 2: text = const Text('Wed', style: style); break;
      case 3: text = const Text('Thu', style: style); break;
      case 4: text = const Text('Fri', style: style); break;
      case 5: text = const Text('Sat', style: style); break;
      case 6: text = const Text('Sun', style: style); break;
      default: text = const Text('', style: style); break;
    }
    return SideTitleWidget(axisSide: meta.axisSide, child: text);
  }

  static Widget _leftTitleWidgets(double value, TitleMeta meta) {
    return Text('${value.toInt()}%', style: const TextStyle(color: Colors.grey, fontSize: 10));
  }

  Widget _buildAnalyticStat(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: Colors.blue.shade700),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ],
    );
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.isEmpty) return false;
    bool isInside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      double xi = polygon[i].longitude, yi = polygon[i].latitude;
      double xj = polygon[j].longitude, yj = polygon[j].latitude;
      
      bool intersect = ((yi > point.latitude) != (yj > point.latitude))
          && (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (intersect) isInside = !isInside;
    }
    return isInside;
  }

  Widget _buildDashboardTab() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Metric Cards
          Row(
            children: [
              _buildMetricCard('Total Zones', _zoneModels.length.toString(), LucideIcons.map),
              const SizedBox(width: 16),
              _buildMetricCard('Total Wards', _wardModels.length.toString(), LucideIcons.mapPin),
              const SizedBox(width: 16),
              _buildMetricCard('Total Users', _users.length.toString(), LucideIcons.users),
            ],
          ),
          const SizedBox(height: 24),
          // Map and Directory Panel
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Map Area
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        FlutterMap(
                          options: MapOptions(
                            initialCenter: const LatLng(12.9716, 77.5946),
                            initialZoom: 12.0,
                            onTap: (tapPosition, point) {
                               bool tappedAWard = false;
                               for (var w in _wardModels) {
                                  if (_isPointInPolygon(point, w.boundary)) {
                                     Zone? parentZone;
                                     for (var z in _zoneModels) {
                                        if (_isWardInZone(w, z)) { parentZone = z; break; }
                                     }
                                     setState(() {
                                        _showDirectoryPanel = true;
                                        _dashboardSelectedZone = parentZone;
                                        _dashboardSelectedWard = w;
                                     });
                                     tappedAWard = true;
                                     break;
                                  }
                               }
                               if (!tappedAWard) {
                                  for (var z in _zoneModels) {
                                     if (_isPointInPolygon(point, z.boundary)) {
                                        setState(() {
                                           _showDirectoryPanel = true;
                                           _dashboardSelectedZone = z;
                                           _dashboardSelectedWard = null;
                                        });
                                        break;
                                     }
                                  }
                               }
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.app',
                            ),
                            Builder(
                              builder: (context) {
                                final camera = MapCamera.of(context);
                                final showWards = camera.zoom >= 13.5;
                                
                                return PolygonLayer(
                                  polygons: [
                                    ..._zoneModels.where((z) => z.boundary.isNotEmpty).map((z) => Polygon(
                                      points: z.boundary,
                                      color: (_dashboardSelectedZone?.id == z.id && _dashboardSelectedWard == null) ? Colors.green.withOpacity(0.3) : Colors.green.withOpacity(0.15),
                                      borderColor: Colors.green,
                                      borderStrokeWidth: (_dashboardSelectedZone?.id == z.id && _dashboardSelectedWard == null) ? 3 : 1.5,
                                    )),
                                    if (showWards)
                                      ..._wardModels.where((w) => w.boundary.isNotEmpty).map((w) => Polygon(
                                        points: w.boundary,
                                        color: (_dashboardSelectedWard?.id == w.id) ? Colors.blue.withOpacity(0.4) : Colors.blue.withOpacity(0.15),
                                        borderColor: Colors.blue,
                                        borderStrokeWidth: (_dashboardSelectedWard?.id == w.id) ? 3 : 1.5,
                                      )),
                                  ],
                                );
                              }
                            ),
                            Builder(
                              builder: (context) {
                                final camera = MapCamera.of(context);
                                final showWards = camera.zoom >= 13.5;
                                
                                final List<Marker> labels = [];
                                
                                if (!showWards) {
                                  for (var z in _zoneModels.where((z) => z.boundary.isNotEmpty)) {
                                    double cLat = 0, cLng = 0;
                                    for (var p in z.boundary) { cLat += p.latitude; cLng += p.longitude; }
                                    labels.add(Marker(
                                      point: LatLng(cLat / z.boundary.length, cLng / z.boundary.length),
                                      width: 140,
                                      height: 40,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.9),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.green.shade700, width: 1.5),
                                          ),
                                          child: Text(
                                            z.name,
                                            style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ));
                                  }
                                }
                                
                                if (showWards) {
                                  for (var w in _wardModels.where((w) => w.boundary.isNotEmpty)) {
                                    double cLat = 0, cLng = 0;
                                    for (var p in w.boundary) { cLat += p.latitude; cLng += p.longitude; }
                                    labels.add(Marker(
                                      point: LatLng(cLat / w.boundary.length, cLng / w.boundary.length),
                                      width: 120,
                                      height: 40,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.85),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.blue.shade700, width: 1),
                                          ),
                                          child: Text(
                                            w.name,
                                            style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 11),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ));
                                  }
                                }

                                return MarkerLayer(markers: labels);
                              }
                            ),
                          ],
                        ),
                        // Info toggle button
                        Positioned(
                          top: 16,
                          right: 16,
                          child: ElevatedButton.icon(
                            onPressed: () => setState(() => _showDirectoryPanel = !_showDirectoryPanel),
                            icon: Icon(_showDirectoryPanel ? LucideIcons.x : LucideIcons.info, size: 18),
                            label: Text(_showDirectoryPanel ? 'Close Directory' : 'Region Directory'),
                            style: ElevatedButton.styleFrom(
                               backgroundColor: Colors.white,
                               foregroundColor: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showDirectoryPanel) const SizedBox(width: 24),
                // Directory Panel
                if (_showDirectoryPanel)
                  Expanded(
                    flex: 1,
                    child: _buildDashboardDirectoryPanel(),
                  )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.blue.shade700, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Color(0xFF1E293B))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardDirectoryPanel() {
    final hasSelection = _dashboardSelectedZone != null || _dashboardSelectedWard != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
               children: [
                  if (hasSelection)
                     IconButton(
                        icon: const Icon(LucideIcons.arrowLeft, size: 20, color: Colors.black87),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() {
                           _dashboardSelectedZone = null;
                           _dashboardSelectedWard = null;
                        }),
                     ),
                  if (hasSelection) const SizedBox(width: 12),
                  Text(hasSelection ? 'Region Details' : 'Region Directory', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
               ]
            ),
          ),
          if (hasSelection)
             Expanded(child: _buildRegionDetailsPanel())
          else
             Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: _zoneModels.map((z) {
                final wardsInZone = _wardModels.where((w) => _isWardInZone(w, z)).toList();
                return ExpansionTile(
                  initiallyExpanded: _dashboardSelectedZone?.id == z.id,
                  onExpansionChanged: (expanded) {
                    if (expanded) {
                      setState(() {
                         _dashboardSelectedZone = z;
                         _dashboardSelectedWard = null;
                      });
                    }
                  },
                  title: Text(z.name, style: TextStyle(fontWeight: FontWeight.bold, color: _dashboardSelectedZone?.id == z.id && _dashboardSelectedWard == null ? Colors.blue.shade700 : Colors.black87)),
                  children: wardsInZone.map((w) {
                    final isSelected = _dashboardSelectedWard?.id == w.id;
                    return ListTile(
                      contentPadding: const EdgeInsets.only(left: 40, right: 16),
                      title: Text(
                        w.name,
                        style: TextStyle(
                           color: isSelected ? Colors.blue.shade700 : Colors.black87,
                           fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      tileColor: isSelected ? Colors.blue.shade50 : Colors.transparent,
                      onTap: () {
                         setState(() {
                           _dashboardSelectedZone = z;
                           _dashboardSelectedWard = isSelected ? null : w;
                         });
                      },
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegionDetailsPanel() {
    final isWard = _dashboardSelectedWard != null;
    final regionName = isWard ? _dashboardSelectedWard!.name : _dashboardSelectedZone!.name;
    
    final officers = _users.where((u) {
       final r = u['role']?.toString().toLowerCase() ?? '';
       final w = u['ward']?.toString().toLowerCase() ?? '';
       final z = u['zone']?.toString().toLowerCase() ?? '';
       if (isWard) {
         return r.contains('ward') && (w.contains(regionName.toLowerCase()) || regionName.toLowerCase().contains(w));
       } else {
         return r.contains('zone') && (z.contains(regionName.toLowerCase()) || regionName.toLowerCase().contains(z));
       }
    }).toList();
    
    final officer = officers.isNotEmpty ? officers.first : null;
    
    final assignedVehicles = _vehicles.where((v) {
       final vWard = v['ward']?.toString().toLowerCase() ?? '';
       final vZone = v['zone']?.toString().toLowerCase() ?? '';
       if (isWard) {
         return vWard.contains(regionName.toLowerCase()) || regionName.toLowerCase().contains(vWard);
       } else {
         return vZone.contains(regionName.toLowerCase()) || regionName.toLowerCase().contains(vZone);
       }
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$regionName Summary', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 16),
          
          if (!isWard) ...[
             Text('Total Wards: ${_wardModels.where((w) => _isWardInZone(w, _dashboardSelectedZone!)).length}', style: const TextStyle(fontSize: 14, color: Colors.black87)),
             const SizedBox(height: 16),
          ],
          
          const Text('Incharge Authority', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          if (officer == null)
            const Text('No officer assigned.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
          else ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blue.shade100,
                  child: Text(officer['name'].toString().substring(0, 1).toUpperCase(), style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(officer['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                      Text(officer['phone'] ?? 'No phone', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: [
                const Text('Registered Fleet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                Text('${assignedVehicles.length} Vehicles', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
             ],
          ),
          const SizedBox(height: 12),
          if (assignedVehicles.isEmpty)
             const Text('No vehicles allocated.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
          else 
             Column(
                children: assignedVehicles.map((v) => Padding(
                   padding: const EdgeInsets.only(bottom: 8),
                   child: Container(
                     padding: const EdgeInsets.all(12),
                     decoration: BoxDecoration(
                       color: Colors.grey.shade50,
                       borderRadius: BorderRadius.circular(8),
                       border: Border.all(color: Colors.grey.shade200),
                     ),
                     child: Row(
                       children: [
                          const Icon(LucideIcons.truck, size: 16, color: Colors.grey),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                               Text(v['number'] ?? 'Unknown', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                               Text(v['type'] ?? 'Compactor', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ]
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                               Text(v['driver_name'] ?? 'No Driver', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                               Text(v['driver_phone'] ?? 'N/A', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ]
                          ),
                       ]
                     )
                   )
                )).toList(),
             ),
        ],
      ),
    );
  }

  Widget _buildOfficerContactRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildRecordItem(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
          child: Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        )
      ],
    );
  }
}
