import 'dart:async';
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
import '../widgets/trash_flag_inspection_modal.dart';
import '../widgets/placeholder_map_switch.dart';
import '../services/ward_zone_service.dart';
import '../services/trash_spots_service.dart';
import '../models/garbage_flag.dart';
import '../models/trail_segment.dart';
import '../widgets/trash_flag_inspection_modal.dart';
import '../services/authority_directory_service.dart';

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
  String _vehicleViewMode = 'both'; // 'both' (Map & List together), 'list', 'map'

  // Search & Filters for Complaints from Users
  String _complaintSearchQuery = '';
  String _complaintStatusFilter = 'All'; // 'All', 'In Progress', 'Resolved'

  // Cached zones & wards
  List<String> _zones = ['All Zones'];
  List<String> _wards = ['All Wards'];

  StreamSubscription? _liveTrackingSub;
  Map<String, Map<String, dynamic>> _liveVehicles = {};

  @override
  void initState() {
    super.initState();
    WardZoneService.instance.init();
    WardZoneService.instance.notifier.addListener(_onWardZoneUpdate);
    TrashSpotsService.instance.init();
    TrashSpotsService.instance.flagsNotifier.addListener(_onWardZoneUpdate);
    TrashSpotsService.instance.showPlaceholdersNotifier.addListener(_onWardZoneUpdate);
    _fetchZonesAndWards();
    _startLiveTrackingListener();
  }

  void _onWardZoneUpdate() {
    if (mounted) setState(() {});
  }

  final Map<String, List<Polyline>> _vehicleTrails = {};
  final Map<String, StreamSubscription> _vehicleTrailSubs = {};

  @override
  void dispose() {
    WardZoneService.instance.notifier.removeListener(_onWardZoneUpdate);
    TrashSpotsService.instance.flagsNotifier.removeListener(_onWardZoneUpdate);
    TrashSpotsService.instance.showPlaceholdersNotifier.removeListener(_onWardZoneUpdate);
    _liveTrackingSub?.cancel();
    for (var sub in _vehicleTrailSubs.values) {
      sub.cancel();
    }
    _vehicleTrailSubs.clear();
    super.dispose();
  }

  void _syncVehicleTrails(List<String> vehicleIds) {
    final currentIds = vehicleIds.toSet();
    final toRemove = _vehicleTrailSubs.keys.where((k) => !currentIds.contains(k)).toList();
    for (var k in toRemove) {
      _vehicleTrailSubs[k]?.cancel();
      _vehicleTrailSubs.remove(k);
      _vehicleTrails.remove(k);
    }

    final today = DateTime.now().toIso8601String().substring(0, 10);
    for (var vId in vehicleIds) {
      if (_vehicleTrailSubs.containsKey(vId)) continue;
      _vehicleTrailSubs[vId] = FirebaseFirestore.instance
          .collection('vehicles')
          .doc(vId)
          .collection('daily_stats')
          .doc(today)
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        final data = snap.data();
        final polylines = TrailSegment.listFromDailyStats(data);
        setState(() {
          _vehicleTrails[vId] = polylines;
        });
      });
    }
  }

  void _startLiveTrackingListener() {
    _liveTrackingSub = FirebaseFirestore.instance.collection('live_tracking').snapshots().listen((snap) {
      if (!mounted) return;
      final activeIds = <String>[];
      setState(() {
        for (var doc in snap.docs) {
          final data = doc.data();
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            _liveVehicles[doc.id] = data;
            activeIds.add(doc.id);
          }
        }
      });
      _syncVehicleTrails(activeIds);
    });
  }

  Future<void> _fetchZonesAndWards() async {
    try {
      final zonesSnap = await FirebaseFirestore.instance.collection('zones').get();
      final wardsSnap = await FirebaseFirestore.instance.collection('wards').get();
      if (mounted) {
        final allFetchedZones = zonesSnap.docs.map((d) => (d.data()['name'] ?? d.id).toString()).toList();
        final allFetchedWards = wardsSnap.docs.map((d) => (d.data()['name'] ?? d.id).toString()).toList();

        final userWard = RoleService.currentUserWard;
        final userZone = RoleService.currentUserZone;

        List<String> zList = ['All Zones', ...allFetchedZones];
        List<String> wList = ['All Wards', ...allFetchedWards];
        String selZone = _vehicleSelectedZone;
        String selWard = _vehicleSelectedWard;

        // If restricted to a specific ward by Role
        if (userWard != null && userWard.trim().isNotEmpty && userWard != 'All Wards') {
          wList = [userWard];
          selWard = userWard;
          if (userZone != null && userZone.trim().isNotEmpty && userZone != 'All Zones') {
            zList = [userZone];
            selZone = userZone;
          }
        } else if (userZone != null && userZone.trim().isNotEmpty && userZone != 'All Zones') {
          // If restricted to a specific zone by Role
          zList = [userZone];
          selZone = userZone;
          final zoneWards = WardZoneService.instance.getWardsForZone(userZone);
          if (zoneWards.isNotEmpty) {
            wList = ['All Wards', ...zoneWards];
          }
        }

        setState(() {
          _zones = zList.toSet().toList();
          _wards = wList.toSet().toList();
          _vehicleSelectedZone = selZone;
          _vehicleSelectedWard = selWard;
        });

        _zoomToSelectedArea(_vehicleSelectedZone, _vehicleSelectedWard);
      }
    } catch (e) {
      debugPrint("Error fetching zones/wards: $e");
    }
  }

  void _zoomToSelectedArea(String zone, String ward) {
    try {
      if (ward != 'All Wards') {
        final matches = WardZoneService.instance.wards.where(
          (w) => w.name.trim().toLowerCase() == ward.trim().toLowerCase(),
        );
        if (matches.isNotEmpty && matches.first.boundary.isNotEmpty) {
          final b = matches.first.boundary;
          double cLat = 0, cLng = 0;
          for (var p in b) {
            cLat += p.latitude;
            cLng += p.longitude;
          }
          _vehicleMapController.move(LatLng(cLat / b.length, cLng / b.length), 15.2);
          return;
        }
      } else if (zone != 'All Zones') {
        final matches = WardZoneService.instance.zones.where(
          (z) => z.name.trim().toLowerCase() == zone.trim().toLowerCase(),
        );
        if (matches.isNotEmpty && matches.first.boundary.isNotEmpty) {
          final b = matches.first.boundary;
          double cLat = 0, cLng = 0;
          for (var p in b) {
            cLat += p.latitude;
            cLng += p.longitude;
          }
          _vehicleMapController.move(LatLng(cLat / b.length, cLng / b.length), 12.5);
          return;
        }
      } else {
        _vehicleMapController.move(const LatLng(12.9716, 77.5946), 11.8);
      }
    } catch (_) {}
  }

  void _onZoneChanged(String? newZone) {
    if (newZone == null) return;
    setState(() {
      _vehicleSelectedZone = newZone;
      if (newZone == 'All Zones') {
        _wards = ['All Wards', ...WardZoneService.instance.wards.map((w) => w.name).toSet()];
      } else {
        final zoneWards = WardZoneService.instance.getWardsForZone(newZone);
        _wards = ['All Wards', ...zoneWards];
        if (_vehicleSelectedWard != 'All Wards' && !zoneWards.contains(_vehicleSelectedWard)) {
          _vehicleSelectedWard = 'All Wards';
        }
      }
    });
    _zoomToSelectedArea(newZone, _vehicleSelectedWard);
  }

  void _onWardChanged(String? newWard) {
    if (newWard == null) return;
    setState(() {
      _vehicleSelectedWard = newWard;
    });
    _zoomToSelectedArea(_vehicleSelectedZone, newWard);
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('trash_spots').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF0F5132)));
        }

        final docs = snapshot.data?.docs ?? [];
        final Map<String, Map<String, dynamic>> flagsMap = {};

        for (var doc in docs) {
          final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
          data['id'] = doc.id;

          // Check if Trash Detected
          final roadStatus = (data['road_status'] ?? '').toString();
          final displayClass = (data['display_class'] ?? '').toString();
          final className = (data['class'] ?? '').toString();
          final trashCount = (data['trash_count'] as num?)?.toInt();
          final isTrash = GarbageFlag.isTrashDetectedSpot(
            roadStatus: roadStatus,
            displayClass: displayClass,
            className: className,
            trashCount: trashCount,
          );
          if (!isTrash) continue;

          // Geographic access filter via RoleService
          final docZone = (data['zone'] ?? '').toString().trim();
          final docWard = (data['ward'] ?? '').toString().trim();
          final lat = ((data['lat'] ?? 0.0) as num).toDouble();
          final lng = ((data['lng'] ?? 0.0) as num).toDouble();

          // Placeholder filter
          final isPh = data['is_placeholder'] == true || doc.id.toLowerCase().startsWith('flag_') || doc.id.toLowerCase().startsWith('seed_');
          if (!TrashSpotsService.instance.showPlaceholders && isPh) {
            continue;
          }

          if (!RoleService.isSpotAllowed(lat, lng, docZone, docWard, 'COM&D')) {
            continue;
          }

          flagsMap[doc.id] = data;
        }

        // Merge backend trash detected flags
        for (var f in TrashSpotsService.instance.allFlags) {
          if (!f.isTrashReport) continue;
          if (!TrashSpotsService.instance.showPlaceholders && f.isPlaceholder) continue;
          if (!flagsMap.containsKey(f.id)) {
            if (!RoleService.isSpotAllowed(f.lat, f.lng, f.zone, f.ward, 'COM&D')) {
              continue;
            }

            flagsMap[f.id] = {
              'id': f.id,
              'lat': f.lat,
              'lng': f.lng,
              'road_status': f.displayClass.isNotEmpty ? f.displayClass : 'Trash Detected',
              'display_class': f.displayClass,
              'class': f.className,
              'confidence': f.confidence,
              'image_url': f.imageUrl,
              'timestamp': Timestamp.fromDate(DateTime.tryParse(f.timestamp) ?? DateTime.now()),
              'status': f.status,
              'vehicle_number': f.vehicleNumber,
              'ward': f.ward,
              'zone': f.zone,
              'model_version': f.modelVersion ?? MODEL_VERSION,
            };
          }
        }

        List<Map<String, dynamic>> allFlags = flagsMap.values.toList();

        // Sort descending by timestamp
        allFlags.sort((a, b) {
          final ta = a['timestamp'];
          final tb = b['timestamp'];
          if (ta is Timestamp && tb is Timestamp) {
            return tb.compareTo(ta);
          }
          return 0;
        });

        // 1. AREA FILTERING FIRST (Zone and Ward filters)
        var areaFilteredFlags = allFlags;
        if (_vehicleSelectedZone != 'All Zones') {
          areaFilteredFlags = areaFilteredFlags.where((f) {
            final lat = ((f['lat'] ?? 0.0) as num).toDouble();
            final lng = ((f['lng'] ?? 0.0) as num).toDouble();
            final z = (f['zone'] ?? '').toString();
            return WardZoneService.instance.matchesZone(
              lat: lat,
              lng: lng,
              docZone: z,
              targetZone: _vehicleSelectedZone,
            );
          }).toList();
        }

        if (_vehicleSelectedWard != 'All Wards') {
          areaFilteredFlags = areaFilteredFlags.where((f) {
            final lat = ((f['lat'] ?? 0.0) as num).toDouble();
            final lng = ((f['lng'] ?? 0.0) as num).toDouble();
            final w = (f['ward'] ?? '').toString();
            return WardZoneService.instance.matchesWard(
              lat: lat,
              lng: lng,
              docWard: w,
              targetWard: _vehicleSelectedWard,
            );
          }).toList();
        }

        // 2. STAT COUNTERS COMPUTED STRICTLY ON THE AREA-FILTERED SPOTS
        final totalCount = areaFilteredFlags.length;
        final activeCount = areaFilteredFlags.where((f) => f['status'] != 'Deflagged').length;
        final deflaggedCount = areaFilteredFlags.where((f) => f['status'] == 'Deflagged').length;

        // 3. Apply Status & Search Filters to the area-filtered spots for the list and map
        var displayedFlags = areaFilteredFlags;
        if (_vehicleStatusFilter == 'Flagged') {
          displayedFlags = displayedFlags.where((f) => f['status'] != 'Deflagged').toList();
        } else if (_vehicleStatusFilter == 'Deflagged') {
          displayedFlags = displayedFlags.where((f) => f['status'] == 'Deflagged').toList();
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
            // Stat Cards Banner - strictly reflects the selected area!
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
                        // View Toggle: Split, List, Map
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () {
                                  setState(() => _vehicleViewMode = 'both');
                                  if (displayedFlags.isNotEmpty) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      try {
                                        final firstLat = ((displayedFlags.first['lat'] ?? 13.0568) as num).toDouble();
                                        final firstLng = ((displayedFlags.first['lng'] ?? 77.5027) as num).toDouble();
                                        _vehicleMapController.move(LatLng(firstLat, firstLng), 13.5);
                                      } catch (_) {}
                                    });
                                  }
                                },
                                icon: Icon(LucideIcons.columns, color: _vehicleViewMode == 'both' ? const Color(0xFF0F5132) : const Color(0xFF94A3B8), size: 18),
                                tooltip: 'Map & List (Split)',
                                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                              ),
                              IconButton(
                                onPressed: () => setState(() => _vehicleViewMode = 'list'),
                                icon: Icon(LucideIcons.list, color: _vehicleViewMode == 'list' ? const Color(0xFF0F5132) : const Color(0xFF94A3B8), size: 18),
                                tooltip: 'List View Only',
                                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() => _vehicleViewMode = 'map');
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
                                icon: Icon(LucideIcons.map, color: _vehicleViewMode == 'map' ? const Color(0xFF0F5132) : const Color(0xFF94A3B8), size: 18),
                                tooltip: 'Map View Only',
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(6),
                              color: const Color(0xFFF8FAFC),
                            ),
                            child: Row(
                              children: [
                                const Text('Role: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                Text(RoleService.currentUserRoleTitle ?? 'None', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _buildFilterChip('All Flags (${totalCount})', _vehicleStatusFilter == 'All', () {
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
                              value: _zones.contains(_vehicleSelectedZone) ? _vehicleSelectedZone : (_zones.isNotEmpty ? _zones.first : 'All Zones'),
                              underline: const SizedBox(),
                              isDense: true,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w600),
                              items: _zones.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                              onChanged: _zones.length <= 1 ? null : _onZoneChanged,
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
                              value: _wards.contains(_vehicleSelectedWard) ? _vehicleSelectedWard : (_wards.isNotEmpty ? _wards.first : 'All Wards'),
                              underline: const SizedBox(),
                              isDense: true,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w600),
                              items: _wards.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                              onChanged: _wards.length <= 1 ? null : _onWardChanged,
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

            // Content Area: Map and/or List
            Expanded(
              child: _vehicleViewMode == 'map'
                  ? _buildVehicleMapView(displayedFlags)
                  : (_vehicleViewMode == 'list'
                      ? _buildVehicleListView(displayedFlags, isMobile)
                      : (isMobile
                          ? Column(
                              children: [
                                SizedBox(
                                  height: 250,
                                  child: _buildVehicleMapView(displayedFlags),
                                ),
                                const SizedBox(height: 8),
                                Expanded(child: _buildVehicleListView(displayedFlags, isMobile)),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _buildVehicleMapView(displayedFlags),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 5,
                                  child: _buildVehicleListView(displayedFlags, isMobile),
                                ),
                              ],
                            ))),
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
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDeflagged ? const Color(0xFF10B981).withOpacity(0.4) : const Color(0xFFEF4444).withOpacity(0.35), width: 1.5),
          ),
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.06),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              try {
                _vehicleMapController.move(LatLng(lat, lng), 15.0);
              } catch (_) {}
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail with click-to-preview
                GestureDetector(
                  onTap: () => _showMarkerDetailsModal(context, flag),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: isMobile ? 100 : 130,
                          height: isMobile ? 100 : 120,
                          color: const Color(0xFFF1F5F9),
                          child: NgrokImage(
                            url: AuthorityDirectoryService.instance.resolveImageUrl(imageUrl, id),
                            fit: BoxFit.cover,
                            width: isMobile ? 100 : 130,
                            height: isMobile ? 100 : 120,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), shape: BoxShape.circle),
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
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
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
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
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

                      // Actions Row: Map Pin, Directions & Deflag
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              try {
                                _vehicleMapController.move(LatLng(lat, lng), 15.0);
                              } catch (_) {}
                            },
                            icon: const Icon(LucideIcons.mapPin, size: 14),
                            label: const Text('Map Pin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2563EB),
                              backgroundColor: const Color(0xFFEFF6FF),
                              side: const BorderSide(color: Color(0xFFBFDBFE)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _openMaps(lat, lng),
                            icon: const Icon(LucideIcons.navigation, size: 14),
                            label: const Text('Directions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F5132),
                              backgroundColor: const Color(0xFFECFDF5),
                              side: const BorderSide(color: Color(0xFFA7F3D0)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!isDeflagged) ...[
                            ElevatedButton.icon(
                              onPressed: () {
                                ComndDeflagScreen.showDeflagSelectionModal(
                                  context: context,
                                  documentId: id,
                                  initialVehicleNumber: vehicleNumber,
                                  initialLocation: '$zone, $ward',
                                  lat: lat,
                                  lng: lng,
                                  ward: ward,
                                  zone: zone,
                                );
                              },
                              icon: const Icon(LucideIcons.camera, size: 14),
                              label: const Text('Deflag', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F5132),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: IconButton(
                                onPressed: () => _confirmQuickDeflag(context, id, flag),
                                icon: const Icon(LucideIcons.checkCheck, color: Color(0xFF059669), size: 18),
                                tooltip: 'Quick Deflag (No Camera)',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                              ),
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
          ),
        );
      },
    );
  }

  Widget _buildVehicleMapView(List<Map<String, dynamic>> flags) {
    const double clusterDist = 0.00018;
    final List<List<Map<String, dynamic>>> clusters = [];

    // Draw assigned road routes (Google Maps Blue) and real-time color-coded driven trails for live fleet vehicles
    List<Polyline> routePolylines = [];
    for (var entry in _liveVehicles.entries) {
      final data = entry.value;
      if (data['assignedRoute'] != null) {
        final List<dynamic> rawRoute = data['assignedRoute'];
        final pts = rawRoute.map((e) => LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble())).toList();
        if (pts.isNotEmpty) {
          // Google Maps Blue Polyline with outer border casing
          routePolylines.add(Polyline(
            points: pts,
            color: const Color(0xFF0D47A1), // Deep Navy Border Casing
            strokeWidth: 8.0,
          ));
          routePolylines.add(Polyline(
            points: pts,
            color: const Color(0xFF1A73E8), // Vibrant Google Maps Navigation Blue
            strokeWidth: 5.5,
          ));
        }
      }
      // Real-time live traversed path streamed directly from moving truck
      if (data['traversed_path'] != null) {
        final List<dynamic> rawPath = data['traversed_path'];
        final pathPts = rawPath.map((e) => LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble())).toList();
        if (pathPts.length >= 2) {
          routePolylines.add(Polyline(
            points: pathPts,
            color: const Color(0xFF00E676), // Bright Green Live Traced Trail
            strokeWidth: 5.0,
          ));
        }
      }
    }
    // Add real vehicle driven breadcrumb trails with condition colors (Green = Clean, Orange = Trash, Red = Very Dirty / Pothole)
    for (var trail in _vehicleTrails.values) {
      routePolylines.addAll(trail);
    }

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
        child: Stack(
          children: [
            FlutterMap(
              mapController: _vehicleMapController,
              options: const MapOptions(
                initialCenter: LatLng(12.9716, 77.5946),
                initialZoom: 11.8,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.nitin.trashtracker',
                ),
                ...WardZoneService.instance.buildLayers(
                  selectedZone: _vehicleSelectedZone,
                  selectedWard: _vehicleSelectedWard,
                ),
                if (routePolylines.isNotEmpty)
                  PolylineLayer(polylines: routePolylines),
                Builder(
                  builder: (context) {
                    final camera = MapCamera.of(context);
                    final hasSpecificWard = _vehicleSelectedWard != 'All Wards' && _vehicleSelectedWard.isNotEmpty;
                    final bool showPins = hasSpecificWard
                        ? (camera.zoom >= 14.8)
                        : (camera.zoom >= WardZoneService.individualWardPinsZoomThreshold);
                    if (!showPins || clusters.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return MarkerLayer(
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
                    );
                  },
                ),
                // Live fleet vehicle markers on Command Screen
                if (_liveVehicles.isNotEmpty)
                  MarkerLayer(
                    markers: _liveVehicles.entries.map((entry) {
                      final data = entry.value;
                      final lat = (data['lat'] as num).toDouble();
                      final lng = (data['lng'] as num).toDouble();
                      final isActive = data['isActive'] as bool? ?? false;
                      return Marker(
                        point: LatLng(lat, lng),
                        width: 90,
                        height: 55,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: isActive ? const Color(0xFF10B981) : const Color(0xFF3B82F6), width: 1.5),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: Text(
                                entry.key,
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isActive ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                              ),
                              child: const Icon(LucideIcons.truck, color: Colors.white, size: 12),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
            // Floating Placeholder vs Real Flags Switch
            Positioned(
              top: 14,
              right: 14,
              child: const PlaceholderMapSwitch(isDark: false),
            ),
          ],
        ),
      ),
    );
  }

  void _showMarkerDetailsModal(BuildContext context, Map<String, dynamic> flag) {
    final vehicle = flag['vehicle_number'] ?? 'Unknown Vehicle';
    final status = flag['status'] ?? 'Flagged';
    final lat = ((flag['lat'] ?? 0.0) as num).toDouble();
    final lng = ((flag['lng'] ?? 0.0) as num).toDouble();
    final isDeflagged = status == 'Deflagged';

    TrashFlagInspectionModal.showFromMap(
      context,
      flag,
      onDeflag: isDeflagged
          ? null
          : () {
              ComndDeflagScreen.showDeflagSelectionModal(
                context: context,
                documentId: flag['id'] ?? '',
                initialVehicleNumber: vehicle.toString(),
                initialLocation: '${flag['zone'] ?? ''}, ${flag['ward'] ?? ''}',
                lat: lat,
                lng: lng,
                ward: flag['ward'],
                zone: flag['zone'],
              );
            },
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
        }

        // Filter complaints by RoleService access and selected Zone/Ward
        List<Map<String, dynamic>> allowedComplaints = userComplaints.where((c) {
          final lat = ((c['lat'] ?? 0.0) as num).toDouble();
          final lng = ((c['lng'] ?? 0.0) as num).toDouble();
          final z = (c['zone'] ?? '').toString();
          final w = (c['ward'] ?? '').toString();

          if (!RoleService.isSpotAllowed(lat, lng, z, w, 'COM&D')) return false;

          if (_vehicleSelectedZone != 'All Zones' &&
              !WardZoneService.instance.matchesZone(lat: lat, lng: lng, docZone: z, targetZone: _vehicleSelectedZone)) {
            return false;
          }

          if (_vehicleSelectedWard != 'All Wards' &&
              !WardZoneService.instance.matchesWard(lat: lat, lng: lng, docWard: w, targetWard: _vehicleSelectedWard)) {
            return false;
          }

          return true;
        }).toList();

        final totalComplaints = allowedComplaints.length;
        final pendingComplaints = allowedComplaints.where((c) => c['status'] != 'Resolved' && c['status'] != 'Deflagged').length;
        final resolvedComplaints = allowedComplaints.where((c) => c['status'] == 'Resolved' || c['status'] == 'Deflagged').length;

        var displayedComplaints = allowedComplaints;
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                        color: const Color(0xFFF8FAFC),
                      ),
                      child: Row(
                        children: [
                          const Text('Role: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                          Text(RoleService.currentUserRoleTitle ?? 'None', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)),
                        ],
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
              child: displayedComplaints.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.messageSquare, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No citizen complaints found',
                            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Reports submitted by citizens will appear here in real time.',
                            style: TextStyle(color: Colors.black54, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
                itemCount: displayedComplaints.length,
                itemBuilder: (context, index) {
                  final complaint = displayedComplaints[index];
                  final isResolved = complaint['status'] == 'Resolved' || complaint['status'] == 'Deflagged';
                  final imageUrl = complaint['image_url'] ?? complaint['image'] ?? '';
                  final lat = ((complaint['lat'] ?? 0.0) as num).toDouble();
                  final lng = ((complaint['lng'] ?? 0.0) as num).toDouble();

                  return Card(
                    color: Colors.white,
                    surfaceTintColor: Colors.transparent,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8F0))),
                    elevation: 1.5,
                    shadowColor: Colors.black.withOpacity(0.04),
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
                                errorBuilder: (_, __, ___) => Container(width: 85, height: 85, color: const Color(0xFFF1F5F9), child: const Icon(Icons.broken_image, color: Color(0xFF94A3B8))),
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
