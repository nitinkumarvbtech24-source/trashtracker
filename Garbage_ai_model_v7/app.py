import io
import base64
from pathlib import Path
from PIL import Image
import numpy as np
import cv2
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from fastapi.staticfiles import StaticFiles
import os
import uuid
from datetime import datetime
from contextlib import asynccontextmanager
from ultralytics import YOLO
import uvicorn

# Configuration
BASE_DIR = Path(__file__).parent
V6_DIR = BASE_DIR.parent / "Garbage_ai_model_v6"

def get_best_model_path():
    candidates = [
        BASE_DIR / "weights" / "garbage_ai_model_v7_best.pt",
        BASE_DIR / "weights" / "garbage_ai_model_v6_best.pt",
        BASE_DIR / "runs" / "garbage_ai_v6_experiment" / "weights" / "best.pt",
        V6_DIR / "weights" / "garbage_ai_model_v6_best.pt",
    ]
    for p in candidates:
        if p.exists():
            return p
    return BASE_DIR / "weights" / "garbage_ai_model_v6_best.pt"

YOLO_MODEL_PATH = get_best_model_path()
RAW_DIR = BASE_DIR / "road cleanliness" if (BASE_DIR / "road cleanliness").exists() else (V6_DIR / "road cleanliness")

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_yolo()
    organize_existing_snapshots()
    yield

