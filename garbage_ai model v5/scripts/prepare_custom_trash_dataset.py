import os
import shutil
import random
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")
OUT_DIR = BASE_DIR / "dataset_trash_yolo"

ds1_dir = BASE_DIR / "aiq trash detection 1.v1i.yolov8"
ds2_dir = BASE_DIR / "trash.v1i.yolov8"
clean_dir = BASE_DIR / "road cleanliness" / "clean roads"

# Set random seed for reproducible train/val/test split
random.seed(42)

# Clear existing target directory if any
if OUT_DIR.exists():
    shutil.rmtree(OUT_DIR)

for split in ["train", "val", "test"]:
    (OUT_DIR / split / "images").mkdir(parents=True, exist_ok=True)
    (OUT_DIR / split / "labels").mkdir(parents=True, exist_ok=True)

# 1. Collect all positive samples (images + labels)
positive_samples = []

# From Dataset 1
ds1_imgs = list(ds1_dir.rglob("*.jpg")) + list(ds1_dir.rglob("*.png")) + list(ds1_dir.rglob("*.jpeg"))
for img_p in ds1_imgs:
    # Find matching label
    lbl_p = img_p.parent.parent / "labels" / f"{img_p.stem}.txt"
    if not lbl_p.exists():
        lbl_p = img_p.with_suffix(".txt")
    if lbl_p.exists():
        positive_samples.append(("ds1", img_p, lbl_p))

# From Dataset 2
ds2_imgs = list(ds2_dir.rglob("*.jpg")) + list(ds2_dir.rglob("*.png")) + list(ds2_dir.rglob("*.jpeg"))
for img_p in ds2_imgs:
    lbl_p = img_p.parent.parent / "labels" / f"{img_p.stem}.txt"
    if not lbl_p.exists():
        lbl_p = img_p.with_suffix(".txt")
    if lbl_p.exists():
        positive_samples.append(("ds2", img_p, lbl_p))

# 2. Collect all negative samples (clean images)
clean_imgs = list(clean_dir.rglob("*.jpg")) + list(clean_dir.rglob("*.png")) + list(clean_dir.rglob("*.jpeg"))
negative_samples = [("clean", img_p, None) for img_p in clean_imgs]

print(f"Collected Positive Samples: {len(positive_samples)}")
print(f"Collected Negative (Clean) Samples: {len(negative_samples)}")

# Shuffle samples
random.shuffle(positive_samples)
random.shuffle(negative_samples)

def split_data(items, train_ratio=0.80, val_ratio=0.10):
    n = len(items)
    n_train = int(n * train_ratio)
    n_val = int(n * val_ratio)
    train_items = items[:n_train]
    val_items = items[n_train:n_train + n_val]
    test_items = items[n_train + n_val:]
    return train_items, val_items, test_items

pos_train, pos_val, pos_test = split_data(positive_samples)
neg_train, neg_val, neg_test = split_data(negative_samples)

splits = {
    "train": pos_train + neg_train,
    "val": pos_val + neg_val,
    "test": pos_test + neg_test
}

stats = {}

for split_name, samples in splits.items():
    random.shuffle(samples)
    img_dest_dir = OUT_DIR / split_name / "images"
    lbl_dest_dir = OUT_DIR / split_name / "labels"
    
    pos_count = 0
    neg_count = 0
    box_count = 0

    for idx, (source_tag, img_p, lbl_p) in enumerate(samples):
        new_name = f"{source_tag}_{split_name}_{idx:04d}"
        dest_img_path = img_dest_dir / f"{new_name}{img_p.suffix.lower()}"
        dest_lbl_path = lbl_dest_dir / f"{new_name}.txt"

        # Copy image
        shutil.copy2(img_p, dest_img_path)

        if lbl_p is not None and lbl_p.exists():
            # Filter/Normalize label lines to ensure class 0 and valid floats
            valid_lines = []
            with open(lbl_p, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 5:
                        try:
                            # Force class ID 0 (trash)
                            cx, cy, w, h = map(float, parts[1:5])
                            # Clamp bounding box coords to [0, 1]
                            cx = max(0.0, min(1.0, cx))
                            cy = max(0.0, min(1.0, cy))
                            w = max(0.0, min(1.0, w))
                            h = max(0.0, min(1.0, h))
                            valid_lines.append(f"0 {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}\n")
                        except ValueError:
                            pass
            with open(dest_lbl_path, 'w', encoding='utf-8') as f:
                f.writelines(valid_lines)
            pos_count += 1
            box_count += len(valid_lines)
        else:
            # Create empty txt label file for clean road negative images
            with open(dest_lbl_path, 'w', encoding='utf-8') as f:
                pass
            neg_count += 1

    stats[split_name] = {
        "total_images": len(samples),
        "positive_images": pos_count,
        "negative_images": neg_count,
        "bounding_boxes": box_count
    }

# Create data.yaml file
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

print("\n--- DATASET CREATION COMPLETED SUCCESSFULLY ---")
print(f"Output Directory: {OUT_DIR}")
for s_name, s_data in stats.items():
    print(f"\nSplit '{s_name.upper()}':")
    print(f"  Total Images: {s_data['total_images']}")
    print(f"  Positive (Trash) Images: {s_data['positive_images']}")
    print(f"  Negative (Clean) Images: {s_data['negative_images']}")
    print(f"  Trash Bounding Boxes: {s_data['bounding_boxes']}")
