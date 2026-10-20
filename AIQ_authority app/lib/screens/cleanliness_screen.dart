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
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../mock_data.dart';
import '../services/map_cache_service.dart';
import '../models/vehicle.dart';
import '../models/ward.dart';
import '../models/zone.dart';
import 'active_fleet_screen.dart';
import 'database_screen.dart';
import 'alerts_screen.dart';

import '../models/garbage_flag.dart';
import '../widgets/trash_pinpoint_marker.dart';
import '../services/ward_zone_service.dart';
import '../services/trash_spots_service.dart';
import '../services/role_service.dart';

class CleanlinessScreen extends StatefulWidget {
  const CleanlinessScreen({super.key});

  @override
  State<CleanlinessScreen> createState() => _CleanlinessScreenState();
}

class _CleanlinessScreenState extends State<CleanlinessScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();
  Vehicle? _selectedVehicle;
  
  List<Vehicle> _vehicles = [];
  List<Ward> _wards = [];
  List<Zone> _zones = [];
  
  String _selectedZone = 'All Zones';
  String _selectedWard = 'All Wards';
  DateTime _selectedDate = DateTime.now();
  bool _isDailyView = true;
  
  StreamSubscription? _zonesSub;
  Map<String, Map<String, dynamic>> _liveTrackingData = {};
  
  StreamSubscription? _liveTrackingSub;
  StreamSubscription? _vehiclesSub;
  StreamSubscription? _wardsSub;

  List<GarbageFlag> _garbageFlags = [];
  List<GarbageFlag> _allRoadFlags = [];
  Timer? _garbageTimer;

  String get _todayDateString => DateTime.now().toIso8601String().split('T')[0];
  StreamSubscription<DocumentSnapshot>? _dailyStatsSub;
  Map<String, dynamic>? _selectedVehicleStats;
  List<LatLng> _selectedVehicleRoute = [];

  StreamSubscription<QuerySnapshot>? _trashSub;
  List<Polyline> _snappedPolylines = [];
  bool _initialMapCentered = false;

  @override
  void initState() {
    super.initState();
    WardZoneService.instance.init();
    WardZoneService.instance.notifier.addListener(_onWardZoneUpdate);
    _fetchDataFromFirestore();
    _startLiveTrackingListener();

    _fetchGarbageFlagsFromFirestore();
  }

  void _onWardZoneUpdate() {
    if (mounted) setState(() {});
  }

  void _fetchGarbageFlagsFromFirestore() {
    TrashSpotsService.instance.flagsNotifier.addListener(_onTrashSpotsUpdated);
    _updateGarbageFlags();

    _trashSub = FirebaseFirestore.instance.collection('trash_spots').snapshots().listen((snapshot) {
      if (!mounted) return;
      _updateGarbageFlags();
    });
  }

  void _onTrashSpotsUpdated() {
    if (mounted) _updateGarbageFlags();
  }

  void _updateGarbageFlags() {
    final active = TrashSpotsService.instance.activeFlags;
    final allRoad = TrashSpotsService.instance.allFlags;
    setState(() {
      _garbageFlags = active;
      _allRoadFlags = allRoad;
    });
    _recalculatePolylines();

    if (!_initialMapCentered && _garbageFlags.isNotEmpty) {
      _initialMapCentered = true;
      try {
        _mapController.move(LatLng(_garbageFlags.first.lat, _garbageFlags.first.lng), 14.0);
      } catch (_) {}
    }
  }

  Future<void> _recalculatePolylines() async {
    final sourceFlags = _allRoadFlags.isNotEmpty ? _allRoadFlags : _garbageFlags;
    Map<String, List<GarbageFlag>> sessions = {};
    for (var flag in sourceFlags) {
      final key = flag.sessionId ?? (flag.vehicleNumber.isNotEmpty ? flag.vehicleNumber : 'default_track');
      sessions.putIfAbsent(key, () => []).add(flag);
    }

    List<Polyline> instantPolylines = [];
    List<Map<String, dynamic>> segmentJobs = [];

    for (var list in sessions.values) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (int i = 0; i < list.length - 1; i++) {
        final start = LatLng(list[i].lat, list[i].lng);
        final end = LatLng(list[i + 1].lat, list[i + 1].lng);
        final dist = const Distance().as(LengthUnit.Meter, start, end);
        
        // Never connect distant trash flags (> 80m) - avoids cross-city diagonal lines
        if (dist > 80.0) continue;

        final flag = list[i + 1];
        final status = (flag.displayClass.isNotEmpty ? flag.displayClass : flag.className);
        final sLower = status.toLowerCase();
        final isNoTrash = sLower.contains('no trash') || sLower.contains('no_trash') || sLower.contains('clean');
        
        // Accurate 3-way Road Cleanliness Color Mapping
        Color segmentColor = const Color(0xFF00E676); // Vibrant Green (Clean Road / No Trash Detected)
        if (flag.className == 'Very_Dirty' || flag.displayClass == 'Very Dirty' || flag.displayClass == 'Very Dirty Road' || status.contains('Very Dirty')) {
          segmentColor = const Color(0xFFFF1744); // Vibrant Red (Very Dirty Road)
        } else if (!isNoTrash && (flag.isTrashDetected || flag.className == 'Trash_Detected' || status.contains('Trash') || flag.trashCount > 0)) {
          segmentColor = const Color(0xFFFF9100); // Vibrant Amber / Orange (Trash Detected)
        }

        if (dist <= 25.0) {
          instantPolylines.add(Polyline(
            points: [start, end],
            color: segmentColor,
            strokeWidth: 6.0,
            borderStrokeWidth: 1.0,
            borderColor: Colors.black12,
          ));
        }

        segmentJobs.add({
          'start': start,
          'end': end,
          'color': segmentColor,
          'distance': dist,
        });
      }
    }

    // Immediately show the road colored polylines with zero latency
    if (mounted) {
      setState(() {
        _snappedPolylines = instantPolylines;
      });
    }

    // Asynchronously enhance segments with OSRM road snapping in parallel
    if (segmentJobs.isEmpty) return;

    try {
      final snappedResults = await Future.wait(segmentJobs.map((job) async {
        final start = job['start'] as LatLng;
        final end = job['end'] as LatLng;
        final color = job['color'] as Color;
        final dist = (job['distance'] as num?)?.toDouble() ?? 50.0;
        try {
          final url = 'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['routes'] != null && data['routes'].isNotEmpty) {
              final coords = data['routes'][0]['geometry']['coordinates'] as List;
              final snappedPoints = coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
              if (snappedPoints.length >= 2) {
                return Polyline(
                  points: snappedPoints,
                  color: color,
                  strokeWidth: 6.0,
                  borderStrokeWidth: 1.0,
                  borderColor: Colors.black12,
                );
              }
            }
          }
        } catch (_) {}
        // Fallback: only if points are close together
        if (dist <= 25.0) {
          return Polyline(
            points: [start, end],
            color: color,
            strokeWidth: 6.0,
            borderStrokeWidth: 1.0,
            borderColor: Colors.black12,
          );
        }
        return Polyline(points: const [], color: Colors.transparent);
      }));

      if (mounted) {
        setState(() {
          _snappedPolylines = snappedResults.where((p) => p.points.isNotEmpty).toList();
        });
      }
    } catch (_) {}
  }

  void _fetchDataFromFirestore() {
    _vehiclesSub = FirebaseFirestore.instance.collection('vehicles').snapshots().listen((snapshot) {
      final vehicles = snapshot.docs.map((doc) => Vehicle.fromJson(doc.id, doc.data())).toList();
      if (!mounted) return;
      setState(() {
        for (var newVehicle in vehicles) {
          Map<String, dynamic>? liveData = _liveTrackingData[newVehicle.vehicleNumber] ?? _liveTrackingData[newVehicle.id];
          if (liveData == null) {
            final cleanV = newVehicle.vehicleNumber.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
            for (var entry in _liveTrackingData.entries) {
              if (entry.key.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '') == cleanV) {
                liveData = entry.value;
                break;
              }
            }
          }
          if (liveData != null) {
            final lat = (liveData['lat'] as num?)?.toDouble();
            final lng = (liveData['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              newVehicle.currentLocation = LatLng(lat, lng);
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
        // Keep selected ward if it still exists
      });
    });

    _zonesSub = FirebaseFirestore.instance.collection('zones').snapshots().listen((snapshot) {
      final zones = snapshot.docs.map((doc) => Zone.fromJson(doc.id, doc.data())).toList();
      if (!mounted) return;
      setState(() => _zones = zones);
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
          final cleanDocId = doc.id.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
          final index = _vehicles.indexWhere((v) {
            if (v.vehicleNumber == doc.id || v.id == doc.id) return true;
            final cleanV = v.vehicleNumber.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
            return cleanV == cleanDocId || v.id.toLowerCase() == cleanDocId;
          });
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
    WardZoneService.instance.notifier.removeListener(_onWardZoneUpdate);
    TrashSpotsService.instance.flagsNotifier.removeListener(_onTrashSpotsUpdated);
    _zonesSub?.cancel();
    _garbageTimer?.cancel();
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

  int get _spotsCleared => _garbageFlags.where((f) => f.className == 'Clean').length;
  int get _spotsFlagged => _garbageFlags.where((f) => f.className == 'Slightly_Dirty' || f.className == 'Very_Dirty').length;
  int get _totalSpots => _garbageFlags.length;
  int get _overallCleanliness => _totalSpots > 0 ? ((_spotsCleared / _totalSpots) * 100).toInt() : 100;

  bool _rayCastIntersect(LatLng point, LatLng vertA, LatLng vertB) {
    double aY = vertA.latitude, bY = vertB.latitude;
    double aX = vertA.longitude, bX = vertB.longitude;
    double pY = point.latitude, pX = point.longitude;

    if ((aY > pY && bY > pY) || (aY < pY && bY < pY) || (aX < pX && bX < pX)) {
      return false; 
    }
    if (aY == bY) return false; 
    
    double m = (aX - bX) / (aY - bY); 
    double x = aX + m * (pY - aY); 
    return x > pX;
  }

  bool _isWardInZone(Ward ward, Zone zone) {
    if (ward.boundary.isEmpty || zone.boundary.isEmpty) return false;
    double cLat = 0, cLng = 0;
    for(var p in ward.boundary) { cLat += p.latitude; cLng += p.longitude; }
    LatLng centroid = LatLng(cLat / ward.boundary.length, cLng / ward.boundary.length);

    int intersectCount = 0;
    for (int j = 0; j < zone.boundary.length - 1; j++) {
      if (_rayCastIntersect(centroid, zone.boundary[j], zone.boundary[j + 1])) {
        intersectCount++;
      }
    }
    if (_rayCastIntersect(centroid, zone.boundary.last, zone.boundary.first)) {
      intersectCount++;
    }
    return (intersectCount % 2) == 1;
  }
  
  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF9FAFB),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF0F5132),
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.database), label: 'Database'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.truck), label: 'Active Fleet'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.bellRing), label: 'Alerts'),
        ],
        onTap: (index) {
          if (index == 0) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const DatabaseScreen()));
          } else if (index == 1) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ActiveFleetScreen()));
          } else if (index == 2) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const AlertsListScreen()));
          }
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(isDesktop ? 24 : 12, isDesktop ? 24 : 12, isDesktop ? 24 : 12, isDesktop ? 16 : 8),
            child: _buildFilterBar(isDesktop),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(isDesktop ? 24 : 12, 0, isDesktop ? 24 : 12, isDesktop ? 24 : 12),
              child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
            ),
          ),
        ],
      ),
    );
  }

  void _updateMapForSelection() {
    List<LatLng> points = [];
    var filteredFlags = _garbageFlags;

    if (_selectedWard != 'All Wards') {
      filteredFlags = filteredFlags.where((f) => f.ward == _selectedWard).toList();
      try {
        final ward = _wards.firstWhere((w) => w.name == _selectedWard);
        if (ward.boundary.isNotEmpty) points.addAll(ward.boundary);
      } catch (_) {}
    } else if (_selectedZone != 'All Zones') {
      try {
        final zone = _zones.firstWhere((z) => z.name == _selectedZone);
        if (zone.boundary.isNotEmpty) points.addAll(zone.boundary);
      } catch (_) {}
    }

    for (var f in filteredFlags) {
      points.add(LatLng(f.lat, f.lng));
    }

    if (points.isNotEmpty) {
      double minLat = points.first.latitude, maxLat = points.first.latitude;
      double minLng = points.first.longitude, maxLng = points.first.longitude;
      for (var p in points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      _mapController.move(LatLng(centerLat, centerLng), 13.5);
    }
  }

  Widget _buildFilterBar(bool isDesktop) {
    final userWard = RoleService.currentUserWard;
    final userZone = RoleService.currentUserZone;

    List<String> availableWards = [];
    if (_selectedZone != 'All Zones') {
      final sZone = _zones.firstWhere((z) => z.name == _selectedZone, orElse: () => Zone(id: '', name: '', boundary: []));
      if (sZone.boundary.isNotEmpty) {
        availableWards = _wards
            .where((w) => w.boundary.isNotEmpty && _isWardInZone(w, sZone))
            .map((w) => w.name)
            .toList();
      }
    } else {
      availableWards = _wards.map((w) => w.name).toList();
    }
    
    List<String> wards = ['All Wards', ...availableWards.toSet()];
    List<String> zones = ['All Zones', ..._zones.map((z) => z.name).toSet()];

    if (userWard != null && userWard.trim().isNotEmpty && userWard != 'All Wards') {
      wards = [userWard];
      if (_selectedWard != userWard) {
        _selectedWard = userWard;
      }
    }
    if (userZone != null && userZone.trim().isNotEmpty && userZone != 'All Zones') {
      zones = [userZone];
      if (_selectedZone != userZone) {
        _selectedZone = userZone;
      }
    }

    final filterContent = Wrap(
      spacing: 16,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildFunctionalDropdown('Zone', _selectedZone, zones, (val) {
          setState(() => _selectedZone = val);
          _updateMapForSelection();
        }),
        _buildFunctionalDropdown('Ward', _selectedWard, wards, (val) {
          setState(() => _selectedWard = val);
          _updateMapForSelection();
        }),
        _buildFunctionalDatePicker(),
        _buildFunctionalToggle(),
        if (!isDesktop) // add the button to wrap on mobile
          ElevatedButton.icon(
            onPressed: () => _showAISettingsDialog(),
            icon: const Icon(LucideIcons.settings, size: 16, color: Colors.white),
            label: const Text('AI Settings', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F5132),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
      ],
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: filterContent),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () => _showAISettingsDialog(),
            icon: const Icon(LucideIcons.settings, size: 16, color: Colors.white),
            label: const Text('AI Settings', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F5132),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      );
    }
    
    return filterContent;
  }

  Widget _buildFunctionalDropdown(String label, String value, List<String> items, Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
              dropdownColor: Colors.white,
              onChanged: (String? newValue) {
                if (newValue != null) onChanged(newValue);
              },
              items: items.map<DropdownMenuItem<String>>((String val) {
                return DropdownMenuItem<String>(
                  value: val,
                  child: Text(val),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFunctionalDatePicker() {
    final dateStr = "${_selectedDate.day} ${_monthString(_selectedDate.month)} ${_selectedDate.year}";
    return GestureDetector(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2101),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF0F5132),
                  onPrimary: Colors.white,
                  onSurface: Colors.black,
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null && picked != _selectedDate) {
          setState(() {
            _selectedDate = picked;
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 18),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.calendar, size: 16, color: Colors.black54),
            const SizedBox(width: 8),
            Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
            const SizedBox(width: 8),
            const Icon(LucideIcons.refreshCw, size: 16, color: Colors.black54),
          ],
        ),
      ),
    );
  }

  String _monthString(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Widget _buildFunctionalToggle() {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isDailyView = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _isDailyView ? const Color(0xFF0F5132) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Daily', style: TextStyle(color: _isDailyView ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _isDailyView = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: !_isDailyView ? const Color(0xFF0F5132) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Monthly', style: TextStyle(color: !_isDailyView ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCards(bool isDesktop) {
    final overallCard = _buildOverallCleanlinessCard(!isDesktop);
    final spotsDetectedCard = _buildGarbageSpotsDetectedCard(!isDesktop);
    final spotsClearedCard = _buildSpotsClearedCard(!isDesktop);
    final officerResponseCard = _buildOfficerResponseCard(!isDesktop);

    if (isDesktop) {
      return Row(
        children: [
          Expanded(child: overallCard),
          const SizedBox(width: 16),
          Expanded(child: spotsDetectedCard),
          const SizedBox(width: 16),
          Expanded(child: spotsClearedCard),
          const SizedBox(width: 16),
          Expanded(child: officerResponseCard),
        ],
      );
    } else {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: overallCard),
              const SizedBox(width: 10),
              Expanded(child: spotsDetectedCard),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: spotsClearedCard),
              const SizedBox(width: 10),
              Expanded(child: officerResponseCard),
            ],
          ),
        ],
      );
    }
  }

  
  List<GarbageFlag> get _filteredGarbageFlags {
    return _garbageFlags.where((f) {
      if (!RoleService.isSpotAllowed(f.lat, f.lng, f.zone, f.ward, 'Street Cleanliness AI')) {
        return false;
      }
      if (_selectedZone != 'All Zones' &&
          !WardZoneService.instance.matchesZone(lat: f.lat, lng: f.lng, docZone: f.zone, targetZone: _selectedZone)) {
        return false;
      }
      if (_selectedWard != 'All Wards' &&
          !WardZoneService.instance.matchesWard(lat: f.lat, lng: f.lng, docWard: f.ward, targetWard: _selectedWard)) {
        return false;
      }
      return true;
    }).toList();
  }

  Widget _buildOverallCleanlinessCard(bool isMobile) {
    final list = _filteredGarbageFlags;
    int total = list.length;
    int cleared = list.where((f) => f.status == 'Resolved' || f.status == 'Deflagged').length;
    int cleanliness = total == 0 ? 100 : ((cleared / total) * 100).toInt();
    
    return _buildBaseCard(
      isMobile: isMobile,
      child: Row(
        children: [
          Container(
            width: isMobile ? 36 : 48,
            height: isMobile ? 36 : 48,
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.eco, color: Colors.green, size: isMobile ? 20 : 28),
          ),
          SizedBox(width: isMobile ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('OVERALL CLEANLINESS', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 9 : 11, fontWeight: FontWeight.bold, letterSpacing: 0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('$cleanliness%', style: TextStyle(color: Colors.black87, fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  
  Widget _buildGarbageSpotsDetectedCard(bool isMobile) {
    final list = _filteredGarbageFlags;
    int total = list.where((f) => f.isTrashDetected).length;
    return _buildBaseCard(
      isMobile: isMobile,
      child: Row(
        children: [
          Container(
            width: isMobile ? 36 : 48,
            height: isMobile ? 36 : 48,
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.delete_outline, color: Colors.redAccent, size: isMobile ? 20 : 28),
          ),
          SizedBox(width: isMobile ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SPOTS DETECTED', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 9 : 11, fontWeight: FontWeight.bold, letterSpacing: 0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('$total', style: TextStyle(color: Colors.black87, fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  
  Widget _buildSpotsClearedCard(bool isMobile) {
    final list = _filteredGarbageFlags;
    int total = list.length;
    int cleared = list.where((f) => f.status == 'Resolved' || f.status == 'Deflagged').length;

    return _buildBaseCard(
      isMobile: isMobile,
      child: Row(
        children: [
          Container(
            width: isMobile ? 36 : 48,
            height: isMobile ? 36 : 48,
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.check_circle_outline, color: Colors.blueAccent, size: isMobile ? 20 : 28),
          ),
          SizedBox(width: isMobile ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SPOTS CLEARED', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 9 : 11, fontWeight: FontWeight.bold, letterSpacing: 0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$cleared', style: TextStyle(color: Colors.blueAccent, fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold)),
                    Text(' / $total', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 13 : 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfficerResponseCard(bool isMobile) {
    final list = _filteredGarbageFlags;
    int total = list.length;
    int responded = list.where((f) => f.status != 'Pending').length;

    return _buildBaseCard(
      isMobile: isMobile,
      child: Row(
        children: [
          Container(
            width: isMobile ? 36 : 48,
            height: isMobile ? 36 : 48,
            decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(10)),
            child: Icon(LucideIcons.userCircle, color: Colors.purpleAccent, size: isMobile ? 20 : 28),
          ),
          SizedBox(width: isMobile ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('OFFICER RESPONSE', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 9 : 11, fontWeight: FontWeight.bold, letterSpacing: 0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$responded', style: TextStyle(color: Colors.purpleAccent, fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold)),
                    Text(' / $total', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 13 : 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBaseCard({required Widget child, bool isMobile = false}) {
    return Container(
      height: isMobile ? 85 : 120,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 24, vertical: isMobile ? 10 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        _buildTopCards(true),
        const SizedBox(height: 24),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _buildMapWrapper(),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Expanded(child: _buildBarChartCard()),
                    const SizedBox(height: 24),
                    Expanded(child: _buildDonutChartCard()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return ListView(
      children: [
        _buildTopCards(false),
        const SizedBox(height: 24),
        SizedBox(
          height: 400,
          child: _buildMapWrapper(),
        ),
        const SizedBox(height: 24),
        _buildBarChartCard(),
        const SizedBox(height: 24),
        _buildDonutChartCard(),
      ],
    );
  }

  Widget _buildMapWrapper() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Live Cleanliness Map', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  children: [
                    _buildMapLegendItem(Colors.green, 'Clean'),
                    const SizedBox(width: 16),
                    _buildMapLegendItem(Colors.orange, 'Moderate'),
                    const SizedBox(width: 16),
                    _buildMapLegendItem(Colors.redAccent, 'Critical'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
              child: _buildMap(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
      ],
    );
  }

  Widget _buildBarChartCard() {
    return Container(
      height: 350,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F5132),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Cleanliness Trend Overview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Row(
                  children: [
                    const Text('All Zones', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                      child: const Text('7 Days', style: TextStyle(color: Color(0xFF0F5132), fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    const Text('30 Days', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 12),
                    const Text('3 Months', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 20, top: 20, bottom: 10, left: 10),
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true, 
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) {
                          if (value % 20 == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Text('${value.toInt()}%', style: const TextStyle(color: Colors.black54, fontSize: 10)),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                          if (value.toInt() >= 0 && value.toInt() < days.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(days[value.toInt()], style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          const yValues = [62, 68, 78, 70, 82, 85, 87];
                          if (value.toInt() >= 0 && value.toInt() < yValues.length) {
                            return Text('${yValues[value.toInt()]}%', style: const TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold));
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: 100,
                  barGroups: [
                    _buildBarGroup(0, 62),
                    _buildBarGroup(1, 68),
                    _buildBarGroup(2, 78),
                    _buildBarGroup(3, 70),
                    _buildBarGroup(4, 82),
                    _buildBarGroup(5, 85),
                    _buildBarGroup(6, 87),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _buildBarGroup(int x, double y) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: const Color(0xFF0F5132),
          width: 16,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(2), topRight: Radius.circular(2)),
        ),
      ],
    );
  }

  Widget _buildDonutChartCard() {
    final list = _filteredGarbageFlags;
    double total = list.isEmpty ? 1 : list.length.toDouble();
    double cleanVal = list.where((f) => f.className == 'Clean').length.toDouble();
    double slightVal = list.where((f) => f.className == 'Slightly_Dirty' || f.displayClass == 'Slightly Dirty').length.toDouble();
    double dirtyVal = list.where((f) => f.className == 'Trash_Detected' || f.className == 'Very_Dirty' || f.displayClass == 'Trash Detected' || f.displayClass == 'Very Dirty').length.toDouble();

    if (cleanVal == 0 && slightVal == 0 && dirtyVal == 0) {
      cleanVal = 137;
      slightVal = 120;
      dirtyVal = 85;
      total = cleanVal + slightVal + dirtyVal;
    } else {
      total = cleanVal + slightVal + dirtyVal;
      if (total == 0) total = 1;
    }

    return Container(
      height: 350,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Waste Condition Distribution', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 4,
                          centerSpaceRadius: 50,
                          sections: [
                            if (cleanVal > 0)
                              PieChartSectionData(
                                color: Colors.green,
                                value: cleanVal,
                                title: '%',
                                radius: 30,
                                titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.transparent),
                              ),
                            if (slightVal > 0)
                              PieChartSectionData(
                                color: Colors.orange,
                                value: slightVal,
                                title: '%',
                                radius: 30,
                                titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.transparent),
                              ),
                            if (dirtyVal > 0)
                              PieChartSectionData(
                                color: Colors.red,
                                value: dirtyVal,
                                title: '%',
                                radius: 30,
                                titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.transparent),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const Text('Total Spots', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLegendItem(Colors.green, 'Clean', cleanVal.toInt(), total.toInt()),
                      const SizedBox(height: 16),
                      _buildLegendItem(Colors.orange, 'Moderate', slightVal.toInt(), total.toInt()),
                      const SizedBox(height: 16),
                      _buildLegendItem(Colors.red, 'Critical', dirtyVal.toInt(), total.toInt()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, int count, int total) {
    int pct = total > 0 ? ((count / total) * 100).round() : 0;
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(' (%)', style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _centerOnCurrentLocation() {
    if (_vehicles.isNotEmpty && _vehicles.first.currentLocation != null) {
      _mapController.move(_vehicles.first.currentLocation!, 15.0);
    }
  }

  void _showTrashPopup(GarbageFlag flag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          '${flag.className.replaceAll('_', ' ')} - ${flag.displayClass}',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 600,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(flag.imageUrl, headers: const {"ngrok-skip-browser-warning": "true"},
                    height: 250, 
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 250,
                      color: Colors.grey.shade200,
                      child: const Center(child: Icon(Icons.broken_image, size: 40, color: Colors.grey)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
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
                              userAgentPackageName: 'com.nitin.trashtracker',
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
                    Text("Confidence: ${(flag.confidence * 100).toStringAsFixed(1)}%", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text("Vehicle: ${flag.vehicleNumber}", style: const TextStyle(color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text("Location: ${flag.zone} - ${flag.ward}", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.directions_outlined, size: 18),
            label: const Text('Directions'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
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
    List<Marker> customTrashMarkers = [];

    if (_selectedVehicleRoute.isEmpty) {
      routePolylines.addAll(_snappedPolylines);
    } else {
      routePolylines.add(Polyline(
        points: _selectedVehicleRoute,
        color: const Color(0xFF00E676), // Vibrant Green for vehicle travelled road
        strokeWidth: 6.0,
      ));
    }

    const double clusterDist = 0.00018;
    final List<List<GarbageFlag>> clusters = [];

    final activeFiltered = _filteredGarbageFlags;
    for (var flag in activeFiltered) {
      if (!flag.isTrashDetected) continue;
      bool added = false;
      for (var c in clusters) {
        if ((flag.lat - c.first.lat).abs() < clusterDist && (flag.lng - c.first.lng).abs() < clusterDist) {
          c.add(flag);
          added = true;
          break;
        }
      }
      if (!added) {
        clusters.add([flag]);
      }
    }

    for (var cluster in clusters) {
      final flag = cluster.first;
      final isVeryDirty = cluster.any((f) => f.className == 'Very_Dirty' || f.displayClass == 'Very Dirty');

      customTrashMarkers.add(Marker(
        point: LatLng(flag.lat, flag.lng),
        width: 38,
        height: 46,
        alignment: Alignment.topCenter,
        child: TrashPinpointWidget(
          count: cluster.length,
          isVeryDirty: isVeryDirty,
          onTap: () => _showTrashPopup(flag),
        ),
      ));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _garbageFlags.isNotEmpty
            ? LatLng(_garbageFlags.first.lat, _garbageFlags.first.lng)
            : (_vehicles.isNotEmpty && _vehicles.first.currentLocation != null
                ? _vehicles.first.currentLocation!
                : const LatLng(13.0568, 77.5027)),
        initialZoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.nitin.trashtracker',
          tileProvider: kIsWeb ? null : CachedTileProvider(store: MapCacheService.store),
        ),
        ...WardZoneService.instance.buildLayers(selectedZone: _selectedZone, selectedWard: _selectedWard),
        PolylineLayer(polylines: routePolylines),
        MarkerLayer(markers: customTrashMarkers),
        MarkerLayer(
          markers: _vehicles.where((v) => v.currentLocation != null).map((vehicle) {
            final statusColor = Color(vehicle.stateColorValue);
            return Marker(
              point: vehicle.currentLocation!,
              width: 90,
              height: 55,
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedVehicle = vehicle);
                  _mapController.move(vehicle.currentLocation!, 15.0);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusColor, width: 1.5),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: Text(
                        vehicle.vehicleNumber.isNotEmpty ? vehicle.vehicleNumber : vehicle.id,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
                      ),
                      child: const Icon(LucideIcons.truck, color: Colors.white, size: 14),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        
        // Add map controls
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'zoomInBtn',
                  mini: true,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.add, color: Colors.black87),
                  onPressed: () {
                    _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
                  },
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'zoomOutBtn',
                  mini: true,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.remove, color: Colors.black87),
                  onPressed: () {
                    _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
                  },
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  heroTag: 'locationBtn',
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: Colors.black87),
                  onPressed: _centerOnCurrentLocation,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAISettingsDialog() async {
    final baseUrl = activeGarbageAiUrl;
    
    double currentThreshold = 0.25;
    double veryDirtyThreshold = 0.50;
    bool isLoading = true;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (isLoading) {
              http.get(Uri.parse('$baseUrl/api/settings')).then((res) {
                if (res.statusCode == 200) {
                  final data = json.decode(res.body);
                  setDialogState(() {
                    currentThreshold = (data['confidence_threshold'] as num?)?.toDouble() ?? 0.25;
                    veryDirtyThreshold = (data['very_dirty_threshold'] as num?)?.toDouble() ?? 0.50;
                    isLoading = false;
                  });
                } else {
                  setDialogState(() => isLoading = false);
                }
              }).catchError((e) {
                setDialogState(() => isLoading = false);
              });
            }
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F5132).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(LucideIcons.sliders, color: Color(0xFF0F5132), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('AI Model Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: isLoading 
                ? const SizedBox(height: 140, child: Center(child: CircularProgressIndicator(color: Color(0xFF0F5132))))
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section 1: Very Dirty Road Confidence Level Setter (MobileNetV3)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red),
                                      SizedBox(width: 6),
                                      Text('Very Dirty Road Confidence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text('${(veryDirtyThreshold * 100).toInt()}%', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Slider(
                                value: veryDirtyThreshold,
                                min: 0.20,
                                max: 0.95,
                                divisions: 15,
                                activeColor: Colors.redAccent,
                                label: '${(veryDirtyThreshold * 100).toInt()}%',
                                onChanged: (val) {
                                  setDialogState(() => veryDirtyThreshold = val);
                                },
                              ),
                              Wrap(
                                spacing: 6,
                                children: [0.35, 0.50, 0.70, 0.85].map((preset) {
                                  final isSel = (veryDirtyThreshold - preset).abs() < 0.03;
                                  return ChoiceChip(
                                    label: Text('${(preset * 100).toInt()}%', style: TextStyle(fontSize: 11, color: isSel ? Colors.white : Colors.black87)),
                                    selected: isSel,
                                    selectedColor: Colors.redAccent,
                                    backgroundColor: Colors.white,
                                    onSelected: (_) => setDialogState(() => veryDirtyThreshold = preset),
                                    visualDensity: VisualDensity.compact,
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 6),
                              const Text('MobileNetV3 classifier threshold required to escalate trash-detected road frames to "VERY DIRTY ROAD" (red alert).', style: TextStyle(fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Section 2: YOLO Detection Confidence
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F5132).withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF0F5132).withOpacity(0.15)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('YOLO Detection Confidence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F5132))),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F5132).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text('${(currentThreshold * 100).toInt()}%', style: const TextStyle(color: Color(0xFF0F5132), fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Slider(
                                value: currentThreshold,
                                min: 0.1,
                                max: 0.9,
                                divisions: 16,
                                activeColor: const Color(0xFF0F5132),
                                label: '${(currentThreshold * 100).toInt()}%',
                                onChanged: (val) {
                                  setDialogState(() => currentThreshold = val);
                                },
                              ),
                              Wrap(
                                spacing: 6,
                                children: [0.15, 0.25, 0.40, 0.60].map((preset) {
                                  final isSel = (currentThreshold - preset).abs() < 0.03;
                                  return ChoiceChip(
                                    label: Text('${(preset * 100).toInt()}%', style: TextStyle(fontSize: 11, color: isSel ? Colors.white : Colors.black87)),
                                    selected: isSel,
                                    selectedColor: const Color(0xFF0F5132),
                                    backgroundColor: Colors.white,
                                    onSelected: (_) => setDialogState(() => currentThreshold = preset),
                                    visualDensity: VisualDensity.compact,
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 6),
                              const Text('Initial candidate threshold: Lower = more detections, higher false positives; Higher = strictly visible trash.', style: TextStyle(fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    setDialogState(() => isLoading = true);
                    try {
                      await http.post(
                        Uri.parse('$baseUrl/api/settings'),
                        headers: {'Content-Type': 'application/json'},
                        body: json.encode({
                          'confidence_threshold': currentThreshold,
                          'very_dirty_threshold': veryDirtyThreshold,
                        }),
                      );
                    } catch (e) {}
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
                  child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }
}
