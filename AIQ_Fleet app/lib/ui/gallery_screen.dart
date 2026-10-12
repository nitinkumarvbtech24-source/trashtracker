import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:io';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/camera_service.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _timer;
  List<Map<String, dynamic>> _snapshots = [];
  Map<String, dynamic> _stats = {"total": 0, "Pending Sync": 0, "No Trash Detected": 0, "Trash Detected": 0, "Not a Road": 0};
  String _selectedFolder = 'All';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _fetchData();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _fetchData();
    });
  }

  Future<void> _fetchData() async {
    try {
      final flags = await DatabaseService().getLocalFlags();
      final queued = await DatabaseService().getAllQueuedSnapshots();
      List<Map<String, dynamic>> allSnaps = [];

      // Queued / Pending offline snapshots first
      for (var q in queued) {
        allSnaps.add({
          'filePath': q['filePath'],
          'display_class': 'Pending Sync',
          'roadStatus': 'Pending Sync',
          'confidence': 0.0,
          'timestamp': q['timestamp'] ?? q['createdAt'] ?? 0,
          'isQueued': true,
          'id': q['id'],
          'lat': q['lat'],
          'lng': q['lng'],
          'retryCount': q['retryCount'] ?? 0,
        });
      }

      for (var snap in flags) {
        var modifiedSnap = Map<String, dynamic>.from(snap);
        String status = modifiedSnap['roadStatus'] ?? '';
        
        if (status == 'Clean Road') {
          modifiedSnap['display_class'] = 'No Trash Detected';
        } else if (status == 'Slightly Dirty Road' || status == 'Very Dirty Road' || status == 'Trash Detected') {
          modifiedSnap['display_class'] = 'Trash Detected';
        } else if (status == 'Not a Road') {
          modifiedSnap['display_class'] = 'Not a Road';
        } else {
          modifiedSnap['display_class'] = status;
        }
        allSnaps.add(modifiedSnap);
      }

      if (mounted) {
        setState(() {
          _snapshots = allSnaps;
          _stats = {
            "total": _snapshots.length,
            "Pending Sync": _snapshots.where((s) => s['display_class'] == 'Pending Sync').length,
            "No Trash Detected": _snapshots.where((s) => s['display_class'] == 'No Trash Detected').length,
            "Trash Detected": _snapshots.where((s) => s['display_class'] == 'Trash Detected').length,
            "Not a Road": _snapshots.where((s) => s['display_class'] == 'Not a Road').length,
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching local flags: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Color _getClassColor(String className) {
    if (className == 'Pending Sync') return const Color(0xFFFFB300);
    if (className == 'No Trash Detected') return const Color(0xFF00E676);
    if (className == 'Trash Detected') return const Color(0xFFFF1744);
    if (className == 'Not a Road') return const Color(0xFF8A8F9D);
    return const Color(0xFF8A8F9D);
  }

  Widget _buildStatCard(String label, int value, [Color? color]) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        border: Border.all(color: color ?? const Color(0xFF334155), width: color != null ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Text(
            value.toString(),
            style: TextStyle(color: color ?? Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTab(String title, IconData icon, Color color) {
    final isSelected = _selectedFolder == title;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedFolder = title);
        Navigator.pop(context); // Close drawer on selection
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : const Color(0xFF1E293B),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF334155),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : const Color(0xFF94A3B8), size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? color : const Color(0xFF94A3B8),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 16),
          ],
        ),
      ),
    );
  }

  List<dynamic> _getFilteredSnapshots() {
    if (_selectedFolder == 'All') return _snapshots;
    return _snapshots.where((s) => s['display_class'] == _selectedFolder).toList();
  }

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final vehicleNo = context.watch<AuthService>().vehicleNumber;

    if (vehicleNo == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(title: const Text('Flags'), backgroundColor: const Color(0xFF111827)),
        body: const Center(child: Text('Not logged in', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Local Snapshots',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 24, color: Colors.white),
            ),
            Text(
              'Device Local Storage • $_selectedFolder',
              style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
        actions: [
          Consumer<CameraService>(
            builder: (context, cameraService, child) {
              if (cameraService.pendingQueueCount > 0) {
                return IconButton(
                  tooltip: 'Sync ${cameraService.pendingQueueCount} queued images',
                  icon: cameraService.isProcessingQueue
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                        )
                      : const Icon(Icons.cloud_upload_rounded, color: Colors.amberAccent),
                  onPressed: () {
                    cameraService.processQueueSequentially();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Syncing ${cameraService.pendingQueueCount} queued images sequentially..."),
                        duration: const Duration(seconds: 2),
                        backgroundColor: const Color(0xFF1E293B),
                      ),
                    );
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Container(
            margin: const EdgeInsets.only(right: 20, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              border: Border.all(color: const Color(0xFF334155)),
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
                Text("LOCAL", style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF111827),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'Dashboard',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  children: [
                    Text("FILTERS", style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildFolderTab('All', Icons.folder_copy_rounded, Colors.blue),
                    _buildFolderTab('Pending Sync', Icons.cloud_queue_rounded, const Color(0xFFFFB300)),
                    _buildFolderTab('No Trash Detected', Icons.folder_rounded, const Color(0xFF00E676)),
                    _buildFolderTab('Trash Detected', Icons.folder_special_rounded, const Color(0xFFFF1744)),
                    _buildFolderTab('Not a Road', Icons.folder_off_rounded, const Color(0xFF8A8F9D)),
                    
                    const SizedBox(height: 24),
                    
                    Text("STATISTICS", style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildStatCard("Total", _stats['total'] ?? 0),
                    _buildStatCard("Pending Sync", _stats['Pending Sync'] ?? 0, const Color(0xFFFFB300)),
                    _buildStatCard("Clean", _stats['No Trash Detected'] ?? 0, const Color(0xFF00E676)),
                    _buildStatCard("Trash", _stats['Trash Detected'] ?? 0, const Color(0xFFFF1744)),
                    _buildStatCard("Other", _stats['Not a Road'] ?? 0, const Color(0xFF8A8F9D)),

                    const SizedBox(height: 20),
                    Consumer<CameraService>(
                      builder: (context, cameraService, child) {
                        if (cameraService.pendingQueueCount > 0) {
                          return ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFB300),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: cameraService.isProcessingQueue
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                : const Icon(Icons.sync_rounded),
                            label: Text(
                              cameraService.isProcessingQueue ? "Syncing..." : "Sync Queue (${cameraService.pendingQueueCount})",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: cameraService.isProcessingQueue ? null : () {
                              cameraService.processQueueSequentially();
                              Navigator.pop(context);
                            },
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
        : _getFilteredSnapshots().isEmpty
            ? Center(
                child: Text(
                  _snapshots.isEmpty 
                      ? "No local snapshots captured yet."
                      : "No images found in the '$_selectedFolder' folder.",
                  style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(16).copyWith(bottom: 80),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.75,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _getFilteredSnapshots().length,
                itemBuilder: (context, index) {
                  final snap = _getFilteredSnapshots()[index];
                  final className = snap['display_class'] ?? 'Unknown';
                  final confidence = (snap['confidence'] ?? 0.0) * 100;
                  final color = _getClassColor(className);
                  final filePath = snap['filePath'] ?? '';
                  final timestamp = snap['timestamp'] ?? 0;

                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      border: Border.all(color: color.withOpacity(0.5), width: 2),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
                            ),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => FullScreenImageScreen(filePath: filePath),
                                  ),
                                );
                              },
                              child: filePath.isNotEmpty
                                ? Image.file(File(filePath), fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, stack) => const Center(
                                      child: Icon(Icons.broken_image, color: Colors.white24, size: 40),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.image_not_supported, color: Colors.white24, size: 40),
                                  ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  className,
                                  style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                snap['isQueued'] == true
                                    ? "Waiting for sync (Item #${snap['id']})"
                                    : "Confidence: ${confidence.toStringAsFixed(1)}%",
                                style: GoogleFonts.inter(
                                  color: snap['isQueued'] == true ? const Color(0xFFFFB300) : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTimestamp(timestamp),
                                style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 10),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
    );
  }
}

class FullScreenImageScreen extends StatelessWidget {
  final String filePath;
  
  const FullScreenImageScreen({super.key, required this.filePath});

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
          child: Image.file(
            File(filePath),
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, color: Colors.white24, size: 64),
          ),
        ),
      ),
    );
  }
}

