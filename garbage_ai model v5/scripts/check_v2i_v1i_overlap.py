import hashlib
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")

src1 = BASE_DIR / "aiq trash detection 1.v2i.yolov8"
src2 = BASE_DIR / "trash.v1i.yolov8"
src3 = BASE_DIR / "Clean road"

def get_hashes(p):
    imgs = list(p.rglob("*.jpg")) + list(p.rglob("*.png")) + list(p.rglob("*.jpeg"))
    h_map = {}
    for img in imgs:
        with open(img, 'rb') as f:
            h = hashlib.md5(f.read()).hexdigest()
        h_map[h] = img
    return h_map

h1 = get_hashes(src1)
h2 = get_hashes(src2)
h3 = get_hashes(src3)

print(f"aiq trash detection 1.v2i.yolov8 total images: {len(h1)}")
print(f"trash.v1i.yolov8 total images:               {len(h2)}")
print(f"Clean road total images:                      {len(h3)}")

overlap_1_2 = set(h1.keys()).intersection(set(h2.keys()))
overlap_1_3 = set(h1.keys()).intersection(set(h3.keys()))
overlap_2_3 = set(h2.keys()).intersection(set(h3.keys()))

print(f"\nOverlap between v2i and trash.v1i: {len(overlap_1_2)}")
print(f"Overlap between v2i and Clean road: {len(overlap_1_3)}")
print(f"Overlap between trash.v1i and Clean road: {len(overlap_2_3)}")
