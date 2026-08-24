import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\services\camera_service.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

start_idx = -1
end_idx = -1

for i, line in enumerate(lines):
    if '// 1. Send to Garbage AI' in line:
        start_idx = i
    if 'return combinedResult;' in line and start_idx != -1:
        end_idx = i
        break

if start_idx != -1 and end_idx != -1:
    new_code = """      // Create request payload
      final requestBody = json.encode({
        'image': 'data:image/jpeg;base64,$base64Image',
        'lat': lat,
        'lng': lng,
        'vehicle_number': vehicleNumber,
        'ward': ward,
        if (sessionId != null) 'session_id': sessionId,
        if (pointType != null) 'point_type': pointType
      });

      // 1. Garbage AI Future
      final garbageFuture = http.post(
        Uri.parse('$GARBAGE_AI_URL/process_frame'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: requestBody,
      ).timeout(const Duration(seconds: 30)).catchError((e) {
        debugPrint("Garbage AI Error: $e");
        return http.Response('{"error": "Garbage timeout"}', 500);
      });

      // 2. Health AI Future
      final healthFuture = http.post(
        Uri.parse('$HEALTH_AI_URL/process_frame'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: requestBody,
      ).timeout(const Duration(seconds: 30)).catchError((e) {
        debugPrint("Health AI Error: $e");
        return http.Response('{"error": "Health timeout"}', 500);
      });

      // Run both concurrently
      final responses = await Future.wait([garbageFuture, healthFuture]);
      final garbageResponse = responses[0];
      final healthResponse = responses[1];

      bool anySuccess = false;

      // Handle Garbage AI Response
      if (garbageResponse.statusCode == 200) {
        anySuccess = true;
        final resBody = json.decode(garbageResponse.body);
        final roadStatus = resBody['road_status'] ?? 'UNKNOWN';
        final confidence = resBody['road_confidence'] ?? 0.0;
        final imageUrl = resBody['image_url'];
        
        if (_latestRoadStatus != roadStatus) {
          _latestRoadStatus = roadStatus;
          notifyListeners();
        }

        // Analytics updates
        _imagesCapturedToday++;
        if (roadStatus == 'Very Dirty Road' || roadStatus == 'Slightly Dirty Road') {
          _imagesFlaggedToday++;
        }
        
        // Sync analytics to Firestore
        FirebaseFirestore.instance.collection('vehicles').doc(vehicleNumber)
          .collection('daily_stats').doc(_todayDateString)
          .set({
            'images_captured': _imagesCapturedToday,
            'images_flagged': _imagesFlaggedToday,
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

        combinedResult['garbage'] = {
          'road_status': roadStatus,
          'road_confidence': confidence
        };
        
        if (imageUrl != null) {
          if (roadStatus == 'Very Dirty Road' || roadStatus == 'Slightly Dirty Road') {
            try {
              await FirebaseFirestore.instance.collection('trash_spots').add({
                'lat': lat,
                'lng': lng,
                'road_status': roadStatus,
                'confidence': confidence,
                'image_url': imageUrl,
                'timestamp': FieldValue.serverTimestamp(),
                'status': 'Flagged',
                'vehicle_number': vehicleNumber,
                'ward': ward,
                if (sessionId != null) 'session_id': sessionId,
                if (pointType != null) 'point_type': pointType,
              });
            } catch (fbErr) {
              debugPrint("Firestore Upload Error (Garbage): $fbErr");
            }
          }
        }
      }

      // Handle Health AI Response
      if (healthResponse.statusCode == 200) {
        anySuccess = true;
        final resBody = json.decode(healthResponse.body);
        final roadStatus = resBody['road_status'] ?? 'UNKNOWN';
        final imageUrl = resBody['image_url'];
        
        combinedResult['health'] = {
          'road_status': roadStatus,
        };

        if (imageUrl != null) {
          if (roadStatus == 'Issues Detected' || roadStatus == 'Issues_Detected') {
            try {
              await FirebaseFirestore.instance.collection('health_spots').add({
                'lat': lat,
                'lng': lng,
                'road_status': roadStatus,
                'image_url': imageUrl,
                'timestamp': FieldValue.serverTimestamp(),
                'status': 'Flagged',
                'vehicle_number': vehicleNumber,
                'ward': ward,
                if (sessionId != null) 'session_id': sessionId,
                if (pointType != null) 'point_type': pointType,
              });
            } catch (fbErr) {
              debugPrint("Firestore Upload Error (Health): $fbErr");
            }
          }
        }
      }

      if (anySuccess) {
        if (!_isBackendConnected) {
          _isBackendConnected = true;
          notifyListeners();
        }
      } else {
        if (_isBackendConnected) {
          _isBackendConnected = false;
          notifyListeners();
        }
      }

      return combinedResult;
"""
    
    # We remove the end_idx line (which is return combinedResult;) since we included it
    lines = lines[:start_idx] + [new_code + '\n'] + lines[end_idx+1:]
    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print("Modifications applied successfully.")
else:
    print("Could not find start or end index.")
