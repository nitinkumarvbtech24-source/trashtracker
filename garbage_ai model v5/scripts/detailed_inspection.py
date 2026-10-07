import os
import glob
import yaml
from pathlib import Path
from PIL import Image

BASE_DIR = Path(r"e:\nitin\model2")

def inspect_dataset_dir(ds_dir, name):
    print(f"\n==========================================")
    print(f"INSPECTING DATASET: {name}")
    print(f"Path: {ds_dir}")
    print(f"==========================================")
    if not ds_dir.exists():
        print("Folder does not exist!")
        return
        
    yaml_files = list(ds_dir.glob("*.yaml")) + list(ds_dir.glob("*.yml"))
    classes = {}
    for yf in yaml_files:
        print(f"Found YAML config: {yf.name}")
        with open(yf, 'r', encoding='utf-8', errors='ignore') as f:
            try:
                content = yaml.safe_load(f)
                print(f"  YAML content: {content}")
                if 'names' in content:
                    classes = content['names']
            except Exception as e:
                print(f"  Error reading YAML: {e}")

    # Search images and label files
    imgs = []
    for ext in ['*.jpg', '*.png', '*.jpeg']:
        imgs.extend(list(ds_dir.rglob(ext)))
    
    txts = [p for p in ds_dir.rglob("*.txt") if not p.name.lower().startswith("readme")]

    print(f"Total Images: {len(imgs)}")
    print(f"Total Label Files: {len(txts)}")

    # Class ID distribution and bounding box validation
    class_counts = {}
    total_bboxes = 0
    invalid_bboxes = 0

    for txt_path in txts:
        with open(txt_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]
            for line in lines:
                parts = line.split()
                if len(parts) >= 5:
                    try:
                        cls_id = int(parts[0])
                        class_counts[cls_id] = class_counts.get(cls_id, 0) + 1
                        total_bboxes += 1
                        cx, cy, w, h = map(float, parts[1:5])
                        if not (0 <= cx <= 1 and 0 <= cy <= 1 and 0 <= w <= 1 and 0 <= h <= 1):
                            invalid_bboxes += 1
                    except ValueError:
                        # Non integer class or invalid float line
                        pass

    print(f"Total Bounding Boxes: {total_bboxes}")
    print(f"Invalid Bounding Boxes: {invalid_bboxes}")
    print(f"Class IDs found: {class_counts}")
    print(f"Classes defined in YAML: {classes}")

inspect_dataset_dir(BASE_DIR / "aiq trash detection 1.v1i.yolov8", "1. aiq trash detection 1.v1i.yolov8")
inspect_dataset_dir(BASE_DIR / "trash.v1i.yolov8", "2. trash.v1i.yolov8")
inspect_dataset_dir(BASE_DIR / "road cleanliness" / "clean roads", "3. clean roads (Clean Road Directory)")
inspect_dataset_dir(BASE_DIR / "dataset", "4. dataset (Workspace Dataset)")
