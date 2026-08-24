import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\cleanliness_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Import Zone model if not imported
if "'../models/zone.dart'" not in content:
    content = content.replace("import '../models/ward.dart';", "import '../models/ward.dart';\nimport '../models/zone.dart';")

# 2. Add state variables to _CleanlinessScreenState
state_vars = '''  List<Vehicle> _vehicles = [];
  List<Ward> _wards = [];
  List<Zone> _zones = [];
  
  String _selectedZone = 'All Zones';
  String _selectedWard = 'All Wards';
  DateTime _selectedDate = DateTime.now();
  bool _isDailyView = true;
  
  StreamSubscription? _zonesSub;'''
content = re.sub(r'  List<Vehicle> _vehicles = \[\];\n  List<Ward> _wards = \[\];', state_vars, content)

# 3. Add _zonesSub to dispose()
dispose_code = '''  @override
  void dispose() {
    _zonesSub?.cancel();'''
content = content.replace('  @override\n  void dispose() {', dispose_code)

# 4. Fetch zones in _fetchDataFromFirestore
fetch_code = '''    _wardsSub = FirebaseFirestore.instance.collection('wards').snapshots().listen((snapshot) {
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
    });'''
content = re.sub(r'    _wardsSub = FirebaseFirestore\.instance\.collection\(\'wards\'\)\.snapshots\(\)\.listen\(\(snapshot\) \{.*?\}\);\n    \}\);', fetch_code, content, flags=re.DOTALL)

# 5. Add _isWardInZone logic and ray cast
raycast_code = '''  bool _rayCastIntersect(LatLng point, LatLng vertA, LatLng vertB) {
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
  Widget build(BuildContext context) {'''
content = content.replace('  @override\n  Widget build(BuildContext context) {', raycast_code)

# 6. Replace _buildFilterBar and children
filter_bar_pattern = r'  Widget _buildFilterBar\(bool isDesktop\) \{.*?Widget _buildDesktopLayout'
new_filter_bar = '''  Widget _buildFilterBar(bool isDesktop) {
    List<String> availableWards = [];
    if (_selectedZone != 'All Zones') {
      final sZone = _zones.firstWhere((z) => z.name == _selectedZone, orElse: () => Zone(id: '', name: '', boundary: []));
      if (sZone.boundary.isNotEmpty) {
        availableWards = _wards
            .where((w) => w.boundary.isNotEmpty && _isWardInZone(w, sZone))
            .map((w) => w.name)
            .toList();
      }
    } else {
      availableWards = _wards.map((w) => w.name).toList();
    }
    
    final wards = ['All Wards', ...availableWards.toSet()];
    final zones = ['All Zones', ..._zones.map((z) => z.name).toSet()];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildFunctionalDropdown('Zone', _selectedZone, zones, (val) {
          setState(() => _selectedZone = val);
        }),
        _buildFunctionalDropdown('Ward', _selectedWard, wards, (val) {
          setState(() => _selectedWard = val);
        }),
        _buildFunctionalDatePicker(),
        _buildFunctionalToggle(),
      ],
    );
  }

  Widget _buildFunctionalDropdown(String label, String value, List<String> items, Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
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
              onChanged: (String? newValue) {
                if (newValue != null) onChanged(newValue);
              },
              items: items.map<DropdownMenuItem<String>>((String val) {
                return DropdownMenuItem<String>(
                  value: val,
                  child: Text(val),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFunctionalDatePicker() {
    final dateStr = "\ \ \";
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
            Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            const Icon(LucideIcons.refreshCw, size: 16, color: Colors.black54),
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
      margin: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isDailyView = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _isDailyView ? const Color(0xFF0F5132) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Daily', style: TextStyle(color: _isDailyView ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _isDailyView = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: !_isDailyView ? const Color(0xFF0F5132) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Monthly', style: TextStyle(color: !_isDailyView ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout'''
content = re.sub(filter_bar_pattern, new_filter_bar, content, flags=re.DOTALL)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated cleanliness_screen.dart filters")
