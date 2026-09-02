import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';

import '../models/vehicle.dart';
import '../models/ward.dart';
import '../models/zone.dart';
import '../services/map_cache_service.dart';

enum MapMode { view, drawWard, drawZone }

class FleetScreen extends StatefulWidget {
  const FleetScreen({super.key});

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {

  MapMode _currentMode = MapMode.view;
  List<LatLng> _drawingPoints = [];
  String? _editingWardId;
  String? _editingZoneId;
  Ward? _selectedWard;
  Zone? _selectedZone;

  int _bottomNavIndex = 0;
  String _activeTab = 'Device Activity Logs';

  final MapController _mapController = MapController();

  List<Vehicle> _vehicles = [];
  List<Ward> _wards = [];
  List<Zone> _zones = [];

  Vehicle? _selectedVehicle;
  
  StreamSubscription? _liveTrackingSub;
  StreamSubscription? _vehiclesSub;
  StreamSubscription? _wardsSub;
  StreamSubscription? _zonesSub;

  String _selectedZoneFilter = 'All Zones';
  String _selectedWardFilter = 'All Wards';
  DateTime _selectedDate = DateTime.now();
  bool _isDaily = true;
  String _searchQuery = '';
  String _driverSearchQuery = '';
  String _deviceLogSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchDataFromFirestore();
    _startLiveTrackingListener();
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatDateTime(DateTime d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${pad(d.month)}-${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}';
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Map<String, Map<String, dynamic>> _liveTrackingData = {};

  void _fetchDataFromFirestore() {
    _vehiclesSub = FirebaseFirestore.instance.collection('vehicles').snapshots().listen((snapshot) {
      final vehicles = snapshot.docs.map((doc) => Vehicle.fromJson(doc.id, doc.data())).toList();
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
            }
          }
        }
        _vehicles = vehicles;
      });
    });

    _wardsSub = FirebaseFirestore.instance.collection('wards').snapshots().listen((snapshot) {
      final wards = snapshot.docs.map((doc) => Ward.fromJson(doc.id, doc.data())).toList();
      if (!mounted) return;
      setState(() => _wards = wards);
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
  }

  @override
  void dispose() {
    _liveTrackingSub?.cancel();
    _vehiclesSub?.cancel();
    _wardsSub?.cancel();
    _zonesSub?.cancel();
    _mapController.dispose();
    super.dispose();
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

  void _updateMapForSelection() {
    List<LatLng> points = [];
    if (_selectedWardFilter != 'All Wards') {
      try {
        final ward = _wards.firstWhere((w) => w.name == _selectedWardFilter);
        if (ward.boundary.isNotEmpty) points.addAll(ward.boundary);
      } catch (_) {}
    } else if (_selectedZoneFilter != 'All Zones') {
      try {
        final zone = _zones.firstWhere((z) => z.name == _selectedZoneFilter);
        if (zone.boundary.isNotEmpty) points.addAll(zone.boundary);
      } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          // Filter Bar
          _buildFilterBar(),
          // Main Content Area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                children: [
                  _buildKPIs(),
                  const SizedBox(height: 24),
                  if (_bottomNavIndex == 0) _buildFleetsAndRoutesView(),
                  if (_bottomNavIndex == 1) _buildDevicesView(),
                  if (_bottomNavIndex == 2) const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("Analytics (Coming Soon)"))),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildBottomNavItem(0, LucideIcons.truck, 'Fleets & Routes'),
            _buildBottomNavItem(1, LucideIcons.barChart2, 'Devices'),
            _buildBottomNavItem(2, LucideIcons.clipboardList, 'Analytics'),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(int index, IconData icon, String label) {
    bool isSelected = _bottomNavIndex == index;
    return InkWell(
      onTap: () => setState(() => _bottomNavIndex = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? const Color(0xFF0F5132) : const Color(0xFF6B7280)),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.inter(
              fontSize: 14, 
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF0F5132) : const Color(0xFF6B7280),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    List<String> zonesList = ['All Zones', ..._zones.map((z) => z.name).toSet()];
    List<String> availableWards = [];
    if (_selectedZoneFilter != 'All Zones') {
      final sZone = _zones.firstWhere((z) => z.name == _selectedZoneFilter, orElse: () => Zone(id: '', name: '', boundary: []));
      if (sZone.boundary.isNotEmpty) {
        availableWards = _wards.where((w) => w.boundary.isNotEmpty && _isWardInZone(w, sZone)).map((w) => w.name).toList();
      }
    } else {
      availableWards = _wards.map((w) => w.name).toList();
    }
    
    final wards = ['All Wards', ...availableWards.toSet()];
    if (!wards.contains(_selectedWardFilter)) _selectedWardFilter = 'All Wards';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: Colors.white,
      child: Row(
        children: [
          _buildDropdown('Zone', _selectedZoneFilter, zonesList, (v) {
            setState(() { _selectedZoneFilter = v; _selectedWardFilter = 'All Wards'; _updateMapForSelection(); });
          }),
          const SizedBox(width: 16),
          _buildDropdown('Ward', _selectedWardFilter, wards, (v) {
            setState(() { _selectedWardFilter = v; _updateMapForSelection(); });
          }),
          const SizedBox(width: 16),
          // Date Picker mimicking mockup
          InkWell(
            onTap: () => _pickDate(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(LucideIcons.calendar, size: 16, color: Color(0xFF6B7280)),
                  const SizedBox(width: 8),
                  Text(
                    _isDaily 
                      ? _formatDate(_selectedDate) 
                      : '${_formatDate(DateTime(_selectedDate.year, _selectedDate.month, 1))} - ${_formatDate(DateTime(_selectedDate.year, _selectedDate.month + 1, 0))}', 
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF111827), fontSize: 13)
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF6B7280)),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Toggle
          Container(
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _isDaily = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(color: _isDaily ? const Color(0xFF0F5132) : Colors.transparent, borderRadius: const BorderRadius.only(topLeft: Radius.circular(7), bottomLeft: Radius.circular(7))),
                    child: Text('Daily', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _isDaily ? Colors.white : const Color(0xFF4B5563), fontSize: 13)),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _isDaily = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(color: !_isDaily ? const Color(0xFF0F5132) : Colors.transparent, borderRadius: const BorderRadius.only(topRight: Radius.circular(7), bottomRight: Radius.circular(7))),
                    child: Text('Monthly', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: !_isDaily ? Colors.white : const Color(0xFF4B5563), fontSize: 13)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
        const SizedBox(height: 4),
        Container(
          width: 180,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF6B7280)),
              isExpanded: true,
              style: GoogleFonts.inter(color: const Color(0xFF111827), fontWeight: FontWeight.w600, fontSize: 13),
              dropdownColor: Colors.white,
              onChanged: (v) { if (v != null) onChanged(v); },
              items: items.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKPIs() {
    return Row(
      children: [
        Expanded(child: _buildKPICard('ACTIVE VEHICLES', '4,287', '77.95% of Total', LucideIcons.truck, const Color(0xFF10B981))),
        const SizedBox(width: 16),
        Expanded(child: _buildKPICard('ROUTES COMPLETED', '1,203', 'Today', LucideIcons.mapPin, const Color(0xFF3B82F6), subtitleColor: const Color(0xFF3B82F6))),
        const SizedBox(width: 16),
        Expanded(child: _buildKPICard('DISTANCE COVERED', '12,842 km', 'Today', LucideIcons.checkCircle, const Color(0xFF8B5CF6), subtitleColor: const Color(0xFF8B5CF6))),
        const SizedBox(width: 16),
        Expanded(child: _buildKPICard('AVG. EFFICIENCY', '86%', '+4% vs Yesterday', LucideIcons.trendingUp, const Color(0xFFF59E0B), subtitleColor: const Color(0xFFF59E0B))),
        const SizedBox(width: 16),
        Expanded(child: _buildKPICard('ON TIME PERFORMANCE', '92%', '+6% vs Yesterday', LucideIcons.clock, const Color(0xFF10B981), subtitleColor: const Color(0xFF10B981))),
        const SizedBox(width: 16),
        Expanded(child: _buildKPICard('VEHICLES NEED REPAIR', '68', '3.87% of Total', LucideIcons.wrench, const Color(0xFFEF4444), subtitleColor: const Color(0xFFEF4444))),
      ],
    );
  }

  Widget _buildKPICard(String title, String value, String subtitle, IconData icon, Color iconColor, {Color subtitleColor = const Color(0xFF10B981)}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF4B5563), letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(value, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: const Color(0xFF111827))),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: subtitleColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFleetsAndRoutesView() {
    return SizedBox(
      height: 650,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 35, child: _buildVehicleListPanel()),
          const SizedBox(width: 24),
          Expanded(flex: 65, child: _buildMapPanel()),
        ],
      ),
    );
  }

  Widget _buildVehicleListPanel() {
    List<Vehicle> filteredList = _vehicles.where((v) {
      bool matchesSearch = _searchQuery.isEmpty || v.vehicleNumber.toLowerCase().contains(_searchQuery.toLowerCase()) || (v.driverName.toLowerCase()).contains(_searchQuery.toLowerCase());
      bool matchesWard = _selectedWardFilter == 'All Wards' || v.assignedWard == _selectedWardFilter;
      return matchesSearch && matchesWard;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vehicle List', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
                    const SizedBox(height: 4),
                    Text('${filteredList.length} Vehicles', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF10B981))),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      width: 180, height: 36,
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(8)),
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: GoogleFonts.inter(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search vehicle...',
                          hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                          border: InputBorder.none,
                          prefixIcon: Icon(LucideIcons.search, size: 16, color: Color(0xFF9CA3AF)),
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(LucideIcons.filter, size: 16, color: Color(0xFF6B7280)),
                    ),
                  ],
                )
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Vehicle ID', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
                Expanded(flex: 2, child: Text('Driver', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
                Expanded(flex: 2, child: Text('Ward / Zone', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
                Expanded(flex: 2, child: Text('Status', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
                Expanded(flex: 2, child: Text('Last Updated', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Expanded(
            child: ListView.separated(
              itemCount: filteredList.length,
              separatorBuilder: (c, i) => const Divider(height: 1, color: Color(0xFFF3F4F6)),
              itemBuilder: (context, index) {
                final v = filteredList[index];
                
                String status = 'Inactive';
                Color statusColor = const Color(0xFFEF4444);
                Color statusBg = const Color(0xFFFEF2F2);
                
                if (v.isActive) {
                  if (v.lastHeartbeat != null && DateTime.now().difference(v.lastHeartbeat!).inMinutes > 5) {
                    status = 'Idle'; statusColor = const Color(0xFFF59E0B); statusBg = const Color(0xFFFFFBEB);
                  } else {
                    status = 'In Route'; statusColor = const Color(0xFF10B981); statusBg = const Color(0xFFECFDF5);
                  }
                }

                String timeAgo = 'Unknown';
                if (v.lastHeartbeat != null) {
                  int mins = DateTime.now().difference(v.lastHeartbeat!).inMinutes;
                  timeAgo = mins < 60 ? '$mins min ago' : '${mins~/60} hr ago';
                }

                return InkWell(
                  onTap: () {
                    setState(() => _selectedVehicle = v);
                    if (v.currentLocation != null) _mapController.move(v.currentLocation!, 15.0);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(6)),
                              child: const Icon(LucideIcons.truck, size: 16, color: Color(0xFF4B5563)),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.vehicleNumber, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF111827))),
                                const SizedBox(height: 2),
                                Text(v.id.substring(0, min(5, v.id.length)), style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280))),
                              ],
                            ),
                          ],
                        )),
                        Expanded(flex: 2, child: Text(v.driverName, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
                        Expanded(flex: 2, child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.assignedWard, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: const Color(0xFF111827))),
                            const SizedBox(height: 2),
                            Text('Zone', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280))),
                          ],
                        )),
                        Expanded(flex: 2, child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                            child: Text(status, style: GoogleFonts.inter(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        )),
                        Expanded(flex: 2, child: Text(timeAgo, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 28, height: 28, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.chevron_left, size: 16)),
                    const SizedBox(width: 8),
                    Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF0F5132), borderRadius: BorderRadius.circular(4)), child: const Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(4)), child: const Text('2', style: TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    const Text('...', style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 8),
                    Container(width: 28, height: 28, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.chevron_right, size: 16)),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMapPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('Live Fleet Map', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
                    const SizedBox(width: 12),
                    Row(
                      children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('Real-time Tracking', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF10B981))),
                      ],
                    )
                  ],
                ),
                Row(
                  children: [
                    
                    if (_currentMode != MapMode.view) ...[
                      ElevatedButton(
                        onPressed: () => setState(() { _currentMode = MapMode.view; _drawingPoints.clear(); }),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                        child: const Text('Cancel', style: TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _currentMode == MapMode.drawWard ? _showNameWardDialog : _showNameZoneDialog,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
                        child: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      const SizedBox(width: 12),
                    ] else ...[
                      InkWell(
                        onTap: () => setState(() { _currentMode = MapMode.drawWard; _drawingPoints.clear(); }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(6)),
                          child: Text('Draw Ward', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F5132))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => setState(() { _currentMode = MapMode.drawZone; _drawingPoints.clear(); }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(6)),
                          child: Text('Draw Zone', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F5132))),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),

                    InkWell(
                      onTap: _showRoutesManagementDialog,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(6), color: const Color(0xFF0F5132).withValues(alpha: 0.1)),
                        child: const Icon(LucideIcons.layers, size: 16, color: Color(0xFF0F5132)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(LucideIcons.maximize, size: 16, color: Color(0xFF6B7280)),
                    ),
                  ],
                )
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: const LatLng(12.9716, 77.5946),
                      initialZoom: 12.0,

                      onTap: (tapPosition, point) {
                        if (_currentMode != MapMode.view) {
                          setState(() => _drawingPoints.add(point));
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.app',
                        tileProvider: kIsWeb ? null : CachedTileProvider(store: MapCacheService.store),
                      ),
                      PolylineLayer(
                        polylines: _vehicles.where((v) => v.assignedRoute != null && v.assignedRoute!.isNotEmpty).map((v) {
                          return Polyline(
                            points: v.assignedRoute!,
                            color: const Color(0xFF3B82F6),
                            strokeWidth: 4.0,
                          );
                        }).toList(),
                      ),
                      MarkerLayer(markers: _buildCustomMarkers()),

                      PolygonLayer(
                        polygons: [
                          ..._wards.where((w) => w.boundary.isNotEmpty).map((w) => Polygon(
                            points: w.boundary,
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderColor: Colors.blue.withValues(alpha: 0.8),
                            borderStrokeWidth: 2,
                          )),
                          ..._zones.where((z) => z.boundary.isNotEmpty).map((z) => Polygon(
                            points: z.boundary,
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderColor: Colors.purple.withValues(alpha: 0.8),
                            borderStrokeWidth: 2,
                          )),
                          if (_drawingPoints.isNotEmpty)
                            Polygon(
                              points: _drawingPoints,
                              color: (_currentMode == MapMode.drawWard ? Colors.blue : Colors.purple).withValues(alpha: 0.3),
                              borderColor: (_currentMode == MapMode.drawWard ? Colors.blue : Colors.purple),
                              borderStrokeWidth: 2,
                            )
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          ..._wards.where((w) => w.boundary.isNotEmpty).map((w) {
                            double cLat = 0, cLng = 0;
                            for (var p in w.boundary) { cLat += p.latitude; cLng += p.longitude; }
                            LatLng centroid = LatLng(cLat / w.boundary.length, cLng / w.boundary.length);
                            return Marker(
                              point: centroid,
                              width: 120, height: 30,
                              child: Center(
                                child: Text(
                                  w.name,
                                  style: const TextStyle(
                                    color: Colors.blue, 
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 14,
                                    shadows: [
                                      Shadow(offset: Offset(-1, -1), color: Colors.white),
                                      Shadow(offset: Offset(1, -1), color: Colors.white),
                                      Shadow(offset: Offset(1, 1), color: Colors.white),
                                      Shadow(offset: Offset(-1, 1), color: Colors.white),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }),
                          ..._zones.where((z) => z.boundary.isNotEmpty).map((z) {
                            double cLat = 0, cLng = 0;
                            for (var p in z.boundary) { cLat += p.latitude; cLng += p.longitude; }
                            LatLng centroid = LatLng(cLat / z.boundary.length, cLng / z.boundary.length);
                            return Marker(
                              point: centroid,
                              width: 120, height: 30,
                              child: Center(
                                child: Text(
                                  z.name,
                                  style: const TextStyle(
                                    color: Colors.purpleAccent, 
                                    fontWeight: FontWeight.w900, 
                                    fontSize: 16,
                                    shadows: [
                                      Shadow(offset: Offset(-1, -1), color: Colors.white),
                                      Shadow(offset: Offset(1, -1), color: Colors.white),
                                      Shadow(offset: Offset(1, 1), color: Colors.white),
                                      Shadow(offset: Offset(-1, 1), color: Colors.white),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                      if (_drawingPoints.isNotEmpty)
                        MarkerLayer(
                          markers: _drawingPoints.map((p) => Marker(
                            point: p,
                            width: 10, height: 10,
                            child: const CircleAvatar(backgroundColor: Colors.red, radius: 5),
                          )).toList(),
                        ),
                    ],
                  ),
                  Positioned(
                    right: 16, bottom: 16,
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                          child: Column(
                            children: [
                              IconButton(icon: const Icon(Icons.add, color: Colors.black87), onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1)),
                              const Divider(height: 1),
                              IconButton(icon: const Icon(Icons.remove, color: Colors.black87), onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        FloatingActionButton(
                          heroTag: "loc",
                          backgroundColor: Colors.white,
                          mini: true,
                          child: const Icon(LucideIcons.target, color: Colors.black87),
                          onPressed: () {},
                        )
                      ],
                    ),
                  ),
                  Positioned(
                    right: 70, bottom: 16,
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          _buildLegendRow(const Color(0xFF10B981), 'In Route', '4,287'),
                          const SizedBox(height: 6),
                          _buildLegendRow(const Color(0xFFF59E0B), 'Idle', '845'),
                          const SizedBox(height: 6),
                          _buildLegendRow(const Color(0xFFEF4444), 'Repair', '368'),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLegendRow(Color color, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF4B5563))),
          ],
        ),
        Text(value, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  List<Marker> _buildCustomMarkers() {
    List<Marker> markers = [];
    for (var v in _vehicles) {
      if (v.currentLocation == null) continue;
      if (!v.isRunning) continue;
      Color statusColor = const Color(0xFFEF4444);
      if (v.isActive) {
        if (v.lastHeartbeat != null && DateTime.now().difference(v.lastHeartbeat!).inMinutes > 5) {
          statusColor = const Color(0xFFF59E0B);
        } else {
          statusColor = const Color(0xFF10B981);
        }
      }

      markers.add(Marker(
        point: v.currentLocation!,
        width: 120, height: 70,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]),
              child: Text(v.vehicleNumber, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
              child: const Icon(LucideIcons.truck, color: Colors.white, size: 14),
            ),
          ],
        ),
      ));
    }
    return markers;
  }

  Widget _buildDevicesView() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildTab('Registered Drivers', LucideIcons.users),
              _buildTab('Device Activity Logs', LucideIcons.list),
              _buildTab('Register New Vehicle & Driver', Icons.add_circle_outline),
            ],
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          if (_activeTab == 'Registered Drivers') _buildRegisteredDrivers(),
          if (_activeTab == 'Device Activity Logs') _buildDeviceActivityLogs(),
          if (_activeTab == 'Register New Vehicle & Driver') _RegisterDriverForm(onRegistered: () => setState(() => _activeTab = 'Registered Drivers')),
          if (_activeTab != 'Device Activity Logs' && _activeTab != 'Registered Drivers' && _activeTab != 'Register New Vehicle & Driver') 
             Container(height: 400, alignment: Alignment.center, child: Text('Content for $_activeTab')),
        ],
      ),
    );
  }

  Widget _buildTab(String label, IconData icon) {
    bool isActive = _activeTab == label;
    return InkWell(
      onTap: () => setState(() => _activeTab = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: isActive ? const Color(0xFF0F5132) : Colors.transparent, width: 3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isActive ? const Color(0xFF0F5132) : const Color(0xFF6B7280)),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.inter(fontWeight: isActive ? FontWeight.bold : FontWeight.w600, color: isActive ? const Color(0xFF0F5132) : const Color(0xFF6B7280), fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisteredDrivers() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Registered Drivers', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
              Container(
                width: 320, height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (val) => setState(() => _driverSearchQuery = val),
                        style: GoogleFonts.inter(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search by driver name, vehicle...',
                          hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const Icon(LucideIcons.search, size: 16, color: Color(0xFF9CA3AF)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Table Header
          Row(
            children: [
              Expanded(flex: 2, child: Text('Driver Name', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
              Expanded(flex: 2, child: Text('Login Phone Number', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
              Expanded(flex: 2, child: Text('Login Password', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
              Expanded(flex: 2, child: Text('Vehicle Number', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
              Expanded(flex: 2, child: Text('Assigned Ward', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
              Expanded(flex: 1, child: Text('Driver Info', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
              Expanded(flex: 2, child: Text('Active Device Number', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
              Expanded(flex: 1, child: Text('Actions', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280)))),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 12),
          // StreamBuilder
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('vehicles').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return Padding(padding: const EdgeInsets.all(20), child: Center(child: Text("Error: ${snapshot.error}")));
              }
              
              var docs = snapshot.hasData ? snapshot.data!.docs : [];
              if (_driverSearchQuery.isNotEmpty) {
                final q = _driverSearchQuery.toLowerCase();
                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['driverName'] ?? '').toString().toLowerCase();
                  final vehicle = (data['vehicleNumber'] ?? '').toString().toLowerCase();
                  final phone = (data['phoneNumber'] ?? '').toString().toLowerCase();
                  return name.contains(q) || vehicle.contains(q) || phone.contains(q);
                }).toList();
              }

              if (docs.isEmpty) {
                return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("No registered drivers found.")));
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildDriverRow(doc.id, data);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDriverRow(String docId, Map<String, dynamic> data) {
    final name = data['driverName']?.toString() ?? 'Unknown';
    final phone = data['phoneNumber']?.toString() ?? '--';
    final password = data['password']?.toString() ?? '--';
    final vehicle = data['vehicleNumber']?.toString() ?? '--';
    final ward = data['assignedWard']?.toString() ?? 'Unassigned';
    final info = data['driverInfo']?.toString() ?? 'aa';
    String device = data['currentDeviceId']?.toString() ?? 'None';
    if (device.isEmpty) device = 'None';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(name, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF111827)))),
          Expanded(flex: 2, child: Text(phone, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(flex: 2, child: Text(password, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(flex: 2, child: Text(vehicle, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(flex: 2, child: Text(ward, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(flex: 1, child: Text(info, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(flex: 2, child: Text(device, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(
            flex: 1,
            child: PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical, size: 16, color: Color(0xFF6B7280)),
              onSelected: (val) {
                if (val == 'edit') {
                  _showEditDriverDialog(docId, data);
                } else if (val == 'assign') {
                  _showAssignWardDialog(docId, ward);
                } else if (val == 'delete') {
                  _deleteDriver(docId);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'assign', child: Text('Assign Ward')),
                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _deleteDriver(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Driver'),
        content: const Text('Are you sure you want to delete this driver?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('vehicles').doc(docId).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver deleted')));
    }
  }

  void _showEditDriverDialog(String docId, Map<String, dynamic> data) {
    final nameCtrl = TextEditingController(text: data['driverName']);
    final phoneCtrl = TextEditingController(text: data['phoneNumber']);
    final vehicleCtrl = TextEditingController(text: data['vehicleNumber']);
    final passCtrl = TextEditingController(text: data['password']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Driver'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Driver Name')),
              const SizedBox(height: 12),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number')),
              const SizedBox(height: 12),
              TextField(controller: vehicleCtrl, decoration: const InputDecoration(labelText: 'Vehicle Number')),
              const SizedBox(height: 12),
              TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Password')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('vehicles').doc(docId).update({
                'driverName': nameCtrl.text.trim(),
                'phoneNumber': phoneCtrl.text.trim(),
                'vehicleNumber': vehicleCtrl.text.trim(),
                'password': passCtrl.text.trim(),
              });
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver updated')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAssignWardDialog(String docId, String currentWard) {
    String? selectedWard = currentWard;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Assign Ward'),
              content: DropdownButtonFormField<String>(
                value: _wards.any((w) => w.name == selectedWard) ? selectedWard : null,
                hint: const Text('Select a Ward'),
                items: _wards.map((w) => DropdownMenuItem(value: w.name, child: Text(w.name))).toList(),
                onChanged: (val) => setState(() => selectedWard = val),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedWard != null) {
                      await FirebaseFirestore.instance.collection('vehicles').doc(docId).update({
                        'assignedWard': selectedWard,
                      });
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Assigned to $selectedWard')));
                      }
                    }
                  },
                  child: const Text('Assign'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDeviceActivityLogs() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onLongPress: () async {
                  final batch = FirebaseFirestore.instance.batch();
                  final logsRef = FirebaseFirestore.instance.collection('device_logs');
                  
                  final dummyData = [
                    {'deviceId': '4_17072026', 'vehicleNumber': 'KA 01 AA 0003', 'driverName': 'sanjana', 'deviceType': 'App', 'loginTime': DateTime.parse('2026-08-14 18:27:12'), 'logoutTime': DateTime.parse('2026-08-14 19:02:45'), 'isActive': true},
                    {'deviceId': '69_14082026', 'vehicleNumber': 'KA 01 AA 0002', 'driverName': 'kokila', 'deviceType': 'Website', 'loginTime': DateTime.parse('2026-08-14 18:26:09'), 'logoutTime': DateTime.parse('2026-08-14 19:00:12'), 'isActive': true},
                    {'deviceId': '4_17072026', 'vehicleNumber': 'KA 01 AA 0002', 'driverName': 'kokila', 'deviceType': 'App', 'loginTime': DateTime.parse('2026-08-14 16:25:37'), 'logoutTime': DateTime.parse('2026-08-14 16:58:21'), 'isActive': true},
                    {'deviceId': '4_17072026', 'vehicleNumber': 'KA 01 AA 0001', 'driverName': 'vijay', 'deviceType': 'App', 'loginTime': DateTime.parse('2026-08-14 15:58:11'), 'logoutTime': DateTime.parse('2026-08-14 16:35:44'), 'isActive': true},
                    {'deviceId': '3_17072026', 'vehicleNumber': 'KA 01 AA 0002', 'driverName': 'kokila', 'deviceType': 'App', 'loginTime': DateTime.parse('2026-08-14 15:41:48'), 'logoutTime': DateTime.parse('2026-08-14 16:10:22'), 'isActive': true},
                    {'deviceId': '22_20072026', 'vehicleNumber': 'KA 01 AA 0003', 'driverName': 'sanjana', 'deviceType': 'App', 'loginTime': DateTime.parse('2026-08-14 15:16:44'), 'logoutTime': DateTime.parse('2026-08-14 15:45:31'), 'isActive': true},
                    {'deviceId': '68_13082026', 'vehicleNumber': 'KA 01 AA 0003', 'driverName': 'sanjana', 'deviceType': 'Website', 'loginTime': DateTime.parse('2026-08-13 14:36:35'), 'logoutTime': DateTime.parse('2026-08-13 15:05:10'), 'isActive': true},
                    {'deviceId': '4_17072026', 'vehicleNumber': 'KA 01 AA 0002', 'driverName': 'kokila', 'deviceType': 'App', 'loginTime': DateTime.parse('2026-08-08 07:55:18'), 'logoutTime': DateTime.parse('2026-08-08 08:25:41'), 'isActive': true},
                    {'deviceId': '67_08082026', 'vehicleNumber': 'KA 01 AA 0001', 'driverName': 'vijay', 'deviceType': 'Website', 'loginTime': DateTime.parse('2026-08-08 07:37:09'), 'logoutTime': DateTime.parse('2026-08-08 08:05:33'), 'isActive': false},
                    {'deviceId': '22_20072026', 'vehicleNumber': 'KA 01 AA 0003', 'driverName': 'sanjana', 'deviceType': 'App', 'loginTime': DateTime.parse('2026-08-07 14:34:42'), 'logoutTime': DateTime.parse('2026-08-07 15:12:03'), 'isActive': true},
                  ];

                  for (var data in dummyData) {
                    batch.set(logsRef.doc(), {
                      ...data,
                      'loginTime': Timestamp.fromDate(data['loginTime'] as DateTime),
                      'logoutTime': Timestamp.fromDate(data['logoutTime'] as DateTime),
                    });
                  }
                  await batch.commit();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dummy Data Populated to Firestore!')));
                },
                child: Text('Device Activity Logs (1,248)', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
              ),
              Row(
                children: [
                  Container(
                    width: 240, height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (val) => setState(() => _deviceLogSearchQuery = val),
                            style: GoogleFonts.inter(fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'Search by device UID...',
                              hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const Icon(LucideIcons.search, size: 16, color: Color(0xFF9CA3AF)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(LucideIcons.filter, size: 16, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFF10B981)), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.download, size: 16, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        Text('Export to CSV', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF10B981), fontSize: 13)),
                      ],
                    ),
                  )
                ],
              )
            ],
          ),
          const SizedBox(height: 24),
          // Table Header
          Row(
            children: [
              Expanded(flex: 2, child: Text('Device UID', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF111827)))),
              Expanded(flex: 2, child: Text('Vehicle Account', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF111827)))),
              Expanded(flex: 2, child: Text('Driver Name', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF111827)))),
              Expanded(flex: 2, child: Text('Type', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF111827)))),
              Expanded(flex: 2, child: Text('Login Time', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF111827)))),
              Expanded(flex: 2, child: Text('Logout Time', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF111827)))),
              Expanded(flex: 1, child: Text('Duration', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF111827)))),
              Expanded(flex: 1, child: Text('Status', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF111827)))),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 12),
          // Real Data Rows
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('device_logs').orderBy('loginTime', descending: true).limit(10).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return Padding(padding: const EdgeInsets.all(20), child: Center(child: Text("Error: ${snapshot.error}")));
              }
              
              var realDocs = snapshot.hasData ? snapshot.data!.docs : [];
              
              if (_deviceLogSearchQuery.isNotEmpty) {
                final q = _deviceLogSearchQuery.toLowerCase();
                realDocs = realDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final deviceId = (data['deviceId'] ?? '').toString().toLowerCase();
                  return deviceId.contains(q);
                }).toList();
              }
              
              List<Widget> rows = realDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                
                DateTime? parseDate(dynamic val) {
                  if (val is Timestamp) return val.toDate();
                  if (val is String) return DateTime.tryParse(val);
                  return null;
                }
                
                final loginDate = parseDate(data['loginTime']);
                final logoutDate = parseDate(data['logoutTime']);
                
                final loginTime = loginDate != null ? _formatDateTime(loginDate) : '--';
                final logoutTime = logoutDate != null ? _formatDateTime(logoutDate) : '--';
                
                String durationStr = '--';
                if (loginDate != null && logoutDate != null) {
                  final diff = logoutDate.difference(loginDate);
                  final m = diff.inMinutes;
                  final s = diff.inSeconds % 60;
                  durationStr = '${m}m ${s}s';
                } else if (loginDate != null) {
                  final diff = DateTime.now().difference(loginDate);
                  final m = diff.inMinutes;
                  final s = diff.inSeconds % 60;
                  durationStr = '${m}m ${s}s';
                }

                return _buildDeviceLogRow(
                  data['deviceId']?.toString() ?? '--',
                  data['vehicleNumber']?.toString() ?? '--',
                  data['driverName']?.toString() ?? '--',
                  data['deviceType']?.toString() ?? 'App',
                  loginTime,
                  logoutTime,
                  durationStr,
                  data['isActive'] ?? true,
                );
              }).toList();

              // Add Dummy Rows at the bottom if no real data is found, or even if it is to fill the table.
              if (realDocs.isEmpty && _deviceLogSearchQuery.isEmpty) {
                rows.addAll([
                  _buildDeviceLogRow('4_17072026', 'KA 01 AA 0003', 'sanjana', 'App', '2026-08-14 18:27:12', '2026-08-14 19:02:45', '35m 33s', true),
                  _buildDeviceLogRow('69_14082026', 'KA 01 AA 0002', 'kokila', 'Website', '2026-08-14 18:26:09', '2026-08-14 19:00:12', '34m 03s', true),
                  _buildDeviceLogRow('4_17072026', 'KA 01 AA 0002', 'kokila', 'App', '2026-08-14 16:25:37', '2026-08-14 16:58:21', '32m 44s', true),
                  _buildDeviceLogRow('4_17072026', 'KA 01 AA 0001', 'vijay', 'App', '2026-08-14 15:58:11', '2026-08-14 16:35:44', '37m 33s', true),
                  _buildDeviceLogRow('3_17072026', 'KA 01 AA 0002', 'kokila', 'App', '2026-08-14 15:41:48', '2026-08-14 16:10:22', '28m 34s', true),
                  _buildDeviceLogRow('22_20072026', 'KA 01 AA 0003', 'sanjana', 'App', '2026-08-14 15:16:44', '2026-08-14 15:45:31', '28m 47s', true),
                  _buildDeviceLogRow('68_13082026', 'KA 01 AA 0003', 'sanjana', 'Website', '2026-08-13 14:36:35', '2026-08-13 15:05:10', '28m 35s', true),
                  _buildDeviceLogRow('4_17072026', 'KA 01 AA 0002', 'kokila', 'App', '2026-08-08 07:55:18', '2026-08-08 08:25:41', '30m 23s', true),
                  _buildDeviceLogRow('67_08082026', 'KA 01 AA 0001', 'vijay', 'Website', '2026-08-08 07:37:09', '2026-08-08 08:05:33', '28m 24s', false),
                  _buildDeviceLogRow('22_20072026', 'KA 01 AA 0003', 'sanjana', 'App', '2026-08-07 14:34:42', '2026-08-07 15:12:03', '37m 21s', true),
                ]);
              }
              
              return Column(children: rows);
            },
          ),
          
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Showing 1 to 10 of 1,248 logs', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280))),
                Row(
                  children: [
                    Container(width: 28, height: 28, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.chevron_left, size: 16)),
                    const SizedBox(width: 8),
                    Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF0F5132), borderRadius: BorderRadius.circular(4)), child: const Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(4)), child: const Text('2', style: TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(4)), child: const Text('3', style: TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    const Text('...', style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 8),
                    Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(4)), child: const Text('125', style: TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Container(width: 28, height: 28, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.chevron_right, size: 16)),
                    const SizedBox(width: 24),
                    Text('Rows per page: ', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B7280))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(4)),
                      child: Row(children: [Text('10', style: GoogleFonts.inter(fontSize: 12)), const SizedBox(width: 8), const Icon(Icons.keyboard_arrow_down, size: 14)]),
                    )
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDeviceLogRow(String uid, String account, String driver, String type, String login, String logout, String duration, bool success) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(uid, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)))),
          Expanded(flex: 2, child: Text(account, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(flex: 2, child: Text(driver, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(flex: 2, child: Row(
            children: [
              Icon(type == 'App' ? LucideIcons.smartphone : LucideIcons.globe, size: 14, color: type == 'App' ? const Color(0xFF10B981) : const Color(0xFF3B82F6)),
              const SizedBox(width: 6),
              Text(type, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563))),
            ],
          )),
          Expanded(flex: 2, child: Text(login, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(flex: 2, child: Text(logout, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(flex: 1, child: Text(duration, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4B5563)))),
          Expanded(flex: 1, child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: success ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(4)),
              child: Text(success ? 'Success' : 'Failed', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: success ? const Color(0xFF10B981) : const Color(0xFFEF4444))),
            ),
          )),
        ],
      ),
    );
  }

