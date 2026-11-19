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
import '../models/trail_segment.dart';
import 'active_fleet_screen.dart';
import 'health_database_screen.dart';
import 'alerts_screen.dart';
import '../services/ward_zone_service.dart';
import '../services/role_service.dart';

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
  String _selectedZone = 'All Zones';
  DateTime _selectedDate = DateTime.now();
  
  bool _isDailyView = true;
  
  Map<String, Map<String, dynamic>> _liveTrackingData = {};
  List<Vehicle> _vehicles = [];
  List<Ward> _wards = [];
  
  StreamSubscription? _liveTrackingSub;
  StreamSubscription? _vehiclesSub;
  StreamSubscription? _wardsSub;
  StreamSubscription? _trashSub;

  List<HealthFlag> _healthFlags = [];
  Timer? _healthTimer;

  String get _todayDateString => DateTime.now().toIso8601String().split('T')[0];
  StreamSubscription<DocumentSnapshot>? _dailyStatsSub;
  Map<String, dynamic>? _selectedVehicleStats;
  List<LatLng> _selectedVehicleRoute = [];

  final Map<String, StreamSubscription> _vehicleDailyStatsSubs = {};
  final Map<String, List<Polyline>> _vehicleTrails = {};
  List<Polyline> _selectedVehiclePolylines = [];
  StreamSubscription? _selectedVehicleStatsSub;

  double _currentMapZoom = 13.0;
  List<Marker> _cachedHealthMarkers = [];
  int _cachedHealthCount = -1;
  String _cachedMarkerFilterKey = '';

  List<Marker> _getOrCreateHealthMarkers(List<HealthFlag> flags) {
    final filterKey = '${flags.length}_${_selectedWard?.name}';
    if (_cachedHealthCount == flags.length && _cachedMarkerFilterKey == filterKey && _cachedHealthMarkers.isNotEmpty) {
      return _cachedHealthMarkers;
    }

    final List<Marker> markers = [];
    Map<String, int> locationCounts = {};
    for (var flag in flags) {
      String locKey = '${flag.lat.toStringAsFixed(5)}_${flag.lng.toStringAsFixed(5)}';
      int count = locationCounts[locKey] ?? 0;
      locationCounts[locKey] = count + 1;

      double offsetLat = flag.lat;
      double offsetLng = flag.lng;
      if (count > 0) {
        offsetLng += (count * 0.0002);
      }

      if (flag.pointType == 'start') {
        markers.add(Marker(
          point: LatLng(offsetLat, offsetLng),
          width: 30, height: 30,
          alignment: Alignment.center,
          child: const Icon(Icons.play_circle_fill, color: Colors.greenAccent, size: 28),
        ));
      } else if (flag.pointType == 'end') {
        markers.add(Marker(
          point: LatLng(offsetLat, offsetLng),
          width: 30, height: 30,
          alignment: Alignment.center,
          child: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 28),
        ));
      }

      if (flag.className != 'Clean' &&
          flag.className != 'Good_Condition' &&
          flag.displayClass != 'Good Condition' &&
          flag.pointType != 'intermediate') {
        Color markerColor = (flag.className == 'Pothole_Detected' || flag.displayClass == 'Pothole Detected') ? Colors.redAccent : Colors.orangeAccent;
        
        markers.add(Marker(
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

    _cachedHealthCount = flags.length;
    _cachedMarkerFilterKey = filterKey;
    _cachedHealthMarkers = markers;
    return _cachedHealthMarkers;
  }

  @override
  void initState() {
    super.initState();
    WardZoneService.instance.init();
    WardZoneService.instance.notifier.addListener(_onWardZoneUpdate);
    _fetchDataFromFirestore();
    _startLiveTrackingListener();

    _fetchHealthFlagsFromFirestore();
  }

  void _onWardZoneUpdate() {
    if (mounted) setState(() {});
  }

  void _fetchHealthFlagsFromFirestore() {
    _trashSub = FirebaseFirestore.instance.collection('health_spots').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _healthFlags = snapshot.docs
            .map((doc) => HealthFlag.fromJson(doc.data(), doc.id))
            .toList();
      });
    });
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
    for (var sub in _vehicleDailyStatsSubs.values) {
      sub.cancel();
    }
    _selectedVehicleStatsSub?.cancel();
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

  List<HealthFlag> get _filteredHealthFlags {
    return _healthFlags.where((f) {
      if (!RoleService.isSpotAllowed(f.lat, f.lng, null, f.ward, 'Road Health Monitor AI')) {
        return false;
      }
      if (_selectedZone != 'All Zones') {
        if (!WardZoneService.instance.matchesZone(lat: f.lat, lng: f.lng, docZone: null, targetZone: _selectedZone)) {
          return false;
        }
      }
      if (_selectedWard != null &&
          _selectedWard!.name != 'All Wards' &&
          !WardZoneService.instance.matchesWard(lat: f.lat, lng: f.lng, docWard: f.ward, targetWard: _selectedWard!.name)) {
        return false;
      }
      return true;
    }).toList();
  }

  void _updateMapForSelection() {
    if (_selectedWard != null && _selectedWard!.name != 'All Wards' && _selectedWard!.boundary.isNotEmpty) {
      double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
      for (var p in _selectedWard!.boundary) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      _mapController.move(LatLng(centerLat, centerLng), 15.2);
    } else if (_selectedZone != 'All Zones') {
      try {
        final z = WardZoneService.instance.zones.firstWhere((zm) => zm.name == _selectedZone);
        if (z.boundary.isNotEmpty) {
          double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
          for (var p in z.boundary) {
            if (p.latitude < minLat) minLat = p.latitude;
            if (p.latitude > maxLat) maxLat = p.latitude;
            if (p.longitude < minLng) minLng = p.longitude;
            if (p.longitude > maxLng) maxLng = p.longitude;
          }
          final centerLat = (minLat + maxLat) / 2;
          final centerLng = (minLng + maxLng) / 2;
          _mapController.move(LatLng(centerLat, centerLng), 12.5);
          return;
        }
      } catch (_) {}
      _mapController.move(const LatLng(12.9716, 77.5946), 12.5);
    } else {
      _mapController.move(const LatLng(12.9716, 77.5946), 11.8);
    }
  }

  int get _spotsCleared => _filteredHealthFlags.where((f) =>
    f.className.toLowerCase().contains('good') ||
    f.displayClass.toLowerCase().contains('good') ||
    f.status == 'Resolved' ||
    f.status == 'Deflagged'
  ).length;

  int get _spotsFlagged => _filteredHealthFlags.where((f) =>
    (f.className.toLowerCase().contains('pothole') ||
     f.className.toLowerCase().contains('bad') ||
     f.displayClass.toLowerCase().contains('pothole') ||
     f.displayClass.toLowerCase().contains('bad')) &&
    f.status != 'Resolved' &&
    f.status != 'Deflagged'
  ).length;

  int get _totalSpots => _filteredHealthFlags.length;

  int get _overallCleanliness {
    if (_totalSpots == 0) return 100;
    return ((_spotsCleared / _totalSpots) * 100).toInt();
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
            Navigator.push(context, MaterialPageRoute(builder: (context) => const HealthDatabaseScreen()));
          } else if (index == 1) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ActiveFleetScreen()));
          } else if (index == 2) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const AlertsListScreen()));
          }
        },
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(isDesktop ? 24 : 12, isDesktop ? 24 : 12, isDesktop ? 24 : 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilterBar(isDesktop),
            const SizedBox(height: 16),
            Expanded(
              child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(bool isDesktop) {
    final bool hasAllAccess = RoleService.hasAllAccess('Road Health Monitor AI');
    final List<String> allowedZones = RoleService.getAllowedZonesForModule('Road Health Monitor AI');
    final List<String> allowedWards = RoleService.getAllowedWardsForModule('Road Health Monitor AI');

    final allZoneModels = WardZoneService.instance.zones;
    final allWardModels = WardZoneService.instance.wards;

    List<String> zItems = (hasAllAccess ? allZoneModels.map((z) => z.name).toList() : allowedZones).toList();
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

    List<String> wItems = allWardModels.where((w) {
      if (!hasAllAccess && !allowedWards.contains('All Wards') && !allowedWards.contains(w.name)) return false;
      if (validSelectedZone == 'All Zones') return true;
      try {
        final z = allZoneModels.firstWhere((zm) => zm.name == validSelectedZone);
        return WardZoneService.instance.isWardInZone(w, z);
      } catch (_) { return false; }
    }).map((w) => w.name).toList();

    if (wItems.length > 1 && !wItems.contains('All Wards')) {
      wItems.insert(0, 'All Wards');
    }
    final wards = wItems.isEmpty ? ['All Wards'] : wItems;

    String currentWardName = _selectedWard?.name ?? 'All Wards';
    if (!wards.contains(currentWardName) && wards.isNotEmpty) {
      currentWardName = wards.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedWard = currentWardName == 'All Wards' ? null : allWardModels.firstWhere((w) => w.name == currentWardName, orElse: () => Ward(id: '', name: currentWardName, boundary: []));
            _updateMapForSelection();
          });
        }
      });
    }

    final dateStr = "${_selectedDate.day} ${_monthString(_selectedDate.month)} ${_selectedDate.year}";

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
            _buildDropdown('Zone', validSelectedZone, zones, (val) {
              setState(() {
                _selectedZone = val;
                _selectedWard = null;
              });
              _updateMapForSelection();
            }),
            const SizedBox(width: 16),
            _buildDropdown('Ward', currentWardName, wards, (val) {
              setState(() {
                _selectedWard = val == 'All Wards' ? null : allWardModels.firstWhere((w) => w.name == val, orElse: () => Ward(id: '', name: val, boundary: []));
              });
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
            // Date Picker
            GestureDetector(
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
                  setState(() => _selectedDate = picked);
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
            ),
            const SizedBox(width: 20),
            // Daily / Monthly Toggle
            Container(
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String) onChanged) {
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

  String _monthString(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Widget _buildTopCards(bool isDesktop) {
    final overallCard = _buildOverallHealthCard(!isDesktop);
    final spotsDetectedCard = _buildHealthSpotsDetectedCard(!isDesktop);
    final spotsClearedCard = _buildSpotsGoodCard(!isDesktop);
    final officerResponseCard = _buildMonitoredCard(!isDesktop);

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

  Widget _buildOverallHealthCard(bool isMobile) {
    return _buildBaseCard(
      isMobile: isMobile,
      child: Row(
        children: [
          Container(
            width: isMobile ? 36 : 48,
            height: isMobile ? 36 : 48,
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.favorite_rounded, color: Colors.green, size: isMobile ? 20 : 28),
          ),
          SizedBox(width: isMobile ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('OVERALL HEALTH', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 9 : 11, fontWeight: FontWeight.bold, letterSpacing: 0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('$_overallCleanliness%', style: TextStyle(color: Colors.black87, fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthSpotsDetectedCard(bool isMobile) {
    return _buildBaseCard(
      isMobile: isMobile,
      child: Row(
        children: [
          Container(
            width: isMobile ? 36 : 48,
            height: isMobile ? 36 : 48,
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: isMobile ? 20 : 28),
          ),
          SizedBox(width: isMobile ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('POTHOLES / BAD', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 9 : 11, fontWeight: FontWeight.bold, letterSpacing: 0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('$_spotsFlagged', style: TextStyle(color: Colors.black87, fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotsGoodCard(bool isMobile) {
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
                Text('GOOD ROADS', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 9 : 11, fontWeight: FontWeight.bold, letterSpacing: 0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$_spotsCleared', style: TextStyle(color: Colors.blueAccent, fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold)),
                    Text(' / $_totalSpots', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 13 : 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitoredCard(bool isMobile) {
    int total = _totalSpots;
    return _buildBaseCard(
      isMobile: isMobile,
      child: Row(
        children: [
          Container(
            width: isMobile ? 36 : 48,
            height: isMobile ? 36 : 48,
            decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(10)),
            child: Icon(LucideIcons.activity, color: Colors.purpleAccent, size: isMobile ? 20 : 28),
          ),
          SizedBox(width: isMobile ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('ROAD SEGMENTS', style: TextStyle(color: Colors.black54, fontSize: isMobile ? 9 : 11, fontWeight: FontWeight.bold, letterSpacing: 0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('$total', style: TextStyle(color: Colors.black87, fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold)),
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
                    Expanded(child: _buildLineGraphCard()),
                    const SizedBox(height: 24),
                    Expanded(child: _buildPieChartCard()),
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
        _buildLineGraphCard(),
        const SizedBox(height: 24),
        _buildPieChartCard(),
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
                const Text('Live Road Health Map', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  children: [
                    _buildMapLegendItem(Colors.green, 'Good Road'),
                    const SizedBox(width: 16),
                    _buildMapLegendItem(Colors.orange, 'Slightly Bad'),
                    const SizedBox(width: 16),
                    _buildMapLegendItem(Colors.redAccent, 'Pothole'),
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

  Widget _buildPieChartCard() {
    final flags = _filteredHealthFlags;
    double cleanVal = flags.where((f) =>
      f.className.toLowerCase().contains('good') ||
      f.displayClass.toLowerCase().contains('good') ||
      f.status == 'Resolved' ||
      f.status == 'Deflagged'
    ).length.toDouble();
    double slightVal = flags.where((f) =>
      (f.className.toLowerCase().contains('bad') || f.displayClass.toLowerCase().contains('bad')) &&
      f.status != 'Resolved' &&
      f.status != 'Deflagged'
    ).length.toDouble();
    double dirtyVal = flags.where((f) =>
      (f.className.toLowerCase().contains('pothole') || f.displayClass.toLowerCase().contains('pothole')) &&
      f.status != 'Resolved' &&
      f.status != 'Deflagged'
    ).length.toDouble();

    double total = cleanVal + slightVal + dirtyVal;

    return Container(
      height: 320,
      padding: const EdgeInsets.all(20),
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
          const Text('Road Health Distribution', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 30,
                      sections: total == 0
                          ? [
                              PieChartSectionData(
                                color: Colors.grey.shade200,
                                value: 1,
                                showTitle: false,
                                radius: 36,
                              ),
                            ]
                          : [
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
                                  color: Colors.redAccent,
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
                    _buildLegendItem(Colors.green, 'Good Road (${cleanVal.toInt()})'),
                    const SizedBox(height: 8),
                    _buildLegendItem(Colors.orange, 'Slightly Bad (${slightVal.toInt()})'),
                    const SizedBox(height: 8),
                    _buildLegendItem(Colors.redAccent, 'Pothole (${dirtyVal.toInt()})'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildLineGraphCard() {
    final now = DateTime.now();
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final List<Map<String, dynamic>> dayStats = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final label = dayNames[d.weekday - 1];
      final daySpots = _filteredHealthFlags.where((f) {
        DateTime? dt;
        try { dt = DateTime.parse(f.timestamp); } catch (_) {}
        if (dt == null) return false;
        return dt.year == d.year && dt.month == d.month && dt.day == d.day;
      }).toList();

      double health;
      if (daySpots.isNotEmpty) {
        final goodCount = daySpots.where((f) =>
          f.className.toLowerCase().contains('good') ||
          f.displayClass.toLowerCase().contains('good') ||
          f.status == 'Resolved' ||
          f.status == 'Deflagged'
        ).length;
        health = (goodCount / daySpots.length) * 100.0;
      } else {
        final cumSpots = _filteredHealthFlags.where((f) {
          DateTime? dt;
          try { dt = DateTime.parse(f.timestamp); } catch (_) {}
          if (dt == null) return false;
          return dt.isBefore(d.add(const Duration(days: 1)));
        }).toList();

        if (cumSpots.isNotEmpty) {
          final goodCount = cumSpots.where((f) =>
            f.className.toLowerCase().contains('good') ||
            f.displayClass.toLowerCase().contains('good') ||
            f.status == 'Resolved' ||
            f.status == 'Deflagged'
          ).length;
          health = (goodCount / cumSpots.length) * 100.0;
        } else {
          health = 100.0;
        }
      }
      return {
        'label': label,
        'value': health.clamp(0.0, 100.0),
      };
    });

    return Container(
      height: 320,
      padding: const EdgeInsets.all(20),
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
          const Text(
            'Health Trend Over Time',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
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
                        return Text('${value.toInt()}%', style: TextStyle(color: Colors.grey.shade600, fontSize: 10));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < dayStats.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              dayStats[idx]['label'] as String,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                            ),
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
                    spots: List.generate(dayStats.length, (i) => FlSpot(i.toDouble(), dayStats[i]['value'] as double)),
                    isCurved: true,
                    color: const Color(0xFF0F5132),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF0F5132).withOpacity(0.08),
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
    List<Polyline> routePolylines = [];

    // Real-time Vehicle Route Tracing & Road Health Color Mapping
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

    final customTrashMarkers = _getOrCreateHealthMarkers(_filteredHealthFlags);

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
            ...WardZoneService.instance.buildLayers(
              selectedWard: _selectedWard?.name,
            ),
            MarkerLayer(
              markers: _vehicles.where((v) => v.currentLocation != null).map((vehicle) {
                  return Marker(
                    point: vehicle.currentLocation!, width: 40, height: 40,
                    child: GestureDetector(
                      onTap: () => _selectVehicle(vehicle),
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
            Builder(
              builder: (context) {
                final camera = MapCamera.of(context);
                final hasSpecificWard = _selectedWard != null && _selectedWard!.name != 'All Wards';
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

