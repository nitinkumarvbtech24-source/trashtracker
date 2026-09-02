import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';
import 'training_database_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = 'Loading...';
  Map<String, String> _savedLinks = {};
  String? _selectedLinkKey;
  bool _allowRouteAssignment = false;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
    _loadSavedLinks();
    _loadFleetPermissions();
  }

  Future<void> _loadFleetPermissions() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('fleet_permissions').get();
      if (doc.exists && doc.data() != null) {
        setState(() {
          _allowRouteAssignment = doc.data()!['allowRouteAssignment'] ?? false;
        });
      }
    } catch (e) {
      debugPrint("Error loading fleet permissions: $e");
    }
  }

  Future<void> _updateFleetPermissions(bool value) async {
    try {
      await FirebaseFirestore.instance.collection('settings').doc('fleet_permissions').set(
        {'allowRouteAssignment': value},
        SetOptions(merge: true),
      );
      setState(() {
        _allowRouteAssignment = value;
      });
    } catch (e) {
      debugPrint("Error updating fleet permissions: $e");
    }
  }

  Future<void> _loadSavedLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? linksJson = prefs.getString('saved_tunnels');
    final String? v2LinksJson = prefs.getString('saved_tunnels_v2');
    final String? v3LinksJson = prefs.getString('saved_tunnels_v3');
    
    Map<String, String> links = {};
    String linksString = (MODEL_VERSION == 3 ? v3LinksJson : (MODEL_VERSION == 2 ? v2LinksJson : linksJson)) ?? '';
    if (linksString.isNotEmpty) {
      links = Map<String, String>.from(json.decode(linksString));
    }
    
    String activeUrl = activeGarbageAiUrl;
    
    if (links.isEmpty) {
      links['Default Ngrok'] = activeUrl;
    }
    
    String? activeKey;
    
    links.forEach((key, value) {
      if (value == activeUrl) {
        activeKey = key;
      }
    });
    
    if (activeKey == null) {
      activeKey = 'Custom Local';
      links[activeKey!] = activeUrl;
    }

    setState(() {
      _savedLinks = links;
      _selectedLinkKey = activeKey;
    });
  }

  Future<void> _saveLinksAndSet(String name, String url) async {
    final prefs = await SharedPreferences.getInstance();
    
    _savedLinks[name] = url;
    if (MODEL_VERSION == 3) {
        await prefs.setString('saved_tunnels_v3', json.encode(_savedLinks));
        await prefs.setString('garbage_ai_v3_url', url);
        GARBAGE_AI_V3_URL = url;
    } else if (MODEL_VERSION == 2) {
        await prefs.setString('saved_tunnels_v2', json.encode(_savedLinks));
        await prefs.setString('garbage_ai_v2_url', url);
        GARBAGE_AI_V2_URL = url;
    } else {
        await prefs.setString('saved_tunnels', json.encode(_savedLinks));
        await prefs.setString('garbage_ai_url', url);
        GARBAGE_AI_URL = url;
    }
    
    setState(() {
      _selectedLinkKey = name;
    });
  }

  Future<void> _setModelVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('model_version', version);
    MODEL_VERSION = version;
    await _loadSavedLinks();
  }

  void _showAddLinkDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Add Tunnel Link', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Link Name (e.g. WiFi 1)', labelStyle: TextStyle(color: Colors.white54)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'URL', labelStyle: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () {
                String name = nameController.text.trim();
                String url = urlController.text.trim();
                if (name.isNotEmpty && url.isNotEmpty) {
                  if (!url.startsWith('http://') && !url.startsWith('https://')) {
                    url = 'https://$url';
                  }
                  _saveLinksAndSet(name, url);
                  Navigator.pop(context);
                }
              },
              child: const Text('Save', style: TextStyle(color: Colors.greenAccent)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = '${info.version}+${info.buildNumber}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'System Settings',
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            
            Text(
              'Connection Settings',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Model Version', style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
                      DropdownButton<int>(
                        dropdownColor: const Color(0xFF1E293B),
                        value: MODEL_VERSION,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('V1 (Port 5000)')),
                          DropdownMenuItem(value: 2, child: Text('V2 (Port 5001)')),
                          DropdownMenuItem(value: 3, child: Text('V3 (Port 5002)')),
                        ],
                        onChanged: (val) {
                          if (val != null) _setModelVersion(val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),
                  Text('Active Tunnel Server', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                  const SizedBox(height: 8),
                  if (_savedLinks.isNotEmpty)
                    DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF1E293B),
                      value: _selectedLinkKey,
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      items: _savedLinks.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text('${entry.key} (${entry.value})', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          _saveLinksAndSet(val, _savedLinks[val]!);
                        }
                      },
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showAddLinkDialog,
                      icon: const Icon(Icons.add_link_rounded, color: Colors.greenAccent),
                      label: const Text('Add New Link', style: TextStyle(color: Colors.greenAccent)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.greenAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'Fleet Management',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: SwitchListTile(
                title: const Text('Fleet Route Assigner Access', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Allow fleet drivers to map and assign their own routes', style: TextStyle(color: Colors.white54, fontSize: 12)),
                value: _allowRouteAssignment,
                activeColor: Colors.blueAccent,
                onChanged: _updateFleetPermissions,
              ),
            ),
            
            const SizedBox(height: 32),

            Text(
              'App Information',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.info_outline_rounded, color: Colors.purpleAccent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Version',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _appVersion,
                          style: GoogleFonts.inter(
                            fontSize: 16, 
                            color: Colors.white, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Upgrader clear cache forces a re-check next time, 
                  // or if UpgradeAlert is in the tree it will evaluate again
                  Upgrader.clearSavedSettings();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Checking for updates...')),
                  );
                },
                icon: const Icon(Icons.system_update_rounded, color: Colors.white),
                label: const Text('Check for Updates', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent.withOpacity(0.8),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
              
              const SizedBox(height: 24),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TrainingDatabaseScreen()));
                  },
                  icon: const Icon(Icons.storage_rounded, color: Colors.white),
                  label: const Text('Training Database', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
