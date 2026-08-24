import os
import cv2
import numpy as np
import requests
import time
import base64
from fastapi import FastAPI, File, UploadFile, Form, BackgroundTasks, Request
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from ultralytics import YOLO
from PIL import Image
from geopy.geocoders import Nominatim

IMAGE_DIR = "detections"

# Initialize Reverse Geocoder
geolocator = Nominatim(user_agent="road_health_ai_app")

os.makedirs(IMAGE_DIR, exist_ok=True)

app = FastAPI(title="Road Health AI Backend (Pothole)")
from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/detections", StaticFiles(directory="detections"), name="detections")

import json

DB_FILE = "database.json"

def load_db():
    if os.path.exists(DB_FILE):
        try:
            with open(DB_FILE, "r") as f:
                data = json.load(f)
                return data.get("recent_potholes", []), data.get("recent_snapshots", [])
        except Exception as e:
            print(f"Error loading database: {e}")
    return [], []

def save_db(potholes, snapshots):
    try:
        with open(DB_FILE, "w") as f:
            json.dump({
                "recent_potholes": potholes,
                "recent_snapshots": snapshots
            }, f, indent=4)
    except Exception as e:
        print(f"Error saving database: {e}")

# Persistent store for the dashboard feed
recent_potholes, recent_snapshots = load_db()

# ---------------------------------------------------------
# 1. Load YOLOv8 Road Health Model (12-Class Detector)
# ---------------------------------------------------------
possible_paths = [
    os.path.join("pothole_detector", "road_health_v3_model.pt"),
    os.path.join("Roadhealthiness_ai model", "modelssync-main", "pothole_detector", "road_health_v3_model.pt"),
    os.path.join("runs", "detect", "road_health_v2_model", "weights", "best.pt"),
    os.path.join("pothole_detector", "two_class_model", "weights", "best.pt"),
    os.path.join("Roadhealthiness_ai model", "modelssync-main", "pothole_detector", "two_class_model", "weights", "best.pt")
]
yolo_model_path = next((p for p in possible_paths if os.path.exists(p)), possible_paths[0])

print(f"Loading Main YOLO Road Health Model from: {yolo_model_path}")
pothole_model = YOLO(yolo_model_path)

# The temporary notification backend URL
EXTERNAL_BACKEND_URL = "http://127.0.0.1:5001/notify_pothole"

def send_notification(data):
    """Sends the data to the external backend in the background."""
    try:
        print(f"Sending notification to {EXTERNAL_BACKEND_URL}: {data}")
        response = requests.post(EXTERNAL_BACKEND_URL, json=data)
        print(f"External backend responded with status: {response.status_code}")
    except Exception as e:
        print(f"Failed to send notification: {e}")

import base64
from fastapi import Request

@app.options("/api/snapshots")
async def options_snapshots():
    return JSONResponse(status_code=200, content={"message": "ok"})

@app.get("/api/snapshots")
async def get_snapshots():
    return JSONResponse(status_code=200, content={"snapshots": recent_snapshots})

