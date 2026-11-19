import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/garbage_flag.dart';
import '../widgets/ngrok_image.dart';
import '../services/role_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../widgets/trash_pinpoint_marker.dart';
import '../services/ward_zone_service.dart';
import '../services/trash_spots_service.dart';
import '../widgets/trash_flag_inspection_modal.dart';
import '../services/authority_directory_service.dart';

class GarbageSpotsScreen extends StatefulWidget {
  const GarbageSpotsScreen({super.key});

  @override
  State<GarbageSpotsScreen> createState() => _GarbageSpotsScreenState();
}

class _GarbageSpotsScreenState extends State<GarbageSpotsScreen> {
  bool _isSidebarOpen = true;
  List<GarbageFlag> _garbageFlags = [];
  bool _isAutoMode = true;
  int _viewMode = 0; // 0 for list, 1 for map
  GarbageFlag? _selectedFlag;
  final MapController _mapController = MapController();

  List<String> _allZones = ['All Zones'];
  List<String> _allWards = ['All Wards'];
  String _filterZone = 'All Zones';
  String _filterWard = 'All Wards';
  String _filterSeverity = 'All Severity';

  StreamSubscription<QuerySnapshot>? _zonesSub;
  StreamSubscription<QuerySnapshot>? _wardsSub;

  @override
  void initState() {
    super.initState();
    WardZoneService.instance.init();
    WardZoneService.instance.notifier.addListener(_onWardZoneUpdate);
    _fetchGarbageFlags();
    _fetchZonesAndWards();
  }

  void _onWardZoneUpdate() {
    if (mounted) setState(() {});
  }

  void _zoomToSelection() {
    if (_filterWard != 'All Wards') {
      try {
        final matches = WardZoneService.instance.wards.where((w) => w.name.trim().toLowerCase() == _filterWard.trim().toLowerCase());
        if (matches.isNotEmpty && matches.first.boundary.isNotEmpty) {
          final centroid = WardZoneService.computeCentroid(matches.first.boundary);
          _mapController.move(centroid, 15.2);
          return;
        }
      } catch (_) {}
    } else if (_filterZone != 'All Zones') {
      try {
        final matches = WardZoneService.instance.zones.where((z) => z.name.trim().toLowerCase() == _filterZone.trim().toLowerCase());
        if (matches.isNotEmpty && matches.first.boundary.isNotEmpty) {
          final centroid = WardZoneService.computeCentroid(matches.first.boundary);
          _mapController.move(centroid, 12.5);
          return;
        }
      } catch (_) {}
    } else {
      _mapController.move(const LatLng(12.9716, 77.5946), 11.8);
    }
  }

