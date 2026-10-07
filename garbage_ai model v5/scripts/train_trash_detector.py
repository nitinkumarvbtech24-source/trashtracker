import os
import shutil
import time
from pathlib import Path
import torch
import numpy as np
import cv2
from PIL import Image
from ultralytics import YOLO

BASE_DIR = Path(r"e:\nitin\model2")
DATA_YAML = BASE_DIR / "dataset_trash_yolo" / "data.yaml"
TARGET_MODEL_DIR = BASE_DIR / "models" / "trash_detector"
TARGET_MODEL_DIR.mkdir(parents=True, exist_ok=True)
BEST_WEIGHTS_PATH = TARGET_MODEL_DIR / "best.pt"

RESULTS_OUTPUT_DIR = BASE_DIR / "results_trash_detector"
RESULTS_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

print("==================================================")
print("STARTING OPTIMIZED YOLOv8 CUSTOM TRASH DETECTOR TRAINING")
print("==================================================")

# 1. Load pretrained yolov8n.pt
model = YOLO("yolov8n.pt")

# 2. Train model over 30 epochs (optimal for 296 transfer learning images to avoid overtraining)
start_time = time.time()
print("\nInitiating training over 30 epochs on dataset:", DATA_YAML)

train_results = model.train(
    data=str(DATA_YAML),
    epochs=30,
    imgsz=640,
    batch=16,
    workers=4,
    project=str(BASE_DIR / "runs" / "detect"),
    name="trash_detector_run",
    exist_ok=True,
    patience=10,
    seed=42,
    verbose=True
)

training_time = time.time() - start_time
print(f"\nTraining completed in {training_time/60:.2f} minutes.")

# Find best weights from run directory
run_dir = BASE_DIR / "runs" / "detect" / "trash_detector_run"
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
val_metrics = trained_model.val(data=str(DATA_YAML), split="test")

precision = val_metrics.results_dict.get("metrics/precision(B)", 0.0)
recall = val_metrics.results_dict.get("metrics/recall(B)", 0.0)
map50 = val_metrics.results_dict.get("metrics/mAP50(B)", 0.0)
map50_95 = val_metrics.results_dict.get("metrics/mAP50-95(B)", 0.0)

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

# Save evaluation report to TXT file
eval_report_path = BASE_DIR / "evaluation_report.txt"
with open(eval_report_path, "w") as f:
    f.write("YOLOv8 CUSTOM TRASH DETECTOR - EVALUATION REPORT\n")
    f.write("================================================\n")
    f.write(f"Model Path: {BEST_WEIGHTS_PATH}\n")
    f.write(f"Training Time: {training_time/60:.2f} mins\n")
    f.write(f"Precision: {precision*100:.2f}%\n")
    f.write(f"Recall: {recall*100:.2f}%\n")
    f.write(f"mAP@50: {map50*100:.2f}%\n")
    f.write(f"mAP@50-95: {map50_95*100:.2f}%\n")
    f.write(f"F1 Score: {f1_score*100:.2f}%\n")

print(f"Evaluation report saved to: {eval_report_path}")

# 4. Specific Checks on Test Split (False Positives, False Negatives, Small Trash)
test_imgs = list((BASE_DIR / "dataset_trash_yolo" / "test" / "images").glob("*.*"))

false_positives = 0
false_negatives = 0
true_positives = 0
true_negatives = 0

print("\n--- DETAILED IMAGE-LEVEL ERROR ANALYSIS ON TEST SPLIT ---")

for img_p in test_imgs:
    # Check if image has ground truth trash
    lbl_p = BASE_DIR / "dataset_trash_yolo" / "test" / "labels" / f"{img_p.stem}.txt"
    has_gt_trash = False
    if lbl_p.exists():
        with open(lbl_p, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
            if len(lines) > 0:
                has_gt_trash = True
                
    # Run prediction
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

print(f"Total Test Images: {len(test_imgs)}")
print(f"True Negatives (Clean Road correct): {true_negatives}")
print(f"True Positives (Trash detected correct): {true_positives}")
print(f"False Positives (Clean Road falsely flagged): {false_positives}")
print(f"False Negatives (Trash missed): {false_negatives}")

# 5. Generate visual verification sample prediction images
print("\n--- GENERATING SAMPLE PREDICTION IMAGES ---")
sample_out_dir = RESULTS_OUTPUT_DIR / "sample_predictions"
sample_out_dir.mkdir(parents=True, exist_ok=True)

# Save annotated test predictions
for i, img_p in enumerate(test_imgs[:10]):
    res = trained_model(str(img_p), conf=0.25, verbose=False)[0]
    res_bgr = res.plot()
    out_path = sample_out_dir / f"test_pred_{i+1:02d}_{img_p.name}"
    cv2.imwrite(str(out_path), res_bgr)

print(f"Saved {min(10, len(test_imgs))} sample prediction images to: {sample_out_dir}")
