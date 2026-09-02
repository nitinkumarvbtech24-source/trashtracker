import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../constants.dart';

class DatabaseScreen extends StatefulWidget {
  final String? vehicleFilter;
  const DatabaseScreen({super.key, this.vehicleFilter});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _timer;
  List<dynamic> _snapshots = [];
  Map<String, dynamic> _stats = {"total": 0, "Clean Road": 0, "Slightly Dirty Road": 0, "Very Dirty Road": 0, "Not a Road": 0};
  String _selectedFolder = 'All';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _fetchData();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      _fetchData();
    });
  }

  Future<void> _fetchData() async {
    try {
      List<dynamic> allSnaps = [];

      try {
        final res1 = await http.get(Uri.parse('$activeGarbageAiUrl/api/snapshots'), headers: {'ngrok-skip-browser-warning': 'true'});
        if (res1.statusCode == 200) {
          final data = json.decode(res1.body);
          allSnaps.addAll(data['snapshots'] ?? []);
        }
      } catch (e) {
        debugPrint("Error fetching Garbage AI: $e");
      }

      try {
        final res2 = await http.get(Uri.parse('$HEALTH_AI_URL/api/snapshots'), headers: {'ngrok-skip-browser-warning': 'true'});
        if (res2.statusCode == 200) {
          final data = json.decode(res2.body);
          allSnaps.addAll(data['snapshots'] ?? []);
        }
      } catch (e) {
        debugPrint("Error fetching Road Health AI from HEALTH_AI_URL: $e");
        try {
            final res3 = await http.get(Uri.parse('http://127.0.0.1:5002/api/snapshots'));
            if (res3.statusCode == 200) {
              final data = json.decode(res3.body);
              allSnaps.addAll(data['snapshots'] ?? []);
            }
        } catch (e2) {
            debugPrint("Error fetching Road Health AI from localhost: $e2");
        }
      }
      
      // Sort by timestamp descending
      allSnaps.sort((a, b) {
        final ta = a['timestamp'] ?? '';
        final tb = b['timestamp'] ?? '';
        return tb.compareTo(ta);
      });

      if (mounted) {
        setState(() {
          if (widget.vehicleFilter != null) {
            allSnaps = allSnaps.where((s) => s['vehicle_number'] == widget.vehicleFilter).toList();
          }
          _snapshots = allSnaps;
          _stats = {
            "total": _snapshots.length,
            "Clean Road": _snapshots.where((s) => s['display_class'] == 'Clean Road').length,
            "Slightly Dirty Road": _snapshots.where((s) => s['display_class'] == 'Slightly Dirty Road').length,
            "Very Dirty Road": _snapshots.where((s) => s['display_class'] == 'Very Dirty Road').length,
            "Pothole Detected": _snapshots.where((s) => s['display_class'] == 'Pothole Detected').length,
            "Not a Road": _snapshots.where((s) => s['display_class'] == 'Not a Road').length,
          };
        });
      }
    } catch (e) {
      debugPrint("Error fetching database data: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Color _getClassColor(String className) {
    if (className == 'Clean Road') return const Color(0xFF00E676);
    if (className == 'Slightly Dirty Road') return const Color(0xFFFF9100);
    if (className == 'Very Dirty Road') return const Color(0xFFFF1744);
    if (className == 'Pothole Detected') return const Color(0xFFD500F9);
    return const Color(0xFF8A8F9D);
  }

  Widget _buildStatCard(String label, int value, [Color? color]) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF161822),
          border: Border.all(color: color ?? const Color(0xFF232738), width: color != null ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(color: Color(0xFF8A8F9D), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              value.toString(),
              style: TextStyle(color: color ?? Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderTab(String title, IconData icon, Color color) {
    final isSelected = _selectedFolder == title;
    return GestureDetector(
      onTap: () => setState(() => _selectedFolder = title),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : const Color(0xFF161822),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF232738),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : const Color(0xFF8A8F9D), size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? color : const Color(0xFF8A8F9D),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<dynamic> _getFilteredSnapshots() {
    if (_selectedFolder == 'All') return _snapshots;
    return _snapshots.where((s) => s['display_class'] == _selectedFolder).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1015),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                widget.vehicleFilter != null ? 'Database - ${widget.vehicleFilter}' : 'Road Cleanliness Analyzer',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24, color: Colors.white),
              ),
            ),
            Text(
              widget.vehicleFilter != null ? 'Live Feed specific to vehicle' : 'Desktop Monitoring System (Live Feed)',
              style: const TextStyle(color: Color(0xFF8A8F9D), fontSize: 12),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 20, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: const Color(0xFF161822),
              border: Border.all(color: const Color(0xFF232738)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: 0.5 + (_pulseController.value * 0.5),
                      child: Transform.scale(
                        scale: 0.95 + (_pulseController.value * 0.1),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 8),
                const Text("ACTIVE CONNECTION", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Folder Tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFolderTab('All', Icons.folder_copy_rounded, Colors.blue),
                  _buildFolderTab('Clean Road', Icons.folder_rounded, const Color(0xFF00E676)),
                  _buildFolderTab('Slightly Dirty Road', Icons.folder_rounded, const Color(0xFFFF9100)),
                  _buildFolderTab('Very Dirty Road', Icons.folder_special_rounded, const Color(0xFFFF1744)),
                          _buildFolderTab('Pothole Detected', Icons.warning_rounded, const Color(0xFFD500F9)),
                  _buildFolderTab('Not a Road', Icons.folder_off_rounded, const Color(0xFF8A8F9D)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Stats Grid
            Row(
              children: [
                _buildStatCard("Total Captures", _stats['total'] ?? 0),
                _buildStatCard("Clean Roads", _stats['Clean Road'] ?? 0, const Color(0xFF00E676)),
                _buildStatCard("Slightly Dirty", _stats['Slightly Dirty Road'] ?? 0, const Color(0xFFFF9100)),
                _buildStatCard("Very Dirty", _stats['Very Dirty Road'] ?? 0, const Color(0xFFFF1744)),
              ],
            ),
            const SizedBox(height: 30),
            
            // Gallery Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text("Captured Road Snapshots", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text("Auto-updating...", style: TextStyle(color: Color(0xFF8A8F9D), fontSize: 14)),
              ],
            ),
            const SizedBox(height: 20),

            // Gallery Grid
            Expanded(
              child: _getFilteredSnapshots().isEmpty
                  ? Center(
                      child: Text(
                        _snapshots.isEmpty 
                            ? "No snapshots captured yet. Capture an image on the Fleet App!"
                            : "No images found in the '$_selectedFolder' folder.",
                        style: const TextStyle(color: Color(0xFF8A8F9D), fontSize: 16),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 350,
                        childAspectRatio: 0.85,
                        crossAxisSpacing: 25,
                        mainAxisSpacing: 25,
                      ),
                      itemCount: _getFilteredSnapshots().length,
                      itemBuilder: (context, index) {
                        final snap = _getFilteredSnapshots()[index];
                        final className = snap['display_class'] ?? 'Unknown';
                        final confidence = (snap['confidence'] ?? 0.0) * 100;
                        final color = _getClassColor(className);
                        final imageUrl = '$activeGarbageAiUrl${snap['image_url']}';
                        final timestamp = snap['timestamp'] ?? 'Unknown Time';
                        final status = 'Logged';

                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF161822),
                            border: Border.all(color: const Color(0xFF232738)),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Image (4/3 aspect roughly handled by flex)
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Color(0xFF232738))),
                                  ),
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => FullScreenImageScreen(imageUrl: imageUrl),
                                        ),
                                      );
                                    },
                                    child: Image.network(imageUrl, headers: const {'ngrok-skip-browser-warning': 'true'},
                                      fit: BoxFit.cover,
                                      errorBuilder: (ctx, err, stack) => const Center(
                                        child: Icon(LucideIcons.imageOff, color: Colors.white24, size: 40),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Info section
                              Padding(
                                padding: const EdgeInsets.all(15.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        className.toUpperCase(),
                                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      "Confidence: ${confidence.toStringAsFixed(1)}%",
                                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      "Status: $status",
                                      style: TextStyle(
                                        color: status == 'Flagged' ? Colors.redAccent : Colors.greenAccent,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      timestamp,
                                      style: const TextStyle(color: Color(0xFF8A8F9D), fontSize: 12),
                                    ),
                                  ],
                                ),
                              )
                            ],
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
}

class FullScreenImageScreen extends StatelessWidget {
  final String imageUrl;
  
  const FullScreenImageScreen({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            headers: const {'ngrok-skip-browser-warning': 'true'},
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => const Icon(LucideIcons.imageOff, color: Colors.white24, size: 64),
          ),
        ),
      ),
    );
  }
}
