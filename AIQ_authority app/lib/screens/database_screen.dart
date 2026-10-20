import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
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
  Map<String, dynamic> _stats = {
    "total": 0,
    "passed_to_yolo": 0,
    "passed_to_mobilenet": 0,
    "bypassed_clean": 0,
    "No Trash / Clean Roads": 0,
    "Trash Detected": 0,
    "Very Dirty Road": 0,
  };
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
      List<dynamic> allSnaps = [];

      try {
        final res1 = await http.get(Uri.parse('$activeGarbageAiUrl/api/snapshots'), headers: {'ngrok-skip-browser-warning': 'true'});
        if (res1.statusCode == 200) {
          final data = json.decode(res1.body);
          List<dynamic> rawSnaps = data['snapshots'] ?? [];
          for (var item in rawSnaps) {
            Map<String, dynamic> snap = Map<String, dynamic>.from(item);
            final status = (snap['road_status'] ?? '').toString();
            final display = (snap['display_class'] ?? '').toString();
            final tag = (snap['training_tag'] ?? '').toString();
            final decision = (snap['decision'] ?? '').toString().toUpperCase();

            final int trashCount = (snap['trash_count'] ?? 0);
            final bool hasTrashBoxes = trashCount > 0 || snap['trash_detected'] == true;

            // 3-way classification: No Trash / Clean Roads, Trash Detected, Very Dirty Road
            // STRICT RULE: If trash spots got identified or got bounded (trashCount > 0),
            // it is EITHER 'Very Dirty Road' OR 'Trash Detected'. NEVER Clean Road!
            if (status == 'Very Dirty Road' ||
                display == 'Very Dirty Road' ||
                tag == 'Very Dirty Road' ||
                decision.contains('VERY DIRTY')) {
              snap['display_class'] = 'Very Dirty Road';
            } else if (hasTrashBoxes ||
                       status == 'Trash Detected' ||
                       display == 'Trash Detected' ||
                       tag == 'Trash Detected' ||
                       decision.contains('TRASH DETECTED')) {
              snap['display_class'] = 'Trash Detected';
            } else {
              snap['display_class'] = 'No Trash / Clean Roads';
            }

            if (snap['training_tag'] == null) {
              snap['training_tag'] = snap['display_class'];
            }
            allSnaps.add(snap);
          }
        }
      } catch (e) {
        debugPrint("Error fetching Garbage AI: $e");
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
          final totalSnaps = _snapshots.length;
          final passedToMobilenet = _snapshots.where((s) {
            final m = s['mobilenet_result'];
            if (m is Map && m['invoked'] == true) return true;
            final d = (s['decision'] ?? '').toString().toUpperCase();
            final status = (s['road_status'] ?? '').toString();
            final disp = (s['display_class'] ?? '').toString();
            final count = (s['trash_count'] ?? 0);
            return status == 'Very Dirty Road' || 
                   disp == 'Very Dirty Road' || 
                   status == 'Trash Detected' || 
                   disp == 'Trash Detected' || 
                   d.contains('VERY DIRTY') || 
                   d.contains('TRASH DETECTED') || 
                   count > 0;
          }).length;
          final bypassedClean = totalSnaps - passedToMobilenet;

          _stats = {
            "total": totalSnaps,
            "passed_to_yolo": totalSnaps,
            "passed_to_mobilenet": passedToMobilenet,
            "bypassed_clean": bypassedClean,
            "No Trash / Clean Roads": _snapshots.where((s) => s['display_class'] == 'No Trash / Clean Roads').length,
            "Trash Detected": _snapshots.where((s) => s['display_class'] == 'Trash Detected').length,
            "Very Dirty Road": _snapshots.where((s) => s['display_class'] == 'Very Dirty Road').length,
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
    if (className == 'No Trash / Clean Roads' || className == 'No Trash Detected' || className == 'Clean Road') {
      return const Color(0xFF00E676); // Green
    }
    if (className == 'Very Dirty Road') {
      return const Color(0xFFFF1744); // Red
    }
    if (className == 'Trash Detected') {
      return const Color(0xFFFF9100); // Amber / Orange
    }
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

  Widget _buildPipelineCountBox({
    required String label,
    required int count,
    required String subtext,
    required Color color,
    required IconData icon,
    bool isMobile = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: isMobile ? 8 : 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 6 : 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: isMobile ? 16 : 20),
          ),
          SizedBox(width: isMobile ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: isMobile ? 9 : 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isMobile ? 2 : 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      count.toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        subtext,
                        style: TextStyle(
                          color: const Color(0xFF8A8F9D),
                          fontSize: isMobile ? 9 : 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
            _selectedFolder = 'All'; // Reset filter when switching mode
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
                widget.vehicleFilter != null ? 'Database - ${widget.vehicleFilter}' : (isAnalysedView ? 'Road Cleanliness (Analysed)' : 'Training Dataset (Raw)'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: isMobile ? 18 : 24, color: Colors.white),
              ),
            ),
            Text(
              isAnalysedView 
                  ? (isMobile ? 'Live Detection Feed' : 'Desktop Monitoring System — Annotated Detections')
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
                    sublabel: 'YOLOv8 Annotations',
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
                          ? 'Showing images with YOLOv8 bounding boxes, confidence ratings & status banners.'
                          : 'Showing unannotated raw camera images tagged by classification result — ready for model retraining.',
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

            // AI Model Processing Pipeline Card (Counts)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: isMobile ? 10 : 12),
              decoration: BoxDecoration(
                color: const Color(0xFF161822),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF232738), width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F2FE).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(LucideIcons.gitBranch, color: Color(0xFF00F2FE), size: 14),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "AI MODEL PROCESSING FLOW",
                        style: TextStyle(
                          color: Color(0xFF8A8F9D),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
                        ),
                        child: Text(
                          "${_stats['bypassed_clean'] ?? 0} Clean Road Bypassed (Saved)",
                          style: const TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPipelineCountBox(
                          label: "Passed to YOLO Model",
                          count: _stats['passed_to_yolo'] ?? 0,
                          subtext: "100% of Captures",
                          color: const Color(0xFF00F2FE),
                          icon: LucideIcons.scan,
                          isMobile: isMobile,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 10),
                        child: Column(
                          children: [
                            const Icon(LucideIcons.arrowRight, color: Color(0xFF8A8F9D), size: 16),
                            if (!isMobile)
                              const Text(
                                "Trash Flagged",
                                style: TextStyle(color: Color(0xFF8A8F9D), fontSize: 9, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _buildPipelineCountBox(
                          label: "Passed to MobileNetV3",
                          count: _stats['passed_to_mobilenet'] ?? 0,
                          subtext: "From YOLO",
                          color: const Color(0xFFA855F7),
                          icon: LucideIcons.cpu,
                          isMobile: isMobile,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Folder Tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFolderTab('All', Icons.folder_copy_rounded, const Color(0xFF00F2FE)),
                  _buildFolderTab('No Trash / Clean Roads', Icons.folder_rounded, const Color(0xFF00E676)),
                  _buildFolderTab('Trash Detected', Icons.folder_special_rounded, const Color(0xFFFF9100)),
                  _buildFolderTab('Very Dirty Road', Icons.warning_amber_rounded, const Color(0xFFFF1744)),
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
                      Expanded(child: _buildStatCard(isAnalysedView ? "No Trash / Clean" : "Tagged: Clean", _stats['No Trash / Clean Roads'] ?? 0, const Color(0xFF00E676), true)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard(isAnalysedView ? "Trash Detected" : "Tagged: Trash", _stats['Trash Detected'] ?? 0, const Color(0xFFFF9100), true)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildStatCard(isAnalysedView ? "Very Dirty Road" : "Tagged: Very Dirty", _stats['Very Dirty Road'] ?? 0, const Color(0xFFFF1744), true)),
                    ],
                  ),
                ],
              )
            else
              Row(
                children: [
                  _buildStatCard(isAnalysedView ? "Total Captures" : "Total Raw Images", _stats['total'] ?? 0, isAnalysedView ? null : const Color(0xFFA855F7)),
                  _buildStatCard(isAnalysedView ? "No Trash / Clean" : "Tagged: Clean", _stats['No Trash / Clean Roads'] ?? 0, const Color(0xFF00E676)),
                  _buildStatCard(isAnalysedView ? "Trash Detected" : "Tagged: Trash", _stats['Trash Detected'] ?? 0, const Color(0xFFFF9100)),
                  _buildStatCard(isAnalysedView ? "Very Dirty Road" : "Tagged: Very Dirty", _stats['Very Dirty Road'] ?? 0, const Color(0xFFFF1744)),
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
                        
                        // Select between raw image and analysed image
                        final annotatedUrl = '$activeGarbageAiUrl${snap['image_url']}';
                        final rawRelative = snap['raw_image_url'] ?? snap['image_url'];
                        final rawUrl = '$activeGarbageAiUrl$rawRelative';
                        
                        final activeDisplayUrl = isAnalysedView ? annotatedUrl : rawUrl;

                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF161822),
                            border: Border.all(
                              color: isAnalysedView 
                                  ? color.withOpacity(0.3) 
                                  : color.withOpacity(0.6),
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
                                              className == 'No Trash / Clean Roads' ? 'CLEAN ROAD' : className.toUpperCase(),
                                              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                className == 'Very Dirty Road'
                                                    ? "Severe Dirty"
                                                    : (className == 'Trash Detected' ? "Litter Detected" : "Clean Surface"),
                                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                              ),
                                              Text(
                                                "${snap['trash_count'] ?? (className == 'No Trash / Clean Roads' ? 0 : 1)} Item(s)",
                                                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "Cleanliness Score: ${(snap['cleanliness_score'] ?? confidence).toStringAsFixed(1)}%",
                                            style: TextStyle(color: color.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.w600),
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
                                          // Prominent Classification Tag Badge for Training Set
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
                                                  className == 'Very Dirty Road'
                                                      ? LucideIcons.alertOctagon
                                                      : (className == 'Trash Detected'
                                                          ? LucideIcons.alertTriangle
                                                          : LucideIcons.checkCircle2),
                                                  color: color,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "TAG: ${className == 'No Trash / Clean Roads' ? 'CLEAN ROAD' : className.toUpperCase()}",
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
                                                className == 'Very Dirty Road'
                                                    ? "Dataset Tag: very_dirty"
                                                    : (className == 'Trash Detected' ? "Dataset Tag: trash" : "Dataset Tag: clean_road"),
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
                "Classification Tag: ${widget.tag == 'No Trash / Clean Roads' ? 'Clean Road' : widget.tag}",
                style: TextStyle(
                  fontSize: 11,
                  color: widget.tag == 'Very Dirty Road'
                      ? const Color(0xFFFF1744)
                      : (widget.tag == 'Trash Detected'
                          ? const Color(0xFFFF9100)
                          : const Color(0xFF00E676)),
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
