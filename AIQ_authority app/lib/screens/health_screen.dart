import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../mock_data.dart';
import '../services/map_cache_service.dart';
import '../models/vehicle.dart';
import '../models/ward.dart';
import 'active_fleet_screen.dart';
import 'health_database_screen.dart';
import 'alerts_screen.dart';

class HealthFlag {
  final String id;
  final String filename;
  final String imageUrl;
  final String className;
  final String displayClass;
  final double confidence;
  final String timestamp;
  final double lat;
  final double lng;
  final String vehicleNumber;
  final String ward;
  final String? sessionId;
  final String? pointType;
  final String status;

  HealthFlag({
    required this.id,
    required this.filename,
    required this.imageUrl,
    required this.className,
    required this.displayClass,
    required this.confidence,
    required this.timestamp,
    required this.lat,
    required this.lng,
    required this.vehicleNumber,
    required this.ward,
    this.sessionId,
    this.pointType,
    required this.status,
  });

  factory HealthFlag.fromJson(Map<String, dynamic> json, [String? docId]) {
    String rawUrl = json['image_url']?.toString() ?? '';
    String resolvedUrl = '';
    
    if (rawUrl.isNotEmpty) {
      if (rawUrl.startsWith('/')) {
        resolvedUrl = '$activeHealthAiUrl$rawUrl';
      } else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
        try {
          Uri parsed = Uri.parse(rawUrl);
          if (parsed.path.startsWith('/images/')) {
            resolvedUrl = '$activeHealthAiUrl${parsed.path}';
          } else {
            resolvedUrl = rawUrl;
          }
        } catch (_) {
          resolvedUrl = rawUrl;
        }
      }
    }

