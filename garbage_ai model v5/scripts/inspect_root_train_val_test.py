import os
import sys
import hashlib
from pathlib import Path

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")

dirs = [BASE_DIR / "train", BASE_DIR / "valid", BASE_DIR / "test"]
trash_v2i_dir = BASE_DIR / "Trash.v2i.yolov8"

def get_hashes(fpath):
    imgs = [p for p in fpath.rglob("*.*") if p.suffix.lower() in [".jpg", ".jpeg", ".png"] and not p.name.startswith("._")]
    h_map = {}
    for img in imgs:
        with open(img, 'rb') as f:
            h = hashlib.md5(f.read()).hexdigest()
        h_map[h] = img
    return h_map

root_hashes = {}
for d in dirs:
    root_hashes.update(get_hashes(d))

v2i_hashes = get_hashes(trash_v2i_dir)

print(f"Total Unique Images in root train/valid/test: {len(root_hashes)}")
print(f"Total Unique Images in Trash.v2i.yolov8:    {len(v2i_hashes)}")

overlap = set(root_hashes.keys()).intersection(set(v2i_hashes.keys()))
print(f"Overlap between root train/valid/test and Trash.v2i.yolov8: {len(overlap)}")
