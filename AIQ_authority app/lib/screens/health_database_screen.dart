import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:lucide_icons/lucide_icons.dart';

import '../constants.dart';

class HealthDatabaseScreen extends StatefulWidget {
  final String? vehicleFilter;
  const HealthDatabaseScreen({super.key, this.vehicleFilter});

  @override
  State<HealthDatabaseScreen> createState() => _HealthDatabaseScreenState();
}

class _HealthDatabaseScreenState extends State<HealthDatabaseScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _timer;
  List<dynamic> _snapshots = [];
  Map<String, dynamic> _stats = {"total": 0, "Good Road": 0, "Bad Road": 0, "Pothole Detected": 0, "Not a Road": 0};
  String _selectedFolder = 'All';
  int _selectedNavIndex = 0; // 0: Analysed Images, 1: Training Dataset (Raw)

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
      final response = await http.get(
        Uri.parse('$activeHealthAiUrl/api/snapshots'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            List<dynamic> allSnaps = data['snapshots'] ?? [];
            if (widget.vehicleFilter != null) {
              allSnaps = allSnaps.where((s) => s['vehicle_number'] == widget.vehicleFilter).toList();
            }
            _snapshots = allSnaps;
            _stats = {
              "total": _snapshots.length,
              "Good Road": _snapshots.where((s) => s['display_class'] == 'Good Road').length,
              "Bad Road": _snapshots.where((s) => s['display_class'] == 'Bad Road').length,
              "Pothole Detected": _snapshots.where((s) => s['display_class'] == 'Pothole Detected').length,
              "Not a Road": _snapshots.where((s) => s['display_class'] == 'Not a Road').length,
            };
          });
        }
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
    if (className == 'Good Road') return const Color(0xFF00E676);
    if (className == 'Bad Road') return const Color(0xFFFF9100);
    if (className == 'Pothole Detected') return const Color(0xFFFF1744);
    return const Color(0xFF8A8F9D);
  }

  Widget _buildStatCard(String label, int value, [Color? color, bool isMobile = false]) {
    final accent = color ?? const Color(0xFF0F5132);
    final cardContent = Container(
      height: isMobile ? 80 : 95,
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 0 : 5),
      padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 14, horizontal: isMobile ? 10 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161822),
        border: Border.all(color: accent.withOpacity(0.5), width: 1.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: isMobile ? 34 : 44,
            height: isMobile ? 34 : 44,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(LucideIcons.barChart2, color: accent, size: isMobile ? 18 : 22),
          ),
          SizedBox(width: isMobile ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: const Color(0xFF8A8F9D),
                    fontSize: isMobile ? 9 : 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isMobile ? 2 : 4),
                Text(
                  value.toString(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 18 : 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isMobile) return cardContent;
    return Expanded(child: cardContent);
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

  Widget _buildBottomNavButton({
    required int index,
    required IconData icon,
    required String label,
    required String sublabel,
    required Color activeColor,
    required bool isMobile,
  }) {
    final isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () {
        if (_selectedNavIndex != index) {
          setState(() {
            _selectedNavIndex = index;
            _selectedFolder = 'All';
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 12, horizontal: isMobile ? 10 : 16),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.16) : const Color(0xFF161822),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFF232738),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
              ? [BoxShadow(color: activeColor.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 3))]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: isMobile ? 18 : 22,
              color: isSelected ? activeColor : const Color(0xFF8A8F9D),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF8A8F9D),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: isMobile ? 12 : 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(
                      color: isSelected ? activeColor : const Color(0xFF6B7280),
                      fontSize: isMobile ? 9 : 11,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
    final isMobile = MediaQuery.of(context).size.width < 768;
    final isAnalysedView = _selectedNavIndex == 0;

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
                widget.vehicleFilter != null ? 'Database - ${widget.vehicleFilter}' : (isAnalysedView ? 'Road Health (Analysed)' : 'Training Dataset (Raw)'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: isMobile ? 18 : 24, color: Colors.white),
              ),
            ),
            Text(
              isAnalysedView
                  ? (isMobile ? 'Live Health Feed' : 'Desktop Monitoring System — Structural Defects')
                  : (isMobile ? 'Raw Captures Tagged' : 'Model Retraining Pipeline — Unannotated Images Tagged'),
              style: TextStyle(color: const Color(0xFF8A8F9D), fontSize: isMobile ? 10 : 12),
            ),
          ],
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: isMobile ? 12 : 20, top: 10, bottom: 10),
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 15),
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
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 6),
                Text(isMobile ? "ACTIVE" : "ACTIVE CONNECTION", style: TextStyle(color: Colors.white, fontSize: isMobile ? 10 : 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12141D),
          border: Border(top: BorderSide(color: Color(0xFF232738), width: 1.5)),
          boxShadow: [
            BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, -4)),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: isMobile ? 8 : 12),
            child: Row(
              children: [
                Expanded(
                  child: _buildBottomNavButton(
                    index: 0,
                    icon: LucideIcons.sparkles,
                    label: 'Analysed Images',
                    sublabel: 'Defect Annotations',
                    activeColor: const Color(0xFF00F2FE),
                    isMobile: isMobile,
                  ),
                ),
                SizedBox(width: isMobile ? 8 : 16),
                Expanded(
                  child: _buildBottomNavButton(
                    index: 1,
                    icon: LucideIcons.database,
                    label: 'Training Dataset',
                    sublabel: 'Raw & Tagged',
                    activeColor: const Color(0xFFA855F7),
                    isMobile: isMobile,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode Banner Info
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isAnalysedView ? const Color(0xFF00F2FE).withOpacity(0.08) : const Color(0xFFA855F7).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isAnalysedView ? const Color(0xFF00F2FE).withOpacity(0.3) : const Color(0xFFA855F7).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isAnalysedView ? LucideIcons.sparkles : LucideIcons.cpu,
                    color: isAnalysedView ? const Color(0xFF00F2FE) : const Color(0xFFA855F7),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isAnalysedView
                          ? 'Showing images with YOLOv8 defect detections, pothole boxes & road status.'
                          : 'Showing unannotated raw camera images tagged with defect classification — ready for model retraining.',
                      style: TextStyle(
                        color: isAnalysedView ? const Color(0xFF67E8F9) : const Color(0xFFD8B4FE),
                        fontSize: isMobile ? 11 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Folder Tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFolderTab('All', Icons.folder_copy_rounded, Colors.blue),
                  _buildFolderTab('Good Road', Icons.folder_rounded, const Color(0xFF00E676)),
                  _buildFolderTab('Bad Road', Icons.folder_rounded, const Color(0xFFFF9100)),
                  _buildFolderTab('Pothole Detected', Icons.warning_rounded, const Color(0xFFFF1744)),
                  _buildFolderTab('Not a Road', Icons.folder_off_rounded, const Color(0xFF8A8F9D)),
                ],
              ),
            ),
            SizedBox(height: isMobile ? 14 : 20),

            // Stats Grid
            if (isMobile)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildStatCard(isAnalysedView ? "Total Captures" : "Total Raw Images", _stats['total'] ?? 0, isAnalysedView ? null : const Color(0xFFA855F7), true)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildStatCard(isAnalysedView ? "Good Roads" : "Tagged: Good Road", _stats["Good Road"] ?? 0, const Color(0xFF00E676), true)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard(isAnalysedView ? "Bad Roads" : "Tagged: Bad Road", _stats["Bad Road"] ?? 0, const Color(0xFFFF9100), true)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildStatCard(isAnalysedView ? "Potholes Detected" : "Tagged: Potholes", _stats["Pothole Detected"] ?? 0, const Color(0xFFFF1744), true)),
                    ],
                  ),
                ],
              )
            else
              Row(
                children: [
                  _buildStatCard(isAnalysedView ? "Total Captures" : "Total Raw Images", _stats['total'] ?? 0, isAnalysedView ? null : const Color(0xFFA855F7)),
                  _buildStatCard(isAnalysedView ? "Good Roads" : "Tagged: Good Road", _stats["Good Road"] ?? 0, const Color(0xFF00E676)),
                  _buildStatCard(isAnalysedView ? "Bad Roads" : "Tagged: Bad Road", _stats["Bad Road"] ?? 0, const Color(0xFFFF9100)),
                  _buildStatCard(isAnalysedView ? "Potholes Detected" : "Tagged: Potholes", _stats["Pothole Detected"] ?? 0, const Color(0xFFFF1744)),
                ],
              ),
            SizedBox(height: isMobile ? 16 : 24),
            
            // Gallery Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isAnalysedView ? "Captured Snapshots (Analysed)" : "Training Dataset (Raw Captures)",
                  style: TextStyle(color: Colors.white, fontSize: isMobile ? 16 : 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  isAnalysedView ? "Live detections" : "Raw camera frames",
                  style: TextStyle(color: const Color(0xFF8A8F9D), fontSize: isMobile ? 11 : 13),
                ),
              ],
            ),
            SizedBox(height: isMobile ? 12 : 16),

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
                        childAspectRatio: 0.82,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                      ),
                      itemCount: _getFilteredSnapshots().length,
                      itemBuilder: (context, index) {
                        final snap = _getFilteredSnapshots()[index];
                        final className = snap['display_class'] ?? 'Unknown';
                        final confidence = (snap['confidence'] ?? 0.0) * 100;
                        final color = _getClassColor(className);
                        final timestamp = snap['timestamp'] ?? 'Unknown Time';
                        final vehicle = snap['vehicle_number'] ?? 'Fleet Capture';
                        
                        final annotatedUrl = '$activeHealthAiUrl${snap['image_url']}';
                        final rawRelative = snap['raw_image_url'] ?? snap['image_url'];
                        final rawUrl = '$activeHealthAiUrl$rawRelative';
                        
                        final activeDisplayUrl = isAnalysedView ? annotatedUrl : rawUrl;

                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF161822),
                            border: Border.all(
                              color: isAnalysedView ? const Color(0xFF232738) : color.withOpacity(0.6),
                              width: isAnalysedView ? 1 : 1.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Image Section
                              Expanded(
                                child: Stack(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      decoration: const BoxDecoration(
                                        border: Border(bottom: BorderSide(color: Color(0xFF232738))),
                                      ),
                                      child: GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => FullScreenImageScreen(
                                                imageUrl: activeDisplayUrl,
                                                alternateImageUrl: isAnalysedView ? rawUrl : annotatedUrl,
                                                title: isAnalysedView ? 'Analysed Inspection' : 'Raw Training Capture',
                                                tag: className,
                                                isRaw: !isAnalysedView,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Image.network(
                                          activeDisplayUrl,
                                          headers: const {'ngrok-skip-browser-warning': 'true'},
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, err, stack) => const Center(
                                            child: Icon(LucideIcons.imageOff, color: Colors.white24, size: 40),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Raw Mode Top Badge
                                    if (!isAnalysedView)
                                      Positioned(
                                        top: 8,
                                        left: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.75),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF00F2FE), width: 1),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(LucideIcons.camera, color: Color(0xFF00F2FE), size: 12),
                                              SizedBox(width: 4),
                                              Text(
                                                "RAW (NO ANNOTATIONS)",
                                                style: TextStyle(color: Color(0xFF00F2FE), fontSize: 9, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Card Info Section
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: isAnalysedView
                                    ? Column(
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
                                              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "Confidence: ${confidence.toStringAsFixed(1)}%",
                                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            "Vehicle: $vehicle",
                                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            timestamp,
                                            style: const TextStyle(color: Color(0xFF8A8F9D), fontSize: 11),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: color.withOpacity(0.2),
                                              border: Border.all(color: color, width: 1.5),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  className == 'Good Road' ? LucideIcons.checkCircle2 : LucideIcons.alertTriangle,
                                                  color: color,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "TAG: ${className.toUpperCase()}",
                                                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Icon(LucideIcons.tag, size: 12, color: Color(0xFFA855F7)),
                                              const SizedBox(width: 4),
                                              Text(
                                                "Dataset Tag: ${className.toLowerCase().replaceAll(' ', '_')}",
                                                style: const TextStyle(color: Color(0xFFD8B4FE), fontSize: 12, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            "Vehicle: $vehicle",
                                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            timestamp,
                                            style: const TextStyle(color: Color(0xFF8A8F9D), fontSize: 11),
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

class FullScreenImageScreen extends StatefulWidget {
  final String imageUrl;
  final String? alternateImageUrl;
  final String? title;
  final String? tag;
  final bool isRaw;

  const FullScreenImageScreen({
    super.key,
    required this.imageUrl,
    this.alternateImageUrl,
    this.title,
    this.tag,
    this.isRaw = false,
  });

  @override
  State<FullScreenImageScreen> createState() => _FullScreenImageScreenState();
}

class _FullScreenImageScreenState extends State<FullScreenImageScreen> {
  late String _currentUrl;
  late bool _showingRaw;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.imageUrl;
    _showingRaw = widget.isRaw;
  }

  void _toggleView() {
    if (widget.alternateImageUrl != null) {
      setState(() {
        if (_currentUrl == widget.imageUrl) {
          _currentUrl = widget.alternateImageUrl!;
          _showingRaw = !widget.isRaw;
        } else {
          _currentUrl = widget.imageUrl;
          _showingRaw = widget.isRaw;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _showingRaw ? "Raw Training Capture (Zero Annotations)" : "Analysed Inspection Feed",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            if (widget.tag != null)
              Text(
                "Classification Tag: ${widget.tag}",
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF00F2FE),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        actions: [
          if (widget.alternateImageUrl != null)
            TextButton.icon(
              onPressed: _toggleView,
              icon: Icon(_showingRaw ? LucideIcons.sparkles : LucideIcons.camera, color: const Color(0xFF00F2FE), size: 16),
              label: Text(
                _showingRaw ? "View Annotated" : "View Raw",
                style: const TextStyle(color: Color(0xFF00F2FE), fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            _currentUrl,
            headers: const {'ngrok-skip-browser-warning': 'true'},
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => const Icon(LucideIcons.imageOff, color: Colors.white24, size: 64),
          ),
        ),
      ),
    );
  }
}

