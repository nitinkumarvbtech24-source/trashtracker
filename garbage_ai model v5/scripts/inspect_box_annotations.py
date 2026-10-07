import os
import sys
from pathlib import Path

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")
BOX_DIR = BASE_DIR / "box annotations"

print("==================================================")
print("INSPECTING 'box annotations' FILE FORMAT AND PAIRINGS")
print("==================================================")

imgs = list(BOX_DIR.rglob("*.jpg")) + list(BOX_DIR.rglob("*.png")) + list(BOX_DIR.rglob("*.jpeg"))
txts = [t for t in BOX_DIR.rglob("*.txt") if not t.name.lower().startswith("readme") and "requirement" not in t.name]

print(f"Total Images in 'box annotations': {len(imgs)}")
print(f"Total Label Files in 'box annotations': {len(txts)}")

for txt_path in txts[:15]:
    print(f"\nLabel File: {txt_path.name}")
    with open(txt_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = [line.strip() for line in f if line.strip()]
        for l in lines:
            print(f"  Content: '{l}'")