  @override
  void dispose() {
    WardZoneService.instance.notifier.removeListener(_onWardZoneUpdate);
    TrashSpotsService.instance.flagsNotifier.removeListener(_onTrashSpotsUpdated);
    _zonesSub?.cancel();
    _wardsSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onTrashSpotsUpdated() {
    if (mounted) _updateGarbageFlags();
  }

  void _updateGarbageFlags() {
    setState(() {
      _garbageFlags = TrashSpotsService.instance.activeFlags;
    });
  }

  void _fetchZonesAndWards() {
    _zonesSub = FirebaseFirestore.instance.collection('zones').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _allZones = ['All Zones', ...snapshot.docs.map((doc) => doc.data()['name'] as String? ?? doc.id).toList()];
      });
    });

    _wardsSub = FirebaseFirestore.instance.collection('wards').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _allWards = ['All Wards', ...snapshot.docs.map((doc) => doc.data()['name'] as String? ?? doc.id).toList()];
      });
    });
  }

  void _fetchGarbageFlags() {
    TrashSpotsService.instance.flagsNotifier.addListener(_onTrashSpotsUpdated);
    _updateGarbageFlags();

    FirebaseFirestore.instance.collection('trash_spots').snapshots().listen((snapshot) {
      if (!mounted) return;
      _updateGarbageFlags();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final showSidebar = !isMobile && _isSidebarOpen;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Row(
        children: [
          if (showSidebar) _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopAppBar(isMobile),
                Expanded(
                  child: _buildContent(isMobile),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _viewMode,
        onTap: (idx) {
          setState(() {
            _viewMode = idx;
            if (idx == 0) _selectedFlag = null; // Clear selection when switching to list
          });
          if (idx == 1 && _garbageFlags.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try {
                _mapController.move(LatLng(_garbageFlags.first.lat, _garbageFlags.first.lng), 14.0);
              } catch (_) {}
            });
          }
        },
        selectedItemColor: const Color(0xFF0F5132),
        unselectedItemColor: const Color(0xFF94A3B8),
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.list), label: 'List View'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.map), label: 'Map View'),
        ],
      ),
    );
  }

  Widget _buildTopAppBar(bool isMobile) {
    return Container(
      color: const Color(0xFF0F5132),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _isSidebarOpen = !_isSidebarOpen;
              });
            },
            icon: const Icon(LucideIcons.menu, color: Colors.white, size: 28),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          if (!isMobile) const Expanded(child: SizedBox()),
          if (isMobile) const SizedBox(width: 12),
          const Expanded(
            flex: 2,
            child: Text(
              'GARBAGE SPOTS IDENTIFIED',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isMobile) const Expanded(child: SizedBox()),
          Stack(
            children: [
              const Icon(LucideIcons.bell, color: Colors.white, size: 24),
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            ],
          ),
          const SizedBox(width: 16),
          const Icon(LucideIcons.userCircle, color: Colors.white, size: 24),
        ],
      ),
    );
  }

  Widget _buildContent(bool isMobile) {
    final bool hasAllAccess = RoleService.hasAllAccess('Street Cleanliness AI');
    final List<String> allowedZones = RoleService.getAllowedZonesForModule('Street Cleanliness AI');
    final List<String> allowedWards = RoleService.getAllowedWardsForModule('Street Cleanliness AI');

    List<String> zItems = (hasAllAccess ? _allZones.where((z) => z != 'All Zones').toList() : allowedZones).toList();
    if (zItems.length > 1 && !zItems.contains('All Zones')) {
      zItems.insert(0, 'All Zones');
    }
    final zonesList = zItems.isEmpty ? ['All Zones'] : zItems;

    String validSelectedZone = _filterZone;
    if (!zonesList.contains(validSelectedZone) && zonesList.isNotEmpty) {
      validSelectedZone = zonesList.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _filterZone != validSelectedZone) {
          setState(() {
            _filterZone = validSelectedZone;
          });
        }
      });
    }

    List<String> wItems = _allWards.where((w) {
      if (w == 'All Wards') return true;
      if (!hasAllAccess && !allowedWards.contains('All Wards') && !allowedWards.contains(w)) return false;
      return true;
    }).toList();

    if (wItems.length > 1 && !wItems.contains('All Wards')) {
      wItems.insert(0, 'All Wards');
    }
    final wardsList = wItems.isEmpty ? ['All Wards'] : wItems;

    String validSelectedWard = _filterWard;
    if (!wardsList.contains(validSelectedWard) && wardsList.isNotEmpty) {
      validSelectedWard = wardsList.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _filterWard != validSelectedWard) {
          setState(() {
            _filterWard = validSelectedWard;
          });
        }
      });
    }

    List<GarbageFlag> filteredFlags = _garbageFlags.where((flag) {
      if (!flag.isTrashDetected) return false;
      if (!hasAllAccess && !allowedWards.contains('All Wards')) {
        if (!allowedWards.any((w) => w.trim().toLowerCase() == flag.ward.trim().toLowerCase())) return false;
      }
      if (validSelectedZone != 'All Zones') {
        final z = flag.zone.trim().toLowerCase();
        final target = validSelectedZone.trim().toLowerCase();
        if (z != target && !z.contains(target) && !target.contains(z)) return false;
      }
      if (validSelectedWard != 'All Wards') {
        final w = flag.ward.trim().toLowerCase();
        final target = validSelectedWard.trim().toLowerCase();
        if (w != target && w.replaceAll(' ', '') != target.replaceAll(' ', '')) return false;
      }
      
      String severity = flag.className.contains('Very_Dirty') ? 'High' : 'Medium';
      if (_filterSeverity != 'All Severity' && severity != _filterSeverity) return false;
      
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Back and Report Mode
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.arrowLeft, color: Color(0xFF0F5132), size: 18),
                label: const Text(
                  'Back to Dashboard',
                  style: TextStyle(color: Color(0xFF0F5132), fontWeight: FontWeight.bold),
                ),
              ),
              Row(
                children: [
                  const Text('Report Mode:', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        _buildModeToggle('Auto', _isAutoMode),
                        _buildModeToggle('Manual', !_isAutoMode),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(LucideIcons.info, color: Color(0xFF94A3B8), size: 20),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Row 2: Filters
          SingleChildScrollView(
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
                const SizedBox(width: 12),
                _buildDropdownFilter(validSelectedZone, zonesList, (val) {
                  if (val != null) {
                    setState(() { _filterZone = val; _filterWard = 'All Wards'; });
                    _zoomToSelection();
                  }
                }),
                const SizedBox(width: 12),
                _buildDropdownFilter(validSelectedWard, wardsList, (val) {
                  if (val != null) {
                    setState(() => _filterWard = val);
                    _zoomToSelection();
                  }
                }),
                const SizedBox(width: 12),
                _buildDropdownFilter(_filterSeverity, ['All Severity', 'High', 'Medium', 'Low'], (val) {
                  if (val != null) setState(() => _filterSeverity = val);
                }),
                const SizedBox(width: 12),
                _buildDateRangeFilter(),
                const SizedBox(width: 24),
                IconButton(onPressed: () {}, icon: const Icon(LucideIcons.filter, color: Color(0xFF64748B))),
                const Text('Filter', style: TextStyle(color: Color(0xFF344054), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Row 3: KPIs
          Builder(
            builder: (context) {
              int totalSpots = filteredFlags.length;
              int clearedSpots = filteredFlags.where((f) => f.className == 'Good_Condition' || f.className == 'Good Condition').length;
              int remainingSpots = totalSpots - clearedSpots;
              int avgCleanliness = totalSpots > 0 ? ((clearedSpots / totalSpots) * 100).toInt() : 100;

              return Row(
                children: [
                  Expanded(child: _buildKpiCard('Total Spots Identified', '$totalSpots', 'Current filtered', LucideIcons.trash2, const Color(0xFFE6F4EA), const Color(0xFF198754), true)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildKpiCard('Total Spots Cleared', '$clearedSpots', 'Current filtered', LucideIcons.checkCircle, const Color(0xFFE6F4EA), const Color(0xFF198754), true)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildKpiCard('Remaining to be Cleared', '$remainingSpots', 'Current filtered', LucideIcons.clock, const Color(0xFFFFF3E0), const Color(0xFFF57C00), false)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildKpiCard('Avg Cleanliness', '$avgCleanliness%', 'Current filtered', LucideIcons.sparkles, const Color(0xFFE3F2FD), const Color(0xFF1E88E5), true)),
                ],
              );
            }
          ),
          const SizedBox(height: 24),

          // Table or Map
          _viewMode == 0
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildTableHeader(),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      if (filteredFlags.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(child: Text('No garbage spots found with current filters.', style: TextStyle(color: Color(0xFF64748B)))),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: math.min(filteredFlags.length, 10), // Limit to 10 for performance
                          separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          itemBuilder: (context, index) {
                            return _buildTableRow(index, filteredFlags[index]);
                          },
                        ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      _buildPagination(),
                    ],
                  ),
                )
              : _buildMapView(filteredFlags),
        ],
      ),
    );
  }

  Widget _buildMapView(List<GarbageFlag> flags) {
    return Container(
      height: 600,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(12.9716, 77.5946),
              initialZoom: 11.8,
              onTap: (_, __) => setState(() => _selectedFlag = null),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nitin.trashtracker',
              ),
              ...WardZoneService.instance.buildLayers(
                selectedZone: _filterZone,
                selectedWard: _filterWard,
              ),
              Builder(
                builder: (context) {
                  final camera = MapCamera.of(context);
                  final hasSpecificWard = _filterWard != 'All Wards' && _filterWard.isNotEmpty;
                  final bool showPins = hasSpecificWard
                      ? (camera.zoom >= 14.8)
                      : (camera.zoom >= WardZoneService.individualWardPinsZoomThreshold);
                  if (!showPins || flags.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  const double clusterDist = 0.00018;
                  final List<List<GarbageFlag>> clusters = [];

                  for (var flag in flags) {
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

                  return MarkerLayer(
                    markers: clusters.map((cluster) {
                      final flag = cluster.first;
                      final isVeryDirty = cluster.any((f) => f.className == 'Very_Dirty' || f.displayClass == 'Very Dirty');
                      return Marker(
                        point: LatLng(flag.lat, flag.lng),
                        width: 38,
                        height: 46,
                        alignment: Alignment.topCenter,
                        child: TrashPinpointWidget(
                          count: cluster.length,
                          isVeryDirty: isVeryDirty,
                          onTap: () {
                            setState(() {
                              _selectedFlag = flag;
                            });
                            _mapController.move(LatLng(flag.lat, flag.lng), 15.0);
                            TrashFlagInspectionModal.show(context, flag);
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
          Positioned(
            bottom: 24,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: null,
                  backgroundColor: Colors.white,
                  onPressed: () {
                    final zoom = _mapController.camera.zoom + 1;
                    _mapController.move(_mapController.camera.center, zoom);
                  },
                  child: const Icon(LucideIcons.plus, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: null,
                  backgroundColor: Colors.white,
                  onPressed: () {
                    final zoom = _mapController.camera.zoom - 1;
                    _mapController.move(_mapController.camera.center, zoom);
                  },
                  child: const Icon(LucideIcons.minus, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: null,
                  backgroundColor: Colors.white,
                  tooltip: 'AI Model Settings',
                  onPressed: _showAISettingsDialog,
                  child: const Icon(LucideIcons.sliders, color: Color(0xFF0F5132)),
                ),
              ],
            ),
          ),
          if (_selectedFlag != null)
            Positioned(
              bottom: 24,
              left: 24,
              right: 80,
              child: _buildFlagPopup(_selectedFlag!),
            ),
        ],
      ),
    );
  }

  Widget _buildFlagPopup(GarbageFlag flag) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 100,
              height: 100,
              child: NgrokImage(
                url: flag.imageUrl,
                fit: BoxFit.cover,
                width: 100,
                height: 100,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Spot ID: ${flag.id.substring(0, math.min(6, flag.id.length)).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20, color: Colors.grey),
                      onPressed: () => setState(() => _selectedFlag = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Location: ${flag.lat.toStringAsFixed(4)}, ${flag.lng.toStringAsFixed(4)}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                Text('Ward: ${flag.ward}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                Text('Detected: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(flag.timestamp))}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final url = 'https://www.google.com/maps/search/?api=1&query=${flag.lat},${flag.lng}';
                    if (await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(Uri.parse(url));
                    }
                  },
                  icon: const Icon(LucideIcons.navigation, size: 16, color: Colors.white),
                  label: const Text('Navigate', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle(String text, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isAutoMode = text == 'Auto';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE6F4EA) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            if (isSelected) const Icon(LucideIcons.zap, size: 14, color: Color(0xFF198754)),
            if (isSelected) const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: isSelected ? const Color(0xFF198754) : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownFilter(String currentValue, List<String> items, Function(String?) onChanged) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          dropdownColor: Colors.white,
          icon: const Icon(LucideIcons.chevronDown, size: 16, color: Color(0xFF64748B)),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item, style: const TextStyle(color: Color(0xFF344054), fontWeight: FontWeight.w500, fontSize: 14)),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateRangeFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.calendar, size: 16, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          const Text('18 Aug 2026 - 24 Aug 2026', style: TextStyle(color: Color(0xFF344054), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, String trend, IconData icon, Color iconBgColor, Color iconColor, bool isPositive) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(value, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(isPositive ? LucideIcons.arrowUp : LucideIcons.arrowDown, size: 14, color: isPositive ? const Color(0xFF198754) : const Color(0xFFDC3545)),
              const SizedBox(width: 4),
              Text(
                trend,
                style: TextStyle(
                  color: isPositive ? const Color(0xFF198754) : const Color(0xFFDC3545),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          const SizedBox(width: 40, child: Text('#', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12))),
          const Expanded(flex: 3, child: Text('Spot Details', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12))),
          const Expanded(flex: 2, child: Text('Location', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12))),
          const Expanded(flex: 1, child: Text('Ward', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12))),
          const Expanded(flex: 1, child: Text('Zone', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12))),
          const Expanded(flex: 1, child: Text('Severity', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12))),
          const Expanded(flex: 2, child: Text('Identified On', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12))),
          const Expanded(flex: 2, child: Text('Reported By', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12))),
          const Expanded(flex: 1, child: Text('Status', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(width: 100, child: Text('Action', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildTableRow(int index, GarbageFlag flag) {
    String severity = flag.className == 'Very_Dirty' ? 'High' : 'Medium';
    Color severityBg = severity == 'High' ? const Color(0xFFFFEBEE) : const Color(0xFFFFF3E0);
    Color severityText = severity == 'High' ? const Color(0xFFD32F2F) : const Color(0xFFF57C00);

    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(flag.timestamp);
    } catch (_) {
      parsedDate = DateTime.now();
    }
    String dateStr = DateFormat('dd MMM yyyy').format(parsedDate);
    String timeStr = DateFormat('hh:mm a').format(parsedDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 40, child: Text('${index + 1}', style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w600))),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => TrashFlagInspectionModal.show(context, flag),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildImage(flag.imageUrl, width: 60, height: 48, seedKey: flag.id),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => TrashFlagInspectionModal.show(context, flag),
                        child: Text('Spot ID: ${flag.id.substring(0, math.min(7, flag.id.length)).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(LucideIcons.mapPin, size: 12, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: InkWell(
                              onTap: () => _openMap(flag.lat, flag.lng),
                              child: Text('${flag.lat.toStringAsFixed(4)}, ${flag.lng.toStringAsFixed(4)}', 
                                style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), decoration: TextDecoration.underline), 
                                overflow: TextOverflow.ellipsis
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(LucideIcons.clock, size: 12, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text('$dateStr, $timeStr', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2, 
            child: InkWell(
              onTap: () => _openMap(flag.lat, flag.lng),
              child: Text('${flag.lat.toStringAsFixed(4)}, ${flag.lng.toStringAsFixed(4)}', 
                style: const TextStyle(color: Color(0xFF2563EB), decoration: TextDecoration.underline)
              ),
            ),
          ),
          Expanded(flex: 1, child: Text(flag.ward, style: const TextStyle(color: Color(0xFF344054)))),
          Expanded(flex: 1, child: Text(flag.zone.isNotEmpty && flag.zone != 'Unknown' ? flag.zone : 'Central Zone', style: const TextStyle(color: Color(0xFF344054)))),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: severityBg, borderRadius: BorderRadius.circular(4)),
                child: Text(severity, style: TextStyle(color: severityText, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateStr, style: const TextStyle(color: Color(0xFF344054), fontWeight: FontWeight.w500)),
                Text(timeStr, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Street Cleanliness AI', style: TextStyle(color: Color(0xFF344054), fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(4)),
                  child: const Text('AI Detected', style: TextStyle(color: Color(0xFF198754), fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              children: const [
                Icon(Icons.circle, size: 8, color: Colors.blue),
                SizedBox(width: 6),
                Text('Unresolved', style: TextStyle(color: Color(0xFF344054), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF198754),
                side: const BorderSide(color: Color(0xFF198754)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Text('Report', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Showing 1 to ${math.min(_garbageFlags.length, 10)} of ${_garbageFlags.length} spots', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          Row(
            children: [
              _buildPageButton(LucideIcons.chevronLeft, false),
              const SizedBox(width: 8),
              _buildPageButton('1', true),
              const SizedBox(width: 8),
              _buildPageButton('2', false),
              const SizedBox(width: 8),
              _buildPageButton('3', false),
              const SizedBox(width: 8),
              const Text('...', style: TextStyle(color: Color(0xFF64748B))),
              const SizedBox(width: 8),
              _buildPageButton('35', false),
              const SizedBox(width: 8),
              _buildPageButton(LucideIcons.chevronRight, false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageButton(dynamic content, bool isActive) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE6F4EA) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isActive ? const Color(0xFF198754) : const Color(0xFFE2E8F0)),
      ),
      alignment: Alignment.center,
      child: content is String
          ? Text(content, style: TextStyle(color: isActive ? const Color(0xFF198754) : const Color(0xFF64748B), fontWeight: isActive ? FontWeight.bold : FontWeight.w500))
          : Icon(content, size: 16, color: const Color(0xFF64748B)),
    );
  }

  // Same sidebar as main_layout.dart, adapted here
  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: Colors.white,
      child: Stack(
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 350,
            child: Opacity(
              opacity: 0.15,
              child: Image.network(
                'https://upload.wikimedia.org/wikipedia/commons/thumb/4/41/Skyline_silhouette.svg/1280px-Skyline_silhouette.svg.png',
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
                color: const Color(0xFF4B7171),
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (context, error, stackTrace) => const SizedBox(),
              ),
            ),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 40, bottom: 24, left: 24, right: 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'STREET\nAIQ',
                          style: TextStyle(
                            color: Color(0xFF0F5132),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            height: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 1.5,
                      color: const Color(0xFF0F5132),
                      width: 100,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'URBAN INTELLIGENCE AS A SERVICE',
                      style: TextStyle(
                        color: Color(0xFF344054),
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildNavItem(0, 'Roles & Access', LucideIcons.users, false),
                    const SizedBox(height: 4),
                    _buildNavItem(1, 'Master Dashboard', LucideIcons.home, true), // Keep dashboard highlighted? Or Cleanliness AI?
                    const SizedBox(height: 4),
                    _buildNavItem(2, 'Fleets & Routes', LucideIcons.truck, false),
                    const SizedBox(height: 4),
                    _buildNavItem(3, 'Street Cleanliness AI', LucideIcons.sparkles, false),
                    const SizedBox(height: 4),
                    _buildNavItem(4, 'Road Health Monitor AI', LucideIcons.car, false),
                    const SizedBox(height: 4),
                    _buildNavItem(5, 'Reports', LucideIcons.fileText, false),
                    const SizedBox(height: 4),
                    _buildNavItem(6, 'Settings', LucideIcons.settings, false),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD1E7DD)),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFD1E7DD),
                      child: Icon(Icons.person, color: Color(0xFF0F5132)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Nitin Kumar V',
                            style: TextStyle(
                              color: Color(0xFF0D1B2A),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Super Admin',
                            style: TextStyle(
                              color: Color(0xFF344054),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down, color: Color(0xFF344054)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String title, IconData icon, bool isSelected) {
    bool active = isSelected; 

    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE6F4EA) : Colors.transparent, // Mockup has light green BG for sidebar active item? No, mockup has light text on green bg or similar. Wait, main_layout uses 0xFF0F5132.
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? const Color(0xFF0F5132) : const Color(0xFF344054),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: active ? const Color(0xFF0F5132) : const Color(0xFF344054),
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String url, {double? width, double? height, BoxFit fit = BoxFit.cover, String? seedKey}) {
    if (url.startsWith('data:image')) {
      try {
        final base64String = url.split(',').last;
        return Image.memory(
          base64Decode(base64String),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildImagePlaceholder(width, height),
        );
      } catch (e) {
        return _buildImagePlaceholder(width, height);
      }
    }
    
    final resolved = AuthorityDirectoryService.instance.resolveImageUrl(url, seedKey);
    return NgrokImage(
      url: resolved,
      width: width,
      height: height,
      fit: fit,
    );
  }

  Widget _buildImagePlaceholder(double? width, double? height) {
    return Container(
      width: width ?? 60, height: height ?? 48, color: Colors.grey[200], child: const Icon(Icons.image, color: Colors.grey),
    );
  }

  Future<void> _openMap(double lat, double lng) async {
    final Uri url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildImage(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: -10,
              right: -10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
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
              // Fetch current threshold
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
                    } catch (e) {
                      debugPrint('Error saving settings: $e');
                    }
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
