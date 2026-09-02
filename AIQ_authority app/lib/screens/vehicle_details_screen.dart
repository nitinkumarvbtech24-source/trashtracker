import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/map_cache_service.dart';
import '../mock_data.dart';
import '../models/vehicle.dart';
import '../models/ward.dart';
import '../constants.dart';
import '../widgets/ngrok_image.dart';
import 'cleanliness_screen.dart';
import '../models/garbage_flag.dart';
import 'database_screen.dart';

class VehicleDetailsScreen extends StatefulWidget {
  final Vehicle vehicle;
  final Ward? ward;

  const VehicleDetailsScreen({
    super.key,
    required this.vehicle,
    this.ward,
  });

  @override
  State<VehicleDetailsScreen> createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen> {
  final MapController _mapController = MapController();
  bool _isFullscreenMap = false;
  StreamSubscription<DocumentSnapshot>? _dailyStatsSub;
  StreamSubscription<DocumentSnapshot>? _vehicleSub;
  Vehicle? _liveVehicle;

  double _distanceCoveredKm = 0.0;
  List<LatLng> _drivenRoute = [];
  
  List<GarbageFlag> _garbageFlags = [];
  StreamSubscription<QuerySnapshot>? _trashSub;

  bool _showAssignedWard = true;
  bool _showFlags = true;

  String get _todayDateString => DateTime.now().toIso8601String().split('T')[0];
  
  @override
  void initState() {
    super.initState();
    _liveVehicle = widget.vehicle;
    _fetchDailyStats();
    _fetchGarbageFlags();

    _vehicleSub = FirebaseFirestore.instance
        .collection('vehicles')
        .doc(widget.vehicle.vehicleNumber)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null) {
        if (mounted) {
          setState(() {
            _liveVehicle = Vehicle.fromJson(doc.id, doc.data() as Map<String, dynamic>);
          });
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_liveVehicle?.currentLocation != null) {
        _mapController.move(_liveVehicle!.currentLocation!, 16.0);
      } else if (widget.ward != null && widget.ward!.boundary.isNotEmpty) {
        _mapController.move(widget.ward!.boundary.first, 15.0);
      }
    });
  }

  void _fetchDailyStats() {
    _dailyStatsSub = FirebaseFirestore.instance
        .collection('vehicles')
        .doc(widget.vehicle.vehicleNumber)
        .collection('daily_stats')
        .doc(_todayDateString)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        if (mounted) {
          setState(() {
            _distanceCoveredKm = (data['distance_km'] ?? 0.0).toDouble();
            if (data['route'] != null) {
              final List<dynamic> rawRoute = data['route'];
              _drivenRoute = rawRoute.map((e) => LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble())).toList();
            }
          });
        }
      }
    });
  }

  Future<void> _fetchGarbageFlags() async {
    _trashSub?.cancel();
    _trashSub = FirebaseFirestore.instance.collection('trash_spots')
        .where('vehicle_number', isEqualTo: widget.vehicle.vehicleNumber)
        .snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _garbageFlags = snapshot.docs
            .map((doc) => GarbageFlag.fromJson(doc.data(), doc.id))
            .where((f) => f.status != 'Resolved' && (f.className == 'Very_Dirty' || f.className == 'Slightly_Dirty' || f.displayClass == 'Very Dirty' || f.displayClass == 'Slightly Dirty'))
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _dailyStatsSub?.cancel();
    _vehicleSub?.cancel();
    _trashSub?.cancel();
    super.dispose();
  }

  Future<void> _resetTrip(DocumentReference tripRef, String? date) async {
    final bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Trip?'),
        content: const Text('This will delete the trip log, clear its colored trail, and hide the active garbage flags for this vehicle. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Reset', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      await tripRef.delete();
      if (date != null) {
        await FirebaseFirestore.instance.collection('vehicles').doc(widget.vehicle.vehicleNumber)
            .collection('daily_stats').doc(date)
            .update({'route': FieldValue.delete()}).catchError((_) {});
      }
      final snapshot = await FirebaseFirestore.instance.collection('trash_spots')
          .where('vehicle_number', isEqualTo: widget.vehicle.vehicleNumber)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'status': 'Resolved'});
      }
      await batch.commit();

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip reset successfully.'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error resetting trip: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _showTripsDialog() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Trips History - ${widget.vehicle.vehicleNumber}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('vehicles')
                        .doc(widget.vehicle.vehicleNumber)
                        .collection('trips')
                        .orderBy('startTime', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No trips found.'));
                      return ListView.builder(
                        controller: scrollController,
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          final doc = snapshot.data!.docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final distance = (data['distanceKm'] as num?)?.toStringAsFixed(2) ?? '0.00';
                          final flags = data['flags'] ?? 0;
                          final startTime = DateTime.tryParse(data['startTime'] ?? '')?.toLocal();
                          final startStr = startTime != null ? '${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')}' : 'N/A';
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: const Icon(Icons.directions_car, color: Colors.blueAccent),
                              title: Text('Trip ${data['date'] ?? ''} - $startStr'),
                              subtitle: Text('Distance: $distance km • Flags: $flags'),
                              trailing: IconButton(
                                icon: const Icon(Icons.refresh_rounded, color: Colors.redAccent),
                                onPressed: () => _resetTrip(doc.reference, data['date']),
                                tooltip: 'Reset Trip',
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    final distanceCovered = '${_distanceCoveredKm.toStringAsFixed(1)} km';
    final flagsTriggered = _garbageFlags.length.toString();
    final wardAuthorityName = 'Auth_${widget.vehicle.assignedWard.replaceAll(" ", "")}';
    final wardAuthorityPhone = '+91 98765 43210';
    final driverPhone = widget.vehicle.phoneNumber ?? '+91 91234 56789';

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F5132),
        title: Text('Vehicle: ${widget.vehicle.vehicleNumber}', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(LucideIcons.bell), onPressed: (){}),
          IconButton(icon: const Icon(LucideIcons.helpCircle), onPressed: (){}),
          IconButton(icon: const Icon(LucideIcons.user), onPressed: (){}),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF0F5132),
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(icon: Icon(LucideIcons.database), label: 'Fleet Database'),
          const BottomNavigationBarItem(icon: Icon(LucideIcons.truck), label: 'Trips'),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(LucideIcons.bell),
                Positioned(
                  right: -4, top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: const Text('3', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),
                )
              ]
            ),
            label: 'Alerts'
          ),
        ],
        onTap: (index) {
          if (index == 0) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => DatabaseScreen(vehicleFilter: widget.vehicle.vehicleNumber)));
          } else if (index == 1) {
            _showTripsDialog();
          }
        },
      ),
      body: _isFullscreenMap
          ? _buildFullscreenMap()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Stats Row
                  Row(
                    children: [
                      Expanded(flex: 2, child: _buildCompactMetricCard('Distance Today', distanceCovered, LucideIcons.mapPin, Colors.blue)),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _buildCompactMetricCard('Flags Today', flagsTriggered, LucideIcons.flag, Colors.red)),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: _buildCompactContactCard('Driver', widget.vehicle.driverName, driverPhone)),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: _buildCompactContactCard('Authority', wardAuthorityName, wardAuthorityPhone)),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(LucideIcons.refreshCw, size: 14, color: Color(0xFF4B5563)),
                                  label: Text('Trips', style: GoogleFonts.inter(color: const Color(0xFF4B5563), fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    side: BorderSide(color: Colors.grey.shade300),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    backgroundColor: Colors.white,
                                  ),
                                  onPressed: _showTripsDialog,
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(LucideIcons.database, size: 14, color: Color(0xFF4B5563)),
                                  label: Text('Fleet DB', style: GoogleFonts.inter(color: const Color(0xFF4B5563), fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    side: BorderSide(color: Colors.grey.shade300),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    backgroundColor: Colors.white,
                                  ),
                                  onPressed: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => DatabaseScreen(vehicleFilter: widget.vehicle.vehicleNumber)));
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Last Updated: 10:30 AM', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF6B7280))),
                                const SizedBox(width: 4),
                                const Icon(LucideIcons.refreshCw, size: 10, color: Color(0xFF6B7280)),
                              ],
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Middle Section: Left & Right Columns
                  isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Column (Map)
                            Expanded(
                              flex: 7,
                              child: _buildSmallMapBox(),
                            ),
                            const SizedBox(width: 24),
                            // Right Column (Charts & Images)
                            Expanded(
                              flex: 5,
                              child: Column(
                                children: [
                                  _buildVehiclePieChart(),
                                  const SizedBox(height: 24),
                                  _buildImageGallery(),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _buildSmallMapBox(),
                            const SizedBox(height: 24),
                            _buildVehiclePieChart(),
                            const SizedBox(height: 24),
                            _buildImageGallery(),
                          ],
                        ),
                ],
              ),
            ),
    );
  }


  Widget _buildCompactMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.inter(color: const Color(0xFF111827), fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactContactCard(String role, String name, String phone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(role == 'Driver' ? LucideIcons.user : LucideIcons.shieldCheck, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role, style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(name, style: GoogleFonts.inter(color: const Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(phone, style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 10)),
                ],
              ),
            ]
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(LucideIcons.phone, color: Colors.green.shade700, size: 14),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallMapBox() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Live Location & Route',
                  style: GoogleFonts.inter(color: const Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => setState(() => _isFullscreenMap = true),
                  icon: const Icon(LucideIcons.maximize2, color: Color(0xFF6B7280), size: 18),
                  tooltip: 'Enlarge',
                )
              ],
            ),
          ),
          SizedBox(
            height: 600,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
              child: Stack(
                children: [
                  _buildMap(),
                  _buildMapControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      bottom: 24,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'btn_current_location',
            mini: true,
            backgroundColor: Colors.white,
            elevation: 2,
            child: const Icon(LucideIcons.crosshair, color: Color(0xFF4B5563)),
            onPressed: () {
              final loc = _liveVehicle?.currentLocation ?? widget.vehicle.currentLocation;
              if (loc != null) _mapController.move(loc, 16.0);
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Ward & Route', style: GoogleFonts.inter(color: const Color(0xFF4B5563), fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Switch(
                      value: _showAssignedWard,
                      onChanged: (val) => setState(() => _showAssignedWard = val),
                      activeColor: Colors.green,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Trash Flags', style: GoogleFonts.inter(color: const Color(0xFF4B5563), fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 20),
                    Switch(
                      value: _showFlags,
                      onChanged: (val) => setState(() => _showFlags = val),
                      activeColor: Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFullscreenMap() {
    return Stack(
      children: [
        _buildMap(),
        Positioned(
          top: 24,
          right: 24,
          child: FloatingActionButton(
            heroTag: 'btn_shrink_map',
            onPressed: () => setState(() => _isFullscreenMap = false),
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF4B5563),
            child: const Icon(LucideIcons.minimize2),
          ),
        ),
        _buildMapControls(),
      ],
    );
  }

  Widget _buildNotificationsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Triggered Flags & Notifications',
              style: GoogleFonts.inter(color: const Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _buildNotificationItem('Garbage Flag', 'Ward: ${widget.vehicle.assignedWard}', '2 min ago', Colors.red, LucideIcons.trash2),
                const SizedBox(height: 12),
                _buildNotificationItem('Pothole Detected', 'Ward: ${widget.vehicle.assignedWard}', '15 min ago', Colors.red, LucideIcons.circle),
                const SizedBox(height: 12),
                _buildNotificationItem('Deviation Alert', 'Off assigned route', '1 hr ago', Colors.orange, LucideIcons.alertTriangle),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(String title, String subtitle, String time, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(color: const Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle, style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 11)),
              ],
            ),
          ),
          Row(
            children: [
              Text(time, style: GoogleFonts.inter(color: const Color(0xFF9CA3AF), fontSize: 11)),
              const SizedBox(width: 8),
              const Icon(LucideIcons.chevronRight, size: 14, color: Color(0xFF9CA3AF)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehiclePieChart() {
    double cleanVal = _garbageFlags.where((f) => f.className == 'Clean').length.toDouble();
    double slightVal = _garbageFlags.where((f) => f.className == 'Slightly_Dirty').length.toDouble();
    double dirtyVal = _garbageFlags.where((f) => f.className == 'Very_Dirty').length.toDouble();
    double total = _garbageFlags.isEmpty ? 1 : _garbageFlags.length.toDouble();
    
    if (cleanVal == 0 && slightVal == 0 && dirtyVal == 0) {
      cleanVal = 1;
      total = 1;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Snapshot Breakdown (Today)', style: GoogleFonts.inter(color: const Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: [
                  if (cleanVal > 0)
                    PieChartSectionData(color: Colors.green, value: cleanVal, title: '${((cleanVal / total) * 100).toInt()}%', radius: 40, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  if (slightVal > 0)
                    PieChartSectionData(color: Colors.orange, value: slightVal, title: '${((slightVal / total) * 100).toInt()}%', radius: 40, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  if (dirtyVal > 0)
                    PieChartSectionData(color: Colors.red, value: dirtyVal, title: '${((dirtyVal / total) * 100).toInt()}%', radius: 40, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem(Colors.green, 'Clean (${cleanVal.toInt()})'),
              _buildLegendItem(Colors.orange, 'Slightly Dirty (${slightVal.toInt()})'),
              _buildLegendItem(Colors.red, 'Very Dirty (${dirtyVal.toInt()})'),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(color: const Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildImageGallery() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Captured Images (Today)', style: GoogleFonts.inter(color: const Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Text('View All', style: GoogleFonts.inter(color: const Color(0xFF4B5563), fontSize: 12)),
                  const SizedBox(width: 4),
                  const Icon(LucideIcons.arrowRight, size: 14, color: Color(0xFF4B5563)),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: _garbageFlags.isEmpty
                ? Center(child: Text("No images captured yet.", style: GoogleFonts.inter(color: Colors.grey.shade500)))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _garbageFlags.length,
                    itemBuilder: (context, index) {
                      final flag = _garbageFlags[index];
                      final isVeryDirty = flag.className == 'Very_Dirty';
                      final color = isVeryDirty ? Colors.red.shade800 : Colors.orange.shade800;
                      final label = isVeryDirty ? 'Very Dirty Road' : 'Slightly Dirty Road';
                      
                      return GestureDetector(
                        onTap: () => _showTrashPopup(flag),
                        child: Container(
                          width: 200,
                          margin: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Image and Banner
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                child: Stack(
                                  children: [
                                    SizedBox(height: 120, width: double.infinity, child: NgrokImage(url: flag.imageUrl, fit: BoxFit.cover)),
                                    Positioned(
                                      bottom: 0, left: 0, right: 0,
                                      child: Container(
                                        color: color.withOpacity(0.9),
                                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                        child: Text('$label (${(flag.confidence*100).toStringAsFixed(1)}%)', style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                              // Details
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                                      child: Text('TRANSFERRED', style: GoogleFonts.inter(color: Colors.green.shade700, fontSize: 8, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                                        const SizedBox(width: 6),
                                        Text(widget.vehicle.assignedWard, style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 10), overflow: TextOverflow.ellipsis),
                                      ]
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(LucideIcons.calendar, size: 10, color: Color(0xFF9CA3AF)),
                                        const SizedBox(width: 6),
                                        Text(flag.timestamp.split(' ')[0], style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 10)),
                                      ]
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(LucideIcons.clock, size: 10, color: Color(0xFF9CA3AF)),
                                        const SizedBox(width: 6),
                                        Text(flag.timestamp.split(' ').length > 1 ? flag.timestamp.split(' ')[1] : '10:15 AM', style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 10)),
                                      ]
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showTrashPopup(GarbageFlag flag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          '${flag.displayClass} - ${flag.timestamp}',
          style: GoogleFonts.inter(color: const Color(0xFF111827), fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 400,
                child: NgrokImage(url: flag.imageUrl, height: 200, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 16),
            Text("Confidence: ${(flag.confidence * 100).toStringAsFixed(1)}%", style: GoogleFonts.inter(color: const Color(0xFF6B7280))),
            const SizedBox(height: 4),
            Text("Lat: ${flag.lat.toStringAsFixed(5)}, Lng: ${flag.lng.toStringAsFixed(5)}", style: GoogleFonts.inter(color: const Color(0xFF9CA3AF), fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.directions_outlined, size: 18),
            label: const Text('Navigate'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132), foregroundColor: Colors.white),
            onPressed: () async {
              final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${flag.lat},${flag.lng}');
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    Map<String, List<GarbageFlag>> sessions = {};
    for (var flag in _garbageFlags) {
      if (flag.sessionId != null) {
        sessions.putIfAbsent(flag.sessionId!, () => []).add(flag);
      }
    }

    List<Polyline> routePolylines = [];
    
    if (_drivenRoute.isNotEmpty) {
      routePolylines.add(Polyline(
        points: _drivenRoute,
        strokeWidth: 4,
        color: Colors.blueAccent.withValues(alpha: 0.8),
      ));
    }

    final currentVehicle = _liveVehicle ?? widget.vehicle;
    final displayLocation = currentVehicle.currentLocation ?? widget.vehicle.currentLocation;

    if (currentVehicle.assignedRoute != null && currentVehicle.assignedRoute!.isNotEmpty) {
      routePolylines.add(Polyline(
        points: currentVehicle.assignedRoute!,
        strokeWidth: 5,
        color: Colors.purpleAccent.withValues(alpha: 0.6),
        borderStrokeWidth: 2,
        borderColor: Colors.white.withValues(alpha: 0.5),
      ));
    }

    sessions.forEach((sessionId, list) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (int i = 0; i < list.length - 1; i++) {
        final start = LatLng(list[i].lat, list[i].lng);
        final end = LatLng(list[i + 1].lat, list[i + 1].lng);
        final status = list[i + 1].className;
        
        Color segmentColor = Colors.green;
        if (status == 'Very_Dirty') segmentColor = Colors.red;
        else if (status == 'Slightly_Dirty') segmentColor = Colors.orange;
        
        routePolylines.add(Polyline(
          points: [start, end],
          color: segmentColor,
          strokeWidth: 4.0,
        ));
      }
    });

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: displayLocation ?? mapCenter,
            initialZoom: mapZoom,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.street_aiq',
              tileProvider: kIsWeb ? null : CachedTileProvider(store: MapCacheService.store),
            ),
            if (_showAssignedWard && widget.ward != null)
              PolygonLayer(
                polygons: [
                  Polygon<Object>(
                    points: widget.ward!.boundary,
                    color: const Color(0xFF3B82F6).withOpacity(0.1),
                    borderColor: const Color(0xFF3B82F6).withOpacity(0.5),
                    borderStrokeWidth: 2,
                  )
                ],
              ),
            if (_showAssignedWard && widget.ward?.optimizedRoute != null)
              PolylineLayer(
                polylines: [
                  Polyline(points: widget.ward!.optimizedRoute!, strokeWidth: 3, color: const Color(0xFF10B981).withOpacity(0.5)),
                ],
              ),
            if (routePolylines.isNotEmpty)
              PolylineLayer(
                polylines: routePolylines,
              ),
            if (_showFlags && _garbageFlags.isNotEmpty)
              MarkerLayer(
                markers: _garbageFlags.where((f) => f.className != 'Clean' && f.pointType != 'intermediate').map((flag) {
                  final isVeryDirty = flag.className == 'Very_Dirty';
                  final markerColor = (isVeryDirty ? Colors.redAccent : Colors.orangeAccent);
                  return Marker(
                    point: LatLng(flag.lat, flag.lng),
                    width: 30,
                    height: 30,
                    child: GestureDetector(
                      onTap: () => _showTrashPopup(flag),
                      child: Icon(Icons.location_on, color: markerColor, size: 24),
                    ),
                  );
                }).toList(),
              ),
            if (_showAssignedWard && currentVehicle.assignedCheckpoints != null && currentVehicle.assignedCheckpoints!.isNotEmpty)
              MarkerLayer(
                markers: currentVehicle.assignedCheckpoints!.asMap().entries.map((entry) {
                  return Marker(
                    point: entry.value,
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                      ),
                      child: Center(
                        child: Text('${entry.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            if (displayLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: displayLocation,
                    width: 100,
                    height: 100,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: Text(
                            currentVehicle.vehicleNumber,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: const Icon(LucideIcons.truck, color: Colors.white, size: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
