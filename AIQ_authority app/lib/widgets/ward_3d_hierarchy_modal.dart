import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../models/ward.dart';
import '../models/ward_official.dart';
import '../services/ward_officials_service.dart';

/// Interactive 3D Cut OpenStreetMap Ward & Leadership Hierarchy Tree Modal
/// Themed in the exact Dashboard Green (#006341) and White combination
class Ward3dHierarchyModal extends StatefulWidget {
  final Ward ward;

  const Ward3dHierarchyModal({super.key, required this.ward});

  /// Opens the modal with smooth 3D scale, fade, and blur animations
  static void show(BuildContext context, Ward ward) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Ward3dHierarchyModal',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, anim1, anim2) {
        return Ward3dHierarchyModal(ward: ward);
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12 * anim1.value, sigmaY: 12 * anim1.value),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.90, end: 1.0).animate(curved),
            child: FadeTransition(
              opacity: anim1,
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  State<Ward3dHierarchyModal> createState() => _Ward3dHierarchyModalState();
}

class _Ward3dHierarchyModalState extends State<Ward3dHierarchyModal> with TickerProviderStateMixin {
  late final List<WardOfficial> _officials;

  // Exact Dashboard Colors
  static const Color dashboardGreen = Color(0xFF006341);
  static const Color cardBgWhite = Color(0xFFFFFFFF);
  static const Color canvasBg = Color(0xFFF4FBF7);

  @override
  void initState() {
    super.initState();
    _officials = WardOfficialsService.instance.getHierarchyForWard(widget.ward);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 860;
    final dialogWidth = isWide ? math.min(size.width * 0.94, 1260.0) : size.width * 0.96;
    final dialogHeight = isWide ? math.min(size.height * 0.90, 840.0) : size.height * 0.94;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          decoration: BoxDecoration(
            color: cardBgWhite,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: dashboardGreen, width: 2.0),
            boxShadow: [
              BoxShadow(
                color: dashboardGreen.withValues(alpha: 0.25),
                blurRadius: 36,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              children: [
                // 1. Top Header Bar (Dashboard Green #006341 + Crisp White)
                _buildHeader(context),

                // 2. Main Content (Split on desktop/tablet, stacked on mobile)
                Expanded(
                  child: isWide ? _buildWideLayout() : _buildMobileLayout(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Header Bar with Dashboard Green (#006341) and White
  Widget _buildHeader(BuildContext context) {
    final wardNum = widget.ward.wardNo;
    final wardTitle = wardNum != null ? 'Ward #$wardNum · ${widget.ward.name}' : widget.ward.name;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: dashboardGreen,
        border: Border(
          bottom: BorderSide(color: Color(0xFF004D32), width: 1.5),
        ),
      ),
      child: Row(
        children: [
          // White & Green 3D Map Cutout Badge
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.map_rounded, color: dashboardGreen, size: 22),
          ),
          const SizedBox(width: 14),

          // Ward Title & Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        wardTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white, width: 1.0),
                      ),
                      child: Text(
                        '${widget.ward.zone ?? 'BBMP'} Zone',
                        style: const TextStyle(
                          color: dashboardGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'OpenStreetMap 3D Cutout · Greater Bengaluru Authority (GBA)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // 3D Cutout Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 1.2),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.layers_rounded, color: Colors.white, size: 14),
                SizedBox(width: 6),
                Text(
                  'REAL OSM WARD VIEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Close Button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
            splashRadius: 20,
            tooltip: 'Close Modal',
          ),
        ],
      ),
    );
  }

  /// Wide Side-by-Side Layout for Desktop & Tablet
  Widget _buildWideLayout() {
    return Row(
      children: [
        // Left Column: Real OpenStreetMap Ward Cut & 3D Extrusion
        Expanded(
          flex: 48,
          child: Container(
            color: canvasBg,
            child: Column(
              children: [
                Expanded(
                  child: WardOsm3dCutoutViewer(ward: widget.ward),
                ),
                _buildTelemetryBar(),
              ],
            ),
          ),
        ),

        // Dashboard Green Vertical Divider Line
        Container(
          width: 2.0,
          color: dashboardGreen.withValues(alpha: 0.25),
        ),

        // Right Column: Leadership & Officers TREE in Green & White
        Expanded(
          flex: 52,
          child: Container(
            color: const Color(0xFFF8FAFC),
            child: WardLeadershipTree(officials: _officials, ward: widget.ward),
          ),
        ),
      ],
    );
  }

  /// Stacked Layout for Mobile Screens
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Top 3D OpenStreetMap Cutout Viewer
        SizedBox(
          height: 270,
          child: Container(
            color: canvasBg,
            child: Stack(
              children: [
                WardOsm3dCutoutViewer(ward: widget.ward),
                Positioned(
                  bottom: 8,
                  left: 12,
                  right: 12,
                  child: _buildMiniTelemetryPill(),
                ),
              ],
            ),
          ),
        ),

        // Divider
        Container(
          height: 2.0,
          color: dashboardGreen.withValues(alpha: 0.25),
        ),

        // Scrollable Leadership Tree below
        Expanded(
          child: Container(
            color: const Color(0xFFF8FAFC),
            child: WardLeadershipTree(officials: _officials, ward: widget.ward),
          ),
        ),
      ],
    );
  }

  /// Telemetry Info Bar in Dashboard Green & White
  Widget _buildTelemetryBar() {
    final perimeterKm = _calculatePerimeterKm(widget.ward.boundary);
    final checkpointCount = widget.ward.checkpoints?.length ?? 12;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBgWhite,
        border: Border(
          top: BorderSide(color: dashboardGreen.withValues(alpha: 0.20), width: 1.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatPill('Cleanliness AIQ', '93% Optimal', Icons.eco_rounded, dashboardGreen),
          _buildStatPill('Ward Perimeter', '${perimeterKm.toStringAsFixed(1)} km', Icons.straighten_rounded, const Color(0xFF1E293B)),
          _buildStatPill('Road Sweepers', '2 Active Tippers', Icons.local_shipping_rounded, dashboardGreen),
          _buildStatPill('Checkpoints', '$checkpointCount Stops', Icons.location_on_rounded, const Color(0xFFD97706)),
        ],
      ),
    );
  }

