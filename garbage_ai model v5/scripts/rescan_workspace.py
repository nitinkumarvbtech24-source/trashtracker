import os
import time
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")

print(f"Scanning directory: {BASE_DIR}\n")

entries = list(BASE_DIR.iterdir())
print(f"Total top-level items: {len(entries)}")

folders_info = []

for entry in sorted(entries, key=lambda x: x.name.lower()):
    if entry.is_dir() and not entry.name.startswith(".") and entry.name not in ["runs", "scratch"]:
        imgs = list(entry.rglob("*.jpg")) + list(entry.rglob("*.png")) + list(entry.rglob("*.jpeg")) + list(entry.rglob("*.webp"))
        txts = [p for p in entry.rglob("*.txt") if not p.name.lower().startswith("readme") and "requirement" not in p.name]
        yamls = list(entry.rglob("*.yaml")) + list(entry.rglob("*.yml"))
        
        folders_info.append({
            "name": entry.name,
            "path": str(entry),
            "images": len(imgs),
            "txt_labels": len(txts),
            "yamls": [y.name for y in yamls],
            "mtime": time.ctime(entry.stat().st_mtime)
        })

print("\n--- SUMMARY OF ALL DATASETS AND FOLDERS IN E:\\nitin\\model2 ---")
for f in folders_info:
    print(f"Folder: '{f['name']}'")
    print(f"  Images: {f['images']} | TXT Labels: {f['txt_labels']} | YAMLs: {f['yamls']}")
    print(f"  Last Modified: {f['mtime']}\n")
