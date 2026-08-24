import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\fleet_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

build_idx = -1
for i, line in enumerate(lines):
    if 'Widget build(BuildContext context) {' in line:
        build_idx = i
        break

if build_idx != -1:
    new_code = '''  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Light grayish-blue background
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F5132), // Dark green
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: const Text('ACTIVE FLEET MANAGEMENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(icon: const Icon(LucideIcons.bell, color: Colors.white), onPressed: () {}),
              Positioned(
                right: 8, top: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                  child: const Text('3', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
              )
            ],
          ),
          IconButton(icon: const Icon(LucideIcons.helpCircle, color: Colors.white), onPressed: () {}),
          IconButton(icon: const Icon(LucideIcons.user, color: Colors.white), onPressed: () {}),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          _buildTopFilterBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 35, child: _buildLeftFleetList()),
                  const SizedBox(width: 16),
                  Expanded(flex: 65, child: _buildRightMap()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopFilterBar() {
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _buildModernDropdown('Zone', _selectedZoneFilter, zonesList, (val) {
                setState(() {
                  _selectedZoneFilter = val;
                  _selectedWardFilter = 'All Wards';
                  _updateMapForSelection();
                });
              }),
              const SizedBox(width: 16),
              _buildModernDropdown('Ward', _selectedWardFilter, wards, (val) {
                setState(() {
                  _selectedWardFilter = val;
                  _updateMapForSelection();
                });
              }),
            ],
          ),
          Row(
            children: [
              _buildModernDropdown('Status', _timeFilter, ['All Status', 'Active', 'Idle', 'Inactive'], (val) => setState(() => _timeFilter = val), isStatus: true),
              const SizedBox(width: 16),
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: IconButton(
                  icon: const Icon(LucideIcons.refreshCw, size: 18, color: Colors.black54),
                  onPressed: _fetchDataFromFirestore,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

  Widget _buildModernDropdown(String label, String value, List<String> items, Function(String) onChanged, {bool isStatus = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isStatus) Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        if (!isStatus) const SizedBox(height: 4),
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
                return DropdownMenuItem<String>(value: val, child: Text(val));
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeftFleetList() {
    // Filter logic
    List<Vehicle> filteredList = _vehicles.where((v) {
      bool matchesSearch = _searchQuery.isEmpty || v.vehicleNumber.toLowerCase().contains(_searchQuery.toLowerCase()) || (v.driverName?.toLowerCase() ?? '').contains(_searchQuery.toLowerCase());
      
      String status = 'Inactive';
      if (v.isActive) {
        status = v.lastHeartbeat != null && DateTime.now().difference(v.lastHeartbeat!).inMinutes > 5 ? 'Idle' : 'Active';
      }
      bool matchesStatus = _timeFilter == 'All Status' || status == _timeFilter;
      
      bool matchesWard = _selectedWardFilter == 'All Wards' || v.ward == _selectedWardFilter;
      
      return matchesSearch && matchesStatus && matchesWard;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Registered Fleet ()', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.search, size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (val) => setState(() => _searchQuery = val),
                            decoration: const InputDecoration(
                              hintText: 'Search fleet, ward or driver...',
                              hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Icon(LucideIcons.filter, size: 18, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredList.length,
              separatorBuilder: (context, index) => const Divider(color: Color(0xFFE2E8F0), height: 1),
              itemBuilder: (context, index) {
                return _buildFleetCard(filteredList[index]);
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Showing 1 to  of  fleets', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Row(
                  children: [
                    _buildPaginationIcon(Icons.chevron_left),
                    _buildPaginationNumber('1', true),
                    _buildPaginationNumber('2', false),
                    _buildPaginationNumber('3', false),
                    const Text(' ... ', style: TextStyle(color: Colors.grey)),
                    _buildPaginationNumber('18', false),
                    _buildPaginationIcon(Icons.chevron_right),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPaginationIcon(IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 28, height: 28,
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
      child: Icon(icon, size: 16, color: Colors.black54),
    );
  }

  Widget _buildPaginationNumber(String num, bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 28, height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF0F5132) : Colors.white,
        border: isActive ? null : Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(num, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.black87)),
    );
  }

  Widget _buildFleetCard(Vehicle vehicle) {
    String status = 'Inactive';
    Color statusColor = Colors.red;
    Color statusBg = Colors.red.shade50;
    
    if (vehicle.isActive) {
      if (vehicle.lastHeartbeat != null && DateTime.now().difference(vehicle.lastHeartbeat!).inMinutes > 5) {
        status = 'Idle';
        statusColor = Colors.orange;
        statusBg = Colors.orange.shade50;
      } else {
        status = 'Active';
        statusColor = Colors.green;
        statusBg = Colors.green.shade50;
      }
    }

    return InkWell(
      onTap: () {
        setState(() => _selectedVehicle = vehicle);
        if (vehicle.currentLocation != null) {
          _mapController.move(vehicle.currentLocation!, 15.0);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vehicle.vehicleNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                const SizedBox(height: 6),
                Text('Ward: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Text('Driver: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRightMap() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(12.9716, 77.5946),
                initialZoom: 12.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.app',
                  tileProvider: CachedTileProvider(store: MapCacheService.instance.cacheStore),
                ),
                MarkerLayer(markers: _buildCustomMarkers()),
              ],
            ),
            Positioned(
              right: 16, bottom: 16,
              child: Column(
                children: [
                  FloatingActionButton(
                    heroTag: "zoomIn",
                    mini: true,
                    backgroundColor: Colors.white,
                    onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
                    child: const Icon(Icons.add, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: "zoomOut",
                    mini: true,
                    backgroundColor: Colors.white,
                    onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
                    child: const Icon(Icons.remove, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  FloatingActionButton(
                    heroTag: "currentLocation",
                    backgroundColor: Colors.white,
                    onPressed: _moveToCurrentLocation,
                    child: const Icon(LucideIcons.target, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildCustomMarkers() {
    List<Marker> markers = [];
    for (var vehicle in _vehicles) {
      if (vehicle.currentLocation == null) continue;
      
      bool isSelected = _selectedVehicle?.id == vehicle.id;
      
      String status = 'Inactive';
      Color statusColor = const Color(0xFFDC2626); // Red
      
      if (vehicle.isActive) {
        if (vehicle.lastHeartbeat != null && DateTime.now().difference(vehicle.lastHeartbeat!).inMinutes > 5) {
          status = 'Idle';
          statusColor = const Color(0xFFF97316); // Orange
        } else {
          status = 'Active';
          statusColor = const Color(0xFF16A34A); // Green
        }
      }

      markers.add(Marker(
        point: vehicle.currentLocation!,
        width: 120,
        height: 70,
        alignment: Alignment.topCenter,
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
              child: Text(vehicle.vehicleNumber, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: const Icon(LucideIcons.truck, color: Colors.white, size: 14),
            ),
          ],
        ),
      ));
    }
    return markers;
  }
}
'''

    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(lines[:build_idx])
        f.write(new_code)
    print("Successfully replaced UI logic in fleet_screen.dart")
else:
    print("Could not find build method")
