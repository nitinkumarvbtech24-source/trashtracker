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
  Map<String, Map<String, dynamic>> _liveTrackingData = {};
  int _bottomNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchDataFromFirestore();
    _startLiveTrackingListener();
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
            final status = data['status'] ?? 'Flagged';
            final roadStatus = data['road_status'] ?? '';
            return status != 'Resolved' && (roadStatus == 'Very Dirty Road' || roadStatus == 'Slightly Dirty Road');
          }).map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });
      }
    });
  }

  @override
  void dispose() {
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
      final response = await http.get(url, headers: {'User-Agent': 'com.example.street_aiq'});
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

    return Scaffold(
      backgroundColor: Colors.transparent, // Background handled by parent Row
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilterRow(),
            const SizedBox(height: 16),
            Expanded(
              child: _bottomNavIndex == 0 
                  ? _buildHomepageContent() 
                  : _buildRegisteredFleetContent(),
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

  Widget _buildHomepageContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKpiGrid(),
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

  Widget _buildRegisteredFleetContent() {
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

  Widget _buildFleetKpis(Vehicle vehicle) {
    return Row(
      children: [
        Expanded(child: _buildNewKpiCard('KM\'s Traveled', '32.4', 'km', LucideIcons.mapPin, Colors.teal, '8%', isPositive: true)),
        const SizedBox(width: 16),
        Expanded(child: _buildNewKpiCard('Potholes Detected', '18', '', Icons.warning_rounded, Colors.orange, '12%', isPositive: true)),
        const SizedBox(width: 16),
        Expanded(child: _buildNewKpiCard('Road Litter Spots', '24', '', LucideIcons.trash2, Colors.teal, '20%', isPositive: true)),
        const SizedBox(width: 16),
        Expanded(child: _buildNewKpiCard('Vehicle Anomalies', '2', '', Icons.report_problem, Colors.red, '5%', isPositive: false)),
        const SizedBox(width: 16),
        Expanded(child: _buildNewKpiCard('Active Time', '5h 42m', '', LucideIcons.clock, Colors.teal, '10%', isPositive: true)),
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


  Widget _buildVehicleHeader(Vehicle vehicle) {
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
            decoration: BoxDecoration(color: const Color(0xFFE8F5E9), shape: BoxShape.circle),
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
                    Text('|   Vehicle Type: Compactor', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)), // Mock
                    const SizedBox(width: 16),
                    Text('|   Fuel Type: Diesel', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)), // Mock
                    const SizedBox(width: 16),
                    Text('|   Model: Tata 1613', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)), // Mock
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

  Widget _buildKpiGrid() {
    return Row(
      children: [
        Expanded(child: _buildNewKpiCard('Total Fleet', '${_filteredVehicles.length}', 'Vehicles', LucideIcons.truck, const Color(0xFF198754), '+ 12%')),
        const SizedBox(width: 16),
        Expanded(
          child: InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const GarbageSpotsScreen()));
            },
            child: _buildNewKpiCard('Garbage Spots Identified', '342', 'Spots', LucideIcons.trash, const Color(0xFF198754), '+ 18%'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: _buildNewKpiCard('Potholes Identified', '215', 'Potholes', LucideIcons.alertTriangle, const Color(0xFFFFC107), '+ 15%')),
        const SizedBox(width: 16),
        Expanded(child: _buildNewKpiCard('Vehicle Anomalies', '18', 'Detected', LucideIcons.alertOctagon, const Color(0xFFDC3545), '- 5%', isPositive: false)),
        const SizedBox(width: 16),
        Expanded(child: _buildNewKpiCard('Total KMs Traveled', '3,254', 'KMs', LucideIcons.mapPin, const Color(0xFF198754), '+ 10%')),
        const SizedBox(width: 16),
        Expanded(child: _buildNewKpiCard('Total Active Time', '128h 42m', 'Hours', LucideIcons.clock, const Color(0xFF198754), '+ 8%')),
      ],
    );
  }

  Widget _buildNewKpiCard(String title, String value, String unit, IconData icon, Color iconColor, String trend, {bool isPositive = true}) {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold), maxLines: 2),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_right, size: 16, color: Color(0xFF64748B)),
                      ],
                    ),
                    Text(unit, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: isPositive ? const Color(0xFF198754) : const Color(0xFFDC3545)),
              const SizedBox(width: 4),
              Expanded(child: Text('$trend from last week', style: TextStyle(fontSize: 10, color: isPositive ? const Color(0xFF198754) : const Color(0xFFDC3545)), overflow: TextOverflow.ellipsis)),
            ],
          )
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
        if (status == 'Very Dirty Road') segmentColor = Colors.redAccent;
        else if (status == 'Slightly Dirty Road') segmentColor = Colors.yellowAccent;
        
        routePolylines.add(Polyline(
          points: [start, end],
          color: segmentColor,
          strokeWidth: 6.0,
        ));
      }
    });

    // Process markers for all spots
    for (var spot in _trashSpots) {
      final lat = spot['lat'] as double;
      final lng = spot['lng'] as double;
      final status = spot['road_status'];
      final pointType = spot['point_type'];
      final isCleared = spot['status'] == 'Cleared';

      // Start/End indicators
      if (pointType == 'start') {
        customTrashMarkers.add(Marker(
          point: LatLng(lat, lng),
          width: 30, height: 30,
          alignment: Alignment.center,
          child: const Icon(Icons.play_circle_fill, color: Colors.greenAccent, size: 28),
        ));
      } else if (pointType == 'end') {
        customTrashMarkers.add(Marker(
          point: LatLng(lat, lng),
          width: 30, height: 30,
          alignment: Alignment.center,
          child: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 28),
        ));
      }

      // Only show flags for dirty or cleared spots (no clutter for Clean spots)
      if (status != 'Clean Road' && status != 'Clean') {
        Color markerColor = isCleared ? Colors.grey : (status == 'Very Dirty Road' ? Colors.redAccent : Colors.orangeAccent);
        
        customTrashMarkers.add(Marker(
          point: LatLng(lat, lng),
          width: 40, height: 40,
          alignment: Alignment.bottomCenter, // Fix anchor point to exact location
          child: GestureDetector(
            onTap: () => _showTrashPopup(spot),
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
                      initialCenter: mapCenter, // Use default until real location loaded
                      initialZoom: mapZoom,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.street_aiq',
                        tileProvider: kIsWeb ? null : CachedTileProvider(store: MapCacheService.store),
                      ),
                      PolygonLayer(
                        polygons: [
                          ..._zonesList.where((z) => z.boundary.isNotEmpty).map((zone) {
                            bool isHighlighted = false;
                            if (_selectedZone == 'All Zones' && _selectedWard == 'All Wards') {
                              isHighlighted = true;
                            } else if (_selectedZone == zone.name && _selectedWard == 'All Wards') {
                              isHighlighted = true;
                            }

                            if (!isHighlighted) return null;
                            return Polygon(
                              points: zone.boundary,
                              color: Colors.blueAccent.withOpacity(0.2),
                              borderColor: Colors.purple.withOpacity(0.5),
                              borderStrokeWidth: 2,
                            );
                          }).whereType<Polygon>(),
                          ..._wardsList.where((w) => w.boundary.isNotEmpty).map((ward) {
                            bool isHighlighted = false;
                            if (_selectedZone == 'All Zones' && _selectedWard == 'All Wards') {
                              isHighlighted = true;
                            } else if (_selectedWard == ward.name) {
                              isHighlighted = true;
                            }

                            if (!isHighlighted) return null;
                            return Polygon(
                              points: ward.boundary,
                              color: Colors.blueAccent.withOpacity(0.2),
                              borderColor: Colors.purple.withOpacity(0.5),
                              borderStrokeWidth: 2,
                            );
                          }).whereType<Polygon>(),
                        ],
                      ),
                      // Real-time markers will go here
                      MarkerLayer(
                        markers: [
                          // Zone Labels
                          ..._zonesList.where((z) => z.boundary.isNotEmpty).map((zone) {
                            bool isHighlighted = false;
                            if (_selectedZone == 'All Zones' && _selectedWard == 'All Wards') isHighlighted = true;
                            else if (_selectedZone == zone.name && _selectedWard == 'All Wards') isHighlighted = true;
                            
                            if (!isHighlighted) return null;
                            double lat = 0; double lng = 0;
                            for(var p in zone.boundary) { lat += p.latitude; lng += p.longitude; }
                            lat /= zone.boundary.length; lng /= zone.boundary.length;
                            return Marker(
                              point: LatLng(lat, lng),
                              width: 100, height: 30,
                              child: Center(
                                child: Text(zone.name, style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 16, shadows: [Shadow(color: Colors.white, blurRadius: 2, offset: Offset(1, 1))]))
                              )
                            );
                          }).whereType<Marker>(),
                          // Ward Labels
                          ..._wardsList.where((w) => w.boundary.isNotEmpty).map((ward) {
                            bool isHighlighted = false;
                            if (_selectedZone == 'All Zones' && _selectedWard == 'All Wards') isHighlighted = true;
                            else if (_selectedWard == ward.name) isHighlighted = true;

                            if (!isHighlighted) return null;
                            double lat = 0; double lng = 0;
                            for(var p in ward.boundary) { lat += p.latitude; lng += p.longitude; }
                            lat /= ward.boundary.length; lng /= ward.boundary.length;
                            return Marker(
                              point: LatLng(lat, lng),
                              width: 100, height: 30,
                              child: Center(
                                child: Text(ward.name, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 14, shadows: [Shadow(color: Colors.white, blurRadius: 2, offset: Offset(1, 1))]))
                              )
                            );
                          }).whereType<Marker>(),
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

  Widget _buildCleanlinessChartCard() {
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
                SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 0,
                        centerSpaceRadius: 50,
                        sections: [
                          PieChartSectionData(color: const Color(0xFF198754), value: 40, showTitle: false, radius: 20),
                          PieChartSectionData(color: const Color(0xFFFFC107), value: 35, showTitle: false, radius: 20),
                          PieChartSectionData(color: const Color(0xFFDC3545), value: 25, showTitle: false, radius: 20),
                        ],
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text('342', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          Text('Total Spots', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildChartLegendItem('Clean Roads', '40%', '(137)', const Color(0xFF198754)),
                    const SizedBox(height: 12),
                    _buildChartLegendItem('Slightly Dirty Roads', '35%', '(120)', const Color(0xFFFFC107)),
                    const SizedBox(height: 12),
                    _buildChartLegendItem('Very Dirty Roads', '25%', '(85)', const Color(0xFFDC3545)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 150,
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
                ),
              )
            ],
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthChartCard() {
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
                SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 0,
                        centerSpaceRadius: 50,
                        sections: [
                          PieChartSectionData(color: const Color(0xFF198754), value: 40, showTitle: false, radius: 20),
                          PieChartSectionData(color: const Color(0xFFFFC107), value: 35, showTitle: false, radius: 20),
                          PieChartSectionData(color: const Color(0xFFDC3545), value: 25, showTitle: false, radius: 20),
                        ],
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text('215', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          Text('Total Issues', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildChartLegendItem('Good Roads', '40%', '(86)', const Color(0xFF198754)),
                    const SizedBox(height: 12),
                    _buildChartLegendItem('Bad Roads', '35%', '(75)', const Color(0xFFFFC107)),
                    const SizedBox(height: 12),
                    _buildChartLegendItem('Potholes', '25%', '(54)', const Color(0xFFDC3545)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 150,
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
                ),
              )
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