  Widget _buildMiniTelemetryPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dashboardGreen, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('AIQ: 93% Optimal', style: TextStyle(color: dashboardGreen, fontWeight: FontWeight.w900, fontSize: 11)),
          Text('• Real OSM Roads & Buildings •', style: TextStyle(color: Color(0xFF1E293B), fontSize: 10, fontWeight: FontWeight.w700)),
          Text('2 Tippers', style: TextStyle(color: dashboardGreen, fontWeight: FontWeight.w900, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  double _calculatePerimeterKm(List<LatLng> points) {
    if (points.length < 2) return 5.4;
    double dist = 0.0;
    const distance = Distance();
    for (int i = 0; i < points.length - 1; i++) {
      dist += distance.as(LengthUnit.Kilometer, points[i], points[i + 1]);
    }
    return dist > 0 ? dist : 5.8;
  }
}

// ============================================================================
// REAL OPENSTREETMAP WARD CUTOUT VIEWER (STRAIGHT & UPRIGHT)
// Displays the REAL OpenStreetMap cut/clipped to the ward polygon inside a straight, upright box
// ============================================================================

class WardOsm3dCutoutViewer extends StatefulWidget {
  final Ward ward;

  const WardOsm3dCutoutViewer({super.key, required this.ward});

  @override
  State<WardOsm3dCutoutViewer> createState() => _WardOsm3dCutoutViewerState();
}

class _WardOsm3dCutoutViewerState extends State<WardOsm3dCutoutViewer> {
  late final MapController _mapController;

  static const Color dashboardGreen = Color(0xFF006341);
  static const Color platformBg = Color(0xFFF4FBF7);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _resetView() {
    if (widget.ward.boundary.isNotEmpty) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(widget.ward.boundary),
          padding: const EdgeInsets.all(32),
        ),
      );
    }
  }

  LatLng _computeCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(12.9716, 77.5946);
    double lat = 0, lng = 0;
    for (var p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  @override
  Widget build(BuildContext context) {
    final centroid = widget.ward.centroid ?? _computeCentroid(widget.ward.boundary);

    return Container(
      color: platformBg,
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          // 1. Straight Upright OpenStreetMap Cutout Box
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: dashboardGreen, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: dashboardGreen.withValues(alpha: 0.18),
                    blurRadius: 22,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                  const BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17.5),
                child: Stack(
                  children: [
                    // The Real OpenStreetMap
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: centroid,
                        initialZoom: 14.5,
                        initialCameraFit: widget.ward.boundary.isNotEmpty
                            ? CameraFit.bounds(
                                bounds: LatLngBounds.fromPoints(widget.ward.boundary),
                                padding: const EdgeInsets.all(36),
                              )
                            : null,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                        ),
                      ),
                      children: [
                        // Official Standard OpenStreetMap Tile Layer (Real Roads, Links, Buildings)
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.nitin.trashtracker',
                        ),

                        // Inverted Mask: Masks out everything outside the ward so ONLY the ward is visible
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: const [
                                LatLng(85, -180),
                                LatLng(85, 180),
                                LatLng(-85, 180),
                                LatLng(-85, -180),
                              ],
                              holePointsList: [widget.ward.boundary],
                              color: platformBg.withValues(alpha: 0.94), // Covers outer region cleanly
                              borderStrokeWidth: 0,
                              borderColor: Colors.transparent,
                            ),
                            // Cut Ward Perimeter Border in Dashboard Green (#006341)
                            Polygon(
                              points: widget.ward.boundary,
                              color: dashboardGreen.withValues(alpha: 0.05), // Soft subtle green tint inside
                              borderStrokeWidth: 4.5,
                              borderColor: dashboardGreen,
                            ),
                          ],
                        ),

                        // Real Geo-Checkpoints on the real roads
                        if (widget.ward.checkpoints != null && widget.ward.checkpoints!.isNotEmpty)
                          MarkerLayer(
                            markers: widget.ward.checkpoints!.take(6).map((cp) {
                              return Marker(
                                point: cp,
                                width: 28,
                                height: 28,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: dashboardGreen,
                                    border: Border.all(color: Colors.white, width: 2.2),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                                    ],
                                  ),
                                  child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 16),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),

                    // Inner border accent
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(17.5),
                            border: Border.all(
                              color: dashboardGreen.withValues(alpha: 0.30),
                              width: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Navigation & Zoom Controls Overlay (Top Right)
          Positioned(
            top: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: dashboardGreen, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_rounded, color: dashboardGreen, size: 20),
                    tooltip: 'Zoom In',
                    onPressed: () {
                      final currentZoom = _mapController.camera.zoom;
                      _mapController.move(_mapController.camera.center, currentZoom + 0.5);
                    },
                    splashRadius: 16,
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, color: dashboardGreen, size: 20),
                    tooltip: 'Zoom Out',
                    onPressed: () {
                      final currentZoom = _mapController.camera.zoom;
                      _mapController.move(_mapController.camera.center, currentZoom - 0.5);
                    },
                    splashRadius: 16,
                  ),
                  IconButton(
                    icon: const Icon(Icons.center_focus_strong_rounded, color: dashboardGreen, size: 20),
                    tooltip: 'Fit Ward Boundary',
                    onPressed: _resetView,
                    splashRadius: 16,
                  ),
                ],
              ),
            ),
          ),

          // 3. Mode Label Banner (Top Left)
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dashboardGreen, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_rounded, color: dashboardGreen, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    widget.ward.wardNo != null
                        ? 'OPENSTREETMAP • WARD ${widget.ward.wardNo}'
                        : 'OPENSTREETMAP • ${widget.ward.name.toUpperCase()}',
                    style: const TextStyle(
                      color: dashboardGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HIERARCHY TREE WIDGET (Themed in Dashboard Green #006341 & White)
// ============================================================================

class WardLeadershipTree extends StatelessWidget {
  final List<WardOfficial> officials;
  final Ward ward;

  static const Color dashboardGreen = Color(0xFF006341);

  const WardLeadershipTree({super.key, required this.officials, required this.ward});

  @override
  Widget build(BuildContext context) {
    final tier1 = officials.where((o) => o.tier == 1).toList();
    final tier2 = officials.where((o) => o.tier == 2).toList();
    final tier3 = officials.where((o) => o.tier == 3).toList();
    final tier4 = officials.where((o) => o.tier == 4).toList();

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Tree Title & Subtitle Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: dashboardGreen, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_tree_rounded, color: dashboardGreen, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'BBMP & GBA CIVIC COMMAND HIERARCHY TREE',
                    style: TextStyle(
                      color: dashboardGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // TIER 1: Apex Leadership (Root Node)
            _buildTierHeader('TIER 1 · APEX MUNICIPAL GOVERNANCE & MP', const Color(0xFFD97706)),
            const SizedBox(height: 10),
            _buildDualNodeRow(tier1),

            // Curved Branch Splitter 1 -> 2
            _buildTreeBranchSplitter(const Color(0xFFD97706), dashboardGreen),

            // TIER 2: State Legislative & Zonal Joint Commissioner
            _buildTierHeader('TIER 2 · STATE LEGISLATURE & ZONAL COMMAND', dashboardGreen),
            const SizedBox(height: 10),
            _buildDualNodeRow(tier2.take(2).toList()),

            // Curved Branch Splitter 2 -> 3
            _buildTreeBranchSplitter(dashboardGreen, dashboardGreen),

            // TIER 3: Sub-Division Engineering & Ward Councillor
            _buildTierHeader('TIER 3 · SUB-DIVISION AEE & LOCAL REPRESENTATIVE', dashboardGreen),
            const SizedBox(height: 10),
            _buildDualNodeRow(tier3),

            // Curved Branch Splitter 3 -> 4
            _buildTreeBranchSplitter(dashboardGreen, const Color(0xFFEA580C)),

            // TIER 4: Field Operations, Health Inspector & Contractor
            _buildTierHeader('TIER 4 · FIELD SANITATION & SWM CONTRACTORS', const Color(0xFFEA580C)),
            const SizedBox(height: 10),
            _buildDualNodeRow(tier4.take(2).toList()),
            if (tier4.length > 2) ...[
              const SizedBox(height: 10),
              _buildSingleNode(tier4.last),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTierHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.3),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildTreeBranchSplitter(Color topColor, Color bottomColor) {
    return SizedBox(
      height: 38,
      width: 240,
      child: CustomPaint(
        painter: _TreeBranchPainter(topColor: topColor, bottomColor: bottomColor),
      ),
    );
  }

  Widget _buildDualNodeRow(List<WardOfficial> pair) {
    if (pair.isEmpty) return const SizedBox.shrink();
    if (pair.length == 1) return _buildSingleNode(pair.first);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: OfficialTreeNodeCard(official: pair[0], wardName: ward.name)),
        const SizedBox(width: 14),
        Expanded(child: OfficialTreeNodeCard(official: pair[1], wardName: ward.name)),
      ],
    );
  }

  Widget _buildSingleNode(WardOfficial official) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: OfficialTreeNodeCard(official: official, wardName: ward.name),
    );
  }
}

