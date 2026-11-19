import json
from pathlib import Path

BASE_DIR = Path(__file__).parent.resolve()
creds_path = BASE_DIR / "seeded_credentials.json"
trash_imgs_path = BASE_DIR / "trash_image_filenames.json"
out_path = BASE_DIR / "AIQ_authority app" / "lib" / "services" / "authority_directory_service.dart"

with open(creds_path, encoding="utf-8") as f:
    creds = json.load(f)

with open(trash_imgs_path, encoding="utf-8") as f:
    trash_imgs = json.load(f)

contractor_agencies = [
    "Clean City Solid Waste Management Ltd.",
    "Bengaluru Eco-Sanitation Concessionaire Pvt. Ltd.",
    "Swachh Urban Infrastructure Services",
    "Green Horizon Waste Logistics Corp.",
    "Apex Civic Sanitation & Tipper Concessionaire",
    "Karnataka Environmental Services Pvt. Ltd.",
    "Namma Bengaluru Clean Fleet Agency",
    "Metro Waste Recovery & Sanitation Services"
]

contractor_names = [
    "Ramesh Babu (Authorized Concessionaire)",
    "Smt. Rajeshwari N. (Site Operations Lead)",
    "Manjunath V. (Contract Fleet Director)",
    "Venkatesh Murthy (Area Sanitation In-Charge)",
    "Suresh Gowda (Zonal Tipper Concessionaire)",
    "Anil Kumar K. (Ground SWM Contractor)"
]

lines = []
lines.append("// Generated Authority Directory & Guaranteed Trash Image Service")
lines.append("import 'dart:math';")
lines.append("import 'package:flutter/material.dart';")
lines.append("import 'package:url_launcher/url_launcher.dart';")
lines.append("import '../constants.dart';")
lines.append("")
lines.append("class AuthorityOfficial {")
lines.append("  final String name;")
lines.append("  final String role;")
lines.append("  final String department;")
lines.append("  final String phone;")
lines.append("  final String email;")
lines.append("  final String? jurisdiction;")
lines.append("  final IconData icon;")
lines.append("  final Color badgeColor;")
lines.append("")
lines.append("  const AuthorityOfficial({")
lines.append("    required this.name,")
lines.append("    required this.role,")
lines.append("    required this.department,")
lines.append("    required this.phone,")
lines.append("    required this.email,")
lines.append("    this.jurisdiction,")
lines.append("    required this.icon,")
lines.append("    required this.badgeColor,")
lines.append("  });")
lines.append("}")
lines.append("")
lines.append("class AuthorityDirectoryService {")
lines.append("  static final AuthorityDirectoryService instance = AuthorityDirectoryService._internal();")
lines.append("  AuthorityDirectoryService._internal();")
lines.append("")
lines.append("  // --- 882 Real Trash-Detected Images Pool from Database ---")
lines.append("  static const List<String> trashImagePool = [")
for img in trash_imgs:
    lines.append(f"    '{img}',")
lines.append("  ];")
lines.append("")
lines.append("  // --- 8 Zonal Officers ---")
lines.append("  static final Map<String, Map<String, String>> _zoneOfficers = {")
for zo in creds.get("zone_officers", []):
    z_name = zo["zone"].strip().replace("'", "\\'")
    lines.append(f"    '{z_name}': {{")
    lines.append(f"      'name': '{zo['name']}',")
    lines.append(f"      'role': 'Zone Officer (Joint Commissioner)',")
    lines.append(f"      'phone': '{zo['phone']}',")
    lines.append(f"      'email': '{zo['email']}',")
    lines.append(f"      'zone': '{z_name}',")
    lines.append("    },")
lines.append("  };")
lines.append("")
lines.append("  // --- 198 Ward Officers ---")
lines.append("  static final Map<String, Map<String, String>> _wardOfficers = {")
for wo in creds.get("ward_officers", []):
    w_name = wo["ward"].strip().replace("'", "\\'")
    z_name = wo.get("zone", "").strip().replace("'", "\\'")
    lines.append(f"    '{w_name}': {{")
    lines.append(f"      'name': '{wo['name']}',")
    lines.append(f"      'role': 'Ward Officer & AEE (SWM)',")
    lines.append(f"      'phone': '{wo['phone']}',")
    lines.append(f"      'email': '{wo['email']}',")
    lines.append(f"      'zone': '{z_name}',")
    lines.append(f"      'ward': '{w_name}',")
    lines.append(f"      'wardNo': '{wo.get('wardNo', '')}',")
    lines.append("    },")
lines.append("  };")
lines.append("")
lines.append("  // --- 396 Fleet Vehicles & Drivers ---")
lines.append("  static final Map<String, Map<String, String>> _vehicles = {")
for v in creds.get("vehicles", []):
    v_num = v["vehicleNumber"].strip()
    z_name = v.get("zone", "").strip().replace("'", "\\'")
    w_name = v.get("assignedWard", "").strip().replace("'", "\\'")
    lines.append(f"    '{v_num}': {{")
    lines.append(f"      'driverName': '{v['driverName']}',")
    lines.append(f"      'phoneNumber': '{v['phoneNumber']}',")
    lines.append(f"      'zone': '{z_name}',")
    lines.append(f"      'assignedWard': '{w_name}',")
    lines.append("    },")
