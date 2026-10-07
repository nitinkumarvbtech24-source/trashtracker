import os
import sys
from pathlib import Path

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")
BOX_DIR = BASE_DIR / "box annotations"

imgs = [p for p in BOX_DIR.rglob("*.*") if p.suffix.lower() in [".jpg", ".png", ".jpeg"] and not p.name.startswith("._")]
txts = [p for p in BOX_DIR.rglob("*.txt") if not p.name.startswith("._") and not p.name.lower().startswith("readme") and "requirement" not in p.name]

print("==================================================")
print("CLEAN INSPECTION OF 'box annotations' (Excluding macOS ._ files)")
print("==================================================")
print(f"Valid Image Files: {len(imgs)}")
print(f"Valid Label Files: {len(txts)}")

pos_cnt = 0
clean_cnt = 0
total_boxes = 0

for img in imgs:
    # Match label file
    lbl = None
    if "images" in img.parts:
        parts = list(img.parts)
        idx = parts.index("images")
        parts[idx] = "labels"
        cand = Path(*parts).with_suffix(".txt")
        if cand.exists() and not cand.name.startswith("._"):
            lbl = cand
    if lbl is None:
        cand = img.with_suffix(".txt")
        if cand.exists() and not cand.name.startswith("._"):
            lbl = cand

    b_cnt = 0
    if lbl and lbl.exists():
        with open(lbl, 'r', encoding='utf-8', errors='ignore') as lf:
            for line in lf:
                parts = line.strip().split()
                if len(parts) >= 5:
                    try:
                        cx, cy, w, h = map(float, parts[1:5])
                        if 0 <= cx <= 1 and 0 <= cy <= 1 and 0 <= w <= 1 and 0 <= h <= 1:
                            b_cnt += 1
                    except ValueError:
                        pass

    if b_cnt > 0:
        pos_cnt += 1
        total_boxes += b_cnt
    else:
        clean_cnt += 1

print(f"Positive Trash Images: {pos_cnt}")
print(f"Clean Images:           {clean_cnt}")
print(f"Total Bounding Boxes:   {total_boxes}")
