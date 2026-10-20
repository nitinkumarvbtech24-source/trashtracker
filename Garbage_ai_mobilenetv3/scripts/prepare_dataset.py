"""
prepare_dataset.py
──────────────────
Reads the flat dataset:
    dataset/
        clean roads/    ← 215 images
        very dirty/     ← 235 images

Produces an ImageFolder-compatible split:
    dataset_split/
        train/
            clean_road/
            very_dirty/
        val/
            clean_road/
            very_dirty/
        test/
            clean_road/
            very_dirty/

Class names are normalised to valid folder names:
    "clean roads" → "clean_road"
    "very dirty"  → "very_dirty"

Run once before training.
"""

import os
import shutil
import random
import yaml
from pathlib import Path

PROJECT_ROOT = Path(r"e:\nitin\models\Garbage_ai_mobilenetv3")
CONFIG_PATH  = PROJECT_ROOT / "configs" / "model_config.yaml"

# Safe folder name mapping
CLASS_NAME_MAP = {
    "clean roads": "clean_road",
    "very dirty":  "very_dirty",
}

VALID_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".JPG", ".JPEG", ".PNG"}


def load_config(path: Path) -> dict:
    with open(path, "r") as f:
        return yaml.safe_load(f)


def prepare():
    cfg    = load_config(CONFIG_PATH)
    ds_cfg = cfg["dataset"]

    raw_root   = Path(ds_cfg["raw_root"])
    split_root = Path(ds_cfg["root"])
    classes    = ds_cfg["classes"]

    train_r = ds_cfg["train_ratio"]
    val_r   = ds_cfg["val_ratio"]
    seed    = ds_cfg["seed"]

    random.seed(seed)

    print("=" * 60)
    print("   Garbage AI – Dataset Preparation (train/val/test split)   ")
    print("=" * 60)
    print(f"Source      : {raw_root}")
    print(f"Destination : {split_root}")
    print(f"Split       : {train_r*100:.0f}% train / {val_r*100:.0f}% val / {(1-train_r-val_r)*100:.0f}% test")
    print()

    if split_root.exists():
        print("⚠  dataset_split/ already exists – removing and recreating...")
        shutil.rmtree(split_root)

    total_copied = 0

    for raw_cls in classes:
        safe_cls = CLASS_NAME_MAP.get(raw_cls, raw_cls.replace(" ", "_"))
        src_dir  = raw_root / raw_cls

        if not src_dir.exists():
            print(f"  ✗ Source class folder not found: {src_dir}")
            continue

        # Collect all valid image files
        all_imgs = sorted([
            f for f in src_dir.iterdir()
            if f.is_file() and f.suffix in VALID_EXTS
        ])
        random.shuffle(all_imgs)

        n       = len(all_imgs)
        n_train = int(n * train_r)
        n_val   = int(n * val_r)

        splits = {
            "train": all_imgs[:n_train],
            "val":   all_imgs[n_train:n_train + n_val],
            "test":  all_imgs[n_train + n_val:],
        }

        print(f"  Class '{raw_cls}' -> '{safe_cls}'  ({n} total)")
        for split_name, files in splits.items():
            dest_dir = split_root / split_name / safe_cls
            dest_dir.mkdir(parents=True, exist_ok=True)
            for f in files:
                shutil.copy2(f, dest_dir / f.name)
            print(f"    {split_name:5s}: {len(files):>3} images -> {dest_dir}")
            total_copied += len(files)

        print()

    print(f"Done! Total files copied: {total_copied}")
    print(f"Destination: {split_root}")
    print("=" * 60)
    print("Now run: python scripts/train_mobilenetv3.py")


if __name__ == "__main__":
    prepare()
