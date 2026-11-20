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
import '../models/trail_segment.dart';
import 'active_fleet_screen.dart';
import 'database_screen.dart';
import 'alerts_screen.dart';

import '../models/garbage_flag.dart';
import '../widgets/trash_pinpoint_marker.dart';
import '../widgets/trash_flag_inspection_modal.dart';
import '../widgets/placeholder_map_switch.dart';
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
  final Map<String, StreamSubscription> _vehicleDailyStatsSubs = {};
  final Map<String, List<Polyline>> _vehicleTrails = {};
  List<Polyline> _selectedVehiclePolylines = [];
  StreamSubscription? _selectedVehicleStatsSub;
  bool _initialMapCentered = false;

  double _currentMapZoom = 13.0;
  List<Marker> _cachedTrashMarkers = [];
  int _cachedTrashCount = -1;
  String _cachedMarkerFilterKey = '';

  List<Marker> _getOrCreateTrashMarkers(List<GarbageFlag> flags) {
    final filterKey = '${flags.length}_${_selectedZone}_${_selectedWard}_${TrashSpotsService.instance.showPlaceholders}';
    if (_cachedTrashCount == flags.length && _cachedMarkerFilterKey == filterKey && _cachedTrashMarkers.isNotEmpty) {
      return _cachedTrashMarkers;
    }

    const double clusterDist = 0.00018;
    final List<List<GarbageFlag>> clusters = [];

    for (var flag in flags) {
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

    final List<Marker> markers = [];
    for (var cluster in clusters) {
      final flag = cluster.first;
      final isVeryDirty = cluster.any((f) => f.className == 'Very_Dirty' || f.displayClass == 'Very Dirty');

      markers.add(Marker(
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

    _cachedTrashCount = flags.length;
    _cachedMarkerFilterKey = filterKey;
    _cachedTrashMarkers = markers;
    return _cachedTrashMarkers;
  }

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

    if (!_initialMapCentered && _garbageFlags.isNotEmpty) {
      _initialMapCentered = true;
      try {
        _mapController.move(LatLng(_garbageFlags.first.lat, _garbageFlags.first.lng), 14.0);
      } catch (_) {}
    }
  }

  void _syncVehicleTrails(List<Vehicle> vehicles) {
    for (var v in vehicles) {
      final vNum = v.vehicleNumber.isNotEmpty ? v.vehicleNumber : v.id;
      if (!_vehicleDailyStatsSubs.containsKey(vNum)) {
        _vehicleDailyStatsSubs[vNum] = FirebaseFirestore.instance
            .collection('vehicles')
            .doc(vNum)
            .collection('daily_stats')
            .doc(_todayDateString)
            .snapshots()
            .listen((doc) {
          if (!mounted) return;
          if (doc.exists && doc.data() != null) {
            final polylines = TrailSegment.listFromDailyStats(doc.data());
            setState(() {
              _vehicleTrails[vNum] = polylines;
              if (_selectedVehicle != null && (_selectedVehicle!.vehicleNumber == vNum || _selectedVehicle!.id == vNum)) {
                _selectedVehiclePolylines = polylines;
              }
            });
          }
        }, onError: (_) {});
      }
    }
  }

  void _selectVehicle(Vehicle vehicle) {
    final vNum = vehicle.vehicleNumber.isNotEmpty ? vehicle.vehicleNumber : vehicle.id;
    setState(() {
      _selectedVehicle = vehicle;
      _selectedVehiclePolylines = _vehicleTrails[vNum] ?? [];
    });
    if (vehicle.currentLocation != null) {
      _mapController.move(vehicle.currentLocation!, 15.5);
    }
    _selectedVehicleStatsSub?.cancel();
    _selectedVehicleStatsSub = FirebaseFirestore.instance
        .collection('vehicles')
        .doc(vNum)
        .collection('daily_stats')
        .doc(_todayDateString)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        setState(() {
          _selectedVehiclePolylines = TrailSegment.listFromDailyStats(doc.data());
        });
      }
    }, onError: (_) {});
  }

  void _clearVehicleSelection() {
    setState(() {
      _selectedVehicle = null;
      _selectedVehiclePolylines = [];
    });
    _selectedVehicleStatsSub?.cancel();
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
        _syncVehicleTrails(vehicles);
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
    for (var sub in _vehicleDailyStatsSubs.values) {
      sub.cancel();
    }
    _selectedVehicleStatsSub?.cancel();
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
      final double targetZoom = (_selectedWard != 'All Wards')
          ? 15.2
          : ((_selectedZone != 'All Zones') ? 12.5 : 11.8);
      _mapController.move(LatLng(centerLat, centerLng), targetZoom);
    } else {
      _mapController.move(const LatLng(12.9716, 77.5946), 11.8);
    }
  }

  Widget _buildFilterBar(bool isDesktop) {
    final bool hasAllAccess = RoleService.hasAllAccess('Street Cleanliness AI');
    final List<String> allowedZones = RoleService.getAllowedZonesForModule('Street Cleanliness AI');
    final List<String> allowedWards = RoleService.getAllowedWardsForModule('Street Cleanliness AI');

    List<String> zItems = (hasAllAccess ? _zones.map((z) => z.name).toList() : allowedZones).toList();
    if (zItems.length > 1 && !zItems.contains('All Zones')) {
      zItems.insert(0, 'All Zones');
    }
    final zones = zItems.isEmpty ? ['All Zones'] : zItems;

    String validSelectedZone = _selectedZone;
    if (!zones.contains(validSelectedZone) && zones.isNotEmpty) {
      validSelectedZone = zones.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedZone != validSelectedZone) {
          setState(() {
            _selectedZone = validSelectedZone;
            _updateMapForSelection();
          });
        }
      });
    }

    List<String> wItems = _wards.where((w) {
      if (!hasAllAccess && !allowedWards.contains('All Wards') && !allowedWards.contains(w.name)) return false;
      if (validSelectedZone == 'All Zones') return true;
      try {
        final z = _zones.firstWhere((zm) => zm.name == validSelectedZone);
        return _isWardInZone(w, z);
      } catch (_) { return false; }
    }).map((w) => w.name).toList();

    if (wItems.length > 1 && !wItems.contains('All Wards')) {
      wItems.insert(0, 'All Wards');
    }
    final wards = wItems.isEmpty ? ['All Wards'] : wItems;

    String validSelectedWard = _selectedWard;
    if (!wards.contains(validSelectedWard) && wards.isNotEmpty) {
      validSelectedWard = wards.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedWard != validSelectedWard) {
          setState(() {
            _selectedWard = validSelectedWard;
            _updateMapForSelection();
          });
        }
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Role Indicator Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
                color: const Color(0xFFF8FAFC),
              ),
              child: Row(
                children: [
                  const Text('Role: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  Text(RoleService.currentUserRoleTitle ?? 'None', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _buildFunctionalDropdown('Zone', validSelectedZone, zones, (val) {
              setState(() {
                _selectedZone = val;
                _selectedWard = 'All Wards';
              });
              _updateMapForSelection();
            }),
            const SizedBox(width: 16),
            _buildFunctionalDropdown('Ward', validSelectedWard, wards, (val) {
              setState(() => _selectedWard = val);
              _updateMapForSelection();
            }),
            const SizedBox(width: 24),
            Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF198754), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                const Text('Live Tracking', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              ],
            ),
            const SizedBox(width: 12),
            Text(
              'Last updated: ${TimeOfDay.now().format(context)}',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            const SizedBox(width: 20),
            _buildFunctionalDatePicker(),
            const SizedBox(width: 20),
            _buildFunctionalToggle(),
            const SizedBox(width: 20),
            ElevatedButton.icon(
              onPressed: () => _showAISettingsDialog(),
              icon: const Icon(LucideIcons.settings, size: 16, color: Colors.white),
              label: const Text('AI Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5132),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFunctionalDropdown(String label, String value, List<String> items, Function(String) onChanged) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      itemBuilder: (context) => items.map((item) => PopupMenuItem(value: item, child: Text(item))).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              ],
            ),
            const SizedBox(width: 20),
            const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B)),
          ],
        ),
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Date', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(LucideIcons.calendar, size: 14, color: Color(0xFF1E293B)),
                    const SizedBox(width: 6),
                    Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 16),
            const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B)),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isDailyView = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _isDailyView ? const Color(0xFF0F5132) : Colors.transparent,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(7), bottomLeft: Radius.circular(7)),
              ),
              child: Text('Daily', style: TextStyle(color: _isDailyView ? Colors.white : const Color(0xFF4B5563), fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _isDailyView = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: !_isDailyView ? const Color(0xFF0F5132) : Colors.transparent,
                borderRadius: const BorderRadius.only(topRight: Radius.circular(7), bottomRight: Radius.circular(7)),
              ),
              child: Text('Monthly', style: TextStyle(color: !_isDailyView ? Colors.white : const Color(0xFF4B5563), fontWeight: FontWeight.bold, fontSize: 13)),
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
    final now = DateTime.now();
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final List<Map<String, dynamic>> dayStats = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final label = dayNames[d.weekday - 1];
      final daySpots = _filteredGarbageFlags.where((f) {
        final t = DateTime.tryParse(f.timestamp);
        if (t == null) return false;
        return t.year == d.year && t.month == d.month && t.day == d.day;
      }).toList();
      double score;
      if (daySpots.isNotEmpty) {
        final clean = daySpots.where((f) =>
          f.className.toLowerCase().contains('clean') ||
          f.status == 'Resolved' ||
          f.status == 'Deflagged'
        ).length;
        score = (clean / daySpots.length) * 100.0;
      } else {
        final cumSpots = _filteredGarbageFlags.where((f) {
          final t = DateTime.tryParse(f.timestamp);
          if (t == null) return false;
          return t.isBefore(d.add(const Duration(days: 1)));
        }).toList();
        if (cumSpots.isNotEmpty) {
          final clean = cumSpots.where((f) =>
            f.className.toLowerCase().contains('clean') ||
            f.status == 'Resolved' ||
            f.status == 'Deflagged'
          ).length;
          score = (clean / cumSpots.length) * 100.0;
        } else {
          score = 100.0;
        }
      }
      return {
        'label': label,
        'value': score.clamp(0.0, 100.0),
      };
    });

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
                          final idx = value.toInt();
                          if (idx >= 0 && idx < dayStats.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                dayStats[idx]['label'] as String,
                                style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
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
                          final idx = value.toInt();
                          if (idx >= 0 && idx < dayStats.length) {
                            final val = (dayStats[idx]['value'] as double).round();
                            return Text('$val%', style: const TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold));
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: 100,
                  barGroups: List.generate(dayStats.length, (i) => _buildBarGroup(i, dayStats[i]['value'] as double)),
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
    double cleanVal = list.where((f) =>
      f.className.toLowerCase().contains('clean') ||
      f.displayClass.toLowerCase().contains('clean') ||
      f.status == 'Resolved' ||
      f.status == 'Deflagged'
    ).length.toDouble();
    double slightVal = list.where((f) =>
      (f.className.toLowerCase().contains('slight') || f.displayClass.toLowerCase().contains('slight')) &&
      f.status != 'Resolved' &&
      f.status != 'Deflagged'
    ).length.toDouble();
    double dirtyVal = list.where((f) =>
      (f.className.toLowerCase().contains('trash') ||
       f.className.toLowerCase().contains('very') ||
       f.className.toLowerCase().contains('dirty') ||
       f.displayClass.toLowerCase().contains('trash') ||
       f.displayClass.toLowerCase().contains('very') ||
       f.displayClass.toLowerCase().contains('dirty')) &&
      f.status != 'Resolved' &&
      f.status != 'Deflagged'
    ).length.toDouble();

    double total = cleanVal + slightVal + dirtyVal;

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
                          sections: total == 0
                              ? [
                                  PieChartSectionData(
                                    color: Colors.grey.shade200,
                                    value: 1,
                                    showTitle: false,
                                    radius: 26,
                                  ),
                                ]
                              : [
                                  if (cleanVal > 0)
                                    PieChartSectionData(
                                      color: Colors.green,
                                      value: cleanVal,
                                      title: '',
                                      radius: 30,
                                    ),
                                  if (slightVal > 0)
                                    PieChartSectionData(
                                      color: Colors.orange,
                                      value: slightVal,
                                      title: '',
                                      radius: 30,
                                    ),
                                  if (dirtyVal > 0)
                                    PieChartSectionData(
                                      color: Colors.red,
                                      value: dirtyVal,
                                      title: '',
                                      radius: 30,
                                    ),
                                ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${list.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
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
        Text('$count ($pct%)', style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _centerOnCurrentLocation() {
    if (_vehicles.isNotEmpty && _vehicles.first.currentLocation != null) {
      _mapController.move(_vehicles.first.currentLocation!, 15.0);
    }
  }

  void _showTrashPopup(GarbageFlag flag) {
    TrashFlagInspectionModal.show(context, flag);
  }

  Widget _buildMap() {
    List<Polyline> routePolylines = [];

    // Real-time Vehicle Route Tracing & Condition Color Mapping
    if (_selectedVehicle != null) {
      final vNum = _selectedVehicle!.vehicleNumber.isNotEmpty ? _selectedVehicle!.vehicleNumber : _selectedVehicle!.id;
      final vehiclePolys = _selectedVehiclePolylines.isNotEmpty 
          ? _selectedVehiclePolylines 
          : (_vehicleTrails[vNum] ?? []);
      routePolylines.addAll(vehiclePolys);
    } else {
      for (var polylines in _vehicleTrails.values) {
        routePolylines.addAll(polylines);
      }
    }

    final activeFiltered = _filteredGarbageFlags;
    final customTrashMarkers = _getOrCreateTrashMarkers(activeFiltered);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(12.9716, 77.5946),
            initialZoom: 11.8,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.nitin.trashtracker',
              tileProvider: kIsWeb ? null : CachedTileProvider(store: MapCacheService.store),
            ),
            ...WardZoneService.instance.buildLayers(selectedZone: _selectedZone, selectedWard: _selectedWard),
            if (routePolylines.isNotEmpty) PolylineLayer(polylines: routePolylines),
            Builder(
              builder: (context) {
                final camera = MapCamera.of(context);
                final hasSpecificWard = _selectedWard != 'All Wards' && _selectedWard.trim().isNotEmpty;
                // Flags strictly appear ONLY when deeply zoomed in to individual ward level
                final bool showPins = hasSpecificWard
                    ? (camera.zoom >= 14.8)
                    : (camera.zoom >= WardZoneService.individualWardPinsZoomThreshold);
                if (!showPins || customTrashMarkers.isEmpty) {
                  return const SizedBox.shrink();
                }
                return MarkerLayer(
                  markers: customTrashMarkers,
                );
              },
            ),
            MarkerLayer(
              markers: _vehicles.where((v) => v.currentLocation != null).map((vehicle) {
                final statusColor = Color(vehicle.stateColorValue);
                return Marker(
                  point: vehicle.currentLocation!,
                  width: 90,
                  height: 55,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () => _selectVehicle(vehicle),
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
            
            // Map Placeholder / Real Flags Toggle Switch
            Positioned(
              top: 16,
              right: 16,
              child: const PlaceholderMapSwitch(isDark: true),
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
        ),
        if (_selectedVehicle != null)
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.truck, color: Color(0xFF00E676), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    "Tracing: ${_selectedVehicle!.vehicleNumber.isNotEmpty ? _selectedVehicle!.vehicleNumber : _selectedVehicle!.id}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _clearVehicleSelection,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 14),
                    ),
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
