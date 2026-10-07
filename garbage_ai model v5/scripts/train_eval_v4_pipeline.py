import os
import sys
import time
import json
import shutil
from pathlib import Path
import cv2
import numpy as np
import torch
from ultralytics import YOLO

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")
DATA_YAML = BASE_DIR / "dataset_trash_yolo_v4" / "data.yaml"
TARGET_MODEL_DIR = BASE_DIR / "models" / "trash_detector"
TARGET_MODEL_DIR.mkdir(parents=True, exist_ok=True)
BEST_WEIGHTS_PATH = TARGET_MODEL_DIR / "best.pt"

RESULTS_OUTPUT_DIR = BASE_DIR / "results_trash_detector"
RESULTS_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

print("==================================================")
print("STARTING YOLOV8 TRAINING PIPELINE (DATASET V4)")
print("==================================================")
print(f"Dataset Path: {DATA_YAML}")
print(f"Target Model Path: {BEST_WEIGHTS_PATH}")

device = "0" if torch.cuda.is_available() else "cpu"
print(f"Compute Device: {device} (CUDA Available: {torch.cuda.is_available()})")

# 1. Initialize pretrained YOLOv8n model
model = YOLO("yolov8n.pt")

# 2. Train model over 100 epochs
start_time = time.time()
print("\nInitiating transfer learning over 100 epochs...")

train_results = model.train(
    data=str(DATA_YAML),
    epochs=100,
    imgsz=640,
    batch=16,
    workers=4,
    device=device,
    project=str(BASE_DIR / "runs" / "detect"),
    name="trash_detector_v4_run",
    exist_ok=True,
    patience=20,
    seed=42,
    verbose=True
)

training_time = time.time() - start_time
print(f"\nTraining completed in {training_time/60:.2f} minutes.")

# Find best weights from run directory
run_dir = BASE_DIR / "runs" / "detect" / "trash_detector_v4_run"
source_best_pt = run_dir / "weights" / "best.pt"

if source_best_pt.exists():
    shutil.copy2(source_best_pt, BEST_WEIGHTS_PATH)
    print(f"✅ Best trained model saved to: {BEST_WEIGHTS_PATH}")
else:
    print(f"⚠️ Warning: {source_best_pt} not found!")

# 3. Load best model for evaluation on unseen TEST split
print("\n==================================================")
print("EVALUATING MODEL ON UNSEEN TEST SPLIT")
print("==================================================")

trained_model = YOLO(str(BEST_WEIGHTS_PATH))
val_metrics = trained_model.val(data=str(DATA_YAML), split="test", device=device)

precision = float(val_metrics.results_dict.get("metrics/precision(B)", 0.0))
recall = float(val_metrics.results_dict.get("metrics/recall(B)", 0.0))
map50 = float(val_metrics.results_dict.get("metrics/mAP50(B)", 0.0))
map50_95 = float(val_metrics.results_dict.get("metrics/mAP50-95(B)", 0.0))

if precision + recall > 0:
    f1_score = 2 * (precision * recall) / (precision + recall)
else:
    f1_score = 0.0

print(f"\n--- EVALUATION METRICS (TEST SPLIT) ---")
print(f"Precision:    {precision*100:.2f}%")
print(f"Recall:       {recall*100:.2f}%")
print(f"mAP@50:       {map50*100:.2f}%")
print(f"mAP@50-95:    {map50_95*100:.2f}%")
print(f"F1 Score:     {f1_score*100:.2f}%")

# 4. Detailed Image-Level Test Metrics (False Positives, Specificity, True Positives)
test_imgs = list((BASE_DIR / "dataset_trash_yolo_v4" / "test" / "images").glob("*.*"))

total_test_images = len(test_imgs)
trash_positive_test_images = 0
clean_road_test_images = 0

false_positives = 0
false_negatives = 0
true_positives = 0
true_negatives = 0

