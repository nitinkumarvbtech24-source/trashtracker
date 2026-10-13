import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/role_service.dart';
import '../widgets/ngrok_image.dart';
import 'comnd_deflag_screen.dart';
import '../constants.dart';
import '../widgets/trash_pinpoint_marker.dart';

class ComndScreen extends StatefulWidget {
  const ComndScreen({super.key});

  @override
  State<ComndScreen> createState() => _ComndScreenState();
}

class _ComndScreenState extends State<ComndScreen> {
  // 0: Complaints from Users, 1: Flags by Vehicles
  int _selectedNavIndex = 1; // Default to Flags by Vehicles as requested

  // Map Controller
  final MapController _vehicleMapController = MapController();

  // Search & Filters for Flags by Vehicles
  String _vehicleSearchQuery = '';
  String _vehicleStatusFilter = 'All'; // 'All', 'Flagged', 'Deflagged'
  String _vehicleSelectedZone = 'All Zones';
  String _vehicleSelectedWard = 'All Wards';
  bool _isVehicleMapView = false;

  // Search & Filters for Complaints from Users
  String _complaintSearchQuery = '';
  String _complaintStatusFilter = 'All'; // 'All', 'In Progress', 'Resolved'

  // Cached zones & wards
  List<String> _zones = ['All Zones'];
  List<String> _wards = ['All Wards'];

  @override
  void initState() {
    super.initState();
    _fetchZonesAndWards();
  }

  Future<void> _fetchZonesAndWards() async {
    try {
      final zonesSnap = await FirebaseFirestore.instance.collection('zones').get();
      final wardsSnap = await FirebaseFirestore.instance.collection('wards').get();
      if (mounted) {
        setState(() {
          _zones = ['All Zones', ...zonesSnap.docs.map((d) => (d.data()['name'] ?? d.id).toString()).toList()];
          _wards = ['All Wards', ...wardsSnap.docs.map((d) => (d.data()['name'] ?? d.id).toString()).toList()];
        });
      }
    } catch (e) {
      debugPrint("Error fetching zones/wards: $e");
    }
  }

