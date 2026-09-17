import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:latlong2/latlong.dart';
import '../models/ward.dart';
import '../models/zone.dart';
import '../services/role_service.dart';

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
  final List<bool> _moduleExpanded = [true, false, false, false, false, false, false];

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
    _wardsSub?.cancel();
    _zonesSub?.cancel();
    _userNameController.dispose();
    _userEmailController.dispose();
    _userPhoneController.dispose();
    _userPasswordController.dispose();
    _userConfirmPasswordController.dispose();
    RoleService.rolesInitialized.removeListener(_onRolesUpdated);
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
    RoleService.rolesInitialized.addListener(_onRolesUpdated);

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
                  ? [
                      _buildLeftColumn(),
                      const SizedBox(width: 24),
                      _buildRightColumn(),
                    ]
                  : [
                      _buildUserManagementLeftColumn(),
                      const SizedBox(width: 24),
                      _buildUserManagementRightColumn(),
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
          _buildTabItem('Role Management', 0),
          const SizedBox(width: 32),
          _buildTabItem('User Management', 1),
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
                  _buildModulePanel('Street Cleanliness AI', LucideIcons.sparkles, 2, currentRole),
                  const SizedBox(height: 12),
                  _buildModulePanel('Road Health Monitor AI', LucideIcons.car, 3, currentRole),
                  const SizedBox(height: 12),
                  _buildModulePanel('Reports', LucideIcons.fileText, 4, currentRole, isExport: true),
                  const SizedBox(height: 12),
                  _buildModulePanel('Roles & Access', LucideIcons.users, 5, currentRole),
                  const SizedBox(height: 12),
                  _buildModulePanel('Settings', LucideIcons.settings, 6, currentRole, isSettings: true),
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
                    value: _filterRole,
                    icon: const Icon(LucideIcons.chevronDown, size: 14, color: Color(0xFF64748B)),
                    items: ['All Roles', ..._roles.map((r) => r['title'].toString())].map((r) {
                      return DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 14, color: Colors.black)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _filterRole = val);
                    },
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
                      children: const [
                        Expanded(flex: 2, child: Text('User Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Email', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 1, child: Text('Role', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 1, child: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 1, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
                        SizedBox(width: 60, child: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)))),
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
}