void _showNameWardDialog() {

    if (_drawingPoints.length < 3) {

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A ward must have at least 3 points.')));

      return;

    }



    final nameController = TextEditingController();

    if (_editingWardId != null) {

      final existingWard = _wards.where((w) => w.id == _editingWardId).firstOrNull;

      if (existingWard != null) {

        nameController.text = existingWard.name;

      }

    }



    showDialog(

      context: context,

      builder: (context) => AlertDialog(

        backgroundColor: const Color(0xFF161E2E),

        title: Text(_editingWardId != null ? 'Update Ward' : 'Save Ward', style: const TextStyle(color: Colors.white)),

        content: TextField(

          controller: nameController,

          style: const TextStyle(color: Colors.white),

          decoration: const InputDecoration(

            labelText: 'Ward Name',

            labelStyle: TextStyle(color: Color(0xFF94A3B8)),

          ),

        ),

        actions: [

          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),

          ElevatedButton(

            onPressed: () async {

              if (nameController.text.isNotEmpty) {

                final newWard = Ward(

                  id: _editingWardId ?? DateTime.now().millisecondsSinceEpoch.toString(),

                  name: nameController.text,

                  boundary: List.from(_drawingPoints),

                );

                

                try {

                  await FirebaseFirestore.instance.collection('wards').doc(newWard.id).set(newWard.toJson());

                  if (mounted) {

                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_editingWardId != null ? 'Ward updated successfully!' : 'Ward saved successfully!')));

                    setState(() {

                      _currentMode = MapMode.view;

                      _drawingPoints.clear();

                      _selectedWard = newWard;

                      _editingWardId = null;

                    });

                    Navigator.pop(context);

                  }

                } catch (e) {

                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save Ward: $e')));

                }

              }

            },

            child: Text(_editingWardId != null ? 'Update' : 'Save'),

          )

        ],

      )

    );

  }