  Future<void> _openMaps(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Google Maps')));
    }
  }

  void _showImagePreviewDialog(BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161822),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(LucideIcons.x, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 520),
                      child: imageUrl.contains('ngrok')
                          ? NgrokImage(url: imageUrl, fit: BoxFit.contain)
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Container(
                                height: 240,
                                color: Colors.white10,
                                child: const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48)),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmQuickDeflag(BuildContext context, String docId, Map<String, dynamic> data) async {
    final vehicle = data['vehicle_number'] ?? 'Vehicle';
    final TextEditingController noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(LucideIcons.checkCircle2, color: Color(0xFF10B981), size: 24),
            SizedBox(width: 10),
            Text('Confirm Deflag', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mark spot flagged by $vehicle as cleared and clean?', style: const TextStyle(fontSize: 14, color: Color(0xFF334155))),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: 'Resolution Note (Optional)',
                hintText: 'e.g. Cleared by maintenance squad',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(LucideIcons.check, size: 16),
            label: const Text('Deflag Spot'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F5132),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('trash_spots').doc(docId).update({
          'status': 'Deflagged',
          'deflagged_at': FieldValue.serverTimestamp(),
          'deflag_note': noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : 'Deflagged by Authority Officer',
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Spot marked as Deflagged / Cleaned!'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ==========================================
  // TOP STATS CARDS
  // ==========================================
  Widget _buildStatCard(String label, int value, IconData icon, Color color, {bool isMobile = false}) {
    return Container(
      height: isMobile ? 80 : 92,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: isMobile ? 36 : 44,
            height: isMobile ? 36 : 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: isMobile ? 18 : 22),
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
                    color: const Color(0xFF64748B),
                    fontSize: isMobile ? 9 : 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value.toString(),
                  style: TextStyle(
                    color: const Color(0xFF0F172A),
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
  }

  // ==========================================
  // TAB 1: FLAGS BY VEHICLES
  // ==========================================
  Widget _buildFlagsByVehiclesView(bool isMobile) {
    final allowedZones = RoleService.getAllowedZonesForModule('COM&D');
    final allowedWards = RoleService.getAllowedWardsForModule('COM&D');
    final hasAllAccess = RoleService.hasAllAccess('COM&D');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('trash_spots').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF0F5132)));
        }

        final docs = snapshot.data?.docs ?? [];
        List<Map<String, dynamic>> allFlags = [];

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;

          // Only Trash Detected
          final roadStatus = (data['road_status'] ?? '').toString();
          if (roadStatus != 'Trash Detected') continue;

          // Model version filter
          final mv = data['model_version'] ?? data['modelVersion'];
          if (mv != null) {
            final s = mv.toString().toLowerCase().trim();
            if (s != MODEL_VERSION.toString() && s != 'v$MODEL_VERSION') continue;
          } else {
            continue;
          }

          // Geographic access filter
          final docZone = (data['zone'] ?? '').toString().trim();
          final docWard = (data['ward'] ?? '').toString().trim();
          bool hasAccess = hasAllAccess;
          if (!hasAccess && allowedZones.isNotEmpty) {
            hasAccess = allowedZones.any((z) => z.trim().toLowerCase() == docZone.toLowerCase());
          }
          if (!hasAccess && allowedWards.isNotEmpty) {
            hasAccess = allowedWards.any((w) => w.trim().toLowerCase() == docWard.toLowerCase());
          }

          if (hasAccess) {
            allFlags.add(data);
          }
        }

        // Sort descending by timestamp
        allFlags.sort((a, b) {
          final ta = a['timestamp'];
          final tb = b['timestamp'];
          if (ta is Timestamp && tb is Timestamp) {
            return tb.compareTo(ta);
          }
          return 0;
        });

        final totalCount = allFlags.length;
        final activeCount = allFlags.where((f) => f['status'] != 'Deflagged').length;
        final deflaggedCount = allFlags.where((f) => f['status'] == 'Deflagged').length;

        // Apply UI Filters
        var displayedFlags = allFlags;
        if (_vehicleStatusFilter == 'Flagged') {
          displayedFlags = displayedFlags.where((f) => f['status'] != 'Deflagged').toList();
        } else if (_vehicleStatusFilter == 'Deflagged') {
          displayedFlags = displayedFlags.where((f) => f['status'] == 'Deflagged').toList();
        }

        if (_vehicleSelectedZone != 'All Zones') {
          displayedFlags = displayedFlags.where((f) {
            final z = (f['zone'] ?? '').toString().trim().toLowerCase();
            final target = _vehicleSelectedZone.trim().toLowerCase();
            return z == target || z.contains(target) || target.contains(z);
          }).toList();
        }
        if (_vehicleSelectedWard != 'All Wards') {
          displayedFlags = displayedFlags.where((f) {
            final w = (f['ward'] ?? '').toString().trim().toLowerCase();
            final target = _vehicleSelectedWard.trim().toLowerCase();
            return w == target || w.replaceAll(' ', '') == target.replaceAll(' ', '');
          }).toList();
        }

        if (_vehicleSearchQuery.trim().isNotEmpty) {
          final query = _vehicleSearchQuery.trim().toLowerCase();
          displayedFlags = displayedFlags.where((f) {
            final veh = (f['vehicle_number'] ?? '').toString().toLowerCase();
            final ward = (f['ward'] ?? '').toString().toLowerCase();
            final zone = (f['zone'] ?? '').toString().toLowerCase();
            final status = (f['road_status'] ?? '').toString().toLowerCase();
            return veh.contains(query) || ward.contains(query) || zone.contains(query) || status.contains(query);
          }).toList();
        }

        return Column(
          children: [
            // Stat Cards Banner
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(child: _buildStatCard('Total Flags', totalCount, LucideIcons.flag, const Color(0xFF3B82F6), isMobile: isMobile)),
                  SizedBox(width: isMobile ? 8 : 12),
                  Expanded(child: _buildStatCard('Active / Need Action', activeCount, LucideIcons.alertTriangle, const Color(0xFFEF4444), isMobile: isMobile)),
                  SizedBox(width: isMobile ? 8 : 12),
                  Expanded(child: _buildStatCard('Deflagged / Cleaned', deflaggedCount, LucideIcons.checkCircle2, const Color(0xFF10B981), isMobile: isMobile)),
                ],
              ),
            ),

            // Controls & Filter Bar
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    // Search & View Toggle
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (val) => setState(() => _vehicleSearchQuery = val),
                            decoration: InputDecoration(
                              hintText: 'Search by Vehicle, Ward, Road Status...',
                              prefixIcon: const Icon(LucideIcons.search, size: 18, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // View Toggle
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => setState(() => _isVehicleMapView = false),
                                icon: Icon(LucideIcons.list, color: !_isVehicleMapView ? const Color(0xFF0F5132) : const Color(0xFF94A3B8), size: 18),
                                tooltip: 'List View',
                                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() => _isVehicleMapView = true);
                                  if (displayedFlags.isNotEmpty) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      try {
                                        final firstLat = ((displayedFlags.first['lat'] ?? 13.0568) as num).toDouble();
                                        final firstLng = ((displayedFlags.first['lng'] ?? 77.5027) as num).toDouble();
                                        _vehicleMapController.move(LatLng(firstLat, firstLng), 14.0);
                                      } catch (_) {}
                                    });
                                  }
                                },
                                icon: Icon(LucideIcons.map, color: _isVehicleMapView ? const Color(0xFF0F5132) : const Color(0xFF94A3B8), size: 18),
                                tooltip: 'Map View',
                                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Filter Chips Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All Flags (${allFlags.length})', _vehicleStatusFilter == 'All', () {
                            setState(() => _vehicleStatusFilter = 'All');
                          }),
                          const SizedBox(width: 8),
                          _buildFilterChip('🚨 Active (${activeCount})', _vehicleStatusFilter == 'Flagged', () {
                            setState(() => _vehicleStatusFilter = 'Flagged');
                          }, activeColor: const Color(0xFFEF4444)),
                          const SizedBox(width: 8),
                          _buildFilterChip('✅ Deflagged (${deflaggedCount})', _vehicleStatusFilter == 'Deflagged', () {
                            setState(() => _vehicleStatusFilter = 'Deflagged');
                          }, activeColor: const Color(0xFF10B981)),
                          const SizedBox(width: 14),
                          // Zone Dropdown
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: DropdownButton<String>(
                              value: _zones.contains(_vehicleSelectedZone) ? _vehicleSelectedZone : 'All Zones',
                              underline: const SizedBox(),
                              isDense: true,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w600),
                              items: _zones.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                              onChanged: (val) => setState(() => _vehicleSelectedZone = val ?? 'All Zones'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Ward Dropdown
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: DropdownButton<String>(
                              value: _wards.contains(_vehicleSelectedWard) ? _vehicleSelectedWard : 'All Wards',
                              underline: const SizedBox(),
                              isDense: true,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w600),
                              items: _wards.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                              onChanged: (val) => setState(() => _vehicleSelectedWard = val ?? 'All Wards'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Content Area: List or Map
            Expanded(
              child: _isVehicleMapView
                  ? _buildVehicleMapView(displayedFlags)
                  : _buildVehicleListView(displayedFlags, isMobile),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap, {Color? activeColor}) {
    final color = activeColor ?? const Color(0xFF0F5132);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : const Color(0xFFCBD5E1), width: isSelected ? 1.5 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? color : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleListView(List<Map<String, dynamic>> flags, bool isMobile) {
    if (flags.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.flag, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('No vehicle flags found matching filter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
            const SizedBox(height: 4),
            const Text('Live flags detected by fleet AI will appear here automatically', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
      itemCount: flags.length,
      itemBuilder: (context, index) {
        final flag = flags[index];
        final id = flag['id'] as String;
        final imageUrl = flag['image_url'] ?? '';
        final vehicleNumber = flag['vehicle_number'] ?? 'Unknown Vehicle';
        final status = flag['status'] ?? 'Flagged';
        final roadStatus = flag['road_status'] ?? 'Trash Detected';
        final confidence = ((flag['confidence'] ?? 0.0) as num).toDouble();
        final ward = flag['ward'] ?? 'Unknown Ward';
        final zone = flag['zone'] ?? 'Unknown Zone';
        final lat = ((flag['lat'] ?? 0.0) as num).toDouble();
        final lng = ((flag['lng'] ?? 0.0) as num).toDouble();
        final isDeflagged = status == 'Deflagged';

        final ts = flag['timestamp'];
        String dateStr = 'Unknown Time';
        if (ts is Timestamp) {
          final dt = ts.toDate();
          dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }

        final deflaggedTs = flag['deflagged_at'];
        String deflaggedDateStr = '';
        if (deflaggedTs is Timestamp) {
          final dt = deflaggedTs.toDate();
          deflaggedDateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDeflagged ? const Color(0xFF10B981).withOpacity(0.4) : const Color(0xFFEF4444).withOpacity(0.35), width: 1.5),
          ),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail with click-to-preview
                GestureDetector(
                  onTap: () {
                    if (imageUrl.isNotEmpty) {
                      _showImagePreviewDialog(context, imageUrl, '$vehicleNumber • $roadStatus');
                    }
                  },
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: isMobile ? 100 : 130,
                          height: isMobile ? 100 : 120,
                          color: const Color(0xFF1E293B),
                          child: imageUrl.isNotEmpty
                              ? (imageUrl.contains('ngrok')
                                  ? NgrokImage(url: imageUrl, fit: BoxFit.cover, width: isMobile ? 100 : 130, height: isMobile ? 100 : 120)
                                  : Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
                                    ))
                              : const Center(child: Icon(LucideIcons.camera, color: Colors.white54, size: 28)),
                        ),
                      ),
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), shape: BoxShape.circle),
                          child: const Icon(LucideIcons.maximize2, color: Colors.white, size: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Details Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Vehicle Badge & Status Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.truck, size: 16, color: Color(0xFF0F5132)),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    vehicleNumber.toUpperCase(),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDeflagged ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isDeflagged ? LucideIcons.checkCheck : LucideIcons.alertCircle, size: 13, color: isDeflagged ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                                const SizedBox(width: 4),
                                Text(
                                  isDeflagged ? 'DEFLAGGED' : 'FLAGGED',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDeflagged ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Road Status & Confidence
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              roadStatus,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                            ),
                          ),
                          if (confidence > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${(confidence * 100).toInt()}% conf',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Location Details
                      Row(
                        children: [
                          const Icon(LucideIcons.mapPin, size: 13, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '$zone • $ward',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF334155)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // Timestamp
                      Row(
                        children: [
                          const Icon(LucideIcons.clock, size: 13, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Text('Reported: $dateStr', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),

                      if (isDeflagged && deflaggedDateStr.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(LucideIcons.check, size: 13, color: Color(0xFF10B981)),
                            const SizedBox(width: 4),
                            Text('Cleaned: $deflaggedDateStr', style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Actions Row: Directions & Deflag
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _openMaps(lat, lng),
                            icon: const Icon(LucideIcons.navigation, size: 14),
                            label: const Text('Directions', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F5132),
                              side: const BorderSide(color: Color(0xFF0F5132)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (!isDeflagged) ...[
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ComndDeflagScreen(
                                      documentId: id,
                                      initialVehicleNumber: vehicleNumber,
                                      initialLocation: '$zone, $ward',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(LucideIcons.camera, size: 14),
                              label: const Text('Deflag', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F5132),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              onPressed: () => _confirmQuickDeflag(context, id, flag),
                              icon: const Icon(LucideIcons.checkCheck, color: Color(0xFF10B981), size: 20),
                              tooltip: 'Quick Deflag (No Camera)',
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(6),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(LucideIcons.checkCheck, color: Color(0xFF059669), size: 14),
                                  SizedBox(width: 4),
                                  Text('Spot Cleaned', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVehicleMapView(List<Map<String, dynamic>> flags) {
    const double clusterDist = 0.00018;
    final List<List<Map<String, dynamic>>> clusters = [];

    for (var f in flags) {
      final lat = ((f['lat'] ?? 0.0) as num).toDouble();
      final lng = ((f['lng'] ?? 0.0) as num).toDouble();
      bool added = false;
      for (var c in clusters) {
        final cLat = ((c.first['lat'] ?? 0.0) as num).toDouble();
        final cLng = ((c.first['lng'] ?? 0.0) as num).toDouble();
        if ((lat - cLat).abs() < clusterDist && (lng - cLng).abs() < clusterDist) {
          c.add(f);
          added = true;
          break;
        }
      }
      if (!added) {
        clusters.add([f]);
      }
    }

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          mapController: _vehicleMapController,
          options: MapOptions(
            initialCenter: flags.isNotEmpty
                ? LatLng(((flags.first['lat'] ?? 13.0568) as num).toDouble(), ((flags.first['lng'] ?? 77.5027) as num).toDouble())
                : const LatLng(13.0568, 77.5027),
            initialZoom: 13,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
            ),
            MarkerLayer(
              markers: clusters.map<Marker>((cluster) {
                final f = cluster.first;
                final lat = ((f['lat'] ?? 0.0) as num).toDouble();
                final lng = ((f['lng'] ?? 0.0) as num).toDouble();
                final status = f['status'] ?? 'Flagged';
                final isDeflagged = status == 'Deflagged';

                return Marker(
                  point: LatLng(lat, lng),
                  width: isDeflagged ? 36 : 38,
                  height: isDeflagged ? 36 : 46,
                  alignment: isDeflagged ? Alignment.center : Alignment.topCenter,
                  child: isDeflagged
                      ? GestureDetector(
                          onTap: () => _showMarkerDetailsModal(context, f),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                            ),
                            child: const Center(
                              child: Icon(LucideIcons.check, color: Colors.white, size: 18),
                            ),
                          ),
                        )
                      : TrashPinpointWidget(
                          count: cluster.length,
                          isVeryDirty: cluster.any((item) => item['road_status'] == 'Very Dirty Road' || item['road_status'] == 'Very_Dirty'),
                          onTap: () => _showMarkerDetailsModal(context, f),
                        ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showMarkerDetailsModal(BuildContext context, Map<String, dynamic> flag) {
    final vehicle = flag['vehicle_number'] ?? 'Unknown Vehicle';
    final status = flag['status'] ?? 'Flagged';
    final roadStatus = flag['road_status'] ?? 'Trash Detected';
    final imageUrl = flag['image_url'] ?? '';
    final lat = ((flag['lat'] ?? 0.0) as num).toDouble();
    final lng = ((flag['lng'] ?? 0.0) as num).toDouble();
    final isDeflagged = status == 'Deflagged';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(vehicle.toString().toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDeflagged ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isDeflagged ? 'DEFLAGGED' : 'FLAGGED',
                    style: TextStyle(color: isDeflagged ? const Color(0xFF059669) : const Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
            if (imageUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: imageUrl.contains('ngrok')
                      ? NgrokImage(url: imageUrl, fit: BoxFit.cover)
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
                        ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text('Status: $roadStatus • ${flag['zone'] ?? ''} - ${flag['ward'] ?? ''}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openMaps(lat, lng),
                    icon: const Icon(LucideIcons.navigation, size: 16),
                    label: const Text('Directions'),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0F5132)),
                  ),
                ),
                if (!isDeflagged) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ComndDeflagScreen(
                              documentId: flag['id'],
                              initialVehicleNumber: vehicle,
                              initialLocation: '${flag['zone'] ?? ''}, ${flag['ward'] ?? ''}',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.camera, size: 16),
                      label: const Text('Deflag Spot'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132), foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 0: COMPLAINTS FROM USERS
  // ==========================================
  Widget _buildComplaintsFromUsersView(bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('user_complaints').snapshots(),
      builder: (context, snapshot) {
        List<Map<String, dynamic>> userComplaints = [];

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          userComplaints = snapshot.data!.docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            data['id'] = d.id;
            return data;
          }).toList();
        } else {
          // Provide realistic initial complaints for testing if collection is empty
          userComplaints = [
            {
              'id': 'CMP-10042',
              'category': 'Garbage Dumped',
              'lat': 12.9750,
              'lng': 77.5980,
              'status': 'In Progress',
              'date': 'Yesterday, 14:30',
              'image_url': 'https://images.unsplash.com/photo-1532996122724-e3c354a0b15b?auto=format&fit=crop&q=80',
              'comment': 'Heavy trash dumped on the sidewalk near commercial street.',
              'ward': 'Ward 01',
              'zone': 'Central Zone',
              'reportCount': 3,
            },
            {
              'id': 'CMP-10021',
              'category': 'Overflowing Bin',
              'lat': 12.9700,
              'lng': 77.5900,
              'status': 'Resolved',
              'date': 'Oct 12, 09:15',
              'image_url': 'https://images.unsplash.com/photo-1605600659928-879857d47228?auto=format&fit=crop&q=80',
              'comment': 'Public bin is overflowing and spilling onto the road.',
              'ward': 'Ward 02',
              'zone': 'East Zone',
              'reportCount': 1,
            },
            {
              'id': 'CMP-10065',
              'category': 'Littered Plastic',
              'lat': 12.9735,
              'lng': 77.5960,
              'status': 'In Progress',
              'date': 'Today, 10:45',
              'image_url': 'https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?auto=format&fit=crop&q=80',
              'comment': 'Plastic bottles scattered around bus stand entrance.',
              'ward': 'Ward 01',
              'zone': 'Central Zone',
              'reportCount': 4,
            },
          ];
        }

        final totalComplaints = userComplaints.length;
        final pendingComplaints = userComplaints.where((c) => c['status'] != 'Resolved' && c['status'] != 'Deflagged').length;
        final resolvedComplaints = userComplaints.where((c) => c['status'] == 'Resolved' || c['status'] == 'Deflagged').length;

        var displayedComplaints = userComplaints;
        if (_complaintStatusFilter == 'In Progress') {
          displayedComplaints = displayedComplaints.where((c) => c['status'] != 'Resolved' && c['status'] != 'Deflagged').toList();
        } else if (_complaintStatusFilter == 'Resolved') {
          displayedComplaints = displayedComplaints.where((c) => c['status'] == 'Resolved' || c['status'] == 'Deflagged').toList();
        }

        if (_complaintSearchQuery.trim().isNotEmpty) {
          final query = _complaintSearchQuery.trim().toLowerCase();
          displayedComplaints = displayedComplaints.where((c) {
            final cat = (c['category'] ?? '').toString().toLowerCase();
            final comment = (c['comment'] ?? '').toString().toLowerCase();
            final id = (c['id'] ?? '').toString().toLowerCase();
            return cat.contains(query) || comment.contains(query) || id.contains(query);
          }).toList();
        }

        return Column(
          children: [
            // Stats Banner
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(child: _buildStatCard('Total Reports', totalComplaints, LucideIcons.messageSquare, const Color(0xFF3B82F6), isMobile: isMobile)),
                  SizedBox(width: isMobile ? 8 : 12),
                  Expanded(child: _buildStatCard('Pending / Action', pendingComplaints, LucideIcons.clock, const Color(0xFFF59E0B), isMobile: isMobile)),
                  SizedBox(width: isMobile ? 8 : 12),
                  Expanded(child: _buildStatCard('Resolved / Deflagged', resolvedComplaints, LucideIcons.checkCircle2, const Color(0xFF10B981), isMobile: isMobile)),
                ],
              ),
            ),

            // Search & Filter
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (val) => setState(() => _complaintSearchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search user complaints...',
                          prefixIcon: const Icon(LucideIcons.search, size: 18, color: Color(0xFF94A3B8)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildFilterChip('All', _complaintStatusFilter == 'All', () => setState(() => _complaintStatusFilter = 'All')),
                    const SizedBox(width: 6),
                    _buildFilterChip('Pending', _complaintStatusFilter == 'In Progress', () => setState(() => _complaintStatusFilter = 'In Progress'), activeColor: const Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    _buildFilterChip('Resolved', _complaintStatusFilter == 'Resolved', () => setState(() => _complaintStatusFilter = 'Resolved'), activeColor: const Color(0xFF10B981)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Complaints List
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
                itemCount: displayedComplaints.length,
                itemBuilder: (context, index) {
                  final complaint = displayedComplaints[index];
                  final isResolved = complaint['status'] == 'Resolved' || complaint['status'] == 'Deflagged';
                  final imageUrl = complaint['image_url'] ?? complaint['image'] ?? '';
                  final lat = ((complaint['lat'] ?? 0.0) as num).toDouble();
                  final lng = ((complaint['lng'] ?? 0.0) as num).toDouble();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 1.5,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imageUrl.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                imageUrl,
                                width: 85,
                                height: 85,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(width: 85, height: 85, color: Colors.grey.shade200, child: const Icon(Icons.broken_image)),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      complaint['category'] ?? 'Complaint',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isResolved ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        isResolved ? 'RESOLVED' : 'PENDING',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isResolved ? const Color(0xFF059669) : const Color(0xFFB45309),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(complaint['comment'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
                                const SizedBox(height: 6),
                                Text('${complaint['zone'] ?? 'Zone'} • ${complaint['ward'] ?? 'Ward'} | ${complaint['date'] ?? ''}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _openMaps(lat, lng),
                                      icon: const Icon(LucideIcons.navigation, size: 13),
                                      label: const Text('Directions', style: TextStyle(fontSize: 11)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF0F5132),
                                        side: const BorderSide(color: Color(0xFF0F5132)),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!isResolved)
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          if (complaint['id'] != null && !complaint['id'].toString().startsWith('CMP-')) {
                                            await FirebaseFirestore.instance.collection('user_complaints').doc(complaint['id']).update({'status': 'Resolved'});
                                          }
                                          setState(() {
                                            complaint['status'] = 'Resolved';
                                          });
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Complaint marked as Resolved!'), backgroundColor: Color(0xFF10B981)));
                                          }
                                        },
                                        icon: const Icon(LucideIcons.check, size: 13),
                                        label: const Text('Resolve', style: TextStyle(fontSize: 11)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF0F5132),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // CUSTOM BOTTOM NAVIGATION BAR (2 TABS)
  // ==========================================
  Widget _buildCustomBottomNavBar(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Tab 0: Complaints from Users
            Expanded(
              child: _buildBottomNavTab(
                index: 0,
                icon: LucideIcons.messageSquare,
                title: 'Complaints from Users',
                subtitle: 'Citizen Reports',
                activeColor: const Color(0xFF3B82F6),
                isMobile: isMobile,
              ),
            ),
            const SizedBox(width: 12),
            // Tab 1: Flags by Vehicles
            Expanded(
              child: _buildBottomNavTab(
                index: 1,
                icon: LucideIcons.truck,
                title: 'Flags by Vehicles',
                subtitle: 'Fleet AI Detections',
                activeColor: const Color(0xFF0F5132),
                isMobile: isMobile,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavTab({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color activeColor,
    required bool isMobile,
  }) {
    final isSelected = _selectedNavIndex == index;

    return GestureDetector(
      onTap: () {
        if (_selectedNavIndex != index) {
          setState(() {
            _selectedNavIndex = index;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 10, horizontal: isMobile ? 8 : 14),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.12) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: activeColor.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: isMobile ? 16 : 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? activeColor : const Color(0xFF475569),
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: isMobile ? 11 : 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isSelected ? activeColor.withOpacity(0.8) : const Color(0xFF94A3B8),
                      fontSize: isMobile ? 9 : 11,
                      fontWeight: FontWeight.w500,
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
    );
  }

  // ==========================================
  // MAIN BUILD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: _selectedNavIndex == 1
          ? _buildFlagsByVehiclesView(isMobile)
          : _buildComplaintsFromUsersView(isMobile),
      bottomNavigationBar: _buildCustomBottomNavBar(isMobile),
    );
  }
}
