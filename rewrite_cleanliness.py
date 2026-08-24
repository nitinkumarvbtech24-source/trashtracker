import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\cleanliness_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# We will replace everything from   @override\n  Widget build(BuildContext context) { to the end.

pattern = r'  @override\n  Widget build\(BuildContext context\) \{.*'

new_ui = '''  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FA),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter Bar
            _buildFilterBar(isDesktop),
            const SizedBox(height: 24),
            
            // Layout (Cards + Map + Charts)
            if (isDesktop) _buildDesktopLayout() else _buildMobileLayout(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(bool isDesktop) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildDropdown('Zone', 'All Zones'),
        _buildDropdown('Ward', 'All Wards'),
        _buildDatePicker('12 May 2025'),
        _buildToggleBtn('Daily', 'Monthly'),
      ],
    );
  }

  Widget _buildDropdown(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(String date) {
    return Container(
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
          Text(date, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          const Icon(LucideIcons.refreshCw, size: 16, color: Colors.black54),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(String active, String inactive) {
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F5132),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(active, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(inactive, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildKPI('OVERALL CLEANLINESS', '\%', '-- vs Yesterday', LucideIcons.checkCircle, Colors.green, const Color(0xFFE8F5E9))),
            const SizedBox(width: 16),
            Expanded(child: _buildKPI('SPOTS FLAGGED', '\', '+12% vs Yesterday', LucideIcons.flag, Colors.redAccent, const Color(0xFFFFEBEE))),
            const SizedBox(width: 16),
            Expanded(child: _buildKPI('SPOTS CLEARED', '\', '+0% vs Yesterday', LucideIcons.checkSquare, Colors.blueAccent, const Color(0xFFE3F2FD))),
            const SizedBox(width: 16),
            Expanded(child: _buildKPI('SPOTS NEED ATTENTION', '\', '-- vs Yesterday', LucideIcons.wrench, Colors.redAccent, const Color(0xFFFFEBEE))),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: SizedBox(
                height: 600,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: _buildMap(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  _buildLineChartCard(),
                  const SizedBox(height: 24),
                  _buildDonutChartCard(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildKPI('CLEANLINESS', '\%', '--', LucideIcons.checkCircle, Colors.green, const Color(0xFFE8F5E9))),
            const SizedBox(width: 12),
            Expanded(child: _buildKPI('FLAGGED', '\', '+12%', LucideIcons.flag, Colors.redAccent, const Color(0xFFFFEBEE))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildKPI('CLEARED', '\', '+0%', LucideIcons.checkSquare, Colors.blueAccent, const Color(0xFFE3F2FD))),
            const SizedBox(width: 12),
            Expanded(child: _buildKPI('ATTENTION', '\', '--', LucideIcons.wrench, Colors.redAccent, const Color(0xFFFFEBEE))),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 400,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildMap(),
          ),
        ),
        const SizedBox(height: 24),
        _buildLineChartCard(),
        const SizedBox(height: 24),
        _buildDonutChartCard(),
      ],
    );
  }

  Widget _buildKPI(String title, String value, String subtitle, IconData icon, Color iconColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(color: Colors.black87, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: subtitle.contains('+') ? Colors.redAccent : Colors.grey, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChartCard() {
    return Container(
      height: 280,
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
                const Text('Cleanliness Trend Over Time', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Row(
                  children: const [
                    Text('All Zones', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 20, top: 20, bottom: 10),
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
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value % 20 != 0) return const SizedBox.shrink();
                          return Text('%', style: const TextStyle(color: Colors.grey, fontSize: 10));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                          if (value.toInt() >= 0 && value.toInt() < days.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(days[value.toInt()], style: const TextStyle(color: Colors.grey, fontSize: 10)),
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
                      spots: const [
                        FlSpot(0, 60),
                        FlSpot(1, 65),
                        FlSpot(2, 78),
                        FlSpot(3, 75),
                        FlSpot(4, 85),
                        FlSpot(5, 88),
                        FlSpot(6, 88),
                      ],
                      isCurved: true,
                      color: const Color(0xFF0F5132),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(radius: 4, color: const Color(0xFF0F5132), strokeWidth: 0);
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF0F5132).withOpacity(0.3),
                            const Color(0xFF0F5132).withOpacity(0.01),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
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

  Widget _buildDonutChartCard() {
    double total = _garbageFlags.isEmpty ? 1 : _garbageFlags.length.toDouble();
    double cleanVal = _garbageFlags.where((f) => f.className == 'Clean').length.toDouble();
    double slightVal = _garbageFlags.where((f) => f.className == 'Slightly_Dirty').length.toDouble();
    double dirtyVal = _garbageFlags.where((f) => f.className == 'Very_Dirty').length.toDouble();

    if (cleanVal == 0 && slightVal == 0 && dirtyVal == 0) {
      cleanVal = 0;
      slightVal = 302;
      dirtyVal = 46;
      total = cleanVal + slightVal + dirtyVal;
    }

    return Container(
      height: 296,
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
                  child: PieChart(
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
                            titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        if (slightVal > 0)
                          PieChartSectionData(
                            color: Colors.orange,
                            value: slightVal,
                            title: '%',
                            radius: 30,
                            titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        if (dirtyVal > 0)
                          PieChartSectionData(
                            color: Colors.red,
                            value: dirtyVal,
                            title: '%',
                            radius: 30,
                            titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLegendItem(Colors.green, 'Clean', cleanVal.toInt()),
                      const SizedBox(height: 16),
                      _buildLegendItem(Colors.orange, 'Slightly Dirty', slightVal.toInt()),
                      const SizedBox(height: 16),
                      _buildLegendItem(Colors.red, 'Very Dirty', dirtyVal.toInt()),
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

  Widget _buildLegendItem(Color color, String label, int count) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(' ()', style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w500)),
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
          ' - ',
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
                              userAgentPackageName: 'com.example.street_aiq',
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
                    Text("Confidence: %", style: const TextStyle(color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text("Vehicle: ", style: const TextStyle(color: Colors.black87)),
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
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted!')));
            },
            child: const Text('Report', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.directions_outlined, size: 18),
            label: const Text('Start'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            onPressed: () async {
              final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=,');
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
        color: Colors.blueAccent,
        strokeWidth: 6.0,
      ));
    }

    Map<String, int> locationCounts = {};
    for (var flag in _garbageFlags) {
      String locKey = '_';
      int count = locationCounts[locKey] ?? 0;
      locationCounts[locKey] = count + 1;

      double offsetLat = flag.lat;
      double offsetLng = flag.lng;
      if (count > 0) {
        offsetLng += (count * 0.0002);
      }

      customTrashMarkers.add(Marker(
        point: LatLng(offsetLat, offsetLng),
        width: 32, height: 32,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () => _showTrashPopup(flag),
          child: Container(
            decoration: BoxDecoration(
              color: flag.className == 'Very_Dirty' ? Colors.red : Colors.orange,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: const Center(
              child: Text(
                'P', 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ),
      ));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _vehicles.isNotEmpty && _vehicles.first.currentLocation != null
            ? _vehicles.first.currentLocation!
            : const LatLng(42.3601, -71.0589),
        initialZoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.street_aiq',
          tileProvider: kIsWeb ? null : CachedTileProvider(store: MapCacheService.store),
        ),
        PolylineLayer(polylines: routePolylines),
        MarkerLayer(markers: customTrashMarkers),
        
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
}
'''
content = re.sub(pattern, new_ui, content, flags=re.DOTALL)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated cleanliness_screen.dart")
