import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'database_screen.dart';
import 'alerts_screen.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../mock_data.dart';
import '../services/map_cache_service.dart';
import '../models/vehicle.dart';
import '../models/ward.dart';
import '../models/zone.dart';
import '../services/role_service.dart';
import 'vehicle_details_screen.dart';

class ActiveFleetScreen extends StatefulWidget {
  const ActiveFleetScreen({super.key});

  @override
  State<ActiveFleetScreen> createState() => _ActiveFleetScreenState();
}

class _ActiveFleetScreenState extends State<ActiveFleetScreen> {
  final MapController _mapController = MapController();
  Vehicle? _selectedVehicle;
  Ward? _selectedWard;
  
  List<Vehicle> _vehicles = [];
  List<Ward> _wards = [];
  
  List<Zone> _zones = [];

  StreamSubscription? _liveTrackingSub;
  StreamSubscription? _vehiclesSub;
  StreamSubscription? _wardsSub;
  StreamSubscription? _zonesSub;
  Map<String, Map<String, dynamic>> _liveTrackingData = {};

  String _searchQuery = '';
  String _selectedZoneFilter = 'All Zones';
  String _selectedWardFilter = 'All Wards';
  String _selectedStatusFilter = 'All Status';

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
    _liveTrackingSub?.cancel();
    _vehiclesSub?.cancel();
    _wardsSub?.cancel();
    _zonesSub?.cancel();
    super.dispose();
  }

  bool _isWardInZone(Ward ward, Zone zone) {
    if (ward.boundary.isEmpty || zone.boundary.isEmpty) return true; // Fallback for dummy data without bounds
    double cLat = 0, cLng = 0;
    for(var p in ward.boundary) { cLat += p.latitude; cLng += p.longitude; }
    LatLng centroid = LatLng(cLat / ward.boundary.length, cLng / ward.boundary.length);

    int intersectCount = 0;
    for (int j = 0; j < zone.boundary.length - 1; j++) {
      if (_rayCastIntersect(centroid, zone.boundary[j], zone.boundary[j + 1])) {
        intersectCount++;
      }
    }
    if (_rayCastIntersect(centroid, zone.boundary.last, zone.boundary.first)) intersectCount++;
    return (intersectCount % 2) == 1;
  }

  bool _rayCastIntersect(LatLng point, LatLng vertA, LatLng vertB) {
    double aY = vertA.latitude, bY = vertB.latitude;
    double aX = vertA.longitude, bX = vertB.longitude;
    double pY = point.latitude, pX = point.longitude;
    if ((aY > pY && bY > pY) || (aY < pY && bY < pY) || (aX < pX && bX < pX)) return false;
    if (aY == bY) return false;
    double m = (aX - bX) / (aY - bY);
    double x = aX + m * (pY - aY);
    return x > pX;
  }

  void _navigateToDetails(Vehicle vehicle) {
    final ward = _wards.where((w) => w.name == vehicle.assignedWard).firstOrNull;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VehicleDetailsScreen(vehicle: vehicle, ward: ward),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasAllAccess = RoleService.hasAllAccess('Fleets & Routes');
    final List<String> allowedZones = RoleService.getAllowedZonesForModule('Fleets & Routes');
    final List<String> allowedWards = RoleService.getAllowedWardsForModule('Fleets & Routes');

    List<String> zItems = (hasAllAccess ? _zones.map((z) => z.name).toList() : allowedZones).toList();
    if (zItems.isNotEmpty && !zItems.contains('All Zones')) {
      zItems.insert(0, 'All Zones');
    }
    final zonesList = zItems.isEmpty ? ['All Zones'] : zItems;

    String validSelectedZone = _selectedZoneFilter;
    if (!zonesList.contains(validSelectedZone) && zonesList.isNotEmpty) {
      validSelectedZone = zonesList.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedZoneFilter != validSelectedZone) {
          setState(() {
            _selectedZoneFilter = validSelectedZone;
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

    if (wItems.isNotEmpty && !wItems.contains('All Wards')) {
      wItems.insert(0, 'All Wards');
    }
    final wardsList = wItems.isEmpty ? ['All Wards'] : wItems;

    String validSelectedWard = _selectedWardFilter;
    if (!wardsList.contains(validSelectedWard) && wardsList.isNotEmpty) {
      validSelectedWard = wardsList.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedWardFilter != validSelectedWard) {
          setState(() {
            _selectedWardFilter = validSelectedWard;
          });
        }
      });
    }

    List<Vehicle> filteredVehicles = _vehicles.where((v) {
      if (!hasAllAccess && !allowedWards.contains('All Wards') && !allowedZones.contains('All Zones')) {
        bool isAllowed = allowedWards.contains(v.assignedWard);
        if (!isAllowed) {
          for (String zName in allowedZones) {
            try {
              final zone = _zones.firstWhere((z) => z.name == zName);
              final ward = _wards.firstWhere((w) => w.name == v.assignedWard);
              if (_isWardInZone(ward, zone)) {
                isAllowed = true;
                break;
              }
            } catch (_) {}
          }
        }
        if (!isAllowed) return false;
      }
      
      bool matchesSearch = _searchQuery.isEmpty || 
        v.vehicleNumber.toLowerCase().contains(_searchQuery.toLowerCase()) || 
        v.driverName.toLowerCase().contains(_searchQuery.toLowerCase()) || 
        v.assignedWard.toLowerCase().contains(_searchQuery.toLowerCase());
      
      bool matchesWard = validSelectedWard == 'All Wards' || v.assignedWard == validSelectedWard;
      bool matchesZone = true;
      if (validSelectedZone != 'All Zones' && validSelectedWard == 'All Wards') {
        try {
          final zone = _zones.firstWhere((z) => z.name == validSelectedZone);
          final ward = _wards.firstWhere((w) => w.name == v.assignedWard);
          if (!_isWardInZone(ward, zone)) matchesZone = false;
        } catch (_) {}
      }
      
      bool matchesStatus = true;
      if (_selectedStatusFilter != 'All Status') {
         if (_selectedStatusFilter == 'Active') matchesStatus = v.statusText == 'Active';
         if (_selectedStatusFilter == 'Idle') matchesStatus = v.statusText == 'Idle';
         if (_selectedStatusFilter == 'Inactive') matchesStatus = v.statusText == 'Inactive';
      }
      
      return matchesSearch && matchesWard && matchesZone && matchesStatus;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F5132),
        title: Text('ACTIVE FLEET MANAGEMENT', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
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
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.database), label: 'Database'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.truck), label: 'Active Fleet'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.bellRing), label: 'Alerts'),
        ],
        onTap: (index) {
          if (index == 0) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => DatabaseScreen()));
          } else if (index == 1) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ActiveFleetScreen()));
          } else if (index == 2) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => AlertsListScreen()));
          }
        },
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
             color: Colors.white,
             padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                  _buildDropdown('Zone', validSelectedZone, zonesList, (val) => setState(() { _selectedZoneFilter = val!; _selectedWardFilter = 'All Wards'; })),
                  const SizedBox(width: 16),
                  _buildDropdown('Ward', validSelectedWard, wardsList, (val) => setState(() => _selectedWardFilter = val!)),
                  const Spacer(),
                  _buildDropdown('', _selectedStatusFilter, ['All Status', 'Active', 'Idle', 'Inactive'], (val) => setState(() => _selectedStatusFilter = val!)),
                  const SizedBox(width: 16),
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                    child: IconButton(icon: const Icon(LucideIcons.refreshCw, size: 18, color: Color(0xFF4B5563)), onPressed: _fetchDataFromFirestore),
                  )
               ]
             )
          ),
          Expanded(
            child: Row(
              children: [
                // Left Sidebar
                Container(
                  width: 380,
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                       Padding(
                         padding: const EdgeInsets.all(24),
                         child: Text('Registered Fleet (${filteredVehicles.length})', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF111827))),
                       ),
                       Padding(
                         padding: const EdgeInsets.symmetric(horizontal: 24),
                         child: TextField(
                           onChanged: (val) => setState(() => _searchQuery = val),
                           style: GoogleFonts.inter(fontSize: 13),
                           decoration: InputDecoration(
                             hintText: 'Search fleet, ward or driver...',
                             hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF), fontSize: 13),
                             prefixIcon: const Icon(LucideIcons.search, size: 18, color: Color(0xFF9CA3AF)),
                             suffixIcon: const Icon(LucideIcons.filter, size: 18, color: Color(0xFF9CA3AF)),
                             contentPadding: const EdgeInsets.symmetric(vertical: 0),
                             border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                             enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                             focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F5132))),
                           ),
                         )
                       ),
                       const SizedBox(height: 16),
                       Expanded(
                         child: ListView.builder(
                           padding: const EdgeInsets.symmetric(horizontal: 24),
                           itemCount: filteredVehicles.length,
                           itemBuilder: (context, index) {
                              final vehicle = filteredVehicles[index];
                              return _buildVehicleCard(vehicle);
                           }
                         )
                       ),
                       // Pagination footer mock
                       Container(
                         padding: const EdgeInsets.all(24),
                         decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text('Showing 1 to ${filteredVehicles.length > 7 ? 7 : filteredVehicles.length} of ${_vehicles.length} fleets', style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 12)),
                             const SizedBox(height: 16),
                             Row(
                               children: [
                                 _pageBtn(LucideIcons.chevronLeft, false),
                                 _pageBtn('1', true),
                                 _pageBtn('2', false),
                                 _pageBtn('3', false),
                                 const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('...')),
                                 _pageBtn('18', false),
                                 _pageBtn(LucideIcons.chevronRight, false),
                               ]
                             )
                           ]
                         )
                       )
                    ]
                  )
                ),
                // Map Area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _buildMap(filteredVehicles),
                    ),
                  )
                ),
              ]
            )
          )
        ]
      )
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty) Text(label, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF6B7280))),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              icon: const Icon(LucideIcons.chevronDown, size: 16, color: Color(0xFF6B7280)),
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF111827))))).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageBtn(dynamic content, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF0F5132) : Colors.white,
        border: Border.all(color: isActive ? const Color(0xFF0F5132) : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: content is String 
        ? Text(content, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.white : const Color(0xFF4B5563)))
        : Icon(content as IconData, size: 16, color: const Color(0xFF4B5563)),
    );
  }

  Widget _buildVehicleCard(Vehicle vehicle) {
    final isSelected = _selectedVehicle?.id == vehicle.id;
    final statusColor = Color(vehicle.stateColorValue);
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedVehicle = vehicle;
          _selectedWard = _wards.where((w) => w.name == vehicle.assignedWard).firstOrNull;
        });
        if (vehicle.currentLocation != null) {
          _mapController.move(vehicle.currentLocation!, 16.0);
        }
        // If they double tap, we can navigate. Single tap just selects.
      },
      onDoubleTap: () => _navigateToDetails(vehicle),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? const Color(0xFF0F5132) : Colors.grey.shade200, width: isSelected ? 2 : 1),
          boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vehicle.vehicleNumber, style: GoogleFonts.inter(color: const Color(0xFF111827), fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text('Ward: ${vehicle.assignedWard}', style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 12)),
                  const SizedBox(height: 2),
                  Text('Driver: ${vehicle.driverName}', style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(vehicle.statusText, style: GoogleFonts.inter(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(LucideIcons.chevronRight, size: 16, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(List<Vehicle> filteredVehicles) {
    return FlutterMap(
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
        MarkerLayer(
          markers: filteredVehicles.where((v) => v.currentLocation != null && v.isRunning).map((vehicle) {
              final statusColor = Color(vehicle.stateColorValue);
              return Marker(
                point: vehicle.currentLocation!, width: 100, height: 100,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedVehicle = vehicle;
                      _selectedWard = _wards.where((w) => w.name == vehicle.assignedWard).firstOrNull;
                    });
                    if (vehicle.currentLocation != null) _mapController.move(vehicle.currentLocation!, 16.0);
                  },
                  onDoubleTap: () => _navigateToDetails(vehicle),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor, 
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                        ),
                        child: Text(vehicle.vehicleNumber, style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle, 
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]
                        ),
                        child: const Icon(LucideIcons.truck, color: Colors.white, size: 14),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
        ),
      ],
    );
  }
}
