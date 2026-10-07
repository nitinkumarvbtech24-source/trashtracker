import os
import hashlib
from pathlib import Path
from PIL import Image

BASE_DIR = Path(r"e:\nitin\model2")

ds1_dir = BASE_DIR / "aiq trash detection 1.v1i.yolov8"
ds2_dir = BASE_DIR / "trash.v1i.yolov8"
clean_dir = BASE_DIR / "road cleanliness" / "clean roads"

def get_image_info(folder):
    imgs = list(folder.rglob("*.jpg")) + list(folder.rglob("*.png")) + list(folder.rglob("*.jpeg"))
    hashes = {}
    shapes = set()
    for img_path in imgs:
        with open(img_path, "rb") as f:
            h = hashlib.md5(f.read()).hexdigest()
        hashes[img_path] = h
        try:
            with Image.open(img_path) as im:
                shapes.add(im.size)
        except Exception:
            pass
    return imgs, hashes, shapes

print("Scanning Dataset 1...")
imgs1, hashes1, shapes1 = get_image_info(ds1_dir)
print("Scanning Dataset 2...")
imgs2, hashes2, shapes2 = get_image_info(ds2_dir)
print("Scanning Dataset 3 (Clean)...")
imgs3, hashes3, shapes3 = get_image_info(clean_dir)

# Check overlaps
h1_set = set(hashes1.values())
h2_set = set(hashes2.values())
h3_set = set(hashes3.values())

overlap_1_2 = h1_set.intersection(h2_set)
overlap_1_3 = h1_set.intersection(h3_set)
overlap_2_3 = h2_set.intersection(h3_set)

print("\n--- DUPLICATE / OVERLAP ANALYSIS ---")
print(f"Dataset 1 unique hashes: {len(h1_set)}")
print(f"Dataset 2 unique hashes: {len(h2_set)}")
print(f"Dataset 3 unique hashes: {len(h3_set)}")
print(f"Duplicates between Dataset 1 and Dataset 2: {len(overlap_1_2)}")
print(f"Duplicates between Dataset 1 and Dataset 3: {len(overlap_1_3)}")
print(f"Duplicates between Dataset 2 and Dataset 3: {len(overlap_2_3)}")

print("\n--- IMAGE RESOLUTION DISTRIBUTIONS ---")
print(f"Dataset 1 resolutions: {shapes1}")
print(f"Dataset 2 resolutions: {shapes2}")
print(f"Dataset 3 resolutions: {shapes3}")
