import os
import sys
import hashlib
import yaml
import shutil
import random
from pathlib import Path

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")

# Sources in order of precedence (highest precedence first to override older annotations)
sources_priority = [
    ("box_annotations", BASE_DIR / "box annotations", True),      # Highest priority: corrected 52/26 images
    ("Trash_v2i", BASE_DIR / "Trash.v2i.yolov8", True),             # Priority 2: re-annotated dataset v2i
    ("aiq_v2i", BASE_DIR / "aiq trash detection 1.v2i.yolov8", True),# Priority 3: aiq v2i dataset
    ("root_split", BASE_DIR, True),                                # Priority 4: newly added root train/valid/test
    ("Clean_road", BASE_DIR / "Clean road", False)                 # Priority 5: clean road negative images
]

print("==================================================")
print("MASTER DATASET AUDIT & DE-DUPLICATION")
print("==================================================")

master_entries = {}
source_counts = {}
raw_image_count = 0
duplicates_overridden = 0

invalid_bboxes_count = 0
missing_annotations_count = 0
partial_annotations_count = 0

for tag, src_path, expected_positive in sources_priority:
    if not src_path.exists():
        continue

    # Find image files (ignoring macOS ._ files)
    if tag == "root_split":
        imgs = []
        for sub_name in ["train", "valid", "test"]:
            sub_dir = BASE_DIR / sub_name
            if sub_dir.exists():
                imgs.extend([p for p in sub_dir.rglob("*.*") if p.suffix.lower() in [".jpg", ".png", ".jpeg"] and not p.name.startswith("._")])
    else:
        imgs = [p for p in src_path.rglob("*.*") if p.suffix.lower() in [".jpg", ".png", ".jpeg"] and not p.name.startswith("._")]

    source_counts[tag] = len(imgs)
    raw_image_count += len(imgs)

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
            if cand.exists() and not cand.name.startswith("._"):
                lbl_p = cand
        if lbl_p is None:
            cand = img_p.with_suffix(".txt")
            if cand.exists() and not cand.name.startswith("._"):
                lbl_p = cand
        if lbl_p is None:
            matches = list(img_p.parent.rglob(f"{img_p.stem}.txt"))
            matches = [m for m in matches if not m.name.startswith("._") and not m.name.lower().startswith("readme")]
            if matches:
                lbl_p = matches[0]

        bboxes = []
        if lbl_p and lbl_p.exists():
            with open(lbl_p, 'r', encoding='utf-8', errors='ignore') as lf:
                for line in lf:
                    parts = line.strip().split()
                    if len(parts) >= 5:
                        try:
                            cx, cy, w, h_box = map(float, parts[1:5])
                            if not (0 <= cx <= 1 and 0 <= cy <= 1 and 0 <= w <= 1 and 0 <= h_box <= 1):
                                invalid_bboxes_count += 1
                            cx = max(0.0, min(1.0, cx))
                            cy = max(0.0, min(1.0, cy))
                            w = max(0.0, min(1.0, w))
                            h_box = max(0.0, min(1.0, h_box))
                            bboxes.append((0, cx, cy, w, h_box)) # Single class 0: trash
                        except ValueError:
                            invalid_bboxes_count += 1

        is_pos = len(bboxes) > 0
        total_area = sum(w * h_box for _, cx, cy, w, h_box in bboxes)

        # Flag missing / partial annotation checks
        if expected_positive and not is_pos:
            missing_annotations_count += 1

        if is_pos and total_area < 0.005:
            partial_annotations_count += 1

        entry = {
            "source": tag,
            "img_path": img_p,
            "lbl_path": lbl_p,
            "bboxes": bboxes,
            "is_positive": is_pos,
            "total_area": total_area
        }

        if h not in master_entries:
            master_entries[h] = entry
        else:
            duplicates_overridden += 1

final_positives = [v for v in master_entries.values() if v["is_positive"]]
final_negatives = [v for v in master_entries.values() if not v["is_positive"]]
total_final_bboxes = sum(len(v["bboxes"]) for v in master_entries.values())

print(f"\n--- AUDIT SUMMARY METRICS ---")
print(f"Total Raw Images Analyzed:           {raw_image_count}")
print(f"Duplicate/Older Versions Removed:    {duplicates_overridden}")
print(f"Final Total Unique Images:           {len(master_entries)}")
print(f"  - Trash/Positive Images:           {len(final_positives)}")
print(f"  - Clean/Negative Images:           {len(final_negatives)}")
print(f"Total Trash Bounding Boxes:          {total_final_bboxes}")
print(f"Invalid Bounding Boxes Found:        {invalid_bboxes_count}")
print(f"Missing Annotations Found:           {missing_annotations_count}")
print(f"Suspicious Partial Annotations:      {partial_annotations_count}")

print(f"\nSource breakdown (raw image files):")
for k, v in source_counts.items():
    print(f"  - {k}: {v} images")

# Prepare fresh split: 80% train / 10% val / 10% test
random.seed(42)
random.shuffle(final_positives)
random.shuffle(final_negatives)

n_pos = len(final_positives)
n_neg = len(final_negatives)

pos_train = final_positives[:int(n_pos * 0.80)]
pos_val = final_positives[int(n_pos * 0.80):int(n_pos * 0.90)]
pos_test = final_positives[int(n_pos * 0.90):]

neg_train = final_negatives[:int(n_neg * 0.80)]
neg_val = final_negatives[int(n_neg * 0.80):int(n_neg * 0.90)]
neg_test = final_negatives[int(n_neg * 0.90):]

splits = {
    "train": pos_train + neg_train,
    "val": pos_val + neg_val,
    "test": pos_test + neg_test
}

print(f"\n--- PROPOSED TRAIN / VAL / TEST SPLITS (80% / 10% / 10%) ---")
for s_name, s_items in splits.items():
    s_pos = sum(1 for item in s_items if item["is_positive"])
    s_neg = len(s_items) - s_pos
    s_boxes = sum(len(item["bboxes"]) for item in s_items)
    print(f"Split '{s_name.upper()}':")
    print(f"  Total Images: {len(s_items)} ({s_pos} positive + {s_neg} clean negative)")
    print(f"  Trash Bounding Boxes: {s_boxes}")