for img_p in test_imgs:
    lbl_p = BASE_DIR / "dataset_trash_yolo_v4" / "test" / "labels" / f"{img_p.stem}.txt"
    has_gt_trash = False
    if lbl_p.exists():
        with open(lbl_p, "r", encoding="utf-8", errors="ignore") as f:
            lines = [line.strip() for line in f if line.strip()]
            if len(lines) > 0:
                has_gt_trash = True

    if has_gt_trash:
        trash_positive_test_images += 1
    else:
        clean_road_test_images += 1

    res = trained_model(str(img_p), conf=0.25, verbose=False)[0]
    num_detections = len(res.boxes)
    pred_trash = (num_detections > 0)

    if not has_gt_trash and pred_trash:
        false_positives += 1
    elif has_gt_trash and not pred_trash:
        false_negatives += 1
    elif has_gt_trash and pred_trash:
        true_positives += 1
    else:
        true_negatives += 1

clean_specificity = (true_negatives / clean_road_test_images * 100.0) if clean_road_test_images > 0 else 100.0

print("\n--- TEST SPLIT IMAGE-LEVEL PERFORMANCE SUMMARY ---")
print(f"Total Test Images:                      {total_test_images}")
print(f"Trash-Positive Test Images:             {trash_positive_test_images}")
print(f"Clean-Road Test Images:                 {clean_road_test_images}")
print(f"Clean-Road Specificity (True Negatives): {clean_specificity:.2f}% ({true_negatives}/{clean_road_test_images})")
print(f"Trash Images Correctly Detected (TP):   {true_positives}/{trash_positive_test_images}")
print(f"Trash Images Missed (FN):               {false_negatives}/{trash_positive_test_images}")
print(f"Clean Images Falsely Flagged (FP):      {false_positives}/{clean_road_test_images}")

# 5. Generate prediction samples using CLEAN visual style (thin 1-2px red boxes, NO text, NO labels)
sample_out_dir = RESULTS_OUTPUT_DIR / "sample_predictions"
sample_out_dir.mkdir(parents=True, exist_ok=True)

for i, img_p in enumerate(test_imgs):
    img_bgr = cv2.imread(str(img_p))
    if img_bgr is None:
        continue
    
    annotated_bgr = img_bgr.copy()
    res = trained_model(str(img_p), conf=0.25, verbose=False)[0]
    boxes = res.boxes

    if len(boxes) > 0:
        for box in boxes:
            x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
            # Draw ONLY a thin 2-pixel red bounding box around detected trash. ZERO text, ZERO labels, ZERO percentages.
            cv2.rectangle(annotated_bgr, (x1, y1), (x2, y2), (0, 0, 255), 2)

    out_path = sample_out_dir / f"clean_style_pred_{i+1:02d}_{img_p.name}"
    cv2.imwrite(str(out_path), annotated_bgr)

print(f"\nSaved {total_test_images} clean-style prediction images to: {sample_out_dir}")

# 6. Save pipeline execution summary
epochs_completed = getattr(train_results, 'epoch', 100) if hasattr(train_results, 'epoch') else 100

summary_data = {
    "status": "COMPLETED",
    "model_path": str(BEST_WEIGHTS_PATH),
    "epochs_completed": epochs_completed,
    "training_time_minutes": round(training_time / 60, 2),
    "precision": round(precision * 100, 2),
    "recall": round(recall * 100, 2),
    "mAP50": round(map50 * 100, 2),
    "mAP50_95": round(map50_95 * 100, 2),
    "f1_score": round(f1_score * 100, 2),
    "total_test_images": total_test_images,
    "trash_positive_test_images": trash_positive_test_images,
    "clean_road_test_images": clean_road_test_images,
    "clean_road_specificity_pct": round(clean_specificity, 2),
    "true_positives": true_positives,
    "true_negatives": true_negatives,
    "false_positives": false_positives,
    "false_negatives": false_negatives,
    "sample_predictions_dir": str(sample_out_dir)
}

with open(BASE_DIR / "training_v4_summary.json", "w", encoding="utf-8") as f:
    json.dump(summary_data, f, indent=2)

print("\n==================================================")
print("YOLOV8 TRAINING & EVALUATION COMPLETED SUCCESSFULLY")
print("==================================================")
