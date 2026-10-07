import os
from pathlib import Path

BASE_DIR = Path(r"e:\nitin\model2")

for ds_name in ["aiq trash detection 1.v1i.yolov8", "trash.v1i.yolov8", "road cleanliness"]:
    ds_path = BASE_DIR / ds_name
    print(f"\n==================== {ds_name} ====================")
    if not ds_path.exists():
        print("Directory does not exist!")
        continue
    for root, dirs, files in os.walk(ds_path):
        rel_root = Path(root).relative_to(ds_path)
        img_files = [f for f in files if f.lower().endswith(('.jpg', '.jpeg', '.png', '.bmp', '.webp'))]
        txt_files = [f for f in files if f.lower().endswith('.txt') and f != 'README.dataset.txt']
        if img_files or txt_files:
            print(f"Subfolder: {rel_root} -> {len(img_files)} images, {len(txt_files)} txt label files")