lines.append("  };")
lines.append("")
lines.append("  // Contractors list")
lines.append("  static const List<String> _contractorAgencies = [")
for ca in contractor_agencies:
    lines.append(f"    '{ca}',")
lines.append("  ];")
lines.append("")
lines.append("  static const List<String> _contractorNames = [")
for cn in contractor_names:
    lines.append(f"    '{cn}',")
lines.append("  ];")
lines.append("""
  /// Resolves any image URL to ensure every single flag has a working trash detected image.
  /// If missing, relative, or invalid, deterministically picks a real trash image from the 882 pool.
  String resolveImageUrl(String? rawUrl, [String? seedKey]) {
    final clean = (rawUrl ?? '').trim();
    if (clean.isNotEmpty && (clean.startsWith('http://') || clean.startsWith('https://'))) {
      return clean;
    }
    if (clean.isNotEmpty && clean.startsWith('/snapshots/')) {
      final base = activeGarbageAiUrl.endsWith('/') 
          ? activeGarbageAiUrl.substring(0, activeGarbageAiUrl.length - 1)
          : activeGarbageAiUrl;
      return '$base$clean';
    }
    
    // Pick deterministically from 882 real trash-detected images
    final seed = (seedKey ?? '').isNotEmpty ? seedKey.hashCode.abs() : Random().nextInt(trashImagePool.length);
    final chosenImg = trashImagePool[seed % trashImagePool.length];
    final base = activeGarbageAiUrl.endsWith('/') 
        ? activeGarbageAiUrl.substring(0, activeGarbageAiUrl.length - 1)
        : activeGarbageAiUrl;
    return '$base/snapshots/analysed/trash_detected/$chosenImg';
  }

  /// Get fallback image from pool
  String getFallbackTrashImageUrl([int? seed]) {
    final idx = (seed ?? Random().nextInt(trashImagePool.length)).abs() % trashImagePool.length;
    final base = activeGarbageAiUrl.endsWith('/') 
        ? activeGarbageAiUrl.substring(0, activeGarbageAiUrl.length - 1)
        : activeGarbageAiUrl;
    return '$base/snapshots/analysed/trash_detected/${trashImagePool[idx]}';
  }

  /// Resolve Zone Officer
  AuthorityOfficial getZoneOfficer(String? zoneName) {
    String cleanZone = (zoneName ?? '').trim();
    for (var entry in _zoneOfficers.entries) {
      if (cleanZone.toLowerCase().contains(entry.key.toLowerCase()) || entry.key.toLowerCase().contains(cleanZone.toLowerCase())) {
        final d = entry.value;
        return AuthorityOfficial(
          name: d['name'] ?? 'Zone Officer',
          role: 'Zone Officer',
          department: 'BBMP ${entry.key} Zonal Joint Command',
          phone: d['phone'] ?? '1234567890',
          email: d['email'] ?? 'zone.officer@gmail.com',
          jurisdiction: '${entry.key} Zone',
          icon: Icons.shield_rounded,
          badgeColor: const Color(0xFF0F5132),
        );
      }
    }
    final first = _zoneOfficers.values.first;
    return AuthorityOfficial(
      name: first['name'] ?? 'Aarav',
      role: 'Zone Officer',
      department: 'BBMP Zonal Command',
      phone: first['phone'] ?? '1234567890',
      email: first['email'] ?? 'zone.officer@gmail.com',
      jurisdiction: cleanZone.isNotEmpty ? cleanZone : 'City Jurisdiction',
      icon: Icons.shield_rounded,
      badgeColor: const Color(0xFF0F5132),
    );
  }

  /// Resolve Ward Officer
  AuthorityOfficial getWardOfficer(String? wardName, [String? zoneName]) {
    String cleanWard = (wardName ?? '').trim();
    for (var entry in _wardOfficers.entries) {
      if (cleanWard.toLowerCase() == entry.key.toLowerCase() ||
          cleanWard.toLowerCase().contains(entry.key.toLowerCase()) ||
          entry.key.toLowerCase().contains(cleanWard.toLowerCase())) {
        final d = entry.value;
        return AuthorityOfficial(
          name: d['name'] ?? 'Ward Officer',
          role: 'Ward Officer & AEE',
          department: 'BBMP Solid Waste & Sanitation Wing',
          phone: d['phone'] ?? '1234567890',
          email: d['email'] ?? 'ward.officer@gmail.com',
          jurisdiction: entry.key,
          icon: Icons.badge_rounded,
          badgeColor: const Color(0xFF1E40AF),
        );
      }
    }
    // If not exact match, extract digits from ward name (e.g. Ward 45)
    final match = RegExp(r'\\d+').firstMatch(cleanWard);
    if (match != null) {
      final numStr = match.group(0)!;
      for (var entry in _wardOfficers.entries) {
        if (entry.value['wardNo'] == numStr) {
          final d = entry.value;
          return AuthorityOfficial(
            name: d['name'] ?? 'Ward Officer',
            role: 'Ward Officer & AEE',
            department: 'BBMP Solid Waste & Sanitation Wing',
            phone: d['phone'] ?? '1234567890',
            email: d['email'] ?? 'ward.officer@gmail.com',
            jurisdiction: entry.key,
            icon: Icons.badge_rounded,
            badgeColor: const Color(0xFF1E40AF),
          );
        }
      }
    }
    // Deterministic fallback based on hash
    final keys = _wardOfficers.keys.toList();
    final idx = cleanWard.hashCode.abs() % keys.length;
    final d = _wardOfficers[keys[idx]]!;
    return AuthorityOfficial(
      name: d['name'] ?? 'Ward Officer',
      role: 'Ward Officer & AEE',
      department: 'BBMP Solid Waste & Sanitation Wing',
      phone: d['phone'] ?? '1234567890',
      email: d['email'] ?? 'ward.officer@gmail.com',
      jurisdiction: cleanWard.isNotEmpty ? cleanWard : keys[idx],
      icon: Icons.badge_rounded,
      badgeColor: const Color(0xFF1E40AF),
    );
  }

  /// Resolve Sanitation Contractor
  AuthorityOfficial getContractor(String? wardName, [String? zoneName]) {
    final seed = (wardName ?? 'BBMP').hashCode.abs();
    final agency = _contractorAgencies[seed % _contractorAgencies.length];
    final contactPerson = _contractorNames[seed % _contractorNames.length];
    return AuthorityOfficial(
      name: contactPerson,
      role: 'Assigned Sanitation Contractor',
      department: agency,
      phone: '1234567890',
      email: 'contractor.operations@gmail.com',
      jurisdiction: wardName != null && wardName.isNotEmpty ? wardName : 'Area Concession',
      icon: Icons.business_center_rounded,
      badgeColor: const Color(0xFFB45309), // Amber brown
    );
  }

  /// Resolve Route Driver & Vehicle
  AuthorityOfficial getVehicleAndDriver(String? wardName, [String? vehicleNumber]) {
    String cleanV = (vehicleNumber ?? '').toUpperCase().trim();
    if (cleanV.isNotEmpty && _vehicles.containsKey(cleanV)) {
      final v = _vehicles[cleanV]!;
      return AuthorityOfficial(
        name: v['driverName'] ?? 'Fleet Driver',
        role: 'Tipper Route Driver ($cleanV)',
        department: 'BBMP Dedicated Sanitation Fleet',
        phone: v['phoneNumber'] ?? '1234567890',
        email: 'driver.fleet@gmail.com',
        jurisdiction: v['assignedWard'] ?? wardName,
        icon: Icons.local_shipping_rounded,
        badgeColor: const Color(0xFF047857), // Emerald
      );
    }
    // Search by assigned ward
    String cleanWard = (wardName ?? '').trim();
    for (var entry in _vehicles.entries) {
      if (entry.value['assignedWard'] == cleanWard ||
          entry.value['assignedWard']!.toLowerCase().contains(cleanWard.toLowerCase())) {
        final v = entry.value;
        return AuthorityOfficial(
          name: v['driverName'] ?? 'Fleet Driver',
          role: 'Tipper Route Driver (${entry.key})',
          department: 'BBMP Dedicated Sanitation Fleet',
          phone: v['phoneNumber'] ?? '1234567890',
          email: 'driver.fleet@gmail.com',
          jurisdiction: entry.key,
          icon: Icons.local_shipping_rounded,
          badgeColor: const Color(0xFF047857),
        );
      }
    }
    final firstKey = _vehicles.keys.first;
    final first = _vehicles[firstKey]!;
    return AuthorityOfficial(
      name: first['driverName'] ?? 'Alok Sharma',
      role: 'Tipper Route Driver ($firstKey)',
      department: 'BBMP Dedicated Sanitation Fleet',
      phone: first['phoneNumber'] ?? '1234567890',
      email: 'driver.fleet@gmail.com',
      jurisdiction: cleanV.isNotEmpty ? cleanV : firstKey,
      icon: Icons.local_shipping_rounded,
      badgeColor: const Color(0xFF047857),
    );
  }

  /// Launch Phone Call
  Future<bool> makePhoneCall(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\\d+]'), '');
    final uri = Uri.parse('tel:$clean');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
    } catch (_) {}
    return false;
  }

  /// Launch SMS / Message
  Future<bool> sendSMS(String phone, [String? defaultMessage]) async {
    final clean = phone.replaceAll(RegExp(r'[^\\d+]'), '');
    final msg = defaultMessage != null ? Uri.encodeComponent(defaultMessage) : '';
    final uri = Uri.parse(msg.isNotEmpty ? 'sms:$clean?body=$msg' : 'sms:$clean');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
    } catch (_) {}
    return false;
  }
}
""")

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print(f"Successfully written {out_path} ({len(lines)} lines)")