app = FastAPI(title="Street AIQ — Real-Time YOLOv8 Road Trash Detection Dashboard (v7)", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

SNAPSHOTS_DIR = BASE_DIR / "snapshots"
ANALYSED_TRASH_DIR = SNAPSHOTS_DIR / "analysed" / "trash_detected"
ANALYSED_NO_TRASH_DIR = SNAPSHOTS_DIR / "analysed" / "no_trash_detected"
TRAINING_TRASH_DIR = SNAPSHOTS_DIR / "training" / "trash_detected"
TRAINING_NO_TRASH_DIR = SNAPSHOTS_DIR / "training" / "no_trash_detected"

for folder in [ANALYSED_TRASH_DIR, ANALYSED_NO_TRASH_DIR, TRAINING_TRASH_DIR, TRAINING_NO_TRASH_DIR]:
    os.makedirs(folder, exist_ok=True)

app.mount("/snapshots", StaticFiles(directory=str(SNAPSHOTS_DIR)), name="snapshots")

history = []
HISTORY_FILE = "history.json"

if os.path.exists(HISTORY_FILE):
    try:
        import json
        with open(HISTORY_FILE, "r") as f:
            history = json.load(f)
    except Exception as e:
        print("Error loading history:", e)
        history = []

yolo_model = None
current_confidence = 0.25

def organize_existing_snapshots():
    global history
    modified = False
    import shutil
    for s in history:
        tag = s.get("training_tag", s.get("road_status", s.get("display_class", "No Trash Detected")))
        cat = "trash_detected" if (tag == "Trash Detected" or s.get("trash_count", 0) > 0) else "no_trash_detected"

        # 1. Categorize Analysed Image
        img_url = s.get("image_url", "")
        if img_url:
            old_name = Path(img_url).name
            target_path = SNAPSHOTS_DIR / "analysed" / cat / old_name
            source_path = SNAPSHOTS_DIR / old_name
            if source_path.exists() and source_path.is_file():
                shutil.move(str(source_path), str(target_path))
                s["image_url"] = f"/snapshots/analysed/{cat}/{old_name}"
                modified = True
            elif target_path.exists():
                s["image_url"] = f"/snapshots/analysed/{cat}/{old_name}"

        # 2. Categorize Training Image
        raw_url = s.get("raw_image_url", "")
        raw_name = Path(raw_url).name if raw_url else ""
        if raw_name:
            target_raw = SNAPSHOTS_DIR / "training" / cat / raw_name
            source_raw = SNAPSHOTS_DIR / raw_name
            if source_raw.exists() and source_raw.is_file():
                shutil.move(str(source_raw), str(target_raw))
                s["raw_image_url"] = f"/snapshots/training/{cat}/{raw_name}"
                modified = True
            elif target_raw.exists():
                s["raw_image_url"] = f"/snapshots/training/{cat}/{raw_name}"
        else:
            if s.get("image_url"):
                img_name = Path(s["image_url"]).name
                analysed_file = SNAPSHOTS_DIR / "analysed" / cat / img_name
                raw_filename = f"raw_{img_name}"
                target_raw = SNAPSHOTS_DIR / "training" / cat / raw_filename
                if analysed_file.exists() and not target_raw.exists():
                    shutil.copy2(str(analysed_file), str(target_raw))
                s["raw_image_url"] = f"/snapshots/training/{cat}/{raw_filename}"
                modified = True

    if modified:
        try:
            with open(HISTORY_FILE, "w") as f:
                import json
                json.dump(history, f)
            print("✅ Successfully categorized existing snapshots into analysed and training folders!")
        except Exception as e:
            print("Error updating history after organizing:", e)

def init_yolo():
    global yolo_model
    print(f"Loading Trained YOLOv8 Street AIQ Detector (v7) from: {YOLO_MODEL_PATH}")
    if YOLO_MODEL_PATH.exists():
        yolo_model = YOLO(str(YOLO_MODEL_PATH))
        print("✅ Trained YOLOv8 Street AIQ Model loaded successfully!")
    else:
        print("Fallback: Loading default yolov8n.pt model...")
        yolo_model = YOLO("yolov8n.pt")

def detect_road_trash(img_bytes):
    global current_confidence
    img_pil = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    img_np = np.array(img_pil)
    img_bgr = cv2.cvtColor(img_np, cv2.COLOR_RGB2BGR)
    h, w, _ = img_bgr.shape
    
    # Run YOLO detection
    results = yolo_model(img_pil, conf=current_confidence)[0]
    boxes = results.boxes
    trash_count = len(boxes)
    
    annotated_bgr = img_bgr.copy()
    
    for box in boxes:
        x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
        conf = float(box.conf[0].item())
        
        # Red bounding box around detected trash
        cv2.rectangle(annotated_bgr, (x1, y1), (x2, y2), (0, 0, 255), 3)
        label_str = f"TRASH {conf*100:.0f}%"
        
        (text_w, text_h), _ = cv2.getTextSize(label_str, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
        cv2.rectangle(annotated_bgr, (x1, max(0, y1 - 25)), (x1 + text_w, max(0, y1)), (0, 0, 255), -1)
        cv2.putText(annotated_bgr, label_str, (x1, max(15, y1 - 8)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2, cv2.LINE_AA)
                    
    if trash_count == 0:
        is_trash_detected = False
        decision_label = "NO TRASH DETECTED (CLEAN ROAD)"
        cleanliness_score = 100.0
        badge_color = "#22c55e" # Green
        recommendation = "✅ CLEAN ROAD: Zero trash detected on the road surface. Road condition optimal."
    else:
        is_trash_detected = True
        decision_label = f"TRASH DETECTED ({trash_count} Item(s))"
        cleanliness_score = max(0.0, 100.0 - (trash_count * 20.0))
        badge_color = "#ef4444" # Red
        recommendation = f"🚨 TRASH DETECTED: {trash_count} trash region(s) identified on road surface. Municipal cleanup required."
        
    banner_h = max(45, int(h * 0.12))
    overlay = annotated_bgr.copy()
    cv2.rectangle(overlay, (0, 0), (w, banner_h), (15, 23, 42), -1)
    cv2.addWeighted(overlay, 0.8, annotated_bgr, 0.2, 0, annotated_bgr)
    
    cv2.putText(annotated_bgr, f"Street AIQ: {decision_label}", (20, int(banner_h * 0.65)),
                cv2.FONT_HERSHEY_SIMPLEX, max(0.6, w / 950.0), (255, 255, 255), 2, cv2.LINE_AA)
                
    bar_h = max(8, int(h * 0.03))
    bar_w = int(w * (cleanliness_score / 100.0))
    bgr_badge = (34, 197, 94) if not is_trash_detected else (239, 68, 68)
    cv2.rectangle(annotated_bgr, (0, h - bar_h), (bar_w, h), (bgr_badge[2], bgr_badge[1], bgr_badge[0]), -1)
    
    annotated_rgb = cv2.cvtColor(annotated_bgr, cv2.COLOR_BGR2RGB)
    pil_out = Image.fromarray(annotated_rgb)
    
    buffer = io.BytesIO()
    pil_out.save(buffer, format="JPEG", quality=92)
    base64_str = base64.b64encode(buffer.getvalue()).decode("utf-8")
    
    return {
        "trash_detected": is_trash_detected,
        "decision": decision_label,
        "trash_count": trash_count,
        "cleanliness_score": round(cleanliness_score, 1),
        "badge_color": badge_color,
        "recommendation": recommendation,
        "annotated_image": f"data:image/jpeg;base64,{base64_str}"
    }

@app.post("/api/predict")
async def predict_file(file: UploadFile = File(...)):
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Uploaded file must be an image.")
    contents = await file.read()
    res = detect_road_trash(contents)
    return JSONResponse(content=res)

@app.get("/api/settings")
async def get_settings():
    global current_confidence
    return JSONResponse(content={"confidence_threshold": current_confidence})

@app.post("/api/settings")
async def update_settings(req: dict):
    global current_confidence
    if "confidence_threshold" in req:
        try:
            current_confidence = float(req["confidence_threshold"])
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid confidence threshold")
    return JSONResponse(content={"status": "success", "confidence_threshold": current_confidence})

@app.get("/api/sample/{category}/{filename}")
async def predict_sample(category: str, filename: str):
    cat_folder = category.replace("_", " ")
    file_path = RAW_DIR / cat_folder / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Sample image not found.")
    with open(file_path, "rb") as f:
        contents = f.read()
    res = detect_road_trash(contents)
    return JSONResponse(content=res)

@app.get("/", response_class=HTMLResponse)
async def get_dashboard():
    samples = []
    for cat, folder in [("clean_roads", "clean roads"), ("slightly_dirty", "slightly dirty"), ("very_dirty", "very dirty")]:
        p = RAW_DIR / folder
        if p.exists():
            files = list(p.glob("*.jpg"))[:2]
            for f in files:
                samples.append({"category": cat, "filename": f.name, "label": f"{cat.replace('_', ' ').title()} Sample"})
                
    sample_buttons_html = "".join([
        f'<button class="sample-btn" onclick="loadSample(\'{s["category"]}\', \'{s["filename"]}\')">{s["label"]}</button>'
        for s in samples
    ])
    
    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Street AIQ — Real-Time YOLOv8 Road Trash Detector v6</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        :root {{
            --bg-primary: #0b0f19;
            --bg-card: rgba(17, 24, 39, 0.75);
            --border-card: rgba(255, 255, 255, 0.08);
            --accent-green: #22c55e;
            --accent-red: #ef4444;
            --accent-cyan: #06b6d4;
            --text-primary: #f8fafc;
            --text-muted: #94a3b8;
        }}
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
            font-family: 'Outfit', sans-serif;
            background-color: var(--bg-primary);
            background-image: 
                radial-gradient(at 0% 0%, rgba(6, 182, 212, 0.12) 0px, transparent 50%),
                radial-gradient(at 100% 100%, rgba(34, 197, 94, 0.1) 0px, transparent 50%);
            color: var(--text-primary);
            min-height: 100vh;
            padding: 24px;
        }}
        .container {{ max-width: 1320px; margin: 0 auto; }}
        header {{
            display: flex; justify-content: space-between; align-items: center;
            padding-bottom: 24px; margin-bottom: 24px; border-bottom: 1px solid var(--border-card);
        }}
        .brand {{ display: flex; align-items: center; gap: 14px; }}
        .logo-icon {{
            width: 44px; height: 44px;
            background: linear-gradient(135deg, #06b6d4, #3b82f6);
            border-radius: 12px; display: flex; align-items: center; justify-content: center;
            font-weight: 800; font-size: 22px; color: white; box-shadow: 0 0 20px rgba(6, 182, 212, 0.4);
        }}
        .brand-title {{
            font-size: 24px; font-weight: 700; letter-spacing: -0.5px;
            background: linear-gradient(90deg, #ffffff, #94a3b8);
            -webkit-background-clip: text; -webkit-text-fill-color: transparent;
        }}
        .badge-live {{
            background: rgba(34, 197, 94, 0.15); color: #4ade80;
            border: 1px solid rgba(74, 222, 128, 0.3); padding: 6px 14px;
            border-radius: 20px; font-size: 13px; font-weight: 600;
            display: flex; align-items: center; gap: 8px;
        }}
        .pulse-dot {{
            width: 8px; height: 8px; background-color: #4ade80; border-radius: 50%;
            animation: pulse 1.8s infinite;
        }}
        @keyframes pulse {{
            0% {{ transform: scale(0.95); box-shadow: 0 0 0 0 rgba(74, 222, 128, 0.7); }}
            70% {{ transform: scale(1); box-shadow: 0 0 0 8px rgba(74, 222, 128, 0); }}
            100% {{ transform: scale(0.95); box-shadow: 0 0 0 0 rgba(74, 222, 128, 0); }}
        }}
        .main-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }}
        @media (max-width: 960px) {{ .main-grid {{ grid-template-columns: 1fr; }} }}
        .card {{
            background: var(--bg-card); backdrop-filter: blur(16px);
            border: 1px solid var(--border-card); border-radius: 20px; padding: 24px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
        }}
        .card-header {{
            font-size: 18px; font-weight: 600; margin-bottom: 16px;
            display: flex; justify-content: space-between; align-items: center; color: #e2e8f0;
        }}
        .dropzone {{
            border: 2px dashed rgba(255, 255, 255, 0.15); border-radius: 16px;
            padding: 40px 20px; text-align: center; cursor: pointer; transition: all 0.3s ease;
            background: rgba(15, 23, 42, 0.4); margin-bottom: 20px;
        }}
        .dropzone:hover, .dropzone.dragover {{ border-color: var(--accent-cyan); background: rgba(6, 182, 212, 0.08); }}
        .upload-icon {{
            width: 56px; height: 56px; margin: 0 auto 16px; background: rgba(255, 255, 255, 0.05);
            border-radius: 50%; display: flex; align-items: center; justify-content: center;
        }}
        .sample-section {{ margin-top: 16px; }}
        .sample-title {{ font-size: 13px; color: var(--text-muted); margin-bottom: 10px; text-transform: uppercase; letter-spacing: 0.8px; }}
        .sample-grid {{ display: flex; flex-wrap: wrap; gap: 8px; }}
        .sample-btn {{
            background: rgba(255, 255, 255, 0.06); border: 1px solid rgba(255, 255, 255, 0.1);
            color: #cbd5e1; padding: 8px 14px; border-radius: 10px; font-size: 13px;
            font-family: inherit; cursor: pointer; transition: all 0.2s;
        }}
        .sample-btn:hover {{ background: rgba(6, 182, 212, 0.2); border-color: var(--accent-cyan); color: white; }}
        .preview-container {{
            position: relative; width: 100%; border-radius: 16px; overflow: hidden; background: #000;
            min-height: 280px; display: flex; align-items: center; justify-content: center; border: 1px solid rgba(255, 255, 255, 0.08);
        }}
        .preview-img {{ width: 100%; max-height: 420px; object-fit: contain; display: block; }}
        .score-box {{
            display: flex; align-items: center; gap: 24px; margin-bottom: 24px; padding: 20px;
            background: rgba(15, 23, 42, 0.6); border-radius: 16px; border: 1px solid rgba(255, 255, 255, 0.06);
        }}
        .status-details {{ flex: 1; }}
        .status-label {{ font-size: 13px; color: var(--text-muted); text-transform: uppercase; }}
        .status-title {{ font-size: 22px; font-weight: 700; margin: 4px 0; }}
        .recommendation-box {{
            margin-top: 20px; padding: 16px; border-radius: 12px; background: rgba(255, 255, 255, 0.04);
            border-left: 4px solid var(--accent-cyan); font-size: 14px; line-height: 1.5; color: #cbd5e1;
        }}
        .spinner {{
            width: 36px; height: 36px; border: 4px solid rgba(255, 255, 255, 0.1);
            border-left-color: var(--accent-cyan); border-radius: 50%; animation: spin 1s linear infinite; display: none;
        }}
        @keyframes spin {{ 100% {{ transform: rotate(360deg); }} }}
    </style>
</head>
<body>

<div class="container">
    <header>
        <div class="brand">
            <div class="logo-icon">AIQ</div>
            <div>
                <div class="brand-title">Street AIQ (YOLOv8 Trash Detector)</div>
                <div style="font-size: 13px; color: var(--text-muted);">Trained with Hard Negatives (v6 Model)</div>
            </div>
        </div>
        <div class="badge-live">
            <div class="pulse-dot"></div> YOLOv8 Road Detector Active
        </div>
    </header>

    <div class="main-grid">
        <div class="card">
            <div class="card-header">
                <span>Upload Road Image</span>
                <span style="font-size: 13px; color: var(--text-muted);">JPG / PNG</span>
            </div>
            
            <div class="dropzone" id="dropzone" onclick="document.getElementById('fileInput').click()">
                <div class="upload-icon">
                    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#06b6d4" stroke-width="2">
                        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                        <polyline points="17 8 12 3 7 8"></polyline>
                        <line x1="12" y1="3" x2="12" y2="15"></line>
                    </svg>
                </div>
                <div style="font-weight: 600; font-size: 16px; margin-bottom: 4px;">Drag & Drop or Click to Upload</div>
                <div style="font-size: 13px; color: var(--text-muted);">YOLOv8 Object Detection Engine</div>
                <input type="file" id="fileInput" accept="image/*" style="display:none" onchange="handleFileUpload(this.files[0])">
            </div>

            <div class="sample-section">
                <div class="sample-title">⚡ 1-Click Test Samples</div>
                <div class="sample-grid">
                    {sample_buttons_html}
                </div>
            </div>
        </div>

        <div class="card">
            <div class="card-header">
                <span>YOLOv8 Detection Analysis</span>
                <span id="confBadge" style="font-size: 13px; color: #4ade80;">--</span>
            </div>

            <div class="preview-container">
                <div class="spinner" id="spinner"></div>
                <img id="previewImg" class="preview-img" src="" alt="Road Preview" style="display:none;">
                <div id="placeholderText" style="color: var(--text-muted); font-size: 14px; text-align: center; padding: 20px;">
                    📷 Upload an image to detect exact trash bounding boxes on the road.
                </div>
            </div>

            <div id="resultsSection" style="margin-top: 24px; display: none;">
                <div class="score-box">
                    <div class="status-details">
                        <div class="status-label">Detection Status</div>
                        <div class="status-title" id="statusTitle">--</div>
                        <div style="font-size: 13px; color: var(--text-muted);" id="confidenceText">Trash Regions Found: 0</div>
                    </div>
                </div>

                <div class="recommendation-box" id="recommendationText">--</div>
            </div>
        </div>
    </div>
</div>

<script>
    const dropzone = document.getElementById('dropzone');

    dropzone.addEventListener('dragover', (e) => {{ e.preventDefault(); dropzone.classList.add('dragover'); }});
    dropzone.addEventListener('dragleave', () => {{ dropzone.classList.remove('dragover'); }});
    dropzone.addEventListener('drop', (e) => {{
        e.preventDefault(); dropzone.classList.remove('dragover');
        if (e.dataTransfer.files.length > 0) handleFileUpload(e.dataTransfer.files[0]);
    }});

    async function handleFileUpload(file) {{
        if (!file) return;
        showLoading();
        const formData = new FormData();
        formData.append('file', file);
        try {{
            const response = await fetch('/api/predict', {{ method: 'POST', body: formData }});
            const data = await response.json();
            renderResults(data);
        }} catch (err) {{
            alert('Error running inference.'); console.error(err);
        }}
    }}

    async function loadSample(category, filename) {{
        showLoading();
        try {{
            const response = await fetch(`/api/sample/${{category}}/${{filename}}`);
            const data = await response.json();
            renderResults(data);
        }} catch (err) {{
            alert('Error loading sample image.'); console.error(err);
        }}
    }}

    function showLoading() {{
        document.getElementById('placeholderText').style.display = 'none';
        document.getElementById('previewImg').style.display = 'none';
        document.getElementById('spinner').style.display = 'block';
        document.getElementById('resultsSection').style.display = 'none';
    }}

    function renderResults(data) {{
        document.getElementById('spinner').style.display = 'none';
        const img = document.getElementById('previewImg');
        img.src = data.annotated_image;
        img.style.display = 'block';

        document.getElementById('resultsSection').style.display = 'block';

        const titleEl = document.getElementById('statusTitle');
        titleEl.innerText = data.decision;
        titleEl.style.color = data.badge_color;

        document.getElementById('confidenceText').innerText = `Detected Bounding Boxes: ${{data.trash_count}}`;
        document.getElementById('confBadge').innerText = data.trash_detected ? 'TRASH DETECTED' : 'NO TRASH';
        document.getElementById('confBadge').style.color = data.badge_color;
        document.getElementById('recommendationText').innerText = data.recommendation;
        document.getElementById('recommendationText').style.borderLeftColor = data.badge_color;
    }}

    window.onload = () => {{
        const firstBtn = document.querySelector('.sample-btn');
        if (firstBtn) firstBtn.click();
    }};
</script>
</body>
</html>"""
    return html_content
class FrameRequest(BaseModel):
    image: str
    lat: float = 0.0
    lng: float = 0.0
    vehicle_number: str = ""
    ward: str = ""
    zone: str = ""
    session_id: str = None
    point_type: str = None

@app.post("/process_frame")
async def process_frame(req: FrameRequest):
    encoded = req.image.split(",", 1)[1] if "," in req.image else req.image
    img_bytes = base64.b64decode(encoded)
    
    uid = str(uuid.uuid4())
    raw_filename = f"raw_{uid}.jpg"
    filename = f"{uid}.jpg"

    # 1. Run AI detection on the raw image
    res = detect_road_trash(img_bytes)
    
    if res["trash_count"] == 0:
        road_status = "No Trash Detected"
        cat_subfolder = "no_trash_detected"
    else:
        road_status = "Trash Detected"
        cat_subfolder = "trash_detected"

    # 2. Save pure raw image (NO annotations) into separate training folder
    training_target = SNAPSHOTS_DIR / "training" / cat_subfolder / raw_filename
    with open(training_target, "wb") as f:
        f.write(img_bytes)

    # 3. Save annotated image with bounding boxes & banner into separate analysed folder
    out_encoded = res["annotated_image"].split(",", 1)[1] if "," in res["annotated_image"] else res["annotated_image"]
    out_bytes = base64.b64decode(out_encoded)
    analysed_target = SNAPSHOTS_DIR / "analysed" / cat_subfolder / filename
    with open(analysed_target, "wb") as f:
        f.write(out_bytes)

    image_url = f"/snapshots/analysed/{cat_subfolder}/{filename}"
    raw_image_url = f"/snapshots/training/{cat_subfolder}/{raw_filename}"

    snapshot = {
        "id": uid,
        "display_class": road_status,
        "road_status": road_status,
        "training_tag": road_status,  # Tagged with model detection for training
        "confidence": res["cleanliness_score"] / 100.0,
        "road_confidence": res["cleanliness_score"] / 100.0,
        "image_url": image_url,          # Analysed image (with bounding boxes & banners)
        "raw_image_url": raw_image_url,  # Raw captured image (ZERO annotations)
        "trash_count": res.get("trash_count", 0),
        "lat": req.lat,
        "lng": req.lng,
        "vehicle_number": req.vehicle_number,
        "ward": req.ward,
        "zone": req.zone,
        "timestamp": datetime.now().strftime("%Y-%m-%d %I:%M:%S %p")
    }
    
    history.append(snapshot)
    if len(history) > 1000:
        history.pop(0)
        
    import json
    try:
        with open(HISTORY_FILE, "w") as f:
            json.dump(history, f)
    except Exception as e:
        print("Error saving history:", e)

    return snapshot

@app.get("/api/snapshots")
async def api_snapshots():
    for s in history:
        if "raw_image_url" not in s:
            s["raw_image_url"] = s.get("image_url")
        if "training_tag" not in s:
            s["training_tag"] = s.get("display_class", s.get("road_status", "No Trash Detected"))
    return {"snapshots": history}

@app.get("/api/training_dataset")
async def api_training_dataset():
    training_items = []
    for s in history:
        training_items.append({
            "id": s.get("id", ""),
            "raw_image_url": s.get("raw_image_url", s.get("image_url")),
            "training_tag": s.get("training_tag", s.get("road_status", "No Trash Detected")),
            "timestamp": s.get("timestamp", ""),
            "vehicle_number": s.get("vehicle_number", ""),
            "lat": s.get("lat", 0.0),
            "lng": s.get("lng", 0.0),
        })
    return {"training_dataset": training_items, "total": len(training_items)}

if __name__ == "__main__":
    # You might want to change the port if v5 is also running. Defaulting to 5001.
    uvicorn.run(app, host="127.0.0.1", port=5001)