/// CustomPainter drawing clean glowing tree branch connectors between tiers
class _TreeBranchPainter extends CustomPainter {
  final Color topColor;
  final Color bottomColor;

  _TreeBranchPainter({required this.topColor, required this.bottomColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final top = Offset(cx, 0);
    final bottomLeft = Offset(size.width * 0.22, size.height);
    final bottomRight = Offset(size.width * 0.78, size.height);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topColor, bottomColor],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Vertical Stem
    canvas.drawLine(top, Offset(cx, size.height * 0.45), linePaint);

    // Left Curved Branch
    final leftPath = Path()
      ..moveTo(cx, size.height * 0.45)
      ..cubicTo(cx, size.height * 0.75, bottomLeft.dx, size.height * 0.75, bottomLeft.dx, bottomLeft.dy);
    canvas.drawPath(leftPath, linePaint);

    // Right Curved Branch
    final rightPath = Path()
      ..moveTo(cx, size.height * 0.45)
      ..cubicTo(cx, size.height * 0.75, bottomRight.dx, size.height * 0.75, bottomRight.dx, bottomRight.dy);
    canvas.drawPath(rightPath, linePaint);

    // Joint Dots
    final dotPaint = Paint()..color = bottomColor;
    canvas.drawCircle(top, 3.5, Paint()..color = topColor);
    canvas.drawCircle(Offset(cx, size.height * 0.45), 3.0, dotPaint);
    canvas.drawCircle(bottomLeft, 3.5, dotPaint);
    canvas.drawCircle(bottomRight, 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _TreeBranchPainter oldDelegate) => false;
}

// ============================================================================
// OFFICIAL TREE NODE CARD (Themed in Dashboard Green #006341 & Crisp White)
// ============================================================================

class OfficialTreeNodeCard extends StatelessWidget {
  final WardOfficial official;
  final String wardName;

