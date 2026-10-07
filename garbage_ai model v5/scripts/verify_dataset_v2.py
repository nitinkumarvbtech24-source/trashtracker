import os
import hashlib
import yaml
import shutil
import random
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")

print("==================================================")
print("VERIFYING COMPLETE DATASET FOR DATASET V2 ASSEMBLY")
print("==================================================")

# Primary candidate sources
sources = [
    ("new_dataset", BASE_DIR / "dataset" / "yolo_street_aiq"),
    ("trash_v1i", BASE_DIR / "trash.v1i.yolov8"),
    ("aiq_v1i", BASE_DIR / "aiq trash detection 1.v1i.yolov8"),
    ("clean_roads_raw", BASE_DIR / "road cleanliness" / "clean roads")
]

all_entries = {} # md5 -> dict of info
duplicates = 0
invalid_boxes = 0

for source_name, src_dir in sources:
    if not src_dir.exists():
        continue
    imgs = list(src_dir.rglob("*.jpg")) + list(src_dir.rglob("*.png")) + list(src_dir.rglob("*.jpeg"))
    for img_p in imgs:
        try:
            with open(img_p, 'rb') as f:
                h = hashlib.md5(f.read()).hexdigest()
        except Exception:
            continue

        # Find label file
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
            matches = list(src_dir.rglob(f"{img_p.stem}.txt"))
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
                            cls_id = int(parts[0])
                            cx, cy, w, h_box = map(float, parts[1:5])
                            if not (0 <= cx <= 1 and 0 <= cy <= 1 and 0 <= w <= 1 and 0 <= h_box <= 1):
                                invalid_boxes += 1
                            # Force class 0 (trash)
                            bboxes.append((0, cx, cy, w, h_box))
                        except ValueError:
                            invalid_boxes += 1

        is_pos = len(bboxes) > 0

        if h not in all_entries:
            all_entries[h] = {
                "source": source_name,
                "img_path": img_p,
                "lbl_path": lbl_p,
                "bboxes": bboxes,
                "is_positive": is_pos
            }
        else:
            duplicates += 1
            # If stored entry had 0 bboxes, but current duplicate HAS bboxes, upgrade
            if not all_entries[h]["is_positive"] and is_pos:
                all_entries[h]["source"] = source_name
                all_entries[h]["img_path"] = img_p
                all_entries[h]["lbl_path"] = lbl_p
                all_entries[h]["bboxes"] = bboxes
                all_entries[h]["is_positive"] = True

positive_entries = [v for v in all_entries.values() if v["is_positive"]]
negative_entries = [v for v in all_entries.values() if not v["is_positive"]]
total_boxes = sum(len(v["bboxes"]) for v in all_entries.values())

print(f"\n--- DATASET INSPECTION METRICS ---")
print(f"Total Unique Images:                  {len(all_entries)}")
print(f"Images with Trash (Positive):          {len(positive_entries)}")
print(f"Clean-Road Images (Negative):          {len(negative_entries)}")
print(f"Total Trash Bounding Boxes:            {total_boxes}")
print(f"Invalid Bounding Boxes Found:          {invalid_boxes}")
print(f"Duplicate Files Filtered Out:        {duplicates}")
print(f"Class Names / Mapping:                 All normalized to single class '0: trash'")

# Calculate 80 / 10 / 10 Split Strategy
random.seed(42)
random.shuffle(positive_entries)
random.shuffle(negative_entries)

n_pos = len(positive_entries)
n_neg = len(negative_entries)

pos_train = positive_entries[:int(n_pos * 0.80)]
pos_val = positive_entries[int(n_pos * 0.80):int(n_pos * 0.90)]
pos_test = positive_entries[int(n_pos * 0.90):]

neg_train = negative_entries[:int(n_neg * 0.80)]
neg_val = negative_entries[int(n_neg * 0.80):int(n_neg * 0.90)]
neg_test = negative_entries[int(n_neg * 0.90):]

train_set = pos_train + neg_train
val_set = pos_val + neg_val
test_set = pos_test + neg_test

print("\n--- PROPOSED TRAIN / VAL / TEST SPLITS (80% / 10% / 10%) ---")
print(f"TRAIN SPLIT (80%):")
print(f"  Total Images: {len(train_set)} ({len(pos_train)} Positive + {len(neg_train)} Clean Negative)")
print(f"  Bounding Boxes: {sum(len(v['bboxes']) for v in train_set)}")

print(f"\nVAL SPLIT (10%):")
print(f"  Total Images: {len(val_set)} ({len(pos_val)} Positive + {len(neg_val)} Clean Negative)")
print(f"  Bounding Boxes: {sum(len(v['bboxes']) for v in val_set)}")

print(f"\nTEST SPLIT (10%):")
print(f"  Total Images: {len(test_set)} ({len(pos_test)} Positive + {len(neg_test)} Clean Negative)")
print(f"  Bounding Boxes: {sum(len(v['bboxes']) for v in test_set)}")
