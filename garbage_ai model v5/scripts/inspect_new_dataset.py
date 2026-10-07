import os
import hashlib
import yaml
from pathlib import Path
from PIL import Image

BASE_DIR = Path(r"e:\nitin\model2")
DATASET_DIR = BASE_DIR / "dataset"

print("==================================================")
print("INSPECTING NEW UPLOADED DATASET: E:\\nitin\\model2\\dataset")
print("==================================================")

yaml_files = list(DATASET_DIR.glob("*.yaml")) + list(DATASET_DIR.glob("*.yml"))
yaml_configs = {}
for yf in yaml_files:
    with open(yf, 'r', encoding='utf-8', errors='ignore') as f:
        try:
            content = yaml.safe_load(f)
            yaml_configs[yf.name] = content
            print(f"Found YAML '{yf.name}':\n  {content}\n")
        except Exception as e:
            print(f"Error loading {yf.name}: {e}")

# Scan images
all_imgs = []
for ext in ['*.jpg', '*.png', '*.jpeg', '*.webp', '*.bmp']:
    all_imgs.extend(list(DATASET_DIR.rglob(ext)))

all_txts = [p for p in DATASET_DIR.rglob("*.txt") if not p.name.lower().startswith("readme") and "requirement" not in p.name]

print(f"Total Image Files found in 'dataset': {len(all_imgs)}")
print(f"Total TXT Label Files found in 'dataset': {len(all_txts)}")

# Analyze images and label pairings
img_by_stem = {}
for img in all_imgs:
    img_by_stem[img.stem] = img

txt_by_stem = {}
for txt in all_txts:
    txt_by_stem[txt.stem] = txt

images_with_trash = 0
clean_images = 0
empty_label_files = 0
missing_label_files = 0

total_bboxes = 0
invalid_bboxes = 0
class_counts = {}

corrupt_images = 0
duplicate_image_hashes = {}
hash_to_paths = {}

for img_path in all_imgs:
    # Check MD5 hash for duplicates
    try:
        with open(img_path, 'rb') as f:
            h = hashlib.md5(f.read()).hexdigest()
        if h in hash_to_paths:
            hash_to_paths[h].append(img_path)
        else:
            hash_to_paths[h] = [img_path]
    except Exception:
        corrupt_images += 1

    # Check matching label file
    lbl_path = txt_by_stem.get(img_path.stem)
    if lbl_path is None:
        # Search relative label directory
        if "images" in img_path.parts:
            parts = list(img_path.parts)
            idx = parts.index("images")
            parts[idx] = "labels"
            alt_lbl = Path(*parts).with_suffix(".txt")
            if alt_lbl.exists():
                lbl_path = alt_lbl

    boxes_in_image = 0
    if lbl_path and lbl_path.exists():
        with open(lbl_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = [line.strip() for line in f if line.strip()]
            for line in lines:
                parts = line.split()
                if len(parts) >= 5:
                    try:
                        cls_id = int(parts[0])
                        class_counts[cls_id] = class_counts.get(cls_id, 0) + 1
                        cx, cy, w, h = map(float, parts[1:5])
                        if not (0 <= cx <= 1 and 0 <= cy <= 1 and 0 <= w <= 1 and 0 <= h <= 1):
                            invalid_bboxes += 1
                        boxes_in_image += 1
                        total_bboxes += 1
                    except ValueError:
                        invalid_bboxes += 1

    if boxes_in_image > 0:
        images_with_trash += 1
    else:
        clean_images += 1

duplicates_count = sum(len(paths) - 1 for paths in hash_to_paths.values() if len(paths) > 1)

print("\n--- DATASET BREAKDOWN ---")
print(f"Total Images:                          {len(all_imgs)}")
print(f"Images with Trash (Positive):          {images_with_trash}")
print(f"Clean-Road Images (Negative):          {clean_images}")
print(f"Total Trash Bounding Boxes:            {total_bboxes}")
print(f"Invalid Bounding Boxes:                {invalid_bboxes}")
print(f"Class IDs found in annotations:        {class_counts}")
print(f"Duplicate Images found:                {duplicates_count}")
print(f"Corrupt Images:                        {corrupt_images}")

# Check subfolder structure (train, valid, test if any)
subfolders = {}
for img in all_imgs:
    rel = img.relative_to(DATASET_DIR)
    parent = rel.parts[0] if len(rel.parts) > 1 else "root"
    subfolders[parent] = subfolders.get(parent, 0) + 1

print(f"\nSubfolder breakdown: {subfolders}")
