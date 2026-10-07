import os
import sys
import shutil
import hashlib
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")

SRC_1 = BASE_DIR / "aiq trash detection 1.v2i.yolov8"
SRC_2 = BASE_DIR / "trash.v1i.yolov8"
SRC_3 = BASE_DIR / "Clean road"

REVIEW_DIR = BASE_DIR / "annotation_review"

# Clear review directory if exists
if REVIEW_DIR.exists():
    shutil.rmtree(REVIEW_DIR)

dirs = {
    "missing": REVIEW_DIR / "missing_annotations",
    "partial": REVIEW_DIR / "partial_annotations",
    "questionable": REVIEW_DIR / "questionable_annotations",
    "clean": REVIEW_DIR / "genuinely_clean",
    "valid": REVIEW_DIR / "valid_annotated"
}

for d in dirs.values():
    d.mkdir(parents=True, exist_ok=True)

sources = [
    ("aiq_v2i", SRC_1, True),      # Expected to have trash
    ("trash_v1i", SRC_2, True),    # Expected to have trash
    ("Clean_road", SRC_3, False)   # Expected to be clean
]

print("==================================================")
print("AUDITING ANNOTATION QUALITY ACROSS ORIGINAL SOURCES")
print("==================================================")

total_images = 0
images_with_annotations = 0
images_without_annotations = 0

missing_annotations_list = []
partial_annotations_list = []
questionable_annotations_list = []
genuinely_clean_list = []
valid_annotated_list = []

for src_name, src_path, expected_positive in sources:
    if not src_path.exists():
        print(f"Warning: {src_path} does not exist!")
        continue

    imgs = list(src_path.rglob("*.jpg")) + list(src_path.rglob("*.png")) + list(src_path.rglob("*.jpeg"))
    for img_p in imgs:
        total_images += 1
        
        # Find matching label file
        lbl_p = None
        if "images" in img_p.parts:
            parts = list(img_p.parts)
            idx = parts.index("images")
            parts[idx] = "labels"
            cand = Path(*parts).with_suffix(".txt")
            if cand.exists():
                lbl_p = cand
        if lbl_p is None:
            cand = img_p.with_suffix(".txt")
            if cand.exists():
                lbl_p = cand
        if lbl_p is None:
            matches = list(src_path.rglob(f"{img_p.stem}.txt"))
            matches = [m for m in matches if not m.name.lower().startswith("readme") and "requirement" not in m.name]
            if matches:
                lbl_p = matches[0]

        bboxes = []
        if lbl_p and lbl_p.exists():
            with open(lbl_p, 'r', encoding='utf-8', errors='ignore') as f:
                lines = [line.strip() for line in f if line.strip()]
                for line in lines:
                    parts = line.split()
                    if len(parts) >= 5:
                        try:
                            cx, cy, w, h = map(float, parts[1:5])
                            bboxes.append((cx, cy, w, h))
                        except ValueError:
                            pass

        num_boxes = len(bboxes)
        total_bbox_area = sum(w * h for _, _, w, h in bboxes)

        # Image analysis for anomaly detection
        cv_img = cv2.imread(str(img_p))
        edge_density = 0.0
        color_std = 0.0

        if cv_img is not None:
            gray = cv2.cvtColor(cv_img, cv2.COLOR_BGR2GRAY)
            edges = cv2.Canny(gray, 50, 150)
            edge_density = float(np.sum(edges > 0)) / (gray.shape[0] * gray.shape[1])
            color_std = float(np.std(gray))

        entry_info = {
            "source": src_name,
            "img_path": img_p,
            "lbl_path": lbl_p,
            "bboxes": bboxes,
            "num_boxes": num_boxes,
            "total_bbox_area": total_bbox_area,
            "edge_density": edge_density,
            "color_std": color_std
        }

        if num_boxes > 0:
            images_with_annotations += 1

            # Check for partial annotations (e.g., high edge/color complexity but very tiny bbox coverage < 1.5% of frame)
            if total_bbox_area < 0.015 and (edge_density > 0.08 or color_std > 45.0):
                partial_annotations_list.append(entry_info)
                # Copy to partial folder
                dest = dirs["partial"] / f"{src_name}_{img_p.name}"
                shutil.copy2(img_p, dest)
                if lbl_p and lbl_p.exists():
                    shutil.copy2(lbl_p, dirs["partial"] / f"{src_name}_{lbl_p.name}")
            # Check for questionable annotations (e.g., box covering > 85% of image or extreme aspect ratio)
            elif any(w > 0.85 and h > 0.85 for _, _, w, h in bboxes) or any(w/max(h, 1e-4) > 10.0 or h/max(w, 1e-4) > 10.0 for _, _, w, h in bboxes):
                questionable_annotations_list.append(entry_info)
                dest = dirs["questionable"] / f"{src_name}_{img_p.name}"
                shutil.copy2(img_p, dest)
                if lbl_p and lbl_p.exists():
                    shutil.copy2(lbl_p, dirs["questionable"] / f"{src_name}_{lbl_p.name}")
            else:
                valid_annotated_list.append(entry_info)
                dest = dirs["valid"] / f"{src_name}_{img_p.name}"
                shutil.copy2(img_p, dest)
                if lbl_p and lbl_p.exists():
                    shutil.copy2(lbl_p, dirs["valid"] / f"{src_name}_{lbl_p.name}")
        else:
            images_without_annotations += 1

            # If image came from positive dataset (aiq_v2i or trash_v1i) but has NO label -> Missing Annotation!
            if expected_positive:
                missing_annotations_list.append(entry_info)
                dest = dirs["missing"] / f"{src_name}_{img_p.name}"
                shutil.copy2(img_p, dest)
                # Create placeholder empty label
                with open(dirs["missing"] / f"{src_name}_{img_p.stem}.txt", 'w') as f:
                    pass
            else:
                genuinely_clean_list.append(entry_info)
                dest = dirs["clean"] / f"{src_name}_{img_p.name}"
                shutil.copy2(img_p, dest)

print(f"\n==================================================")
print(f"ANNOTATION AUDIT REPORT SUMMARY")
print(f"==================================================")
print(f"Total Source Images Audited:          {total_images}")
print(f"Images WITH Annotations:               {images_with_annotations}")
print(f"Images WITHOUT Annotations:            {images_without_annotations}")
print(f"  - Genuinely Clean Road Images:       {len(genuinely_clean_list)}")
print(f"  - Suspicious Missing Annotations:    {len(missing_annotations_list)}")
print(f"Suspicious Partial Annotations:        {len(partial_annotations_list)}")
print(f"Questionable Annotations:              {len(questionable_annotations_list)}")
print(f"Valid Complete Annotations:            {len(valid_annotated_list)}")

print(f"\nAll review images and labels saved to: {REVIEW_DIR}")
