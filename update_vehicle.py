import re

filepath = 'e:/vc code/.vscode/trash tracker/AIQ_authority app/lib/screens/vehicle_details_screen.dart'

with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add import
content = content.replace("import 'cleanliness_screen.dart';", "import 'cleanliness_screen.dart';\nimport 'database_screen.dart';")

# 2. Add state variables
state_vars = """
  StreamSubscription<DocumentSnapshot>? _dailyStatsSub;
  StreamSubscription<DocumentSnapshot>? _vehicleSub;
  Vehicle? _liveVehicle;
"""
content = re.sub(r'\s*StreamSubscription<DocumentSnapshot>\?\s*_dailyStatsSub;', state_vars, content)

# 3. Add to initState
init_state_replacement = """
  void initState() {
    super.initState();
    _liveVehicle = widget.vehicle;
    _fetchDailyStats();
    _fetchGarbageFlags();
    _garbageTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchGarbageFlags();
    });

    _vehicleSub = FirebaseFirestore.instance
        .collection('vehicles')
        .doc(widget.vehicle.vehicleNumber)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null) {
        if (mounted) {
          setState(() {
            _liveVehicle = Vehicle.fromJson(doc.data()!);
          });
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.ward != null && widget.ward!.boundary.isNotEmpty) {
        _mapController.move(widget.ward!.boundary.first, 15.0);
      } else if (widget.vehicle.assignedRoute != null && widget.vehicle.assignedRoute!.isNotEmpty) {
        _mapController.move(widget.vehicle.assignedRoute!.first, 15.0);
      } else if (_liveVehicle?.currentLocation != null) {
        _mapController.move(_liveVehicle!.currentLocation!, 15.0);
      }
    });
  }
"""
content = re.sub(r'\s*@override\s*void initState\(\)\s*\{.*?\n  \}', init_state_replacement, content, flags=re.DOTALL)

# 4. Add to dispose
dispose_replacement = """
  @override
  void dispose() {
    _dailyStatsSub?.cancel();
    _vehicleSub?.cancel();
    _garbageTimer?.cancel();
    super.dispose();
  }
"""
content = re.sub(r'\s*@override\s*void dispose\(\)\s*\{.*?\n  \}', dispose_replacement, content, flags=re.DOTALL)

# 5. Update AppBar
appbar_target = r"iconTheme: const IconThemeData\(color: Colors\.white\),\s*\),"
appbar_replacement = """iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: ElevatedButton.icon(
              icon: const Icon(LucideIcons.database, size: 16),
              label: const Text('Database'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent.withOpacity(0.2),
                foregroundColor: Colors.blueAccent,
                elevation: 0,
                side: const BorderSide(color: Colors.blueAccent),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DatabaseScreen(vehicleFilter: widget.vehicle.vehicleNumber),
                  ),
                );
              },
            ),
          ),
        ],
      ),"""
content = re.sub(appbar_target, appbar_replacement, content)

# 6. Replace _buildMap
buildmap_target = r"\s*Widget _buildMap\(\)\s*\{.*?\n  \}\n"
buildmap_replacement = """
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
        strokeWidth: 6,
        color: Colors.blueAccent.withOpacity(0.4),
      ));
    }

    sessions.forEach((sessionId, list) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (int i = 0; i < list.length - 1; i++) {
        final start = LatLng(list[i].lat, list[i].lng);
        final end = LatLng(list[i + 1].lat, list[i + 1].lng);
        final status = list[i + 1].className;
        
        Color segmentColor = Colors.greenAccent;
        if (status == 'Very_Dirty') segmentColor = Colors.redAccent;
        else if (status == 'Slightly_Dirty') segmentColor = Colors.orangeAccent;
        
        routePolylines.add(Polyline(
          points: [start, end],
          color: segmentColor,
          strokeWidth: 6.0,
        ));
      }
    });

    final currentVehicle = _liveVehicle ?? widget.vehicle;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: currentVehicle.currentLocation ?? mapCenter,
            initialZoom: mapZoom,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.street_aiq',
              tileProvider: kIsWeb ? null : CachedTileProvider(store: MapCacheService.store),
            ),
            if (widget.ward != null)
              PolygonLayer(
                polygons: [
                  Polygon<Object>(
                    points: widget.ward!.boundary,
                    color: const Color(0xFF3B82F6).withOpacity(0.2),
                    borderColor: const Color(0xFF3B82F6),
                    borderStrokeWidth: 2,
                  )
                ],
              ),
            if (widget.ward?.optimizedRoute != null)
              PolylineLayer(
                polylines: [
                  Polyline(points: widget.ward!.optimizedRoute!, strokeWidth: 5, color: const Color(0xFF10B981).withOpacity(0.3)),
                ],
              ),
            if (routePolylines.isNotEmpty)
              PolylineLayer(
                polylines: routePolylines,
              ),
            if (_garbageFlags.isNotEmpty)
              MarkerLayer(
                markers: _garbageFlags.map((flag) {
                  final isVeryDirty = flag.className == 'Very_Dirty';
                  final markerColor = flag.className == 'Clean' ? Colors.greenAccent : (isVeryDirty ? Colors.redAccent : Colors.orangeAccent);
                  return Marker(
                    point: LatLng(flag.lat, flag.lng),
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => _showTrashPopup(flag),
                      child: Icon(
                        Icons.tour_rounded,
                        color: markerColor,
                        size: 30,
                        shadows: const [Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))],
                      ),
                    ),
                  );
                }).toList(),
              ),
            if (currentVehicle.currentLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: currentVehicle.currentLocation!,
                    width: 40,
                    height: 40,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF334155))),
                          child: Text(currentVehicle.vehicleNumber.length > 4 ? currentVehicle.vehicleNumber.substring(0, 4) : currentVehicle.vehicleNumber, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: currentVehicle.isActive ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                            shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(LucideIcons.truck, color: Colors.white, size: 12),
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
"""
content = re.sub(buildmap_target, buildmap_replacement, content, flags=re.DOTALL)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated vehicle_details_screen.dart")
