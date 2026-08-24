import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\services\camera_service.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Split status variables and add latestResult
content = content.replace(
    "String _latestRoadStatus = 'UNKNOWN';",
    "String _latestGarbageStatus = 'UNKNOWN';\n  Map<String, dynamic>? latestResult;\n  String _latestHealthStatus = 'UNKNOWN';"
)

content = content.replace(
    "String get latestRoadStatus => _latestRoadStatus;",
    "String get latestRoadStatus => _latestGarbageStatus;"
)

# 2. Update toggleAutoCapture to reset new variables
content = content.replace(
    "_latestRoadStatus = 'UNKNOWN';",
    "_latestGarbageStatus = 'UNKNOWN';\n      _latestHealthStatus = 'UNKNOWN';\n      latestResult = null;"
)

# 3. Update Garbage status update
content = content.replace(
    "if (_latestRoadStatus != roadStatus) {\n              _latestRoadStatus = roadStatus;",
    "if (_latestGarbageStatus != roadStatus) {\n              _latestGarbageStatus = roadStatus;"
)

# 4. Inject Health API Request
health_api_injection = '''          }
        } catch (e) {
          debugPrint("Error pinging Garbage AI: ");
          _isBackendConnected = false;
          notifyListeners();
        }

        // 2. Send to Health AI
        try {
          final healthResponse = await http.post(
            Uri.parse('/process_frame'),
            headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
            body: json.encode({
              'image': 'data:image/jpeg;base64,',
              'lat': lat,
              'lng': lng,
              'vehicle_number': vehicleNumber,
              'ward': ward,
              if (sessionId != null) 'session_id': sessionId,
              if (pointType != null) 'point_type': pointType
            }),
          ).timeout(const Duration(seconds: 30));

          if (healthResponse.statusCode == 200) {
            final resBody = json.decode(healthResponse.body);
            final roadStatus = resBody['road_status'] ?? 'UNKNOWN';
            final imageUrl = resBody['image_url'];
            
            if (_latestHealthStatus != roadStatus) {
              _latestHealthStatus = roadStatus;
              notifyListeners();
            }

            latestResult = combinedResult;
            combinedResult['health'] = {
              'road_status': roadStatus,
            };

            if (imageUrl != null) {
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
            }
'''

content = content.replace(
    "          }\n        } catch (e) {\n          debugPrint(\"Error pinging Garbage AI: \");\n          _isBackendConnected = false;\n          notifyListeners();\n        }",
    health_api_injection
)

# 5. Fix final return of combinedResult
content = content.replace(
    "return combinedResult;\n      } catch (e) {\n        debugPrint(\"Error capturing snapshot: \");\n        return null;\n      }",
    "latestResult = combinedResult;\n        return combinedResult;\n      } catch (e) {\n        debugPrint(\"Error capturing snapshot: \");\n        return null;\n      }"
)


with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("camera_service.dart updated.")
