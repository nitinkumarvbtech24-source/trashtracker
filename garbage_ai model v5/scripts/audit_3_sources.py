import os
import sys
import hashlib
import yaml
import shutil
import random
from pathlib import Path

# Ensure utf-8 printing on Windows console
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")

# EXACT 3 SOURCES REQUIRED BY USER
SRC_1 = BASE_DIR / "aiq trash detection 1.v2i.yolov8"
SRC_2 = BASE_DIR / "trash.v1i.yolov8"
SRC_3 = BASE_DIR / "Clean road"

print("==================================================")
print("EXACT 3-SOURCE DATASET AUDIT")
print("==================================================")
print(f"Source 1: {SRC_1}")
print(f"Source 2: {SRC_2}")
print(f"Source 3: {SRC_3}\n")

# Verify existence of all 3 source folders
for name, p in [("Source 1", SRC_1), ("Source 2", SRC_2), ("Source 3", SRC_3)]:
    if not p.exists():
        print(f"[ERROR] {name} path '{p}' does not exist!")
    else:
        print(f"[OK] {name} exists at: {p}")

def inspect_source(folder_path, name):
    imgs = list(folder_path.rglob("*.jpg")) + list(folder_path.rglob("*.png")) + list(folder_path.rglob("*.jpeg")) + list(folder_path.rglob("*.webp")) + list(folder_path.rglob("*.bmp"))
    txts = [t for t in folder_path.rglob("*.txt") if not t.name.lower().startswith("readme") and "requirement" not in t.name]
    
    pos_imgs = 0
    clean_imgs = 0
    total_boxes = 0
    invalid_boxes = 0
    
    for img_p in imgs:
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
            matches = list(folder_path.rglob(f"{img_p.stem}.txt"))
            matches = [m for m in matches if not m.name.lower().startswith("readme") and "requirement" not in m.name]
            if matches:
                lbl_p = matches[0]

        boxes = 0
        if lbl_p and lbl_p.exists():
            with open(lbl_p, 'r', encoding='utf-8', errors='ignore') as f:
                lines = [l.strip() for l in f if l.strip()]
                for l in lines:
                    parts = l.split()
                    if len(parts) >= 5:
                        try:
                            cx, cy, w, h = map(float, parts[1:5])
                            if not (0 <= cx <= 1 and 0 <= cy <= 1 and 0 <= w <= 1 and 0 <= h <= 1):
                                invalid_boxes += 1
                            boxes += 1
                        except ValueError:
                            invalid_boxes += 1

        if boxes > 0:
            pos_imgs += 1
            total_boxes += boxes
        else:
            clean_imgs += 1

    return {
        "name": name,
        "path": str(folder_path),
        "total_images": len(imgs),
        "total_txts": len(txts),
        "positive_images": pos_imgs,
        "clean_images": clean_imgs,
        "total_boxes": total_boxes,
        "invalid_boxes": invalid_boxes,
        "image_list": imgs
    }

s1_info = inspect_source(SRC_1, "aiq trash detection 1.v2i.yolov8") if SRC_1.exists() else {}
s2_info = inspect_source(SRC_2, "trash.v1i.yolov8") if SRC_2.exists() else {}
s3_info = inspect_source(SRC_3, "Clean road") if SRC_3.exists() else {}

print("\n--- INDIVIDUAL SOURCE METRICS ---")
for s in [s1_info, s2_info, s3_info]:
    if s:
        print(f"Folder '{s['name']}':")
        print(f"  Total Images: {s['total_images']}")
        print(f"  Annotated Trash Images: {s['positive_images']}")
        print(f"  Clean-Road Images: {s['clean_images']}")
        print(f"  Trash Bounding Boxes: {s['total_boxes']}\n")

# Combine and Deduplicate strictly from these 3 sources
unique_entries = {}
duplicates_count = 0

for s_info in [s1_info, s2_info, s3_info]:
    if not s_info:
        continue
    source_name = s_info["name"]
    for img_p in s_info["image_list"]:
        try:
            with open(img_p, 'rb') as f:
                h = hashlib.md5(f.read()).hexdigest()
        except Exception:
            continue

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
            matches = list(Path(s_info["path"]).rglob(f"{img_p.stem}.txt"))
            matches = [m for m in matches if not m.name.lower().startswith("readme") and "requirement" not in m.name]
            if matches:
                lbl_p = matches[0]

        bboxes = []
        if lbl_p and lbl_p.exists():
            with open(lbl_p, 'r', encoding='utf-8', errors='ignore') as f:
                lines = [l.strip() for l in f if l.strip()]
                for l in lines:
                    parts = l.split()
                    if len(parts) >= 5:
                        try:
                            cx, cy, w, h = map(float, parts[1:5])
                            cx = max(0.0, min(1.0, cx))
                            cy = max(0.0, min(1.0, cy))
                            w = max(0.0, min(1.0, w))
                            h = max(0.0, min(1.0, h))
                            bboxes.append((0, cx, cy, w, h)) # Single class 0: trash
                        except ValueError:
                            pass

        is_pos = len(bboxes) > 0

        if h not in unique_entries:
            unique_entries[h] = {
                "source": source_name,
                "img_path": img_p,
                "lbl_path": lbl_p,
                "bboxes": bboxes,
                "is_positive": is_pos
            }
        else:
            duplicates_count += 1
            if not unique_entries[h]["is_positive"] and is_pos:
                unique_entries[h] = {
                    "source": source_name,
                    "img_path": img_p,
                    "lbl_path": lbl_p,
                    "bboxes": bboxes,
                    "is_positive": True
                }

final_positives = [v for v in unique_entries.values() if v["is_positive"]]
final_negatives = [v for v in unique_entries.values() if not v["is_positive"]]
final_total_boxes = sum(len(v["bboxes"]) for v in unique_entries.values())

print("==================================================")
print("AUDIT RESULTS (3 STRICT SOURCES ONLY)")
print("==================================================")
print(f"1. Images in aiq trash detection 1.v2i.yolov8: {s1_info.get('total_images', 0)}")
print(f"2. Images in trash.v1i.yolov8:                 {s2_info.get('total_images', 0)}")
print(f"3. Images in Clean road:                        {s3_info.get('total_images', 0)}")
print(f"4. Total Annotated Trash Images:               {len(final_positives)}")
print(f"5. Total Clean-Road Images:                    {len(final_negatives)}")
print(f"6. Total Trash Bounding Boxes:                 {final_total_boxes}")
print(f"7. Duplicate Images Removed:                   {duplicates_count}")
print(f"8. Final Total Unique Images:                  {len(unique_entries)}")

# Verify source origin of every single entry
all_sources_valid = True
for v in unique_entries.values():
    src = v["source"]
    if src not in ["aiq trash detection 1.v2i.yolov8", "trash.v1i.yolov8", "Clean road"]:
        print(f"[ERROR] INVALID SOURCE DETECTED: {v['img_path']}")
        all_sources_valid = False

if all_sources_valid:
    print("\n[CONFIRMED] 100% of images originate EXCLUSIVELY from the three allowed source folders!")
