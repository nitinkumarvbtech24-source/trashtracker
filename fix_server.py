import os

file_path = r'e:\vc code\.vscode\trash tracker\Road health monitoring AI\backend\server.py'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add recent_snapshots
content = content.replace(
    "recent_potholes = []",
    "recent_potholes = []\nrecent_snapshots = []"
)

# 2. Update get_snapshots
content = content.replace(
    'return JSONResponse(status_code=200, content={"snapshots": []})',
    'return JSONResponse(status_code=200, content={"snapshots": recent_snapshots})'
)

# 3. Save snapshot in process_frame_route
import re
target_block = '''        return JSONResponse(status_code=200, content={
            "road_status": overall_status,
            "image_url": f"/detections/{filename_only}"
        })'''
replacement_block = '''        snapshot_data = {
            "vehicle_number": data.get('vehicle_number', 'Unknown'),
            "ward": data.get('ward', 'Unknown'),
            "lat": latitude,
            "lng": longitude,
            "display_class": overall_status,
            "road_status": overall_status,
            "confidence": 1.0,
            "image_url": f"/detections/{filename_only}",
            "timestamp": filename_only.replace('.jpg', '')
        }
        recent_snapshots.insert(0, snapshot_data)
        if len(recent_snapshots) > 100:
            recent_snapshots.pop()

        return JSONResponse(status_code=200, content={
            "road_status": overall_status,
            "image_url": f"/detections/{filename_only}"
        })'''
content = content.replace(target_block, replacement_block)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("server.py updated.")
