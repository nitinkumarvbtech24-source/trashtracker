import os
from pathlib import Path
import hashlib

BASE_DIR = Path(r"e:\nitin\model2")

print("--- FULL BASE DIR IMAGE SEARCH ---")
all_imgs = list(BASE_DIR.rglob("*.jpg")) + list(BASE_DIR.rglob("*.png")) + list(BASE_DIR.rglob("*.jpeg"))
print(f"Total image files found across entire workspace: {len(all_imgs)}")

# Group images by top-level parent relative to BASE_DIR
grouped = {}
for img in all_imgs:
    try:
        rel = img.relative_to(BASE_DIR)
        top = rel.parts[0]
    except Exception:
        top = "root"
    grouped[top] = grouped.get(top, 0) + 1

for k, v in grouped.items():
    print(f"  Folder '{k}': {v} images")

print("\n--- LABEL SEARCH ---")
all_labels = [p for p in BASE_DIR.rglob("*.txt") if p.name != "README.dataset.txt" and "requirements" not in p.name]
print(f"Total txt label files found: {len(all_labels)}")
label_grouped = {}
for lbl in all_labels:
    try:
        rel = lbl.relative_to(BASE_DIR)
        top = rel.parts[0]
    except Exception:
        top = "root"
    label_grouped[top] = label_grouped.get(top, 0) + 1

for k, v in label_grouped.items():
    print(f"  Folder '{k}': {v} label files")
