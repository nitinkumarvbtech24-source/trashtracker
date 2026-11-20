import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
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
    final String? v5LinksJson = prefs.getString('saved_tunnels_v5');
    final String? v7LinksJson = prefs.getString('saved_tunnels_v7');
    
    Map<String, String> links = {};
    String linksString = (MODEL_VERSION == 7 ? v7LinksJson : (MODEL_VERSION == 5 ? v5LinksJson : (MODEL_VERSION == 3 ? v3LinksJson : (MODEL_VERSION == 2 ? v2LinksJson : linksJson)))) ?? '';
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
    if (MODEL_VERSION == 7) {
        await prefs.setString('saved_tunnels_v7', json.encode(_savedLinks));
        await prefs.setString('garbage_ai_v7_url', url);
        GARBAGE_AI_V7_URL = url;
    } else if (MODEL_VERSION == 5) {
        await prefs.setString('saved_tunnels_v5', json.encode(_savedLinks));
        await prefs.setString('garbage_ai_v5_url', url);
        GARBAGE_AI_V5_URL = url;
    } else if (MODEL_VERSION == 3) {
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
    updateBackendUrl(url);
    
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
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('Add / Connect Backend', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5132),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Auto-Sync Live URL (Code: 5002)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        try {
                          final snap = await FirebaseFirestore.instance.collection('settings').doc('server_config').get();
                          if (snap.exists && snap.data() != null) {
                            final remote = snap.data()!['active_backend_url'] as String?;
                            if (remote != null && remote.isNotEmpty) {
                              setDialogState(() {
                                urlController.text = remote;
                                if (nameController.text.isEmpty) {
                                  nameController.text = remote.contains('ngrok') ? 'Ngrok Static' : (remote.contains('trycloudflare') ? 'Cloudflare Live' : 'Active Server');
                                }
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Synced: $remote'), backgroundColor: const Color(0xFF0F5132)));
                              }
                            }
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.redAccent));
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ActionChip(
                          label: const Text('1: Ngrok', style: TextStyle(fontSize: 10, color: Colors.white70)),
                          backgroundColor: const Color(0xFF334155),
                          onPressed: () {
                            setDialogState(() {
                              urlController.text = 'https://divided-headache-slogan.ngrok-free.dev';
                              if (nameController.text.isEmpty) nameController.text = 'Ngrok Static';
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('2: Cloudflare', style: TextStyle(fontSize: 10, color: Colors.white70)),
                          backgroundColor: const Color(0xFF334155),
                          onPressed: () async {
                            try {
                              final snap = await FirebaseFirestore.instance.collection('settings').doc('server_config').get();
                              final cf = snap.data()?['cloudflare_url'] ?? snap.data()?['active_backend_url'];
                              if (cf != null && cf.toString().isNotEmpty) {
                                setDialogState(() {
                                  urlController.text = cf.toString();
                                  if (nameController.text.isEmpty) nameController.text = 'Cloudflare Live';
                                });
                              }
                            } catch (_) {}
                          },
                        ),
                        ActionChip(
                          label: const Text('3: Local 5002', style: TextStyle(fontSize: 10, color: Colors.white70)),
                          backgroundColor: const Color(0xFF334155),
                          onPressed: () {
                            setDialogState(() {
                              urlController.text = 'http://127.0.0.1:5002';
                              if (nameController.text.isEmpty) nameController.text = 'Local 5002';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Link Name (e.g. WiFi 1 / Ngrok)',
                        labelStyle: TextStyle(color: Colors.white54),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'URL or Code (5002 / 1 / 2 / 3)',
                        labelStyle: TextStyle(color: Colors.white54),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () async {
                    String name = nameController.text.trim();
                    String url = urlController.text.trim();

                    // Expand quick numeric shortcuts
                    if (url == '1') {
                      url = 'https://divided-headache-slogan.ngrok-free.dev';
                      if (name.isEmpty) name = 'Ngrok Static';
                    } else if (url == '2') {
                      try {
                        final snap = await FirebaseFirestore.instance.collection('settings').doc('server_config').get();
                        url = (snap.data()?['cloudflare_url'] ?? snap.data()?['active_backend_url'] ?? 'https://divided-headache-slogan.ngrok-free.dev').toString();
                      } catch (_) {
                        url = 'https://divided-headache-slogan.ngrok-free.dev';
                      }
                      if (name.isEmpty) name = 'Cloudflare Live';
                    } else if (url == '5002') {
                      try {
                        final snap = await FirebaseFirestore.instance.collection('settings').doc('server_config').get();
                        url = (snap.data()?['active_backend_url'] ?? 'https://divided-headache-slogan.ngrok-free.dev').toString();
                      } catch (_) {
                        url = 'https://divided-headache-slogan.ngrok-free.dev';
                      }
                      if (name.isEmpty) name = 'Server 5002';
                    } else if (url == '3') {
                      url = 'http://127.0.0.1:5002';
                      if (name.isEmpty) name = 'Local 5002';
                    }

                    if (url.isNotEmpty) {
                      if (!url.startsWith('http://') && !url.startsWith('https://')) {
                        url = 'https://$url';
                      }
                      if (name.isEmpty) name = 'Custom Link';
                      _saveLinksAndSet(name, url);
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Save & Connect', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
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
                      Text('V7 + MobileNetV3 (Port 5001)', style: GoogleFonts.inter(fontSize: 14, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('YOLOv7 (Object Detection) + MobileNetV3 (Cleanliness Classification)', style: GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showAISettingsDialog,
                      icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
                      label: const Text('AI Model Settings & Thresholds', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5132),
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
                    } catch (e) {
                      debugPrint('Error saving settings: $e');
                    }
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