@app.post("/process_frame")
async def process_frame_route(request: Request, background_tasks: BackgroundTasks):
    try:
        data = await request.json()
        image_data = data.get('image', '')
        latitude = data.get('lat', 0.0)
        longitude = data.get('lng', 0.0)
        
        if not image_data:
            return JSONResponse(status_code=400, content={"error": "No image data"})
            
        image_b64 = image_data.split(',')[1] if ',' in image_data else image_data
        image_bytes = base64.b64decode(image_b64)
        nparr = np.frombuffer(image_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if frame is None:
            return JSONResponse(status_code=400, content={"error": "Invalid image"})

        frame_height, frame_width = frame.shape[:2]
        frame_area = frame_height * frame_width
        
        try:
            location_obj = geolocator.reverse(f"{latitude}, {longitude}", timeout=3)
            address = location_obj.address if location_obj else "Unknown Address"
        except Exception:
            address = f"Lat: {latitude}, Lng: {longitude} (Address unavailable)"
            
        class_map = {
            0: "not a road",
            1: "good road",
            2: "bad road",
            3: "pothole",
            4: "bad road ? damaged",
            5: "bad road ? debris",
            6: "bad road ? obstruction",
            7: "pothole ? big pothole",
            8: "pothole ? small pothole"
        }
        color_map = {
            0: (128, 128, 128),
            1: (0, 255, 0),
            2: (0, 0, 255),
            3: (0, 255, 255),
            4: (0, 140, 255),
            5: (0, 165, 255),
            6: (0, 100, 255),
            7: (0, 0, 200),
            8: (0, 200, 255)
        }

        results = pothole_model(frame, verbose=False)
        
        has_pothole = False
        has_bad_road = False
        has_good_road = False
        
        for result in results:
            for box in result.boxes:
                conf = float(box.conf[0].cpu().numpy())
                if conf < 0.35:
                    continue
                    
                xyxy = box.xyxy[0].cpu().numpy()
                cls_id = int(box.cls[0].cpu().numpy())
                cls_name = class_map.get(cls_id, f"Class_{cls_id}")
                color = color_map.get(cls_id, (0, 255, 0))

                x1, y1, x2, y2 = map(int, xyxy)
                cv2.rectangle(frame, (x1, y1), (x2, y2), color, 3)
                cv2.putText(frame, f"{cls_name} {conf:.2f}", (x1, max(y1 - 10, 15)), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
                
                if cls_id in [3, 7, 8]:
                    has_pothole = True
                elif cls_id in [2, 4, 5, 6]:
                    has_bad_road = True
                elif cls_id == 1:
                    has_good_road = True

        overall_status = "Good Condition"
        if has_pothole:
            overall_status = "Pothole Detected"
        elif has_bad_road:
            overall_status = "Bad Road"
            
        filename_only = f"event_{int(time.time())}.jpg"
        filename = f"detections/{filename_only}"
        cv2.imwrite(filename, frame)
        
        # Only notify the temporary python backend for the dashboard if needed
        # (Skipping external notification for /process_frame to avoid spam, or we can add it)

        snapshot_data = {
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

        save_db(recent_potholes, recent_snapshots)

        return JSONResponse(status_code=200, content={
            "road_status": overall_status,
            "image_url": f"/detections/{filename_only}"
        })
        
    except Exception as e:
        print(f"Error in process_frame: {e}")
        return JSONResponse(status_code=500, content={"error": str(e)})

@app.post("/detect")
async def detect_anomalies(
    background_tasks: BackgroundTasks,
    image: UploadFile = File(...),
    latitude: float = Form(...),
    longitude: float = Form(...)
):
    contents = await image.read()
    nparr = np.frombuffer(contents, np.uint8)
    frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    
    if frame is None:
        return JSONResponse(status_code=400, content={"error": "Invalid image"})

    frame_height, frame_width = frame.shape[:2]
    frame_area = frame_height * frame_width
    pil_image = Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    
    # Reverse Geocoding to get exact address
    try:
        location_obj = geolocator.reverse(f"{latitude}, {longitude}", timeout=3)
        address = location_obj.address if location_obj else "Unknown Address"
    except Exception as e:
        print(f"Geocoding error: {e}")
        address = f"Lat: {latitude}, Lng: {longitude} (Address unavailable)"
        
    pothole_detections = []
    
    # ---------------------------
    # A. 9-CLASS ROAD HEALTH INFERENCE & HIERARCHICAL FORMATTING
    # ---------------------------
    class_map = {
        0: "not a road",
        1: "good road",
        2: "bad road",
        3: "pothole",
        4: "bad road → damaged",
        5: "bad road → debris",
        6: "bad road → obstruction",
        7: "pothole → big pothole",
        8: "pothole → small pothole"
    }

    color_map = {
        0: (128, 128, 128),
        1: (0, 255, 0),
        2: (0, 0, 255),
        3: (0, 255, 255),
        4: (0, 140, 255),
        5: (0, 165, 255),
        6: (0, 100, 255),
        7: (0, 0, 200),
        8: (0, 200, 255)
    }

    results = pothole_model(frame, verbose=False)
    for result in results:
        for box in result.boxes:
            conf = float(box.conf[0].cpu().numpy())
            if conf < 0.35:
                continue
                
            xyxy = box.xyxy[0].cpu().numpy()
            cls_id = int(box.cls[0].cpu().numpy())
            cls_name = class_map.get(cls_id, f"Class_{cls_id}")
            color = color_map.get(cls_id, (0, 255, 0))

            x1, y1, x2, y2 = map(int, xyxy)
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 3)
            cv2.putText(frame, f"{cls_name} {conf:.2f}", (x1, max(y1 - 10, 15)), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)

            bbox_area = (x2 - x1) * (y2 - y1)
            ratio = bbox_area / frame_area
            
            pothole_data = {
                "classification": cls_name,
                "confidence": round(conf, 3),
                "location": {"lat": latitude, "lng": longitude},
                "address": address,
                "area_ratio": round(ratio, 4),
                "timestamp": int(time.time())
            }
            pothole_detections.append(pothole_data)

    # ---------------------------
    # AGGREGATION & SAVING
    # ---------------------------
    if pothole_detections:
        filename_only = f"event_{int(time.time())}.jpg"
        filename = f"detections/{filename_only}"
        cv2.imwrite(filename, frame)
        
        for d in pothole_detections:
            d['image_url'] = f"/detections/{filename_only}"
            recent_potholes.insert(0, d)
            background_tasks.add_task(send_notification, d)
            
        recent_potholes[:] = recent_potholes[:50]
        save_db(recent_potholes, recent_snapshots)

    return {
        "message": f"Processed frame. Detected {len(pothole_detections)} pothole(s).",
        "potholes": pothole_detections
    }

@app.get("/api/feed")
async def get_feed():
    return {
        "potholes": recent_potholes
    }

@app.get("/", response_class=HTMLResponse)
@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard():
    with open("backend/dashboard.html", "r", encoding="utf-8") as f:
        content = f.read()
    return HTMLResponse(
        content=content, 
        headers={
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Pragma": "no-cache",
            "Expires": "0"
        }
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5002)




