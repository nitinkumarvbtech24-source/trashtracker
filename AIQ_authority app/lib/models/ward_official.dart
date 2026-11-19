import 'package:flutter/material.dart';

class WardOfficial {
  final String id;
  final String name;
  final String designation;
  final String department;
  final int tier; // 1: Apex Governance, 2: Zonal/MLA, 3: Sub-Division Executive, 4: Field Operations
  final String tierTitle;
  final String phone;
  final String email;
  final String? whatsapp;
  final String officeAddress;
  final String? photoUrl;
  final String status;
  final Color accentColor;
  final IconData icon;

  WardOfficial({
    required this.id,
    required this.name,
    required this.designation,
    required this.department,
    required this.tier,
    required this.tierTitle,
    required this.phone,
    required this.email,
    this.whatsapp,
    required this.officeAddress,
    this.photoUrl,
    this.status = 'Active On Duty',
    this.accentColor = Colors.blueAccent,
    this.icon = Icons.person_rounded,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'designation': designation,
    'department': department,
    'tier': tier,
    'tierTitle': tierTitle,
    'phone': phone,
    'email': email,
    'whatsapp': whatsapp,
    'officeAddress': officeAddress,
    'photoUrl': photoUrl,
    'status': status,
  };

  factory WardOfficial.fromJson(Map<String, dynamic> json) => WardOfficial(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    designation: json['designation'] ?? '',
    department: json['department'] ?? '',
    tier: (json['tier'] as num?)?.toInt() ?? 4,
    tierTitle: json['tierTitle'] ?? 'Field Operations',
    phone: json['phone'] ?? '',
    email: json['email'] ?? '',
    whatsapp: json['whatsapp'],
    officeAddress: json['officeAddress'] ?? '',
    photoUrl: json['photoUrl'],
    status: json['status'] ?? 'Active On Duty',
  );
}