  static const Color dashboardGreen = Color(0xFF006341);

  const OfficialTreeNodeCard({
    super.key,
    required this.official,
    required this.wardName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dashboardGreen.withValues(alpha: 0.45), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: dashboardGreen.withValues(alpha: 0.08),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Bar with Photo & Official Info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Authentic Photo Avatar with Green Status Ring
                _buildPhotoAvatar(official),
                const SizedBox(width: 12),

                // Name & Designation
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        official.name,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        official.designation,
                        style: const TextStyle(
                          color: dashboardGreen,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        official.department,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons Bar (Call, Mail, Message) in Green & White
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                // 📞 Call Action
                Expanded(
                  child: _buildActionBtn(
                    icon: Icons.call_rounded,
                    label: 'Call',
                    color: dashboardGreen,
                    onTap: () {
                      _showToast(context, 'Calling ${official.name}...');
                      WardOfficialsService.instance.launchCall(official.phone);
                    },
                  ),
                ),
                const SizedBox(width: 6),

                // ✉️ Email Action
                Expanded(
                  child: _buildActionBtn(
                    icon: Icons.email_rounded,
                    label: 'Email',
                    color: const Color(0xFF0284C7),
                    onTap: () {
                      _showToast(context, 'Drafting email to ${official.name}...');
                      WardOfficialsService.instance.launchMail(
                        official.email,
                        wardName: wardName,
                        officialName: official.name,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),

                // 💬 WhatsApp / Message Action
                Expanded(
                  child: _buildActionBtn(
                    icon: Icons.chat_bubble_rounded,
                    label: 'Message',
                    color: const Color(0xFF10B981),
                    onTap: () {
                      _showToast(context, 'Opening chat for ${official.name}...');
                      WardOfficialsService.instance.launchMessage(
                        official.whatsapp ?? official.phone,
                        wardName: wardName,
                        officialName: official.name,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Official Photo Avatar with Dashboard Green Frame and Fallback to Initials
  Widget _buildPhotoAvatar(WardOfficial official) {
    final photo = official.photoUrl;

    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: dashboardGreen, width: 2.0),
            boxShadow: [
              BoxShadow(
                color: dashboardGreen.withValues(alpha: 0.25),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipOval(
            child: (photo != null && photo.isNotEmpty)
                ? Image.network(
                    photo,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: const Color(0xFFE8F5E9),
                        child: const Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: dashboardGreen),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return _buildInitialsFallback(official);
                    },
                  )
                : _buildInitialsFallback(official),
          ),
        ),

        // Green Online Status Dot
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF10B981),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialsFallback(WardOfficial official) {
    final initials = official.name
        .replaceAll('Shri', '')
        .replaceAll('Smt.', '')
        .replaceAll('Dr.', '')
        .trim()
        .split(' ')
        .take(2)
        .map((s) => s.isNotEmpty ? s[0] : '')
        .join();

    return Container(
      color: const Color(0xFFE8F5E9),
      child: Center(
        child: Text(
          initials.isNotEmpty ? initials : 'GOV',
          style: const TextStyle(
            color: dashboardGreen,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: dashboardGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }
}
