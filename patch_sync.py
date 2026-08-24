import os
import re
import json

# 1. Update camera_service.dart
camera_service = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\services\camera_service.dart'
with open(camera_service, 'r', encoding='utf-8') as f:
    content = f.read()

old_block = '''      // 1. Garbage AI Future
      final garbageFuture = http.post(
        Uri.parse('/process_frame'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: requestBody,
      ).timeout(const Duration(seconds: 30)).catchError((e) {
        debugPrint("Garbage AI Error: ");
        return http.Response('{"error": "Garbage timeout"}', 500);
      });

      // 2. Health AI Future
      final healthFuture = http.post(
        Uri.parse('/process_frame'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: requestBody,
      ).timeout(const Duration(seconds: 30)).catchError((e) {
        debugPrint("Health AI Error: ");
        return http.Response('{"error": "Health timeout"}', 500);
      });

      // Run both concurrently
      final responses = await Future.wait([garbageFuture, healthFuture]);
      final garbageResponse = responses[0];
      final healthResponse = responses[1];'''

new_block = '''      // 1. Send to Garbage AI First
      final garbageResponse = await http.post(
        Uri.parse('/process_frame'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: requestBody,
      ).timeout(const Duration(seconds: 30)).catchError((e) {
        debugPrint("Garbage AI Error: ");
        return http.Response('{"error": "Garbage timeout"}', 500);
      });

      String garbageStatus = 'Unknown';
      if (garbageResponse.statusCode == 200) {
        try {
          final data = json.decode(garbageResponse.body);
          garbageStatus = data['road_status'] ?? 'UNKNOWN';
        } catch (_) {}
      }

      // Add force_status if it's Not a Road
      final Map<String, dynamic> bodyMap = json.decode(requestBody);
      if (garbageStatus == 'Not a Road') {
        bodyMap['force_status'] = 'Not a Road';
      }
      final healthRequestBody = json.encode(bodyMap);

      // 2. Send to Health AI
      final healthResponse = await http.post(
        Uri.parse('/process_frame'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: healthRequestBody,
      ).timeout(const Duration(seconds: 30)).catchError((e) {
        debugPrint("Health AI Error: ");
        return http.Response('{"error": "Health timeout"}', 500);
      });'''

if old_block in content:
    content = content.replace(old_block, new_block)
    with open(camera_service, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Patched camera_service.dart")
else:
    print("Could not find old block in camera_service.dart")


# 2. Update flask_app.py
flask_app = r'e:\vc code\.vscode\trash tracker\Roadhealthiness_ai model\modelssync-main\flask_app.py'
with open(flask_app, 'r', encoding='utf-8') as f:
    f_content = f.read()

flask_old_block = '''        image_b64 = image_data.split(',')[1] if ',' in image_data else image_data
        image_bytes = base64.b64decode(image_b64)
        
        from PIL import ImageOps
        pil_image = Image.open(io.BytesIO(image_bytes)).convert('RGB')
        pil_image = ImageOps.exif_transpose(pil_image)
        
        rgb_frame = np.array(pil_image)
        cv_frame = cv2.cvtColor(rgb_frame, cv2.COLOR_RGB2BGR)
        
        detections = []
        road_class_str = "Good Road"
        
        if model is not None:'''

flask_new_block = '''        image_b64 = image_data.split(',')[1] if ',' in image_data else image_data
        image_bytes = base64.b64decode(image_b64)
        
        from PIL import ImageOps
        pil_image = Image.open(io.BytesIO(image_bytes)).convert('RGB')
        pil_image = ImageOps.exif_transpose(pil_image)
        
        rgb_frame = np.array(pil_image)
        cv_frame = cv2.cvtColor(rgb_frame, cv2.COLOR_RGB2BGR)
        
        detections = []
        road_class_str = "Good Road"
        
        force_status = data.get('force_status')
        if force_status == 'Not a Road':
            road_class_str = "Not a Road"
            # Bypass YOLO since we already know it's not a road
        elif model is not None:'''

if flask_old_block in f_content:
    f_content = f_content.replace(flask_old_block, flask_new_block)
    with open(flask_app, 'w', encoding='utf-8') as f:
        f.write(f_content)
    print("Patched flask_app.py")
else:
    print("Could not find old block in flask_app.py")
