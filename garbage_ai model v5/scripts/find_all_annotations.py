import os
import hashlib
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")

print("==================================================")
print("COMPREHENSIVE WORKSPACE DATASET SCAN")
print("==================================================")

# Search all subdirectories for images and matching label files
all_image_paths = []
for root, dirs, files in os.walk(BASE_DIR):
    # Ignore runs, scratch, .git
    if any(ignore in root for ignore in ["runs", "scratch", ".git", ".agents"]):
        continue
    for f in files:
        ext = os.path.splitext(f)[1].lower()
        if ext in [".jpg", ".png", ".jpeg", ".webp", ".bmp"]:
            all_image_paths.append(Path(root) / f)

print(f"Total raw image files found across workspace: {len(all_image_paths)}")

# Calculate MD5 hashes to identify true unique physical images
unique_map = {} # md5 -> dict of info

for img_p in all_image_paths:
    try:
        with open(img_p, 'rb') as f:
            h = hashlib.md5(f.read()).hexdigest()
    except Exception:
        continue

    # Find candidate txt label file
    lbl_p = None
    
    # Check 1: labels directory parallel to images directory
    if "images" in img_p.parts:
        parts = list(img_p.parts)
        idx = parts.index("images")
        parts[idx] = "labels"
        cand = Path(*parts).with_suffix(".txt")
        if cand.exists():
            lbl_p = cand

    # Check 2: same folder txt
    if lbl_p is None:
        cand = img_p.with_suffix(".txt")
        if cand.exists():
            lbl_p = cand

    # Check 3: search workspace for stem.txt
    if lbl_p is None:
        matches = list(BASE_DIR.rglob(f"{img_p.stem}.txt"))
        matches = [m for m in matches if not m.name.lower().startswith("readme") and "requirement" not in m.name and "runs" not in str(m)]
        if matches:
            lbl_p = matches[0]

    # Count boxes
    bboxes = []
    if lbl_p and lbl_p.exists():
        with open(lbl_p, 'r', encoding='utf-8', errors='ignore') as f:
            lines = [l.strip() for l in f if l.strip()]
            for l in lines:
                parts = l.split()
                if len(parts) >= 5:
                    try:
                        cls_id = int(parts[0])
                        cx, cy, w, h = map(float, parts[1:5])
                        bboxes.append((cls_id, cx, cy, w, h))
                    except ValueError:
                        pass

    if h not in unique_map:
        unique_map[h] = {
            "img_path": img_p,
            "lbl_path": lbl_p,
            "bboxes": bboxes,
            "rel_path": str(img_p.relative_to(BASE_DIR))
        }
    else:
        # If existing stored entry has 0 bboxes, but current duplicate HAS bboxes, use the annotated version!
        if len(unique_map[h]["bboxes"]) == 0 and len(bboxes) > 0:
            unique_map[h] = {
                "img_path": img_p,
                "lbl_path": lbl_p,
                "bboxes": bboxes,
                "rel_path": str(img_p.relative_to(BASE_DIR))
            }

unique_positive = [v for v in unique_map.values() if len(v["bboxes"]) > 0]
unique_negative = [v for v in unique_map.values() if len(v["bboxes"]) == 0]
total_bboxes = sum(len(v["bboxes"]) for v in unique_map.values())
all_cls_ids = set()
for v in unique_map.values():
    for b in v["bboxes"]:
        all_cls_ids.add(b[0])

print("\n--- GLOBAL UNIQUE DATASET SUMMARY ---")
print(f"Total Unique Images:                  {len(unique_map)}")
print(f"Unique Positive (Trash) Images:       {len(unique_positive)}")
print(f"Unique Negative (Clean Road) Images:  {len(unique_negative)}")
print(f"Total Unique Bounding Boxes:          {total_bboxes}")
print(f"Class IDs found across annotations:   {all_cls_ids}")

# Distribution of images by top-level folder for unique positive vs negative
pos_by_folder = {}
neg_by_folder = {}
for v in unique_map.values():
    folder = Path(v["rel_path"]).parts[0]
    if len(v["bboxes"]) > 0:
        pos_by_folder[folder] = pos_by_folder.get(folder, 0) + 1
    else:
        neg_by_folder[folder] = neg_by_folder.get(folder, 0) + 1

print("\nPositive Images (with Trash BBoxes) by Top-Level Folder:")
for k, v in pos_by_folder.items():
    print(f"  Folder '{k}': {v} unique images")

print("\nNegative Images (Clean Roads / Background) by Top-Level Folder:")
for k, v in neg_by_folder.items():
    print(f"  Folder '{k}': {v} unique images")
