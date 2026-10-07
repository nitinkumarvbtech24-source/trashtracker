import os
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")

for folder in [
    BASE_DIR / "aiq trash detection 1.v1i.yolov8",
    BASE_DIR / "trash.v1i.yolov8",
    BASE_DIR / "road cleanliness" / "clean roads",
    BASE_DIR / "road cleanliness" / "slightly dirty",
    BASE_DIR / "road cleanliness" / "very dirty",
    BASE_DIR / "road cleanliness final (1)",
    BASE_DIR / "Clean road"
]:
    print(f"\nChecking folder: {folder}")
    if not folder.exists():
        print("Does not exist!")
        continue
    imgs = list(folder.rglob("*.jpg")) + list(folder.rglob("*.png")) + list(folder.rglob("*.jpeg"))
    txts = [p for p in folder.rglob("*.txt") if not p.name.lower().startswith("readme")]
    print(f"  Images: {len(imgs)}")
    print(f"  TXT Labels: {len(txts)}")
