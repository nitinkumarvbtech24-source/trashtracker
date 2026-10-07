import os
import sys
from pathlib import Path
from ultralytics import YOLO

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")
MODEL_PATH = BASE_DIR / "models" / "trash_detector" / "best.pt"
TEST_IMG_DIR = BASE_DIR / "dataset_trash_yolo_v4" / "test" / "images"
TEST_LBL_DIR = BASE_DIR / "dataset_trash_yolo_v4" / "test" / "labels"

print("==================================================")
print("EXACT CLEAN-ROAD & TRASH-POSITIVE THRESHOLD VERIFICATION")
print("==================================================")
print(f"Model Path: {MODEL_PATH}")
print(f"Test Image Directory: {TEST_IMG_DIR}\n")

model = YOLO(str(MODEL_PATH))

test_img_paths = sorted(list(TEST_IMG_DIR.glob("*.*")))

clean_images = []
trash_positive_images = []

for img_p in test_img_paths:
    lbl_p = TEST_LBL_DIR / f"{img_p.stem}.txt"
    has_boxes = False
    if lbl_p.exists():
        with open(lbl_p, "r", encoding="utf-8", errors="ignore") as f:
            lines = [l.strip() for l in f if l.strip()]
            if len(lines) > 0:
                has_boxes = True
    
    if has_boxes:
        trash_positive_images.append(img_p)
    else:
        clean_images.append(img_p)

print(f"Total Test Set Files:           {len(test_img_paths)}")
print(f"Trash-Positive Images (GT > 0): {len(trash_positive_images)}")
print(f"Clean-Road Images (GT == 0):    {len(clean_images)}\n")

print("Clean-Road Image Filenames:")
for idx, p in enumerate(clean_images, 1):
    print(f"  [{idx}] {p.name}")

thresholds = [0.25, 0.20, 0.15, 0.10]

for t in thresholds:
    print(f"\n==================================================")
    print(f"EVALUATING INFERENCE AT CONFIDENCE THRESHOLD = {t:.2f}")
    print(f"==================================================")

    # 1. Evaluate clean-road images (7 images)
    clean_correct = 0
    clean_false_positives = 0
    fp_details = []

    for img_p in clean_images:
        res = model(str(img_p), conf=t, verbose=False)[0]
        boxes = res.boxes
        if len(boxes) == 0:
            clean_correct += 1
        else:
            clean_false_positives += 1
            box_confs = [round(float(b.conf[0].item()), 3) for b in boxes]
            fp_details.append({
                "filename": img_p.name,
                "box_count": len(boxes),
                "confidences": box_confs
            })

    # 2. Evaluate trash-positive images (40 images)
    trash_detected = 0
    trash_missed = 0

    for img_p in trash_positive_images:
        res = model(str(img_p), conf=t, verbose=False)[0]
        boxes = res.boxes
        if len(boxes) > 0:
            trash_detected += 1
        else:
            trash_missed += 1

    clean_specificity = (clean_correct / len(clean_images)) * 100.0 if len(clean_images) > 0 else 100.0

    print(f"Clean-Road Performance:")
    print(f"  - Clean Images with ZERO Detections: {clean_correct} / {len(clean_images)}")
    print(f"  - Clean Images with AT LEAST ONE Detection: {clean_false_positives} / {len(clean_images)}")
    print(f"  - Clean-Road Specificity: {clean_specificity:.2f}%")

    if clean_false_positives > 0:
        print(f"  - False Positive Clean Image Details:")
        for fp in fp_details:
            print(f"      File: {fp['filename']} | Boxes: {fp['box_count']} | Confidences: {fp['confidences']}")

    print(f"\nTrash-Positive Performance:")
    print(f"  - Trash-Positive Images Detected: {trash_detected} / {len(trash_positive_images)}")
    print(f"  - Trash-Positive Images Missed:   {trash_missed} / {len(trash_positive_images)}")
