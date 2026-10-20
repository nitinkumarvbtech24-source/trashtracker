import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ward_zone_service.dart';

class RoleService {
  static final List<String> modules = [
    'Master Dashboard',
    'Fleets & Routes',
    'COM&D',
    'Street Cleanliness AI',
    'Road Health Monitor AI',
    'Reports',
    'Roles & Access',
    'Settings'
  ];

  static List<Map<String, dynamic>>? globalRoles;
  static final ValueNotifier<int> rolesUpdated = ValueNotifier(0);
  static final ValueNotifier<Map<String, dynamic>?> currentUserPermissions = ValueNotifier(null);

  static Future<void> initRoles(List<String> allZones, List<String> allWards) async {
    FirebaseFirestore.instance.collection('roles').snapshots().listen((snapshot) async {
      if (snapshot.docs.isEmpty && globalRoles == null) {
        // Seed default roles to Firestore
        final defaultRoles = _getDefaultRoles(allZones, allWards);
        for (var role in defaultRoles) {
          await FirebaseFirestore.instance.collection('roles').doc(role['title']).set(_serializeRole(role));
        }
      } else {
        globalRoles = snapshot.docs.map((doc) => _deserializeRole(doc.data(), doc.id)).toList();
        rolesUpdated.value++;
        _updateCurrentUserPermissions();
      }
    });
  }

  static String? _currentUserRoleTitle;
  static String? _currentUserZone;
  static String? _currentUserWard;

  static void setCurrentUserRole(String roleTitle, {String? zone, String? ward}) {
    _currentUserRoleTitle = roleTitle;
    _currentUserZone = zone;
    _currentUserWard = ward;
    _updateCurrentUserPermissions();
  }

  static String? get currentUserRoleTitle => _currentUserRoleTitle;
  static String? get currentUserZone => _currentUserZone;
  static String? get currentUserWard => _currentUserWard;

  static void _updateCurrentUserPermissions() {
    if (_currentUserRoleTitle != null && globalRoles != null) {
      currentUserPermissions.value = getRolePermissions(_currentUserRoleTitle!);
    }
  }

  static bool hasAllAccess(String moduleName) {
    if (_currentUserRoleTitle == 'Super Admin') return true;
    // Area-restricted users (e.g. Ward Officer or Zone Officer) never have all access
    if (_currentUserWard != null && _currentUserWard != 'All Wards' && _currentUserWard!.trim().isNotEmpty) {
      return false;
    }
    if (_currentUserZone != null && _currentUserZone != 'All Zones' && _currentUserZone!.trim().isNotEmpty) {
      return false;
    }
    final perms = currentUserPermissions.value?[moduleName];
    if (perms == null) return false;
    if (perms['viewAccess'] == 'All Data (All Zones & Wards)') return true;
    final zones = List<String>.from(perms['zones'] ?? []);
    if (zones.contains('All Zones')) return true;
    return false;
  }

  static List<String> getAllowedZonesForModule(String moduleName) {
    if (_currentUserZone != null && _currentUserZone != 'All Zones' && _currentUserZone!.trim().isNotEmpty) {
      return [_currentUserZone!];
    }
    if (_currentUserWard != null && _currentUserWard != 'All Wards' && _currentUserWard!.trim().isNotEmpty) {
      final wardNameClean = _currentUserWard!.trim().toLowerCase();
      for (var z in WardZoneService.instance.zones) {
        final matchingWards = WardZoneService.instance.getWardsForZone(z.name);
        if (matchingWards.any((w) => w.trim().toLowerCase() == wardNameClean)) {
          return [z.name];
        }
      }
    }
    if (hasAllAccess(moduleName)) return []; // Empty means all allowed
    final perms = currentUserPermissions.value?[moduleName];
    if (perms == null) return [];
    return List<String>.from(perms['zones'] ?? []);
  }

  static List<String> getAllowedWardsForModule(String moduleName) {
    if (_currentUserWard != null && _currentUserWard != 'All Wards' && _currentUserWard!.trim().isNotEmpty) {
      return [_currentUserWard!];
    }
    if (_currentUserZone != null && _currentUserZone != 'All Zones' && _currentUserZone!.trim().isNotEmpty) {
      final zoneWards = WardZoneService.instance.getWardsForZone(_currentUserZone!);
      if (zoneWards.isNotEmpty) return zoneWards;
    }
    if (hasAllAccess(moduleName)) return []; // Empty means all allowed
    final perms = currentUserPermissions.value?[moduleName];
    if (perms == null) return [];
    return List<String>.from(perms['wards'] ?? []);
  }

  static bool isSpotAllowed(double lat, double lng, String? docZone, String? docWard, String moduleName) {
    if (hasAllAccess(moduleName)) return true;
    final allowedWards = getAllowedWardsForModule(moduleName);
    final allowedZones = getAllowedZonesForModule(moduleName);

    if (allowedWards.isNotEmpty) {
      return allowedWards.any((targetWard) =>
          WardZoneService.instance.matchesWard(lat: lat, lng: lng, docWard: docWard, targetWard: targetWard));
    }
    if (allowedZones.isNotEmpty) {
      return allowedZones.any((targetZone) =>
          WardZoneService.instance.matchesZone(lat: lat, lng: lng, docZone: docZone, targetZone: targetZone));
    }
    return true;
  }

