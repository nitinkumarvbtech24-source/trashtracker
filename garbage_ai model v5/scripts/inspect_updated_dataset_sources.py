import os
import sys
import hashlib
import yaml
from pathlib import Path

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")

print("==================================================")
print("DEEP INSPECTION OF ALL UPDATED DATASET SOURCES")
print("==================================================")

candidate_folders = [
    ("box_annotations", BASE_DIR / "box annotations"),
    ("Trash_v2i", BASE_DIR / "Trash.v2i.yolov8"),
    ("aiq_v2i", BASE_DIR / "aiq trash detection 1.v2i.yolov8"),
    ("trash_v1i", BASE_DIR / "trash.v1i.yolov8"),
    ("Clean_road", BASE_DIR / "Clean road"),
    ("root_train", BASE_DIR / "train"),
    ("root_valid", BASE_DIR / "valid"),
    ("root_test", BASE_DIR / "test")
]

for tag, fpath in candidate_folders:
    print(f"\n--------------------------------------------------")
    print(f"Folder: '{tag}' -> Path: {fpath}")
    if not fpath.exists():
        print("  Status: DOES NOT EXIST!")
        continue
    
    imgs = list(fpath.rglob("*.jpg")) + list(fpath.rglob("*.png")) + list(fpath.rglob("*.jpeg"))
    txts = [t for t in fpath.rglob("*.txt") if not t.name.lower().startswith("readme") and "requirement" not in t.name]
    yamls = list(fpath.glob("*.yaml")) + list(fpath.glob("*.yml"))
    
    yaml_names = {}
    for y in yamls:
        try:
            with open(y, 'r', encoding='utf-8', errors='ignore') as yf:
                content = yaml.safe_load(yf)
                if isinstance(content, dict) and 'names' in content:
                    yaml_names[y.name] = content['names']
        except Exception:
            pass

    total_bboxes = 0
    invalid_bboxes = 0
    pos_images = 0
    clean_images = 0

    for img in imgs:
        # Find matching txt label
        lbl = None
        if "images" in img.parts:
            parts = list(img.parts)
            idx = parts.index("images")
            parts[idx] = "labels"
            cand = Path(*parts).with_suffix(".txt")
            if cand.exists():
                lbl = cand
        if lbl is None:
            cand = img.with_suffix(".txt")
            if cand.exists():
                lbl = cand
        if lbl is None:
            matches = list(fpath.rglob(f"{img.stem}.txt"))
            matches = [m for m in matches if not m.name.lower().startswith("readme") and "requirement" not in m.name]
            if matches:
                lbl = matches[0]

        b_cnt = 0
        if lbl and lbl.exists():
            with open(lbl, 'r', encoding='utf-8', errors='ignore') as lf:
                for line in lf:
                    parts = line.strip().split()
                    if len(parts) >= 5:
                        try:
                            cx, cy, w, h = map(float, parts[1:5])
                            if not (0 <= cx <= 1 and 0 <= cy <= 1 and 0 <= w <= 1 and 0 <= h <= 1):
                                invalid_bboxes += 1
                            b_cnt += 1
                        except ValueError:
                            invalid_bboxes += 1

        if b_cnt > 0:
            pos_images += 1
            total_bboxes += b_cnt
        else:
            clean_images += 1

    print(f"  Images: {len(imgs)} | Label TXTs: {len(txts)}")
    print(f"  Trash Annotated Images: {pos_images} | Clean Road Images: {clean_images}")
    print(f"  Total Bounding Boxes: {total_bboxes} | Invalid Bboxes: {invalid_bboxes}")
    print(f"  YAML Classes defined: {yaml_names}")