    return HealthFlag(
      id: docId ?? json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      filename: json['filename'] ?? 'snapshot',
      imageUrl: resolvedUrl,
      className: json['class'] ?? json['road_status']?.toString().replaceAll(' Road', '').replaceAll(' ', '_') ?? 'Unknown',
      displayClass: json['display_class'] ?? json['road_status']?.toString().replaceAll(' Road', '') ?? 'Unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] is Timestamp ? (json['timestamp'] as Timestamp).toDate().toIso8601String() : (json['timestamp']?.toString() ?? DateTime.now().toIso8601String()),
      lat: (json['lat'] as num?)?.toDouble() ?? 42.3601,
      lng: (json['lng'] as num?)?.toDouble() ?? -71.0589,
      vehicleNumber: json['vehicle_number'] ?? 'Unknown',
      ward: json['ward'] ?? 'Unknown',
      sessionId: json['session_id'],
      pointType: json['point_type'],
      status: json['status'] ?? 'Flagged',
    );
  }
}

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();
  Vehicle? _selectedVehicle;
  Ward? _selectedWard;
  
  bool _isDailyView = true;
  
  Map<String, Map<String, dynamic>> _liveTrackingData = {};
  List<Vehicle> _vehicles = [];
  List<Ward> _wards = [];
  
  StreamSubscription? _liveTrackingSub;
  StreamSubscription? _vehiclesSub;
  StreamSubscription? _wardsSub;

  List<HealthFlag> _healthFlags = [];
  Timer? _healthTimer;

  String get _todayDateString => DateTime.now().toIso8601String().split('T')[0];
  StreamSubscription<DocumentSnapshot>? _dailyStatsSub;
  Map<String, dynamic>? _selectedVehicleStats;
  List<LatLng> _selectedVehicleRoute = [];

  StreamSubscription<QuerySnapshot>? _trashSub;
  List<Polyline> _snappedPolylines = [];

  @override
  void initState() {
    super.initState();
    _fetchDataFromFirestore();
    _startLiveTrackingListener();

    _fetchHealthFlagsFromFirestore();
  }

  void _fetchHealthFlagsFromFirestore() {
    _trashSub = FirebaseFirestore.instance.collection('health_spots').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _healthFlags = snapshot.docs
            .map((doc) => HealthFlag.fromJson(doc.data(), doc.id))
            .where((f) => f.status != 'Resolved' && (f.className == 'Pothole_Detected' || f.displayClass == 'Pothole Detected' || f.className == 'Bad_Road' || f.displayClass == 'Bad Road'))
            .toList();
      });
      _recalculatePolylines();
    });
  }

  Future<void> _recalculatePolylines() async {
    Map<String, List<HealthFlag>> sessions = {};
    for (var flag in _healthFlags) {
      if (flag.sessionId != null) {
        sessions.putIfAbsent(flag.sessionId!, () => []).add(flag);
      }
    }

    List<Polyline> newPolylines = [];

    for (var list in sessions.values) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (int i = 0; i < list.length - 1; i++) {
        final start = LatLng(list[i].lat, list[i].lng);
        final end = LatLng(list[i + 1].lat, list[i + 1].lng);
        final status = list[i + 1].className;
        
        Color segmentColor = Colors.greenAccent;
        if (status == 'Pothole_Detected' || status == 'Pothole Detected') segmentColor = Colors.redAccent;
        else if (status == 'Bad_Road' || status == 'Bad Road') segmentColor = Colors.orangeAccent;
        

        try {
          final url = 'http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['routes'] != null && data['routes'].isNotEmpty) {
              final coords = data['routes'][0]['geometry']['coordinates'] as List;
              final snappedPoints = coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
              newPolylines.add(Polyline(points: snappedPoints, color: segmentColor, strokeWidth: 6.0));
              continue;
            }
          }
        } catch (_) {}
        // Fallback to straight line
        newPolylines.add(Polyline(points: [start, end], color: segmentColor, strokeWidth: 6.0));
      }
    }

    if (mounted) {
      setState(() {
        _snappedPolylines = newPolylines;
      });
    }
  }

  void _fetchDataFromFirestore() {
    _vehiclesSub = FirebaseFirestore.instance.collection('vehicles').snapshots().listen((snapshot) {
      final vehicles = snapshot.docs.map((doc) => Vehicle.fromJson(doc.id, doc.data())).toList();
      if (!mounted) return;
      setState(() {
        for (var newVehicle in vehicles) {
          final liveData = _liveTrackingData[newVehicle.vehicleNumber] ?? _liveTrackingData[newVehicle.id];
          if (liveData != null) {
            if (liveData['lat'] != null && liveData['lng'] != null) {
              newVehicle.currentLocation = LatLng(liveData['lat'], liveData['lng']);
            }
            newVehicle.isActive = liveData['isActive'] ?? false;
            final Timestamp? ts = liveData['timestamp'] as Timestamp?;
            if (ts != null) newVehicle.lastHeartbeat = ts.toDate();
          } else {
            final existingIndex = _vehicles.indexWhere((v) => v.id == newVehicle.id);
            if (existingIndex != -1) {
              newVehicle.currentLocation = _vehicles[existingIndex].currentLocation;
              newVehicle.isActive = _vehicles[existingIndex].isActive;
              newVehicle.lastHeartbeat = _vehicles[existingIndex].lastHeartbeat;
            }
          }
        }
        _vehicles = vehicles;
        if (_selectedVehicle != null) {
          final index = _vehicles.indexWhere((v) => v.id == _selectedVehicle!.id);
          if (index != -1) _selectedVehicle = _vehicles[index];
        }
      });
    });

    _wardsSub = FirebaseFirestore.instance.collection('wards').snapshots().listen((snapshot) {
      final wards = snapshot.docs.map((doc) => Ward.fromJson(doc.id, doc.data())).toList();
      if (!mounted) return;
      setState(() {
        _wards = wards;
        if (_selectedWard != null) {
          final index = _wards.indexWhere((w) => w.id == _selectedWard!.id);
          if (index != -1) _selectedWard = _wards[index];
        }
      });
    });
  }

  void _startLiveTrackingListener() {
    _liveTrackingSub = FirebaseFirestore.instance.collection('live_tracking').snapshots().listen((snapshot) {
      bool changed = false;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        _liveTrackingData[doc.id] = data;
        
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        final isActive = data['isActive'] as bool? ?? false;
        final Timestamp? timestamp = data['timestamp'] as Timestamp?;

        if (lat != null && lng != null && mounted) {
          final index = _vehicles.indexWhere((v) => v.vehicleNumber == doc.id || v.id == doc.id);
          if (index != -1) {
            _vehicles[index].currentLocation = LatLng(lat, lng);
            _vehicles[index].isActive = isActive;
            if (timestamp != null) {
              _vehicles[index].lastHeartbeat = timestamp.toDate();
            }
            changed = true;
          }
        }
      }
      if (changed && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _liveTrackingSub?.cancel();
    _vehiclesSub?.cancel();
    _wardsSub?.cancel();
    _dailyStatsSub?.cancel();
    _trashSub?.cancel();
    super.dispose();
  }

  Color _getCleanlinessColor(String level) {
    switch (level) {
      case "Clean":
        return Colors.blue;
      case "Moderate":
        return Colors.orange;
      case "Dirty":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  int get _spotsCleared => _healthFlags.where((f) => f.className == 'Good_Condition' || f.displayClass == 'Good Condition').length;
  int get _spotsFlagged => _healthFlags.where((f) => f.className == 'Slightly_Dirty' || f.className == 'Very_Dirty').length;
  int get _totalSpots => _healthFlags.length;
  int get _overallCleanliness => _totalSpots > 0 ? ((_spotsCleared / _totalSpots) * 100).toInt() : 100;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF111827),
        selectedItemColor: Colors.white,
        unselectedItemColor: const Color(0xFF94A3B8),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.database), label: 'Database'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.truck), label: 'Active Fleet'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.bellRing), label: 'Alerts'),
        ],
        onTap: (index) {
          if (index == 0) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const HealthDatabaseScreen()));
          } else if (index == 1) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ActiveFleetScreen()));
          } else if (index == 2) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const AlertsListScreen()));
          }
        },
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Heading
            Row(
              children: [
                const Icon(LucideIcons.sparkles, color: Colors.blueAccent, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Road Health Monitor',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 2. Desktop or Mobile Layout
            if (isDesktop) _buildDesktopLayout() else _buildMobileLayout(),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Row: Stat Cards
        Row(
          children: [
            Expanded(child: _buildStatCard('Overall Health', '$_overallCleanliness%', LucideIcons.checkCircle, Colors.greenAccent)),
            const SizedBox(width: 16),
            Expanded(child: _buildStatCard('Spots Flagged', '$_spotsFlagged', LucideIcons.flag, Colors.redAccent)),
            const SizedBox(width: 16),
            Expanded(child: _buildStatCard('Spots Cleared', '$_spotsCleared', LucideIcons.checkSquare, Colors.blueAccent)),
          ],
        ),
        const SizedBox(height: 24),
        // Bottom Row: Map and Graphs
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Map
            Expanded(
              flex: 5,
              child: SizedBox(
                height: 624,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildMap(),
                ),
              ),
            ),
            const SizedBox(width: 24),
            // Right: Graphs
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  _buildLineGraphCard(),
                  const SizedBox(height: 24),
                  _buildPieChartCard(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard('Cleanliness', '$_overallCleanliness%', LucideIcons.checkCircle, Colors.greenAccent)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('Flagged', '$_spotsFlagged', LucideIcons.flag, Colors.redAccent)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildStatCard('Cleared', '$_spotsCleared', LucideIcons.checkSquare, Colors.blueAccent)),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 400,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _buildMap(),
          ),
        ),
        const SizedBox(height: 24),
        _buildLineGraphCard(),
        const SizedBox(height: 24),
        _buildPieChartCard(),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChartCard() {
    double total = _healthFlags.isEmpty ? 1 : _healthFlags.length.toDouble();
    double cleanVal = _healthFlags.where((f) => f.className == 'Good_Condition' || f.displayClass == 'Good Condition').length.toDouble();
    double slightVal = _healthFlags.where((f) => f.className == 'Slightly_Dirty').length.toDouble();
    double dirtyVal = _healthFlags.where((f) => f.className == 'Pothole_Detected' || f.displayClass == 'Pothole Detected').length.toDouble();

    // Avoid all 0 values for PieChart
    if (cleanVal == 0 && slightVal == 0 && dirtyVal == 0) {
      cleanVal = 1; 
      total = 1;
    }

    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 30,
                sections: [
                  if (cleanVal > 0)
                    PieChartSectionData(
                      color: Colors.green,
                      value: cleanVal,
                      title: '${((cleanVal / total) * 100).toInt()}%',
                      radius: 40,
                      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  if (slightVal > 0)
                    PieChartSectionData(
                      color: Colors.orange,
                      value: slightVal,
                      title: '${((slightVal / total) * 100).toInt()}%',
                      radius: 40,
                      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  if (dirtyVal > 0)
                    PieChartSectionData(
                      color: Colors.red,
                      value: dirtyVal,
                      title: '${((dirtyVal / total) * 100).toInt()}%',
                      radius: 40,
                      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegendItem(Colors.green, 'Clean (${cleanVal.toInt()})'),
              const SizedBox(height: 8),
              _buildLegendItem(Colors.orange, 'Slightly Dirty (${slightVal.toInt()})'),
              const SizedBox(height: 8),
              _buildLegendItem(Colors.red, 'Very Dirty (${dirtyVal.toInt()})'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _buildLineGraphCard() {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cleanliness Trend Over Time',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text('${value.toInt()}%', style: const TextStyle(color: Colors.white54, fontSize: 10));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        if (value.toInt() >= 0 && value.toInt() < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(days[value.toInt()], style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 60),
                      FlSpot(1, 65),
                      FlSpot(2, 72),
                      FlSpot(3, 80),
                      FlSpot(4, 75),
                      FlSpot(5, 82),
                      FlSpot(6, 85),
                    ],
                    isCurved: true,
                    color: Colors.blueAccent,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blueAccent.withOpacity(0.2),
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

  void _centerOnCurrentLocation() {
    if (_vehicles.isNotEmpty && _vehicles.first.currentLocation != null) {
      _mapController.move(_vehicles.first.currentLocation!, 15.0);
    }
  }

  void _showTrashPopup(HealthFlag flag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          '${flag.displayClass} - ${flag.ward}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 600,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side: Image
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(flag.imageUrl, headers: const {"ngrok-skip-browser-warning": "true"},
                    height: 250, 
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Right side: Map & Details
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 180,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(flag.lat, flag.lng),
                            initialZoom: 16.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.street_aiq',
                              tileProvider: kIsWeb ? null : CachedTileProvider(store: MapCacheService.store),
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(flag.lat, flag.lng),
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.location_on, color: Colors.redAccent, size: 40),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Confidence: ${(flag.confidence * 100).toStringAsFixed(1)}%",
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Vehicle: ${flag.vehicleNumber}",
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              // Handle Report logic
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted!')));
            },
            child: const Text('Report', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.directions_outlined, size: 18),
            label: const Text('Start'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
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
    // --- Compute Polylines and Markers from _healthFlags ---
    Map<String, List<HealthFlag>> sessions = {};
    for (var flag in _healthFlags) {
      if (flag.sessionId != null) {
        sessions.putIfAbsent(flag.sessionId!, () => []).add(flag);
      }
    }

    List<Polyline> routePolylines = [];
    List<Marker> customTrashMarkers = [];

    // Process sessions into polylines for flags without a live route
    if (_selectedVehicleRoute.isEmpty) {
      routePolylines.addAll(_snappedPolylines);
    } else {
      routePolylines.add(Polyline(
        points: _selectedVehicleRoute,
        color: Colors.blueAccent,
        strokeWidth: 6.0,
      ));
    }

    // Process markers
    Map<String, int> locationCounts = {};
    for (var flag in _healthFlags) {
      String locKey = '${flag.lat.toStringAsFixed(5)}_${flag.lng.toStringAsFixed(5)}';
      int count = locationCounts[locKey] ?? 0;
      locationCounts[locKey] = count + 1;

      double offsetLat = flag.lat;
      double offsetLng = flag.lng;
      if (count > 0) {
        offsetLng += (count * 0.0002);
      }

      if (flag.pointType == 'start') {
        customTrashMarkers.add(Marker(
          point: LatLng(offsetLat, offsetLng),
          width: 30, height: 30,
          alignment: Alignment.center,
          child: const Icon(Icons.play_circle_fill, color: Colors.greenAccent, size: 28),
        ));
      } else if (flag.pointType == 'end') {
        customTrashMarkers.add(Marker(
          point: LatLng(offsetLat, offsetLng),
          width: 30, height: 30,
          alignment: Alignment.center,
          child: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 28),
        ));
      }

      if (flag.className != 'Clean' && flag.pointType != 'intermediate') {
        Color markerColor = (flag.className == 'Pothole_Detected' || flag.displayClass == 'Pothole Detected') ? Colors.redAccent : Colors.orangeAccent;
        
        customTrashMarkers.add(Marker(
          point: LatLng(offsetLat, offsetLng),
          width: 40, height: 40,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () => _showTrashPopup(flag),
            child: Icon(
              Icons.tour_rounded,
              color: markerColor,
              size: 32,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))],
            ),
          ),
        ));
      }
    }
    // ----------------------------------------------------

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: mapCenter,
            initialZoom: mapZoom,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.street_aiq',
              tileProvider: kIsWeb ? null : CachedTileProvider(store: MapCacheService.store),
            ),
            if (_selectedWard != null)
              PolygonLayer(
                polygons: [
                  Polygon<Object>(
                    points: _selectedWard!.boundary,
                    color: const Color(0xFF3B82F6).withOpacity(0.2),
                    borderColor: const Color(0xFF3B82F6),
                    borderStrokeWidth: 2,
                  )
                ],
              ),
            if (_selectedWard?.optimizedRoute != null)
              PolylineLayer(
                polylines: [
                  Polyline(points: _selectedWard!.optimizedRoute!, strokeWidth: 5, color: const Color(0xFF10B981)),
                ],
              ),
            MarkerLayer(
              markers: _vehicles.where((v) => v.currentLocation != null).map((vehicle) {
                  return Marker(
                    point: vehicle.currentLocation!, width: 40, height: 40,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedVehicle = vehicle;
                          _selectedWard = _wards.where((w) => w.name == vehicle.assignedWard).firstOrNull;
                          _selectedVehicleStats = null;
                          _selectedVehicleRoute = [];
                        });
                        
                        _dailyStatsSub?.cancel();
                        _dailyStatsSub = FirebaseFirestore.instance.collection('vehicles').doc(vehicle.vehicleNumber).collection('daily_stats').doc(_todayDateString).snapshots().listen((doc) {
                          if (doc.exists && doc.data() != null) {
                            if (mounted) {
                              setState(() {
                                _selectedVehicleStats = doc.data()!;
                                if (doc.data()!['route'] != null) {
                                  final List<dynamic> rawRoute = doc.data()!['route'];
                                  _selectedVehicleRoute = rawRoute.map((p) => LatLng(p['lat'], p['lng'])).toList();
                                }
                              });
                            }
                          }
                        });

                        if (_selectedWard != null && _selectedWard!.boundary.isNotEmpty) {
                          _mapController.move(_selectedWard!.boundary.first, 15.0);
                        } else if (vehicle.assignedRoute != null && vehicle.assignedRoute!.isNotEmpty) {
                          _mapController.move(vehicle.assignedRoute!.first, 15.0);
                        } else if (vehicle.currentLocation != null) {
                          _mapController.move(vehicle.currentLocation!, 15.0);
                        }
                      },
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF334155))),
                            child: Text(vehicle.vehicleNumber.length > 4 ? vehicle.vehicleNumber.substring(0, 4) : vehicle.vehicleNumber, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: vehicle.isActive ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                              shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(LucideIcons.truck, color: Colors.white, size: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
            ),
            if (routePolylines.isNotEmpty)
              PolylineLayer(
                polylines: routePolylines,
              ),
            if (customTrashMarkers.isNotEmpty)
              MarkerLayer(
                markers: customTrashMarkers,
              ),
          ],
        ),
        if (_selectedVehicle != null)
          Positioned(
            top: 16,
            right: 16,
            child: _buildVehicleDetailsCard(_selectedVehicle!),
          ),
        // Current Location Button
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'clean_location',
            onPressed: _centerOnCurrentLocation,
            mini: true,
            backgroundColor: const Color(0xFF1E293B),
            child: const Icon(Icons.my_location_rounded, color: Colors.blueAccent),
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleDetailsCard(Vehicle vehicle) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3B82F6), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Vehicle Details',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _selectedVehicle = null;
                    _selectedVehicleStats = null;
                    _selectedVehicleRoute = [];
                  });
                  _dailyStatsSub?.cancel();
                },
              )
            ],
          ),
          const Divider(color: Colors.white24),
          Text('Vehicle: ${vehicle.vehicleNumber}', style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 8),
          
          if (_selectedVehicleStats != null) ...[
            _buildStatRow(Icons.route, 'Distance:', '${(_selectedVehicleStats!['distance_km'] ?? 0.0).toStringAsFixed(2)} km'),
            const SizedBox(height: 4),
            _buildStatRow(Icons.camera_alt, 'Captures:', '${_selectedVehicleStats!['images_captured'] ?? 0}'),
            const SizedBox(height: 4),
            _buildStatRow(Icons.flag, 'Flags:', '${_selectedVehicleStats!['images_flagged'] ?? 0}', color: Colors.redAccent),
          ] else ...[
            const Text('No data for today yet.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]
        ],
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value, {Color? color}) {
    return Row(
      children: [
        Icon(icon, color: color ?? Colors.white70, size: 14),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const Spacer(),
        Text(value, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  Widget _buildNotificationCenter({bool isDrawer = false}) {
    return Container(
      decoration: BoxDecoration(
        color: isDrawer ? Colors.transparent : const Color(0xFF111827),
        borderRadius: isDrawer ? BorderRadius.zero : BorderRadius.circular(16),
        border: isDrawer ? null : Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(LucideIcons.bellRing, color: Color(0xFFEF4444), size: 20),
                SizedBox(width: 12),
                Text(
                  'Real-Time Alerts',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: _healthFlags.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text("No AI flags detected yet.", style: TextStyle(color: Colors.white54)),
                      )
                    ]
                  : _healthFlags.take(5).map((flag) {
                      Color color = Colors.grey;
                      if (flag.className == 'Clean') color = Colors.greenAccent;
                      if (flag.className == 'Slightly_Dirty') color = Colors.orangeAccent;
                      if (flag.className == 'Pothole_Detected' || flag.displayClass == 'Pothole Detected') color = Colors.redAccent;
                      else if (flag.className == 'Bad_Road' || flag.displayClass == 'Bad Road') color = Colors.orangeAccent;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildAlertItem(flag, color),
                      );
                    }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertItem(HealthFlag flag, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(flag.imageUrl, headers: const {"ngrok-skip-browser-warning": "true"}, 
              width: 48, 
              height: 48, 
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 48, height: 48, color: const Color(0xFF334155),
                child: const Icon(LucideIcons.imageOff, color: Colors.white54, size: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(flag.displayClass, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(flag.timestamp, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Confidence: ${(flag.confidence * 100).toStringAsFixed(1)}%', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${flag.vehicleNumber} • ${flag.ward}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.directions_outlined, color: Colors.blueAccent, size: 20),
            onPressed: () => _showTrashPopup(flag),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

