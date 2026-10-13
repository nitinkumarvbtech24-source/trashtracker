import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vehicle.dart';
import '../models/ward.dart';
import '../models/zone.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../mock_data.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import '../services/map_cache_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'garbage_spots_screen.dart';
import '../services/role_service.dart';
import '../constants.dart';
import '../widgets/trash_pinpoint_marker.dart';
import '../services/ward_zone_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  bool _isGettingLocation = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  String _selectedRole = 'Master Admin';
  String _selectedZone = 'All Zones';
  String _selectedWard = 'All Wards';
  DateTime _selectedDate = DateTime.now();

  List<Vehicle> _vehicles = [];
  Vehicle? _selectedFleetVehicle;
  List<Ward> _wardsList = [];
  List<Zone> _zonesList = [];
  List<Map<String, dynamic>> _trashSpots = [];
  StreamSubscription<QuerySnapshot>? _vehiclesSub;
  StreamSubscription<QuerySnapshot>? _wardsSub;
  StreamSubscription<QuerySnapshot>? _zonesSub;
  StreamSubscription<QuerySnapshot>? _liveTrackingSub;
  StreamSubscription<QuerySnapshot>? _trashSub;
  bool _isFullScreenMap = false;
  bool _initialMapCentered = false;
  Map<String, Map<String, dynamic>> _liveTrackingData = {};
  int _bottomNavIndex = 0;

  @override
  void initState() {
    super.initState();
    WardZoneService.instance.init();
    WardZoneService.instance.notifier.addListener(_onWardZoneUpdate);
    _fetchDataFromFirestore();
    _startLiveTrackingListener();
  }

  void _onWardZoneUpdate() {
    if (mounted) setState(() {});
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
        
        // Auto-select first vehicle if none selected for fleet view
        if (_selectedFleetVehicle == null && _vehicles.isNotEmpty) {
          _selectedFleetVehicle = _vehicles.first;
        } else if (_selectedFleetVehicle != null) {
          final idx = _vehicles.indexWhere((v) => v.id == _selectedFleetVehicle!.id);
          if (idx != -1) _selectedFleetVehicle = _vehicles[idx];
        }
      });
    });

    _wardsSub = FirebaseFirestore.instance.collection('wards').snapshots().listen((snapshot) {
      final wards = snapshot.docs.map((doc) => Ward.fromJson(doc.id, doc.data())).toList();
      if (!mounted) return;
      setState(() => _wardsList = wards);
    });

    _zonesSub = FirebaseFirestore.instance.collection('zones').snapshots().listen((snapshot) {
      final zones = snapshot.docs.map((doc) => Zone.fromJson(doc.id, doc.data())).toList();
      if (!mounted) return;
      setState(() => _zonesList = zones);
    });
  }

  void _startLiveTrackingListener() {
    _liveTrackingSub = FirebaseFirestore.instance.collection('live_tracking').snapshots().listen((snapshot) {
      bool changed = false;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        _liveTrackingData[doc.id] = data;
        
        final lat = data['lat'] as double?;
        final lng = data['lng'] as double?;
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

    _trashSub = FirebaseFirestore.instance.collection('trash_spots').snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _trashSpots = snapshot.docs.where((doc) {
            final data = doc.data();
            final mv = data['model_version'] ?? data['modelVersion'];
            if (mv != null) {
              final s = mv.toString().toLowerCase().trim();
              if (s != MODEL_VERSION.toString() && s != 'v$MODEL_VERSION') return false;
            } else {
              return false;
            }
            final status = data['status'] ?? 'Flagged';
            final roadStatus = data['road_status'] ?? '';
            return status != 'Resolved' && status != 'Deflagged' && roadStatus == 'Trash Detected';
          }).map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });

        if (!_initialMapCentered && _trashSpots.isNotEmpty) {
          _initialMapCentered = true;
          try {
            final firstLat = (_trashSpots.first['lat'] as num).toDouble();
            final firstLng = (_trashSpots.first['lng'] as num).toDouble();
            _mapController.move(LatLng(firstLat, firstLng), 14.0);
          } catch (_) {}
        }
      }
    });
  }

  @override
  void dispose() {
    WardZoneService.instance.notifier.removeListener(_onWardZoneUpdate);
    _liveTrackingSub?.cancel();
    _vehiclesSub?.cancel();
    _wardsSub?.cancel();
    _zonesSub?.cancel();
    _trashSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

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

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1');
      final response = await http.get(url, headers: {'User-Agent': 'com.nitin.trashtracker'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          final newLocation = LatLng(lat, lon);
          _mapController.move(newLocation, 14.0);
          setState(() {
            _currentLocation = newLocation;
          });
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Place not found')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  List<Vehicle> get _filteredVehicles {
    final bool hasAllAccess = RoleService.hasAllAccess('Master Dashboard');
    final List<String> allowedWards = RoleService.getAllowedWardsForModule('Master Dashboard');
    final List<String> allowedZones = RoleService.getAllowedZonesForModule('Master Dashboard');

    return _vehicles.where((v) {
      if (!hasAllAccess && !allowedWards.contains('All Wards') && !allowedZones.contains('All Zones')) {
        bool isAllowed = allowedWards.contains(v.assignedWard);
        if (!isAllowed) {
          for (String zName in allowedZones) {
            try {
              final zone = _zonesList.firstWhere((z) => z.name == zName);
              final ward = _wardsList.firstWhere((w) => w.name == v.assignedWard);
              if (_isWardInZone(ward, zone)) {
                isAllowed = true;
                break;
              }
            } catch (_) {}
          }
        }
        if (!isAllowed) return false;
      }

      if (_selectedWard != 'All Wards' && v.assignedWard != _selectedWard) return false;
      if (_selectedZone != 'All Zones' && _selectedWard == 'All Wards') {
        try {
          final zone = _zonesList.firstWhere((z) => z.name == _selectedZone);
          final ward = _wardsList.firstWhere((w) => w.name == v.assignedWard);
          if (!_isWardInZone(ward, zone)) return false;
        } catch (_) {}
      }
      return true;
    }).toList();
  }

  void _updateMapForSelection() {
    List<LatLng> points = [];
    var filteredVehicles = _filteredVehicles;
    
    // 1. Gather points from Ward if selected
    if (_selectedWard != 'All Wards') {
      try {
        final ward = _wardsList.firstWhere((w) => w.name == _selectedWard);
        if (ward.boundary.isNotEmpty) points.addAll(ward.boundary);
        if (ward.optimizedRoute != null) points.addAll(ward.optimizedRoute!);
      } catch (_) {}
    } else if (_selectedZone != 'All Zones') {
      // 2. Gather points from Zone if selected (and no specific ward is selected)
      try {
        final zone = _zonesList.firstWhere((z) => z.name == _selectedZone);
        if (zone.boundary.isNotEmpty) points.addAll(zone.boundary);
      } catch (_) {}
    }

    // 3. Always gather active vehicle points
    for (var v in filteredVehicles) {
      if (v.assignedRoute != null) points.addAll(v.assignedRoute!);
      if (v.assignedCheckpoints != null) points.addAll(v.assignedCheckpoints!);
      if (v.currentLocation != null) points.add(v.currentLocation!);
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
    } else {
      _mapController.move(mapCenter, mapZoom);
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
      );

      final newLocation = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _currentLocation = newLocation;
      });

      _mapController.move(newLocation, 15.0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
        });
      }
    }
  }

  void _centerOnCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
    } else if (_filteredVehicles.isNotEmpty && _filteredVehicles.first.currentLocation != null) {
      _mapController.move(_filteredVehicles.first.currentLocation!, 15.0);
    }
  }

  void _showTrashPopup(Map<String, dynamic> spot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          spot['road_status'] ?? 'Dirty Spot',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spot['image_url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(spot['image_url'], headers: const {"ngrok-skip-browser-warning": "true"}, height: 200, width: double.infinity, fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),
            Text(
              "Confidence: ${((spot['confidence'] ?? 0.0) * 100).toStringAsFixed(1)}%",
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              "Status: ${spot['status']}",
              style: TextStyle(
                color: spot['status'] == 'Flagged' ? Colors.redAccent : Colors.greenAccent,
                fontWeight: FontWeight.bold
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreenMap) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.arrowLeft, color: Color(0xFF1E293B)),
                    onPressed: () => setState(() => _isFullScreenMap = false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _buildFilterRow()),
                ],
              ),
            ),
            Expanded(child: Padding(padding: const EdgeInsets.all(16), child: _buildMapCard(isFullScreen: true))),
          ],
        ),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: Colors.transparent, // Background handled by parent Row
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilterRow(),
            const SizedBox(height: 16),
            Expanded(
              child: _bottomNavIndex == 0 
                  ? _buildHomepageContent(isMobile) 
                  : _buildRegisteredFleetContent(isMobile),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: (index) => setState(() => _bottomNavIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Homepage'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.truck), label: 'Registered Fleet'),
        ],
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF006341),
        unselectedItemColor: Colors.grey,
        elevation: 8,
      ),
    );
  }

  Widget _buildHomepageContent(bool isMobile) {
    if (isMobile) {
      return ListView(
        children: [
          _buildKpiGrid(true),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: _buildMapCard(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 380,
            child: _buildRegisteredVehiclesTable(),
          ),
          const SizedBox(height: 16),
          _buildCleanlinessChartCard(isMobile: true),
          const SizedBox(height: 16),
          _buildHealthChartCard(isMobile: true),
          const SizedBox(height: 24),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKpiGrid(false),
        const SizedBox(height: 16),
        Expanded(
          flex: 5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: _buildMapCard(),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: _buildRegisteredVehiclesTable(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          flex: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildCleanlinessChartCard()),
              const SizedBox(width: 16),
              Expanded(child: _buildHealthChartCard()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegisteredFleetContent([bool isMobile = false]) {
    if (isMobile) {
      return ListView(
        children: [
          // Mobile vehicle selector card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Select Vehicle (${_filteredVehicles.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                    if (_selectedFleetVehicle != null)
                      Text(_selectedFleetVehicle!.vehicleNumber, style: const TextStyle(color: Color(0xFF006341), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _filteredVehicles.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final v = _filteredVehicles[index];
                      final isSelected = _selectedFleetVehicle?.id == v.id;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedFleetVehicle = v),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFE8F5E9) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isSelected ? const Color(0xFF006341) : Colors.grey.shade300, width: isSelected ? 1.5 : 1),
                          ),
                          child: Row(
                            children: [
                              Icon(LucideIcons.truck, size: 16, color: isSelected ? const Color(0xFF006341) : Colors.grey),
                              const SizedBox(width: 6),
                              Text(v.vehicleNumber.isNotEmpty ? v.vehicleNumber : v.id, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? const Color(0xFF006341) : Colors.black87)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_selectedFleetVehicle != null) ...[
            _buildVehicleHeader(_selectedFleetVehicle!, true),
            const SizedBox(height: 14),
            _buildFleetKpis(_selectedFleetVehicle!, true),
            const SizedBox(height: 14),
            SizedBox(
              height: 300,
              child: _buildFleetMiddleSection(_selectedFleetVehicle!),
            ),
            const SizedBox(height: 14),
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(LucideIcons.database, color: Colors.white, size: 18),
                    label: const Text('Database', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF006341),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(LucideIcons.map, color: Color(0xFF006341), size: 16),
                        label: const Text('Trip Details', style: TextStyle(color: Color(0xFF006341), fontSize: 13, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF006341)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(LucideIcons.barChart2, color: Color(0xFF006341), size: 16),
                        label: const Text('Analytics', style: TextStyle(color: Color(0xFF006341), fontSize: 13, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF006341)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFleetLeftSidebar(),
        const SizedBox(width: 24),
        Expanded(
          child: _selectedFleetVehicle == null 
              ? const Center(child: CircularProgressIndicator())
              : _buildFleetRightContent(),
        ),
      ],
    );
  }

  Widget _buildFleetLeftSidebar() {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Vehicles in ${_selectedWard == 'All Wards' ? 'All Wards' : _selectedWard} (${_filteredVehicles.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search vehicle...',
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                    suffixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.filter_list, size: 20),
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: _filteredVehicles.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final vehicle = _filteredVehicles[index];
                bool isSelected = _selectedFleetVehicle?.id == vehicle.id;
                
                String stateText = 'Offline';
                Color stateColor = Colors.grey;
                if (vehicle.isActive) {
                  stateText = vehicle.currentLocation != null ? 'Moving' : 'Idle';
                  stateColor = vehicle.currentLocation != null ? Colors.green : Colors.blue;
                }

                return GestureDetector(
                  onTap: () => setState(() => _selectedFleetVehicle = vehicle),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFE8F5E9) : Colors.white,
                      border: Border.all(color: isSelected ? const Color(0xFF006341) : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.truck, color: Color(0xFF006341), size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(vehicle.vehicleNumber.isNotEmpty ? vehicle.vehicleNumber : vehicle.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black)),
                              const SizedBox(height: 4),
                              Text('Driver: ${vehicle.driverName.isNotEmpty ? vehicle.driverName : 'Unassigned'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                Container(width: 8, height: 8, decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle)),
                                const SizedBox(width: 4),
                                Text(stateText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text('32 km/h', style: TextStyle(fontSize: 12, color: Colors.grey)), // Mock speed
                          ],
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black54),
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Center(child: Text('Pagination Controls Placeholder', style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildFleetRightContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVehicleHeader(_selectedFleetVehicle!),
        const SizedBox(height: 16),
        _buildFleetKpis(_selectedFleetVehicle!),
        const SizedBox(height: 16),
        Expanded(
          child: _buildFleetMiddleSection(_selectedFleetVehicle!),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(LucideIcons.database, color: Colors.white),
                label: const Text('Database', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006341),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(LucideIcons.map, color: Color(0xFF006341)),
                label: const Text('Trip Details', style: TextStyle(color: Color(0xFF006341), fontSize: 16, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF006341)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(LucideIcons.barChart2, color: Color(0xFF006341)),
                label: const Text('Analytics', style: TextStyle(color: Color(0xFF006341), fontSize: 16, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF006341)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFleetKpis(Vehicle vehicle, [bool isMobile = false]) {
    final c1 = _buildNewKpiCard('KM\'s Traveled', '32.4', 'km', LucideIcons.mapPin, Colors.teal, '8%', isPositive: true, isMobile: isMobile);
    final c2 = _buildNewKpiCard('Potholes', '18', '', Icons.warning_rounded, Colors.orange, '12%', isPositive: true, isMobile: isMobile);
    final c3 = _buildNewKpiCard('Road Litter', '24', '', LucideIcons.trash2, Colors.teal, '20%', isPositive: true, isMobile: isMobile);
    final c4 = _buildNewKpiCard('Anomalies', '2', '', Icons.report_problem, Colors.red, '5%', isPositive: false, isMobile: isMobile);
    final c5 = _buildNewKpiCard('Active Time', '5h 42m', '', LucideIcons.clock, Colors.teal, '10%', isPositive: true, isMobile: isMobile);

    if (isMobile) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: c1),
              const SizedBox(width: 8),
              Expanded(child: c2),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: c3),
              const SizedBox(width: 8),
              Expanded(child: c4),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: c5),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: c1),
        const SizedBox(width: 16),
        Expanded(child: c2),
        const SizedBox(width: 16),
        Expanded(child: c3),
        const SizedBox(width: 16),
        Expanded(child: c4),
        const SizedBox(width: 16),
        Expanded(child: c5),
      ],
    );
  }

  Widget _buildFleetMiddleSection(Vehicle vehicle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: Container(
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Live Tracking', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(LucideIcons.maximize2, size: 12, color: Color(0xFF006341)),
                        label: const Text('Enlarge', style: TextStyle(color: Color(0xFF006341), fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: const Size(0, 32),
                        ),
                      )
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          Container(color: Colors.grey.shade100, child: const Center(child: Text('Map View Placeholder'))), // Placeholder for actual FlutterMap
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildFleetLegendItem(Colors.green, 'Moving'),
                      _buildFleetLegendItem(Colors.blue, 'Idle'),
                      _buildFleetLegendItem(Colors.red, 'Stopped'),
                      _buildFleetLegendItem(Colors.orange, 'Maintenance'),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFleetLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );
  }


  Widget _buildVehicleHeader(Vehicle vehicle, [bool isMobile = false]) {
    final buttons = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.phone, color: Color(0xFF006341), size: 16),
            label: const Text('Call Driver', style: TextStyle(color: Color(0xFF006341), fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.headset_mic, color: Color(0xFF006341), size: 16),
            label: const Text('Call Authority', style: TextStyle(color: Color(0xFF006341), fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                  child: const Icon(LucideIcons.truck, size: 22, color: Color(0xFF006341)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              vehicle.vehicleNumber.isNotEmpty ? vehicle.vehicleNumber : vehicle.id,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.green), borderRadius: BorderRadius.circular(4)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                                const SizedBox(width: 4),
                                const Text('Moving', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Driver: ${vehicle.driverName.isNotEmpty ? vehicle.driverName : 'Unassigned'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            buttons,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
            child: const Icon(LucideIcons.truck, size: 32, color: Color(0xFF006341)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(vehicle.vehicleNumber.isNotEmpty ? vehicle.vehicleNumber : vehicle.id, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.green), borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          const Text('Moving', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Driver: ${vehicle.driverName.isNotEmpty ? vehicle.driverName : 'Unassigned'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    const SizedBox(width: 16),
                    Text('|   Vehicle Type: Compactor', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    const SizedBox(width: 16),
                    Text('|   Fuel Type: Diesel', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    const SizedBox(width: 16),
                    Text('|   Model: Tata 1613', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.phone, color: Color(0xFF006341), size: 18),
            label: const Text('Call Driver', style: TextStyle(color: Color(0xFF006341))),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.headset_mic, color: Color(0xFF006341), size: 18),
            label: const Text('Call Authority', style: TextStyle(color: Color(0xFF006341))),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }




  Widget _buildFilterRow() {
    final bool hasAllAccess = RoleService.hasAllAccess('Master Dashboard');
    final List<String> allowedZones = RoleService.getAllowedZonesForModule('Master Dashboard');
    final List<String> allowedWards = RoleService.getAllowedWardsForModule('Master Dashboard');

    List<String> zItems = (hasAllAccess ? _zonesList.map((z) => z.name).toList() : allowedZones).toList();
    if (zItems.length > 1 && !zItems.contains('All Zones')) {
      zItems.insert(0, 'All Zones');
    }
    final zones = zItems.isEmpty ? ['All Zones'] : zItems;

    // Auto-correct _selectedZone without calling setState during build
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

    List<String> wItems = _wardsList.where((w) {
      if (!hasAllAccess && !allowedWards.contains('All Wards') && !allowedWards.contains(w.name)) return false;
      if (validSelectedZone == 'All Zones') return true;
      try {
        final z = _zonesList.firstWhere((zm) => zm.name == validSelectedZone);
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
              setState(() => _selectedZone = val);
              _updateMapForSelection();
            }),
            const SizedBox(width: 16),
            _buildDropdown('Ward', validSelectedWard, wards, (val) {
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
            const SizedBox(width: 16),
            const Icon(LucideIcons.refreshCw, color: Color(0xFF64748B), size: 20),
            const SizedBox(width: 24),
            _buildDatePicker(),
          ],
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF006341),
                  onPrimary: Colors.white,
                  onSurface: Color(0xFF1E293B),
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
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(8),
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
                    Text(
                      '${_selectedDate.day} ${_getMonthName(_selectedDate.month)} ${_selectedDate.year}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 24),
            const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B)),
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
            const SizedBox(width: 24),
            const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiGrid([bool isMobile = false]) {
    final card1 = _buildNewKpiCard('Total Fleet', '${_filteredVehicles.length}', 'Vehicles', LucideIcons.truck, const Color(0xFF198754), '+ 12%', isMobile: isMobile);
    final card2 = InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const GarbageSpotsScreen()));
      },
      child: _buildNewKpiCard('Garbage Spots', '${_trashSpots.length}', 'Spots', LucideIcons.trash, const Color(0xFF198754), '+ 18%', isMobile: isMobile),
    );
    final card3 = _buildNewKpiCard('Potholes', '215', 'Potholes', LucideIcons.alertTriangle, const Color(0xFFFFC107), '+ 15%', isMobile: isMobile);
    final card4 = _buildNewKpiCard('Vehicle Anomalies', '18', 'Detected', LucideIcons.alertOctagon, const Color(0xFFDC3545), '- 5%', isPositive: false, isMobile: isMobile);
    final card5 = _buildNewKpiCard('Total KMs', '3,254', 'KMs', LucideIcons.mapPin, const Color(0xFF198754), '+ 10%', isMobile: isMobile);
    final card6 = _buildNewKpiCard('Active Time', '128h 42m', 'Hours', LucideIcons.clock, const Color(0xFF198754), '+ 8%', isMobile: isMobile);

    if (isMobile) {
      return Column(
        children: [
          Row(children: [Expanded(child: card1), const SizedBox(width: 10), Expanded(child: card2)]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: card3), const SizedBox(width: 10), Expanded(child: card4)]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: card5), const SizedBox(width: 10), Expanded(child: card6)]),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: card1),
        const SizedBox(width: 16),
        Expanded(child: card2),
        const SizedBox(width: 16),
        Expanded(child: card3),
        const SizedBox(width: 16),
        Expanded(child: card4),
        const SizedBox(width: 16),
        Expanded(child: card5),
        const SizedBox(width: 16),
        Expanded(child: card6),
      ],
    );
  }

  Widget _buildNewKpiCard(String title, String value, String unit, IconData icon, Color iconColor, String trend, {bool isPositive = true, bool isMobile = false}) {
    return Container(
      height: isMobile ? 85 : 110,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: isMobile ? 36 : 46,
            height: isMobile ? 36 : 46,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: isMobile ? 18 : 24),
          ),
          SizedBox(width: isMobile ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: isMobile ? 9 : 11,
                    color: Colors.black54,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: isMobile ? 18 : 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      trend,
                      style: TextStyle(
                        fontSize: isMobile ? 8 : 10,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? const Color(0xFF198754) : const Color(0xFFDC3545),
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

  Widget _buildMapCard({bool isFullScreen = false}) {
    // --- Compute Polylines and Markers from _trashSpots ---
    Map<String, List<Map<String, dynamic>>> sessions = {};
    for (var spot in _trashSpots) {
      if (spot['session_id'] != null) {
        sessions.putIfAbsent(spot['session_id'], () => []).add(spot);
      }
    }

    List<Polyline> routePolylines = [];
    List<Marker> customTrashMarkers = [];

    // Process sessions into polylines
    sessions.forEach((sessionId, list) {
      list.sort((a, b) {
        final tA = a['timestamp'] as Timestamp?;
        final tB = b['timestamp'] as Timestamp?;
        if (tA == null && tB == null) return 0;
        if (tA == null) return -1;
        if (tB == null) return 1;
        return tA.compareTo(tB);
      });

      for (int i = 0; i < list.length - 1; i++) {
        final start = LatLng(list[i]['lat'] as double, list[i]['lng'] as double);
        final end = LatLng(list[i + 1]['lat'] as double, list[i + 1]['lng'] as double);
        final status = list[i + 1]['road_status'];
        
        Color segmentColor = Colors.greenAccent;
        if (status == 'Very Dirty Road' || status == 'Trash Detected') segmentColor = Colors.redAccent;
        else if (status == 'Slightly Dirty Road') segmentColor = Colors.yellowAccent;
        
        routePolylines.add(Polyline(
          points: [start, end],
          color: segmentColor,
          strokeWidth: 6.0,
        ));
      }
    });

    // Process clustered markers for trash spots
    const double clusterDist = 0.00018;
    final List<List<Map<String, dynamic>>> clusters = [];

    for (var spot in _trashSpots) {
      final lat = (spot['lat'] as num).toDouble();
      final lng = (spot['lng'] as num).toDouble();
      bool added = false;
      for (var c in clusters) {
        final cLat = (c.first['lat'] as num).toDouble();
        final cLng = (c.first['lng'] as num).toDouble();
        if ((lat - cLat).abs() < clusterDist && (lng - cLng).abs() < clusterDist) {
          c.add(spot);
          added = true;
          break;
        }
      }
      if (!added) {
        clusters.add([spot]);
      }
    }

    for (var cluster in clusters) {
      final spot = cluster.first;
      final lat = (spot['lat'] as num).toDouble();
      final lng = (spot['lng'] as num).toDouble();
      final isVeryDirty = cluster.any((s) => s['road_status'] == 'Very Dirty Road' || s['road_status'] == 'Trash Detected');

      customTrashMarkers.add(Marker(
        point: LatLng(lat, lng),
        width: 38,
        height: 46,
        alignment: Alignment.topCenter,
        child: TrashPinpointWidget(
          count: cluster.length,
          isVeryDirty: isVeryDirty,
          onTap: () => _showTrashPopup(spot),
        ),
      ));
    }
    // ----------------------------------------------------

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Live Map - Ward 45',
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isFullScreenMap = !_isFullScreenMap;
                    });
                  },
                  icon: Icon(isFullScreen ? LucideIcons.minimize2 : LucideIcons.maximize2, size: 14, color: const Color(0xFF006341)),
                  label: Text(isFullScreen ? 'Minimize' : 'Enlarge', style: const TextStyle(color: Color(0xFF006341))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                )
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _trashSpots.isNotEmpty
                          ? LatLng((_trashSpots.first['lat'] as num).toDouble(), (_trashSpots.first['lng'] as num).toDouble())
                          : (_filteredVehicles.isNotEmpty && _filteredVehicles.first.currentLocation != null
                              ? _filteredVehicles.first.currentLocation!
                              : const LatLng(13.0568, 77.5027)),
                      initialZoom: 13.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.nitin.trashtracker',
                        tileProvider: kIsWeb ? null : CachedTileProvider(store: MapCacheService.store),
                      ),
                      ...WardZoneService.instance.buildLayers(
                        selectedZone: _selectedZone,
                        selectedWard: _selectedWard,
                      ),
                      // Real-time markers will go here
                      MarkerLayer(
                        markers: [
                          if (_currentLocation != null)
                            Marker(
                              point: _currentLocation!,
                              width: 20,
                              height: 20,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 12, spreadRadius: 4),
                                  ]
                                ),
                              ),
                            ),
                          ..._filteredVehicles.where((v) => v.currentLocation != null && v.isRunning).map((vehicle) {
                            return Marker(
                              point: vehicle.currentLocation!, width: 100, height: 60,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.white)
                                    ),
                                    child: Text(vehicle.vehicleNumber.isNotEmpty ? vehicle.vehicleNumber : vehicle.id, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Color(vehicle.stateColorValue),
                                      shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))]
                                    ),
                                    child: const Icon(LucideIcons.truck, color: Colors.white, size: 14),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                      if (routePolylines.isNotEmpty)
                        PolylineLayer(
                          polylines: routePolylines,
                        ),
                      if (customTrashMarkers.isNotEmpty)
                        MarkerLayer(
                          markers: customTrashMarkers,
                        )
                    ],
                  ),
                  
                  // Search Bar Overlay
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search place (Nominatim API)',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(LucideIcons.search, color: Color(0xFF94A3B8)),
                          suffixIcon: _isSearching 
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : IconButton(
                                icon: const Icon(LucideIcons.arrowRight, color: Color(0xFF3B82F6)),
                                onPressed: _searchPlace,
                              ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        onSubmitted: (_) => _searchPlace(),
                      ),
                    ),
                  ),
                  
                  // Map Legend
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: Row(
                        children: [
                          _buildLegendItem(Colors.green, 'Moving'),
                          const SizedBox(width: 12),
                          _buildLegendItem(Colors.grey, 'Idle'),
                          const SizedBox(width: 12),
                          _buildLegendItem(Colors.red, 'Stopped'),
                          const SizedBox(width: 12),
                          _buildLegendItem(Colors.orange, 'Maintenance'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildRegisteredVehiclesTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.bold),
                    children: [
                      const TextSpan(text: 'Registered Vehicles '),
                      TextSpan(text: '(${_filteredVehicles.length})', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.normal)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 200,
                      height: 36,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const TextField(
                        decoration: InputDecoration(
                          hintText: 'Search vehicle...',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          prefixIcon: Icon(LucideIcons.search, size: 16, color: Color(0xFF94A3B8)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(LucideIcons.filter, size: 16, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(const Color(0xFFF8FAFC)),
                  columns: const [
                    DataColumn(label: Text('Vehicle Number', style: TextStyle(color: Color(0xFF64748B), fontSize: 12))),
                    DataColumn(label: Text('Driver Name', style: TextStyle(color: Color(0xFF64748B), fontSize: 12))),
                    DataColumn(label: Text('Contact', style: TextStyle(color: Color(0xFF64748B), fontSize: 12))),
                    DataColumn(label: Text('Zone', style: TextStyle(color: Color(0xFF64748B), fontSize: 12))),
                    DataColumn(label: Text('Ward', style: TextStyle(color: Color(0xFF64748B), fontSize: 12))),
                    DataColumn(label: Text('Status', style: TextStyle(color: Color(0xFF64748B), fontSize: 12))),
                    DataColumn(label: Text('Details', style: TextStyle(color: Color(0xFF64748B), fontSize: 12))),
                  ],
                  rows: _filteredVehicles.isEmpty 
                      ? [
                          const DataRow(cells: [
                            DataCell(Text('No vehicles found')),
                            DataCell(Text('')),
                            DataCell(Text('')),
                            DataCell(Text('')),
                            DataCell(Text('')),
                            DataCell(Text('')),
                            DataCell(Text('')),
                          ])
                        ]
                      : _filteredVehicles.map((v) {
                          return _buildTableRow(
                            v,
                            v.vehicleNumber.isNotEmpty ? v.vehicleNumber : v.id,
                            v.driverName.isNotEmpty ? v.driverName : 'Unassigned',
                            v.phoneNumber ?? '+91 98765 43210',
                            _getZoneForWard(v.assignedWard),
                            v.assignedWard,
                            v.statusText,
                            Color(v.stateColorValue),
                          );
                        }).toList(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Showing ${_filteredVehicles.length} of ${_filteredVehicles.length} vehicles', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              ],
            ),
          )
        ],
      ),
    );
  }

  String _getZoneForWard(String wardName) {
    if (wardName == 'Unassigned' || wardName.isEmpty) return 'Unassigned';
    final wardObj = _wardsList.firstWhere((w) => w.name == wardName, orElse: () => Ward(id: '', name: '', boundary: []));
    if (wardObj.boundary.isEmpty) return 'Unknown';
    for (var z in _zonesList) {
      if (z.boundary.isNotEmpty && _isWardInZone(wardObj, z)) {
        return z.name;
      }
    }
    return 'Unknown';
  }

  DataRow _buildTableRow(Vehicle vehicle, String id, String driver, String phone, String zone, String ward, String status, Color statusColor) {
    return DataRow(cells: [
      DataCell(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.truck, size: 16, color: Color(0xFF006341)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black), overflow: TextOverflow.ellipsis),
          ),
        ],
      )),
      DataCell(Text(driver, style: const TextStyle(fontSize: 12, color: Colors.black))),
      DataCell(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(phone, style: const TextStyle(fontSize: 12, color: Colors.black)),
          const SizedBox(width: 8),
          const Icon(LucideIcons.phone, size: 16, color: Color(0xFF006341)),
        ],
      )),
      DataCell(Text(zone, style: const TextStyle(fontSize: 12, color: Colors.black))),
      DataCell(Text(ward, style: const TextStyle(fontSize: 12, color: Colors.black))),
      DataCell(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(status, style: const TextStyle(fontSize: 12, color: Colors.black)),
        ],
      )),
      DataCell(
        IconButton(
          icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF64748B)),
          onPressed: () {
            setState(() {
              _selectedFleetVehicle = vehicle;
              _bottomNavIndex = 1; // 1 represents Registered Fleet tab
            });
          },
        ),
      ),
    ]);
  }

  Widget _buildCleanlinessChartCard({bool isMobile = false}) {
    final donut = SizedBox(
      width: isMobile ? 110 : 150,
      height: isMobile ? 110 : 150,
      child: Stack(
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 0,
              centerSpaceRadius: isMobile ? 35 : 50,
              sections: [
                PieChartSectionData(color: const Color(0xFF198754), value: 40, showTitle: false, radius: isMobile ? 16 : 20),
                PieChartSectionData(color: const Color(0xFFFFC107), value: 35, showTitle: false, radius: isMobile ? 16 : 20),
                PieChartSectionData(color: const Color(0xFFDC3545), value: 25, showTitle: false, radius: isMobile ? 16 : 20),
              ],
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('342', style: TextStyle(fontSize: isMobile ? 18 : 24, fontWeight: FontWeight.bold)),
                Text('Total Spots', style: TextStyle(fontSize: isMobile ? 9 : 10, color: const Color(0xFF64748B))),
              ],
            ),
          )
        ],
      ),
    );

    final legend = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildChartLegendItem('Clean Roads', '40%', '(137)', const Color(0xFF198754)),
        const SizedBox(height: 10),
        _buildChartLegendItem('Slightly Dirty', '35%', '(120)', const Color(0xFFFFC107)),
        const SizedBox(height: 10),
        _buildChartLegendItem('Very Dirty', '25%', '(85)', const Color(0xFFDC3545)),
      ],
    );

    final lineChartWidget = SizedBox(
      height: isMobile ? 110 : 150,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: const Color(0xFFE2E8F0), strokeWidth: 1, dashArray: [4, 4])),
          titlesData: FlTitlesData(
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (value, meta) {
              const dates = ['8 May', '9 May', '10 May', '11 May', '12 May', '13 May', '14 May'];
              if (value.toInt() >= 0 && value.toInt() < dates.length) {
                return Text(dates[value.toInt()], style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)));
              }
              return const Text('');
            })),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (value, meta) {
              return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)));
            })),
          ),
          borderData: FlBorderData(show: false),
          minX: 0, maxX: 6, minY: 0, maxY: 400,
          lineBarsData: [
            LineChartBarData(
              spots: const [FlSpot(0, 80), FlSpot(1, 120), FlSpot(2, 90), FlSpot(3, 180), FlSpot(4, 230), FlSpot(5, 180), FlSpot(6, 280)],
              isCurved: true,
              color: const Color(0xFF198754),
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: const Color(0xFF198754), strokeWidth: 2, strokeColor: Colors.white)),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
      ),
    );

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Road Cleanliness Monitor (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
            const SizedBox(height: 14),
            Row(
              children: [
                donut,
                const SizedBox(width: 14),
                Expanded(child: legend),
              ],
            ),
            const SizedBox(height: 14),
            lineChartWidget,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Road Cleanliness Monitor (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                donut,
                const SizedBox(width: 16),
                Expanded(child: legend),
                const SizedBox(width: 16),
                Expanded(child: lineChartWidget),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthChartCard({bool isMobile = false}) {
    final donut = SizedBox(
      width: isMobile ? 110 : 150,
      height: isMobile ? 110 : 150,
      child: Stack(
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 0,
              centerSpaceRadius: isMobile ? 35 : 50,
              sections: [
                PieChartSectionData(color: const Color(0xFF198754), value: 40, showTitle: false, radius: isMobile ? 16 : 20),
                PieChartSectionData(color: const Color(0xFFFFC107), value: 35, showTitle: false, radius: isMobile ? 16 : 20),
                PieChartSectionData(color: const Color(0xFFDC3545), value: 25, showTitle: false, radius: isMobile ? 16 : 20),
              ],
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('215', style: TextStyle(fontSize: isMobile ? 18 : 24, fontWeight: FontWeight.bold)),
                Text('Total Issues', style: TextStyle(fontSize: isMobile ? 9 : 10, color: const Color(0xFF64748B))),
              ],
            ),
          )
        ],
      ),
    );

    final legend = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildChartLegendItem('Good Roads', '40%', '(86)', const Color(0xFF198754)),
        const SizedBox(height: 10),
        _buildChartLegendItem('Bad Roads', '35%', '(75)', const Color(0xFFFFC107)),
        const SizedBox(height: 10),
        _buildChartLegendItem('Potholes', '25%', '(54)', const Color(0xFFDC3545)),
      ],
    );

    final lineChartWidget = SizedBox(
      height: isMobile ? 110 : 150,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: const Color(0xFFE2E8F0), strokeWidth: 1, dashArray: [4, 4])),
          titlesData: FlTitlesData(
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (value, meta) {
              const dates = ['8 May', '9 May', '10 May', '11 May', '12 May', '13 May', '14 May'];
              if (value.toInt() >= 0 && value.toInt() < dates.length) {
                return Text(dates[value.toInt()], style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)));
              }
              return const Text('');
            })),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (value, meta) {
              return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)));
            })),
          ),
          borderData: FlBorderData(show: false),
          minX: 0, maxX: 6, minY: 0, maxY: 250,
          lineBarsData: [
            LineChartBarData(
              spots: const [FlSpot(0, 100), FlSpot(1, 60), FlSpot(2, 50), FlSpot(3, 120), FlSpot(4, 90), FlSpot(5, 140), FlSpot(6, 220)],
              isCurved: true,
              color: const Color(0xFFFFC107),
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: const Color(0xFFFFC107), strokeWidth: 2, strokeColor: Colors.white)),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
      ),
    );

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Road Health Monitor (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
            const SizedBox(height: 14),
            Row(
              children: [
                donut,
                const SizedBox(width: 14),
                Expanded(child: legend),
              ],
            ),
            const SizedBox(height: 14),
            lineChartWidget,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Road Health Monitor (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                donut,
                const SizedBox(width: 16),
                Expanded(child: legend),
                const SizedBox(width: 16),
                Expanded(child: lineChartWidget),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegendItem(String label, String percent, String count, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
        Text(percent, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(width: 4),
        Text(count, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
      ],
    );
  }

}
