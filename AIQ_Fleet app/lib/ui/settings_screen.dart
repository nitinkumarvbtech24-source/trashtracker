import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:upgrader/upgrader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import '../services/auth_service.dart';
import '../services/camera_service.dart';
import 'local_folder_screen.dart';
import '../constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = 'Loading...';
  Map<String, String> _savedLinks = {};
  String? _selectedLinkKey;
  bool _isBackingUp = false;

  Future<void> _backupTrainingDatabase() async {
    if (_isBackingUp) return;
    setState(() => _isBackingUp = true);
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final pendingDir = Directory('${directory.path}/pending_training_images');
      if (!await pendingDir.exists()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pending images to backup.')));
        setState(() => _isBackingUp = false);
        return;
      }

      int successCount = 0;
      int failCount = 0;

      final entities = await pendingDir.list(recursive: true).toList();
      final imageFiles = entities.whereType<File>().where((e) => e.path.endsWith('.jpg')).toList();

      if (imageFiles.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pending images to backup.')));
        setState(() => _isBackingUp = false);
        return;
      }

      for (var imageFile in imageFiles) {
        try {
          final parentDir = imageFile.parent;
          final dateStr = parentDir.uri.pathSegments[parentDir.uri.pathSegments.length - 2];
          final folderName = parentDir.parent.uri.pathSegments[parentDir.parent.uri.pathSegments.length - 2];
          final fileName = imageFile.uri.pathSegments.last;
          final timestamp = fileName.replaceAll('.jpg', '');
          
          final metaFile = File('${parentDir.path}/$timestamp.json');
          Map<String, dynamic> metadata = {};
          if (await metaFile.exists()) {
             metadata = jsonDecode(await metaFile.readAsString());
          }

          final bytes = await imageFile.readAsBytes();
          final base64Image = base64Encode(bytes);

          final response = await http.post(
            Uri.parse('$GARBAGE_AI_URL/upload_training'),
            headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
            body: json.encode({
              'image': 'data:image/jpeg;base64,$base64Image',
              'vehicle_number': metadata['vehicle_number'] ?? 'Unknown',
              'driver_name': metadata['driver_name'] ?? 'Unknown',
            }),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final resBody = json.decode(response.body);
            final serverImageUrl = resBody['image_url'];

            await FirebaseFirestore.instance.collection('training_data').add({
              'folder_name': folderName,
              'date': dateStr,
              'image_url': '$GARBAGE_AI_URL$serverImageUrl',
              'timestamp': FieldValue.serverTimestamp(),
              'lat': metadata['lat'] ?? 0.0,
              'lng': metadata['lng'] ?? 0.0,
              'vehicle_number': metadata['vehicle_number'] ?? 'Unknown',
              'driver_name': metadata['driver_name'] ?? 'Unknown',
            });

            await imageFile.delete();
            if (await metaFile.exists()) {
              await metaFile.delete();
            }
            successCount++;
          } else {
            debugPrint("Backup failed for $imageFile with status: ${response.statusCode}");
            failCount++;
          }
        } catch (e) {
          debugPrint("Failed to backup $imageFile: $e");
          failCount++;
        }
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup complete! Success: $successCount, Failed: $failCount')));

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup error: $e')));
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }
  void initState() {
    super.initState();
    _initPackageInfo();
    _loadSavedLinks();

  }

  Future<void> _loadSavedLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? linksJson = prefs.getString('saved_tunnels');
    
    Map<String, String> links = {};
    if (linksJson != null && linksJson.isNotEmpty) {
      links = Map<String, String>.from(json.decode(linksJson));
    }
    
    if (links.isEmpty) {
      links['Default Ngrok'] = GARBAGE_AI_URL;
    }
    
    String activeUrl = GARBAGE_AI_URL;
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
    await prefs.setString('saved_tunnels', json.encode(_savedLinks));
    await prefs.setString('garbage_ai_url', url);
    GARBAGE_AI_URL = url;
    
    setState(() {
      _selectedLinkKey = name;
    });
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
    final auth = context.watch<AuthService>();
    final cameraService = context.watch<CameraService>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings & Account',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              
              _buildSectionTitle('Account Profile'),
              const SizedBox(height: 16),
              _buildInfoCard(
                icon: Icons.person_rounded,
                title: 'Driver Name',
                value: auth.driverName ?? 'Unknown Driver',
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 12),
              _buildInfoCard(
                icon: Icons.local_shipping_rounded,
                title: 'Vehicle Number',
                value: auth.vehicleNumber ?? 'Not Assigned',
                color: Colors.orangeAccent,
              ),
              
              const SizedBox(height: 32),

              _buildSectionTitle('Connection Settings'),
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
              

              
              _buildSectionTitle('App Information'),
              const SizedBox(height: 16),
              _buildInfoCard(
                icon: Icons.info_outline_rounded,
                title: 'Current Version',
                value: _appVersion,
                color: Colors.purpleAccent,
              ),
              const SizedBox(height: 16),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Check for updates manually
                    Upgrader.clearSavedSettings();
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

              const SizedBox(height: 32),
              
              _buildSectionTitle('Device Information'),
              const SizedBox(height: 16),
              _buildInfoCard(
                icon: Icons.perm_device_information_rounded,
                title: 'Device UID',
                value: auth.deviceId ?? 'Generating...',
                color: Colors.greenAccent,
                isMonospace: true,
              ),
              
              const SizedBox(height: 32),
              
              _buildSectionTitle('Training Database'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: SwitchListTile(
                  title: const Text('Auto Capture Mode', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Capture continuously at intervals', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: cameraService.isTrainingAutoMode,
                  activeColor: Colors.orangeAccent,
                  onChanged: (val) {
                    cameraService.setTrainingAutoMode(val);
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isBackingUp ? null : _backupTrainingDatabase,
                  icon: _isBackingUp ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.cloud_upload_rounded, color: Colors.white),
                  label: Text(_isBackingUp ? 'Backing Up...' : 'Manual Backup', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await Gal.open();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open gallery: $e')));
                      }
                    }
                  },
                  icon: const Icon(Icons.photo_library_rounded, color: Colors.white),
                  label: const Text('Open Device Gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              
              const SizedBox(height: 48),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    context.read<AuthService>().logout();
                  },
                  icon: const Icon(Icons.power_settings_new_rounded, color: Colors.white),
                  label: const Text('Secure Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              
              const SizedBox(height: 120), // Bottom padding for navbar
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white54,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon, 
    required String title, 
    required String value, 
    required Color color,
    bool isMonospace = false,
  }) {
    return Container(
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
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 16, 
                    color: Colors.white, 
                    fontWeight: FontWeight.bold,
                  ).copyWith(
                    fontFamily: isMonospace ? 'monospace' : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
