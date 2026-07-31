import re

filepath_telemetry = 'e:/vc code/.vscode/trash tracker/AIQ_Fleet app/lib/services/telemetry_service.dart'
filepath_camera = 'e:/vc code/.vscode/trash tracker/AIQ_Fleet app/lib/services/camera_service.dart'

# Update telemetry_service.dart
with open(filepath_telemetry, 'r', encoding='utf-8') as f:
    t_content = f.read()

state_additions = """
  // Analytics State
  double _totalDistanceMeters = 0.0;
  List<Map<String, dynamic>> _dailyRoute = [];
  String get _todayDateString => DateTime.now().toIso8601String().split('T')[0];

  // Trip State
  String? currentTripId;
  double tripDistanceMeters = 0.0;
  int tripFlags = 0;
"""
t_content = re.sub(r'\s*// Analytics State\s*double _totalDistanceMeters = 0\.0;\s*List<Map<String, dynamic>> _dailyRoute = \[\];\s*String get _todayDateString => DateTime\.now\(\)\.toIso8601String\(\)\.split\(\'T\'\)\[0\];', state_additions, t_content, flags=re.DOTALL)

set_navigating_replacement = """
  void setNavigating(bool val) {
    _isNavigating = val;
    final auth = AuthService();
    if (auth.isLoggedIn && auth.vehicleNumber != null) {
      final db = FirebaseFirestore.instance;
      final vNum = auth.vehicleNumber!;

      if (_isNavigating) {
        currentTripId = 'trip_${DateTime.now().millisecondsSinceEpoch}';
        tripDistanceMeters = 0.0;
        tripFlags = 0;
        db.collection('vehicles').doc(vNum).collection('trips').doc(currentTripId).set({
          'tripId': currentTripId,
          'date': _todayDateString,
          'startTime': DateTime.now().toIso8601String(),
          'distanceKm': 0.0,
          'flags': 0,
        });
      } else {
        if (currentTripId != null) {
          db.collection('vehicles').doc(vNum).collection('trips').doc(currentTripId).update({
            'endTime': DateTime.now().toIso8601String(),
            'distanceKm': tripDistanceMeters / 1000.0,
            'flags': tripFlags,
          });
          currentTripId = null;
        }
      }

      db.collection('live_tracking').doc(vNum).set({
        'isActive': _isNavigating,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    notifyListeners();
  }

  void incrementTripFlags() {
    if (_isNavigating && currentTripId != null) {
      tripFlags++;
      final auth = AuthService();
      if (auth.isLoggedIn && auth.vehicleNumber != null) {
        FirebaseFirestore.instance.collection('vehicles').doc(auth.vehicleNumber!).collection('trips').doc(currentTripId).update({
          'flags': tripFlags,
        });
      }
    }
  }
"""
t_content = re.sub(r'\s*void setNavigating\(bool val\) \{.*?\n  \}\n', set_navigating_replacement, t_content, flags=re.DOTALL)

start_tracking_target = r"_totalDistanceMeters \+= dist;\n\s*_dailyRoute\.add\(\{"
start_tracking_replace = """_totalDistanceMeters += dist;
        tripDistanceMeters += dist;
        if (currentTripId != null && _dailyRoute.length % 5 == 0) {
          final auth = AuthService();
          if (auth.vehicleNumber != null) {
            FirebaseFirestore.instance.collection('vehicles').doc(auth.vehicleNumber!).collection('trips').doc(currentTripId).update({
              'distanceKm': tripDistanceMeters / 1000.0,
            });
          }
        }
        _dailyRoute.add({"""
t_content = re.sub(start_tracking_target, start_tracking_replace, t_content)

with open(filepath_telemetry, 'w', encoding='utf-8') as f:
    f.write(t_content)

# Update camera_service.dart
with open(filepath_camera, 'r', encoding='utf-8') as f:
    c_content = f.read()

# Call TelemetryService().incrementTripFlags() when a spot is saved
camera_target = r"if \(sessionId != null\) \'session_id\': sessionId,\n\s*\}\);"
camera_replace = """if (sessionId != null) 'session_id': sessionId,
              });
              TelemetryService().incrementTripFlags();"""
c_content = re.sub(camera_target, camera_replace, c_content)

with open(filepath_camera, 'w', encoding='utf-8') as f:
    f.write(c_content)

print("Updated telemetry_service.dart and camera_service.dart")
