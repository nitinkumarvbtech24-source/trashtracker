import os
import shutil
from pathlib import Path
from ultralytics import YOLO

BASE_DIR = Path(r"e:\nitin\model2")
YOLO_DIR = BASE_DIR / "dataset" / "yolo_street_aiq"
MODEL_DIR = BASE_DIR / "models"
MODEL_DIR.mkdir(parents=True, exist_ok=True)

def prepare_street_aiq_yolo_dataset():
    if YOLO_DIR.exists():
        shutil.rmtree(YOLO_DIR)
        
    (YOLO_DIR / "images" / "train").mkdir(parents=True, exist_ok=True)
    (YOLO_DIR / "images" / "val").mkdir(parents=True, exist_ok=True)
    (YOLO_DIR / "images" / "test").mkdir(parents=True, exist_ok=True)
    
    (YOLO_DIR / "labels" / "train").mkdir(parents=True, exist_ok=True)
    (YOLO_DIR / "labels" / "val").mkdir(parents=True, exist_ok=True)
    (YOLO_DIR / "labels" / "test").mkdir(parents=True, exist_ok=True)
    
    import random
    random.seed(42)
    
    # 1. Clean Road Images (195 images) - Hard Negatives with 0 boxes (empty label files)
    clean_dir = BASE_DIR / "road cleanliness" / "clean roads"
    clean_imgs = [f for f in clean_dir.glob("*.*") if f.suffix.lower() in ['.jpg', '.jpeg', '.png']]
    random.shuffle(clean_imgs)
    
    n_clean = len(clean_imgs)
    n_clean_train = int(n_clean * 0.8)
    n_clean_val = int(n_clean * 0.1)
    
    clean_splits = {
        "train": clean_imgs[:n_clean_train],
        "val": clean_imgs[n_clean_train:n_clean_train + n_clean_val],
        "test": clean_imgs[n_clean_train + n_clean_val:]
    }
    
    for split, files in clean_splits.items():
        for img in files:
            shutil.copy2(img, YOLO_DIR / "images" / split / img.name)
            # Empty label file tells YOLO: NO TRASH HERE
            with open(YOLO_DIR / "labels" / split / f"{img.stem}.txt", "w") as f:
                pass

    # 2. Trash Images (342 images) - Using auto_labeled / refined bounding boxes
    auto_lbl_dir = BASE_DIR / "dataset" / "auto_labeled" / "labels"
    trash_imgs = []
    for cat in ["slightly dirty", "very dirty"]:
        c_dir = BASE_DIR / "road cleanliness" / cat
        for img in c_dir.glob("*.*"):
            if img.suffix.lower() in ['.jpg', '.jpeg', '.png']:
                lbl = auto_lbl_dir / f"{img.stem}.txt"
                trash_imgs.append((img, lbl))
                
    random.shuffle(trash_imgs)
    n_trash = len(trash_imgs)
    n_trash_train = int(n_trash * 0.8)
    n_trash_val = int(n_trash * 0.1)
    
    trash_splits = {
        "train": trash_imgs[:n_trash_train],
        "val": trash_imgs[n_trash_train:n_trash_train + n_trash_val],
        "test": trash_imgs[n_trash_train + n_trash_val:]
    }
    
    for split, pairs in trash_splits.items():
        for img, lbl in pairs:
            shutil.copy2(img, YOLO_DIR / "images" / split / img.name)
            if lbl.exists():
                shutil.copy2(lbl, YOLO_DIR / "labels" / split / f"{img.stem}.txt")
            else:
                with open(YOLO_DIR / "labels" / split / f"{img.stem}.txt", "w") as f:
                    pass

    # Write data.yaml
    yaml_content = f"""path: {YOLO_DIR.as_posix()}
train: images/train
val: images/val
test: images/test

names:
  0: trash
"""
    yaml_path = YOLO_DIR / "data.yaml"
    with open(yaml_path, "w") as f:
        f.write(yaml_content)
        
    print(f"YOLO Street AIQ dataset setup complete: {yaml_path}")
    return yaml_path

def train_baseline_yolo():
    yaml_path = prepare_street_aiq_yolo_dataset()
    
    print("\n==================================================")
    print("TRAINING YOLOV8 BASELINE ROAD TRASH DETECTOR")
    print("==================================================")
    
    model = YOLO("yolov8n.pt")
    
    results = model.train(
        data=str(yaml_path),
        epochs=30,
        imgsz=640,
        batch=16,
        workers=0,
        name="street_aiq_yolo",
        project=str(BASE_DIR / "runs"),
        exist_ok=True,
        save=True
    )
    
    best_pt = BASE_DIR / "runs" / "street_aiq_yolo" / "weights" / "best.pt"
    target_pt = MODEL_DIR / "yolov8_street_aiq.pt"
    
    if best_pt.exists():
        shutil.copy2(best_pt, target_pt)
        print(f"\n✅ YOLOv8 Street AIQ Model trained successfully! Saved to: {target_pt}")

if __name__ == "__main__":
    train_baseline_yolo()
