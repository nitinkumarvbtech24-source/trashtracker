import os
import sys
import time
import uuid
import glob
import cv2
import numpy as np
from flask import Flask, render_template, request, jsonify, send_from_directory
from ultralytics import YOLO

# Web Application Paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.normpath(os.path.join(BASE_DIR, "..", "Garbage_ai_model_v6", "weights", "garbage_ai_model_v6_best.pt"))
UPLOADS_DIR = os.path.join(BASE_DIR, "static", "uploads")
RESULTS_DIR = os.path.join(BASE_DIR, "static", "results")
SAMPLES_DIR = os.path.join(BASE_DIR, "static", "samples")

os.makedirs(UPLOADS_DIR, exist_ok=True)
os.makedirs(RESULTS_DIR, exist_ok=True)
os.makedirs(SAMPLES_DIR, exist_ok=True)

app = Flask(__name__)

# Global model container
print("Loading Garbage_ai_model_v6 trained YOLOv8m model...")
try:
    model = YOLO(MODEL_PATH)
    print(f"Model loaded successfully from: {MODEL_PATH}")
except Exception as e:
    print(f"Warning: Failed to load model from {MODEL_PATH}: {e}")
    model = None

# Stats tracking
stats = {
    "total_scans": 0,
    "total_detected_trash": 0,
    "model_name": "Garbage_ai_model_v6 (YOLOv8m)",
    "device": "NVIDIA GeForce RTX 4060 GPU"
}

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/samples", methods=["GET"])
def get_samples():
    sample_files = glob.glob(os.path.join(SAMPLES_DIR, "*.*"))
    samples = [os.path.basename(f) for f in sample_files[:12]]
    return jsonify({"samples": samples})

@app.route("/api/detect", methods=["POST"])
def detect_trash():
    global stats
    if model is None:
        return jsonify({"error": "AI Model not loaded"}), 500

    conf_thresh = float(request.form.get("confidence", 0.25))
    
    # Check if upload file or sample selected
    filename = None
    filepath = None

    if "file" in request.files and request.files["file"].filename != "":
        file = request.files["file"]
        ext = os.path.splitext(file.filename)[1]
        if ext.lower() not in [".jpg", ".jpeg", ".png", ".bmp", ".webp"]:
            return jsonify({"error": "Unsupported image format"}), 400
        
        unique_name = f"upload_{uuid.uuid4().hex[:8]}{ext}"
        filepath = os.path.join(UPLOADS_DIR, unique_name)
        file.save(filepath)
        filename = unique_name
    elif "sample" in request.form:
        sample_name = request.form["sample"]
        filepath = os.path.join(SAMPLES_DIR, sample_name)
        if not os.path.exists(filepath):
            return jsonify({"error": "Sample image not found"}), 404
        filename = f"sample_{sample_name}"
    else:
        return jsonify({"error": "No image file provided"}), 400

    # Read image
    img = cv2.imread(filepath)
    if img is None:
        return jsonify({"error": "Failed to read image"}), 400
    
    h_orig, w_orig = img.shape[:2]

    # Run AI Inference
    start_time = time.time()
    results = model.predict(source=filepath, conf=conf_thresh, imgsz=640, verbose=False)
    inference_time = (time.time() - start_time) * 1000.0  # ms
    
    res = results[0]
    boxes = res.boxes
    
    detections = []
    confidences = []
    
    # Render custom styled output with bounding boxes
    annotated_img = img.copy()
    
    for idx, box in enumerate(boxes):
        conf = float(box.conf[0])
        cls_id = int(box.cls[0])
        xyxy = box.xyxy[0].cpu().numpy().tolist()
        x1, y1, x2, y2 = map(int, xyxy)
        
        confidences.append(conf)
        
        # Color coding: bright green box with dark backdrop tag
        box_color = (0, 220, 100) # vibrant green
        tag_bg = (15, 23, 42)    # dark slate
        
        # Bounding box line
        cv2.rectangle(annotated_img, (x1, y1), (x2, y2), box_color, 3)
        
        # Label tag
        label_text = f"Trash {conf * 100:.1f}%"
        (text_w, text_h), baseline = cv2.getTextSize(label_text, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
        
        # Tag background rectangle
        cv2.rectangle(annotated_img, (x1, max(0, y1 - text_h - 10)), (x1 + text_w + 10, y1), tag_bg, -1)
        cv2.rectangle(annotated_img, (x1, max(0, y1 - text_h - 10)), (x1 + text_w + 10, y1), box_color, 1)
        cv2.putText(annotated_img, label_text, (x1 + 5, max(15, y1 - 5)), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)
        
        detections.append({
            "id": idx + 1,
            "class": "trash",
            "confidence": round(conf * 100, 2),
            "box": [round(x1, 1), round(y1, 1), round(x2, 1), round(y2, 1)],
            "width": round(x2 - x1, 1),
            "height": round(y2 - y1, 1)
        })
        
    # Save annotated result image
    res_filename = f"res_{filename}"
    res_filepath = os.path.join(RESULTS_DIR, res_filename)
    cv2.imwrite(res_filepath, annotated_img)

    # Calculate statistics & risk evaluation
    total_count = len(detections)
    stats["total_scans"] += 1
    stats["total_detected_trash"] += total_count

    avg_conf = round(float(np.mean(confidences)) * 100, 2) if confidences else 0.0
    max_conf = round(float(np.max(confidences)) * 100, 2) if confidences else 0.0
    min_conf = round(float(np.min(confidences)) * 100, 2) if confidences else 0.0

    if total_count == 0:
        risk_level = "CLEAN"
        risk_color = "emerald"
        recommendation = "No road trash detected. Area is clean."
    elif total_count <= 2:
        risk_level = "LOW RISK"
        risk_color = "yellow"
        recommendation = "Isolated trash detected. Scheduled cleanup recommended."
    elif total_count <= 5:
        risk_level = "MODERATE HAZARD"
        risk_color = "orange"
        recommendation = "Multiple trash items detected. Priority cleanup advised."
    else:
        risk_level = "HIGH CONTAMINATION"
        risk_color = "rose"
        recommendation = "Severe waste accumulation detected! Immediate dispatch required."

    return jsonify({
        "success": True,
        "image_name": filename,
        "original_url": f"/static/uploads/{filename}" if "upload_" in filename else f"/static/samples/{filename.replace('sample_', '')}",
        "result_url": f"/static/results/{res_filename}",
        "image_dims": {"width": w_orig, "height": h_orig},
        "summary": {
            "total_trash_detected": total_count,
            "average_confidence": avg_conf,
            "max_confidence": max_conf,
            "min_confidence": min_conf,
            "risk_level": risk_level,
            "risk_color": risk_color,
            "recommendation": recommendation,
            "inference_time_ms": round(inference_time, 1),
            "confidence_threshold_used": conf_thresh
        },
        "detections": detections,
        "global_stats": stats
    })

if __name__ == "__main__":
    print("Starting Garbage AI v6 Web Dashboard on http://127.0.0.1:5000 ...")
    app.run(host="127.0.0.1", port=5000, debug=False)
