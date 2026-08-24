import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\database_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

if "import 'package:shared_preferences/shared_preferences.dart';" not in content:
    content = content.replace("import 'dart:async';", "import 'dart:async';\nimport 'package:shared_preferences/shared_preferences.dart';")

fetch_old = '''  Future<void> _fetchData() async {
    try {
      final response = await http.get(
        Uri.parse('\/api/snapshots'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            List<dynamic> allSnaps = data['snapshots'] ?? [];
            if (widget.vehicleFilter != null) {
              allSnaps = allSnaps.where((s) => s['vehicle_number'] == widget.vehicleFilter).toList();
            }
            _snapshots = allSnaps;
            _stats = {
              "total": _snapshots.length,
              "Clean Road": _snapshots.where((s) => s['display_class'] == 'Clean Road').length,
              "Slightly Dirty Road": _snapshots.where((s) => s['display_class'] == 'Slightly Dirty Road').length,
              "Very Dirty Road": _snapshots.where((s) => s['display_class'] == 'Very Dirty Road').length,
              "Not a Road": _snapshots.where((s) => s['display_class'] == 'Not a Road').length,
            };
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching database data: \");
    }
  }'''

fetch_new = '''  Future<void> _fetchData() async {
    try {
      final response = await http.get(
        Uri.parse('\/api/snapshots'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_garbage_snapshots', response.body);
        
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            List<dynamic> allSnaps = data['snapshots'] ?? [];
            if (widget.vehicleFilter != null) {
              allSnaps = allSnaps.where((s) => s['vehicle_number'] == widget.vehicleFilter).toList();
            }
            _snapshots = allSnaps;
            _stats = {
              "total": _snapshots.length,
              "Clean Road": _snapshots.where((s) => s['display_class'] == 'Clean Road').length,
              "Slightly Dirty Road": _snapshots.where((s) => s['display_class'] == 'Slightly Dirty Road').length,
              "Very Dirty Road": _snapshots.where((s) => s['display_class'] == 'Very Dirty Road').length,
              "Not a Road": _snapshots.where((s) => s['display_class'] == 'Not a Road').length,
            };
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching database data: \");
      // Load from cache on error
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString('cached_garbage_snapshots');
      if (cachedStr != null && mounted) {
        final data = json.decode(cachedStr);
        setState(() {
          List<dynamic> allSnaps = data['snapshots'] ?? [];
          if (widget.vehicleFilter != null) {
            allSnaps = allSnaps.where((s) => s['vehicle_number'] == widget.vehicleFilter).toList();
          }
          _snapshots = allSnaps;
          _stats = {
            "total": _snapshots.length,
            "Clean Road": _snapshots.where((s) => s['display_class'] == 'Clean Road').length,
            "Slightly Dirty Road": _snapshots.where((s) => s['display_class'] == 'Slightly Dirty Road').length,
            "Very Dirty Road": _snapshots.where((s) => s['display_class'] == 'Very Dirty Road').length,
            "Not a Road": _snapshots.where((s) => s['display_class'] == 'Not a Road').length,
          };
        });
      }
    }
  }'''

content = content.replace(fetch_old, fetch_new)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated database_screen.dart")
