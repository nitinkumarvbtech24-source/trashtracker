import os
import yaml
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")
DATASET_DIR = BASE_DIR / "dataset"

print("==================================================")
print("FAST INSPECTION: E:\\nitin\\model2\\dataset")
print("==================================================")

yaml_files = list(DATASET_DIR.glob("*.yaml")) + list(DATASET_DIR.glob("*.yml"))
for yf in yaml_files:
    with open(yf, 'r', encoding='utf-8', errors='ignore') as f:
        try:
            print(f"YAML '{yf.name}': {yaml.safe_load(f)}")
        except Exception as e:
            print(f"Error reading YAML: {e}")

# Walk dataset folder
img_extensions = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
image_paths = []
label_paths = {}

for root, dirs, files in os.walk(DATASET_DIR):
    for file in files:
        ext = os.path.splitext(file)[1].lower()
        full_p = Path(root) / file
        if ext in img_extensions:
            image_paths.append(full_p)
        elif ext == ".txt" and not file.lower().startswith("readme") and "requirement" not in file:
            label_paths[full_p.stem] = full_p

print(f"Total Images Found: {len(image_paths)}")
print(f"Total Label Files Found: {len(label_paths)}")

positive_images = 0
clean_images = 0
total_bboxes = 0
invalid_bboxes = 0
class_counts = {}

for img_p in image_paths:
    lbl_p = label_paths.get(img_p.stem)
    bboxes_in_img = 0
    if lbl_p and lbl_p.exists():
        with open(lbl_p, 'r', encoding='utf-8', errors='ignore') as f:
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
                        bboxes_in_img += 1
                        total_bboxes += 1
                    except ValueError:
                        invalid_bboxes += 1

    if bboxes_in_img > 0:
        positive_images += 1
    else:
        clean_images += 1

print("\n--- RESULTS ---")
print(f"Total Images: {len(image_paths)}")
print(f"Positive Images (with Trash bboxes): {positive_images}")
print(f"Clean Images (without Trash bboxes): {clean_images}")
print(f"Total Bounding Boxes: {total_bboxes}")
print(f"Invalid Bounding Boxes: {invalid_bboxes}")
print(f"Class IDs found: {class_counts}")
