import os
import shutil
import random
import hashlib
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")
OUT_DIR = BASE_DIR / "dataset_trash_yolo_v2"

sources = [
    ("new_dataset", BASE_DIR / "dataset" / "yolo_street_aiq"),
    ("trash_v1i", BASE_DIR / "trash.v1i.yolov8"),
    ("aiq_v1i", BASE_DIR / "aiq trash detection 1.v1i.yolov8"),
    ("clean_roads_raw", BASE_DIR / "road cleanliness" / "clean roads")
]

random.seed(42)

if OUT_DIR.exists():
    shutil.rmtree(OUT_DIR)

for split in ["train", "val", "test"]:
    (OUT_DIR / split / "images").mkdir(parents=True, exist_ok=True)
    (OUT_DIR / split / "labels").mkdir(parents=True, exist_ok=True)

all_entries = {}

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
                            cx, cy, w, h_box = map(float, parts[1:5])
                            cx = max(0.0, min(1.0, cx))
                            cy = max(0.0, min(1.0, cy))
                            w = max(0.0, min(1.0, w))
                            h_box = max(0.0, min(1.0, h_box))
                            bboxes.append((0, cx, cy, w, h_box))
                        except ValueError:
                            pass

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
            if not all_entries[h]["is_positive"] and is_pos:
                all_entries[h] = {
                    "source": source_name,
                    "img_path": img_p,
                    "lbl_path": lbl_p,
                    "bboxes": bboxes,
                    "is_positive": True
                }

positive_entries = [v for v in all_entries.values() if v["is_positive"]]
negative_entries = [v for v in all_entries.values() if not v["is_positive"]]

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

splits = {
    "train": pos_train + neg_train,
    "val": pos_val + neg_val,
    "test": pos_test + neg_test
}

split_stats = {}

for split_name, samples in splits.items():
    random.shuffle(samples)
    img_dest_dir = OUT_DIR / split_name / "images"
    lbl_dest_dir = OUT_DIR / split_name / "labels"

    pos_count = 0
    neg_count = 0
    box_count = 0

    for idx, entry in enumerate(samples):
        new_stem = f"{entry['source']}_{split_name}_{idx:04d}"
        img_p = entry['img_path']
        dest_img_path = img_dest_dir / f"{new_stem}{img_p.suffix.lower()}"
        dest_lbl_path = lbl_dest_dir / f"{new_stem}.txt"

        shutil.copy2(img_p, dest_img_path)

        if entry['is_positive']:
            lines = [f"0 {cx:.6f} {cy:.6f} {w:.6f} {h_box:.6f}\n" for _, cx, cy, w, h_box in entry['bboxes']]
            with open(dest_lbl_path, 'w', encoding='utf-8') as f:
                f.writelines(lines)
            pos_count += 1
            box_count += len(lines)
        else:
            with open(dest_lbl_path, 'w', encoding='utf-8') as f:
                pass
            neg_count += 1

    split_stats[split_name] = {
        "total_images": len(samples),
        "positive_images": pos_count,
        "negative_images": neg_count,
        "bounding_boxes": box_count
    }

# Save data.yaml
yaml_content = f"""path: {OUT_DIR.as_posix()}
train: train/images
val: val/images
test: test/images

nc: 1
names:
  0: trash
"""

with open(OUT_DIR / "data.yaml", 'w', encoding='utf-8') as f:
    f.write(yaml_content)

print(f"\n==================================================")
print(f"NEW DATASET CREATED: {OUT_DIR}")
print(f"==================================================")

for s_name, s_data in split_stats.items():
    print(f"Split '{s_name.upper()}':")
    print(f"  Total Images: {s_data['total_images']} ({s_data['positive_images']} positive + {s_data['negative_images']} clean negative)")
    print(f"  Trash Bounding Boxes: {s_data['bounding_boxes']}\n")
