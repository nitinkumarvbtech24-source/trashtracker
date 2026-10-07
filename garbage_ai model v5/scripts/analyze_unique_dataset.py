import os
import hashlib
import yaml
import shutil
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")

print("==================================================")
print("DE-DUPLICATION AND UNIQUE ANALYSIS OF ALL DATASETS")
print("==================================================")

# Search all dataset directories in E:\nitin\model2
search_dirs = [
    BASE_DIR / "dataset",
    BASE_DIR / "trash.v1i.yolov8",
    BASE_DIR / "aiq trash detection 1.v1i.yolov8",
    BASE_DIR / "road cleanliness" / "clean roads"
]

all_images = []
for d in search_dirs:
    if d.exists():
        for ext in ['*.jpg', '*.png', '*.jpeg', '*.webp', '*.bmp']:
            all_images.extend(list(d.rglob(ext)))

print(f"Total raw image files found across all dataset directories: {len(all_images)}")

# Map MD5 hash to unique image entry
# Each entry will store: hash -> {image_path, label_path, bboxes, is_positive}
unique_images = {}
duplicate_count = 0

for img_path in all_images:
    try:
        with open(img_path, 'rb') as f:
            h = hashlib.md5(f.read()).hexdigest()
    except Exception:
        continue

    # Find matching txt label file
    lbl_path = None
    # 1. Check same stem in parent's labels sibling
    if "images" in img_path.parts:
        parts = list(img_path.parts)
        idx = parts.index("images")
        parts[idx] = "labels"
        candidate = Path(*parts).with_suffix(".txt")
        if candidate.exists():
            lbl_path = candidate
    
    # 2. Check same directory stem
    if lbl_path is None:
        candidate = img_path.with_suffix(".txt")
        if candidate.exists():
            lbl_path = candidate

    # 3. Check any matching label file in workspace
    if lbl_path is None:
        matches = list(BASE_DIR.rglob(f"{img_path.stem}.txt"))
        matches = [m for m in matches if not m.name.lower().startswith("readme") and "requirement" not in m.name]
        if matches:
            lbl_path = matches[0]

    # Parse bboxes if label file exists
    bboxes = []
    if lbl_path and lbl_path.exists():
        with open(lbl_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = [line.strip() for line in f if line.strip()]
            for line in lines:
                parts = line.split()
                if len(parts) >= 5:
                    try:
                        cls_id = int(parts[0])
                        cx, cy, w, h = map(float, parts[1:5])
                        cx = max(0.0, min(1.0, cx))
                        cy = max(0.0, min(1.0, cy))
                        w = max(0.0, min(1.0, w))
                        h = max(0.0, min(1.0, h))
                        bboxes.append((0, cx, cy, w, h)) # Force class 0: trash
                    except ValueError:
                        pass

    is_positive = len(bboxes) > 0

    if h not in unique_images:
        unique_images[h] = {
            "img_path": img_path,
            "lbl_path": lbl_path,
            "bboxes": bboxes,
            "is_positive": is_positive
        }
    else:
        duplicate_count += 1
        # If existing stored entry had NO bboxes, but current duplicate HAS bboxes, upgrade to positive!
        if len(unique_images[h]["bboxes"]) == 0 and len(bboxes) > 0:
            unique_images[h]["img_path"] = img_path
            unique_images[h]["lbl_path"] = lbl_path
            unique_images[h]["bboxes"] = bboxes
            unique_images[h]["is_positive"] = True

print(f"\n--- UNIQUE DATASET METRICS ---")
print(f"Total Unique Images:                  {len(unique_images)}")

positive_unique = [v for v in unique_images.values() if v["is_positive"]]
negative_unique = [v for v in unique_images.values() if not v["is_positive"]]
total_unique_bboxes = sum(len(v["bboxes"]) for v in unique_images.values())

print(f"Unique Images with Trash (Positive): {len(positive_unique)}")
print(f"Unique Clean-Road Images (Negative): {len(negative_unique)}")
print(f"Total Unique Trash Bounding Boxes:   {total_unique_bboxes}")
print(f"Duplicate Files Filtered Out:        {duplicate_count}")