void _showNameZoneDialog() {

    if (_drawingPoints.length < 3) {

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A zone must have at least 3 points.')));

      return;

    }



    final nameController = TextEditingController();

    if (_editingZoneId != null) {

      final existingZone = _zones.where((z) => z.id == _editingZoneId).firstOrNull;

      if (existingZone != null) {

        nameController.text = existingZone.name;

      }

    }



    showDialog(

      context: context,

      builder: (context) => AlertDialog(

        backgroundColor: const Color(0xFF161E2E),

        title: Text(_editingZoneId != null ? 'Update Zone' : 'Save Zone', style: const TextStyle(color: Colors.white)),

        content: TextField(

          controller: nameController,

          style: const TextStyle(color: Colors.white),

          decoration: const InputDecoration(

            labelText: 'Zone Name',

            labelStyle: TextStyle(color: Color(0xFF94A3B8)),

          ),

        ),

        actions: [

          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),

          ElevatedButton(

            onPressed: () async {

              if (nameController.text.isNotEmpty) {

                final newZone = Zone(

                  id: _editingZoneId ?? DateTime.now().millisecondsSinceEpoch.toString(),

                  name: nameController.text,

                  boundary: List.from(_drawingPoints),

                );

                

                try {

                  await FirebaseFirestore.instance.collection('zones').doc(newZone.id).set(newZone.toJson());

                  if (mounted) {

                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_editingZoneId != null ? 'Zone updated successfully!' : 'Zone saved successfully!')));

                    setState(() {

                      _currentMode = MapMode.view;

                      _drawingPoints.clear();

                      _selectedZone = newZone;

                      _editingZoneId = null;

                    });

                    Navigator.pop(context);

                  }

                } catch (e) {

                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save Zone: $e')));

                }

              }

            },

            child: Text(_editingZoneId != null ? 'Update' : 'Save'),

          )

        ],

      )

    );

  }

  void _editWard(Ward ward) {
    Navigator.of(context).pop();
    setState(() {
      _currentMode = MapMode.drawWard;
      _editingWardId = ward.id;
      _drawingPoints = List.from(ward.boundary);
    });
  }

  void _editZone(Zone zone) {
    Navigator.of(context).pop();
    setState(() {
      _currentMode = MapMode.drawZone;
      _editingZoneId = zone.id;
      _drawingPoints = List.from(zone.boundary);
    });
  }

  Future<void> _deleteWard(Ward ward) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Ward'),
        content: Text('Are you sure you want to delete ${ward.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('wards').doc(ward.id).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${ward.name} deleted.')));
    }
  }

  Future<void> _deleteZone(Zone zone) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Zone'),
        content: Text('Are you sure you want to delete ${zone.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('zones').doc(zone.id).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${zone.name} deleted.')));
    }
  }

  void _showRoutesManagementDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 500,
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Routes Management', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          labelColor: Color(0xFF0F5132),
                          indicatorColor: Color(0xFF0F5132),
                          unselectedLabelColor: Colors.grey,
                          tabs: [Tab(text: 'Zones'), Tab(text: 'Wards')],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildRoutesList('Zones'),
                              _buildRoutesList('Wards'),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildRoutesList(String type) {
    if (type == 'Zones') {
      if (_zones.isEmpty) return const Center(child: Text('No zones created.'));
      return ListView.builder(
        itemCount: _zones.length,
        itemBuilder: (context, index) {
          final zone = _zones[index];
          return ListTile(
            title: Text(zone.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            subtitle: Text('${zone.boundary.length} points', style: GoogleFonts.inter(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(LucideIcons.edit2, size: 18, color: Colors.blue), onPressed: () => _editZone(zone)),
                IconButton(icon: const Icon(LucideIcons.trash2, size: 18, color: Colors.red), onPressed: () { Navigator.of(context).pop(); _deleteZone(zone); }),
              ],
            ),
          );
        },
      );
    } else {
      if (_wards.isEmpty) return const Center(child: Text('No wards created.'));
      return ListView.builder(
        itemCount: _wards.length,
        itemBuilder: (context, index) {
          final ward = _wards[index];
          return ListTile(
            title: Text(ward.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            subtitle: Text('${ward.boundary.length} points', style: GoogleFonts.inter(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(LucideIcons.edit2, size: 18, color: Colors.blue), onPressed: () => _editWard(ward)),
                IconButton(icon: const Icon(LucideIcons.trash2, size: 18, color: Colors.red), onPressed: () { Navigator.of(context).pop(); _deleteWard(ward); }),
              ],
            ),
          );
        },
      );
    }
  }
}

