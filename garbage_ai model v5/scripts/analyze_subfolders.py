import os
import yaml
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")
DATASET_DIR = BASE_DIR / "dataset"

print("==================================================")
print("SUBFOLDER ANALYSIS OF E:\\nitin\\model2\\dataset")
print("==================================================")

subdirs = [p for p in DATASET_DIR.iterdir() if p.is_dir()]

for sub in subdirs:
    imgs = list(sub.rglob("*.jpg")) + list(sub.rglob("*.png")) + list(sub.rglob("*.jpeg"))
    txts = [t for t in sub.rglob("*.txt") if not t.name.lower().startswith("readme") and "requirement" not in t.name]
    
    bboxes = 0
    pos_imgs = 0
    clean_imgs = 0

    for img in imgs:
        # Find matching label
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
        
        box_cnt = 0
        if lbl and lbl.exists():
            with open(lbl, 'r', encoding='utf-8', errors='ignore') as f:
                lines = [l.strip() for l in f if l.strip()]
                for l in lines:
                    p = l.split()
                    if len(p) >= 5:
                        box_cnt += 1

        if box_cnt > 0:
            pos_imgs += 1
            bboxes += box_cnt
        else:
            clean_imgs += 1

    print(f"\nSubfolder: '{sub.name}'")
    print(f"  Path: {sub}")
    print(f"  Total Images: {len(imgs)}")
    print(f"  Label Files: {len(txts)}")
    print(f"  Annotated Trash Images: {pos_imgs}")
    print(f"  Clean Road Images: {clean_imgs}")
    print(f"  Trash Bounding Boxes: {bboxes}")