  static List<Map<String, dynamic>> _getDefaultRoles(List<String> allZones, List<String> allWards) {
    List<Map<String, dynamic>> roles = [
      {
        'title': 'Super Admin',
        'subtitle': 'Full access to all modules and settings',
        'icon': LucideIcons.shield,
        'users': 0, 
        'isSystem': true,
        'color': const Color(0xFF198754),
        'bgColor': const Color(0xFFE6F4EA),
        'permissions': _generateFullPermissions(allZones, allWards),
      },
      {
        'title': 'Authority',
        'subtitle': 'Can access all modules and edit data',
        'icon': LucideIcons.briefcase,
        'users': 0,
        'isSystem': false,
        'color': const Color(0xFF8B5CF6),
        'bgColor': const Color(0xFFF3E8FF),
        'permissions': _generateFullPermissions(allZones, allWards),
      },
      {
        'title': 'Zone Officer',
        'subtitle': 'Access to zone-level data and operations',
        'icon': LucideIcons.users,
        'users': 0,
        'isSystem': false,
        'color': const Color(0xFF3B82F6),
        'bgColor': const Color(0xFFDBEAFE),
        'permissions': _generateDefaultPermissions(),
      },
      {
        'title': 'Ward Officer',
        'subtitle': 'Access to ward-level data and operations',
        'icon': LucideIcons.award,
        'users': 0,
        'isSystem': false,
        'color': const Color(0xFFF97316),
        'bgColor': const Color(0xFFFFEDD5),
        'permissions': _generateDefaultPermissions(),
      },
    ];

    (roles[2]['permissions'] as Map<String, dynamic>)['Master Dashboard']['enabled'] = true;
    (roles[2]['permissions'] as Map<String, dynamic>)['Master Dashboard']['actions'] = {'view': true, 'add': true, 'edit': true, 'delete': false};
    return roles;
  }

  static Map<String, dynamic> _serializeRole(Map<String, dynamic> role) {
    return {
      'title': role['title'],
      'subtitle': role['subtitle'],
      'iconCode': (role['icon'] as IconData).codePoint,
      'isSystem': role['isSystem'],
      'colorValue': (role['color'] as Color).value,
      'bgColorValue': (role['bgColor'] as Color).value,
      'permissions': role['permissions'],
    };
  }

  static Map<String, dynamic> _deserializeRole(Map<String, dynamic> data, String id) {
    Map<String, dynamic> perms = data['permissions'] ?? _generateDefaultPermissions();
    // Ensure all registered modules exist in the parsed permissions
    for (String mod in modules) {
      if (!perms.containsKey(mod)) {
        perms[mod] = {
          'enabled': false,
          'viewAccess': 'Zone Based Access',
          'actions': {'view': false, 'add': false, 'edit': false, 'delete': false},
          'export': false,
          'zones': <String>[],
          'wards': <String>[],
        };
      }
    }

    return {
      'id': id,
      'title': data['title'] ?? id,
      'subtitle': data['subtitle'] ?? '',
      'icon': IconData(data['iconCode'] ?? 0xe000, fontFamily: 'LucideIcons', fontPackage: 'lucide_icons'),
      'isSystem': data['isSystem'] ?? false,
      'color': Color(data['colorValue'] ?? 0xFF000000),
      'bgColor': Color(data['bgColorValue'] ?? 0xFFFFFFFF),
      'permissions': perms,
      'users': 0, 
    };
  }

  static Future<void> saveRole(Map<String, dynamic> role) async {
    final title = role['title'] as String;
    await FirebaseFirestore.instance.collection('roles').doc(title).set(_serializeRole(role));
  }

  static Future<void> deleteRole(String title) async {
    await FirebaseFirestore.instance.collection('roles').doc(title).delete();
  }

  static Map<String, dynamic> _generateDefaultPermissions() {
    Map<String, dynamic> perms = {};
    for (String mod in modules) {
      perms[mod] = {
        'enabled': false,
        'viewAccess': 'Zone Based Access',
        'actions': {'view': false, 'add': false, 'edit': false, 'delete': false},
        'export': false,
        'zones': <String>['North Zone'],
        'wards': <String>['Ward 01', 'Ward 02'],
      };
    }
    return perms;
  }

  static Map<String, dynamic> _generateFullPermissions(List<String> allZones, List<String> allWards) {
    Map<String, dynamic> perms = {};
    for (String mod in modules) {
      perms[mod] = {
        'enabled': true,
        'viewAccess': 'All Data (All Zones & Wards)',
        'actions': {'view': true, 'add': true, 'edit': true, 'delete': true},
        'export': true,
        'zones': List<String>.from(allZones),
        'wards': List<String>.from(allWards),
      };
    }
    return perms;
  }

  static Map<String, dynamic>? getRolePermissions(String roleTitle) {
    if (globalRoles == null) return null;
    try {
      return globalRoles!.firstWhere((r) => r['title'] == roleTitle)['permissions'];
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> generateDefaultPermissionsForNewRole() {
    return _generateDefaultPermissions();
  }
}