class _RegisterDriverForm extends StatefulWidget {
  final VoidCallback onRegistered;
  const _RegisterDriverForm({required this.onRegistered});
  
  @override
  State<_RegisterDriverForm> createState() => _RegisterDriverFormState();
}

class _RegisterDriverFormState extends State<_RegisterDriverForm> {
  final _nameController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final vehicle = _vehicleController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (name.isEmpty || vehicle.isEmpty || phone.isEmpty || password.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All fields are required')));
      return;
    }
    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final existing = await FirebaseFirestore.instance.collection('vehicles')
          .where('vehicleNumber', isEqualTo: vehicle).get();
      if (existing.docs.isNotEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle number already registered')));
        setState(() => _isLoading = false);
        return;
      }
      
      await FirebaseFirestore.instance.collection('vehicles').add({
        'driverName': name,
        'vehicleNumber': vehicle,
        'phoneNumber': phone,
        'password': password,
        'assignedWard': 'Unassigned',
        'driverInfo': '',
        'currentDeviceId': '',
        'currentSessionId': '',
        'registeredAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver registered successfully!')));
      widget.onRegistered();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4))],
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Register New Driver', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF111827)), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Enter the credentials for the Fleet App', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280)), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              _buildField('Driver Name', _nameController, LucideIcons.user),
              const SizedBox(height: 16),
              _buildField('Vehicle Number', _vehicleController, LucideIcons.truck),
              const SizedBox(height: 16),
              _buildField('Phone Number', _phoneController, LucideIcons.phone, keyboardType: TextInputType.phone),
              const SizedBox(height: 16),
              _buildField('Password', _passwordController, LucideIcons.lock, obscureText: true),
              const SizedBox(height: 16),
              _buildField('Confirm Password', _confirmPasswordController, LucideIcons.lock, obscureText: true),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F5132),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Register Driver', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon, {bool obscureText = false, TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF111827)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: const Color(0xFF6B7280)),
        prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F5132))),
      ),
    );
  }
}
