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

# Remove any stray *_annotated.jpg files created during test runs
stray_files = list(TEST_IMG_DIR.glob("*_annotated.jpg"))
for sf in stray_files:
    sf.unlink()
    print(f"Removed stray test artifact: {sf.name}")

model = YOLO(str(MODEL_PATH))

test_img_paths = sorted([p for p in TEST_IMG_DIR.glob("*.*") if not p.name.endswith("_annotated.jpg")])

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

print("\n==================================================")
print("REAL TEST SET THRESHOLD VERIFICATION (47 GENUINE TEST IMAGES)")
print("==================================================")
print(f"Total Genuine Test Set Images:   {len(test_img_paths)}")
print(f"Trash-Positive Test Images:       {len(trash_positive_images)}")
print(f"Clean-Road Test Images:           {len(clean_images)}\n")

print("The 7 Genuine Clean-Road Image Filenames:")
for idx, p in enumerate(clean_images, 1):
    print(f"  [{idx}] {p.name}")

thresholds = [0.25, 0.20, 0.15, 0.10]

threshold_report = []

for t in thresholds:
    print(f"\n--------------------------------------------------")
    print(f"EVALUATING INFERENCE AT CONFIDENCE THRESHOLD = {t:.2f}")
    print(f"--------------------------------------------------")

    # 1. Clean-Road Evaluation
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

    # 2. Trash-Positive Evaluation
    trash_detected = 0
    trash_missed = 0
    missed_filenames = []

    for img_p in trash_positive_images:
        res = model(str(img_p), conf=t, verbose=False)[0]
        boxes = res.boxes
        if len(boxes) > 0:
            trash_detected += 1
        else:
            trash_missed += 1
            missed_filenames.append(img_p.name)

    clean_specificity = (clean_correct / len(clean_images)) * 100.0 if len(clean_images) > 0 else 100.0

    print(f"Clean-Road Results:")
    print(f"  - Clean Images with ZERO Detections:       {clean_correct} / {len(clean_images)}")
    print(f"  - Clean Images with AT LEAST ONE Detection:{clean_false_positives} / {len(clean_images)}")
    print(f"  - Clean-Road Specificity:                  {clean_specificity:.2f}%")

    if clean_false_positives > 0:
        print(f"  - False Positive Details:")
        for fp in fp_details:
            print(f"      File: {fp['filename']} | Boxes: {fp['box_count']} | Confidences: {fp['confidences']}")

    print(f"\nTrash-Positive Results:")
    print(f"  - Trash-Positive Images Detected:          {trash_detected} / {len(trash_positive_images)}")
    print(f"  - Trash-Positive Images Missed:            {trash_missed} / {len(trash_positive_images)}")

    threshold_report.append({
        "threshold": t,
        "clean_zero": clean_correct,
        "clean_fp": clean_false_positives,
        "clean_spec_pct": clean_specificity,
        "fp_details": fp_details,
        "trash_detected": trash_detected,
        "trash_missed": trash_missed,
        "missed_filenames": missed_filenames
    })
