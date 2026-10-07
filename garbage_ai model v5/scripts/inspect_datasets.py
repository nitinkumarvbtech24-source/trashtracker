import os
import glob
import yaml
import torch
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")

ds1_path = BASE_DIR / "aiq trash detection 1.v1i.yolov8"
ds2_path = BASE_DIR / "trash.v1i.yolov8"
clean_path = BASE_DIR / "road cleanliness" / "clean roads"

print("--- GPU / CUDA AVAILABILITY ---")
print(f"PyTorch Version: {torch.__version__}")
print(f"CUDA Available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"Device Name: {torch.cuda.get_device_name(0)}")
else:
    print("Device: CPU")

print("\n--- DATASET 1: aiq trash detection 1.v1i.yolov8 ---")
if ds1_path.exists():
    yaml_file1 = ds1_path / "data.yaml"
    if yaml_file1.exists():
        with open(yaml_file1, 'r') as f:
            data1 = yaml.safe_load(f)
            print(f"YAML config: {data1}")
    
    img1_count = len(list(ds1_path.rglob("*.jpg")) + list(ds1_path.rglob("*.png")) + list(ds1_path.rglob("*.jpeg")))
    lbl1_files = list(ds1_path.rglob("*.txt"))
    # Exclude README.dataset.txt if any
    lbl1_files = [f for f in lbl1_files if f.name != "README.dataset.txt"]
    bbox1_count = 0
    for l in lbl1_files:
        with open(l, 'r') as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]
            bbox1_count += len(lines)
    print(f"Total Images: {img1_count}")
    print(f"Total Label Files: {len(lbl1_files)}")
    print(f"Total Bounding Boxes: {bbox1_count}")

print("\n--- DATASET 2: trash.v1i.yolov8 ---")
if ds2_path.exists():
    yaml_file2 = ds2_path / "data.yaml"
    if yaml_file2.exists():
        with open(yaml_file2, 'r') as f:
            data2 = yaml.safe_load(f)
            print(f"YAML config: {data2}")
            
    img2_count = len(list(ds2_path.rglob("*.jpg")) + list(ds2_path.rglob("*.png")) + list(ds2_path.rglob("*.jpeg")))
    lbl2_files = list(ds2_path.rglob("*.txt"))
    lbl2_files = [f for f in lbl2_files if f.name != "README.dataset.txt"]
    bbox2_count = 0
    for l in lbl2_files:
        with open(l, 'r') as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]
            bbox2_count += len(lines)
    print(f"Total Images: {img2_count}")
    print(f"Total Label Files: {len(lbl2_files)}")
    print(f"Total Bounding Boxes: {bbox2_count}")

print("\n--- DATASET 3: Clean Road Images ---")
if clean_path.exists():
    clean_imgs = list(clean_path.rglob("*.jpg")) + list(clean_path.rglob("*.png")) + list(clean_path.rglob("*.jpeg"))
    print(f"Clean Road Directory: {clean_path}")
    print(f"Total Clean Images: {len(clean_imgs)}")
else:
    print("Clean road directory not found at default location. Searching codebase for clean road images...")
    clean_search = list(BASE_DIR.rglob("*clean*"))
    for cs in clean_search:
        if cs.is_dir():
            imgs = list(cs.glob("*.jpg")) + list(cs.glob("*.png"))
            if len(imgs) > 0:
                print(f"Found clean dir: {cs} ({len(imgs)} images)")
