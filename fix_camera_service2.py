import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\services\camera_service.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Replace connection state variables
content = content.replace(
    'bool _isBackendConnected = false;\n  bool get isBackendConnected => _isBackendConnected;',
    '''bool _isGarbageConnected = false;
  bool _isHealthConnected = false;
  bool get isGarbageConnected => _isGarbageConnected;
  bool get isHealthConnected => _isHealthConnected;'''
)

# 2. Update _checkHealth()
old_check_health = '''  Future<void> _checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('/api/snapshots'),
        headers: {'ngrok-skip-browser-warning': 'true'}
      ).timeout(const Duration(seconds: 3));
      final connected = response.statusCode == 200;
      if (_isBackendConnected != connected) {
        _isBackendConnected = connected;
        notifyListeners();
      }
    } catch (e) {
      if (_isBackendConnected) {
        _isBackendConnected = false;
        notifyListeners();
      }
    }
  }'''
new_check_health = '''  Future<void> _checkHealth() async {
    try {
      final resG = await http.get(Uri.parse('/api/snapshots'), headers: {'ngrok-skip-browser-warning': 'true'}).timeout(const Duration(seconds: 3));
      final gConn = resG.statusCode == 200;
      if (_isGarbageConnected != gConn) {
        _isGarbageConnected = gConn;
        notifyListeners();
      }
    } catch (e) {
      if (_isGarbageConnected) {
        _isGarbageConnected = false;
        notifyListeners();
      }
    }
    try {
      final resH = await http.get(Uri.parse('/api/snapshots'), headers: {'ngrok-skip-browser-warning': 'true'}).timeout(const Duration(seconds: 3));
      final hConn = resH.statusCode == 200;
      if (_isHealthConnected != hConn) {
        _isHealthConnected = hConn;
        notifyListeners();
      }
    } catch (e) {
      if (_isHealthConnected) {
        _isHealthConnected = false;
        notifyListeners();
      }
    }
  }'''
content = content.replace(old_check_health, new_check_health)

# 3. Update connection state in captureManualSnapshot
content = content.replace(
    'if (!_isBackendConnected) {\n              _isBackendConnected = true;\n              notifyListeners();\n            }',
    'if (!_isGarbageConnected) {\n              _isGarbageConnected = true;\n              notifyListeners();\n            }'
)
content = content.replace(
    'if (_isBackendConnected) {\n            _isBackendConnected = false;\n            notifyListeners();\n          }',
    'if (_isGarbageConnected) {\n            _isGarbageConnected = false;\n            notifyListeners();\n          }'
)

# Also for health connection state in POST
content = content.replace(
    '''        if (healthResponse.statusCode == 200) {''',
    '''        if (healthResponse.statusCode == 200) {
          if (!_isHealthConnected) {
            _isHealthConnected = true;
            notifyListeners();
          }'''
)
content = content.replace(
    '''      } catch (e) {
        debugPrint("Health AI Error: ");
      }''',
    '''      } catch (e) {
        debugPrint("Health AI Error: ");
        if (_isHealthConnected) {
          _isHealthConnected = false;
          notifyListeners();
        }
      }'''
)

# 4. Remove restrictions on Firestore saving!
old_garbage_save = '''          if (imageUrl != null) {
            if (roadStatus == 'Very Dirty Road' || roadStatus == 'Slightly Dirty Road') {
              try {
                await FirebaseFirestore.instance.collection('trash_spots').add({
                  'lat': lat,
                  'lng': lng,
                  'road_status': roadStatus,
                  'image_url': imageUrl,
                  'timestamp': FieldValue.serverTimestamp(),
                  'vehicle_number': vehicleNumber,
                  'ward': ward,
                  'status': 'Flagged',
                  'zone': prefs.getString('assignedZone') ?? 'Unknown Zone',
                });
              } catch (fbErr) {
                debugPrint("Firestore Upload Error: ");
              }
            }
          }'''
new_garbage_save = '''          if (imageUrl != null) {
            try {
              bool isFlagged = (roadStatus == 'Very Dirty Road' || roadStatus == 'Slightly Dirty Road');
              await FirebaseFirestore.instance.collection('trash_spots').add({
                'lat': lat,
                'lng': lng,
                'road_status': roadStatus,
                'image_url': imageUrl,
                'timestamp': FieldValue.serverTimestamp(),
                'vehicle_number': vehicleNumber,
                'ward': ward,
                'status': isFlagged ? 'Flagged' : 'Logged',
                'zone': prefs.getString('assignedZone') ?? 'Unknown Zone',
              });
            } catch (fbErr) {
              debugPrint("Firestore Upload Error: ");
            }
          }'''
content = content.replace(old_garbage_save, new_garbage_save)

old_health_save = '''          if (imageUrl != null) {
            if (roadStatus == 'Pothole Detected' || roadStatus == 'Bad Road') {
              try {
                await FirebaseFirestore.instance.collection('health_spots').add({
                  'lat': lat,
                  'lng': lng,
                  'road_status': roadStatus,
                  'image_url': imageUrl,
                  'timestamp': FieldValue.serverTimestamp(),
                  'vehicle_number': vehicleNumber,
                  'ward': ward,
                  'status': 'Flagged',
                  'zone': prefs.getString('assignedZone') ?? 'Unknown Zone',
                });
              } catch (e) {
                debugPrint("Error saving to Firestore: ");
              }
            }
          }'''
new_health_save = '''          if (imageUrl != null) {
            try {
              bool isFlagged = (roadStatus == 'Pothole Detected' || roadStatus == 'Bad Road');
              await FirebaseFirestore.instance.collection('health_spots').add({
                'lat': lat,
                'lng': lng,
                'road_status': roadStatus,
                'image_url': imageUrl,
                'timestamp': FieldValue.serverTimestamp(),
                'vehicle_number': vehicleNumber,
                'ward': ward,
                'status': isFlagged ? 'Flagged' : 'Logged',
                'zone': prefs.getString('assignedZone') ?? 'Unknown Zone',
              });
            } catch (e) {
              debugPrint("Error saving to Firestore: ");
            }
          }'''
content = content.replace(old_health_save, new_health_save)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("camera_service.dart updated.")
