import os
import glob
import yaml
import torch
from torchvision import transforms, datasets
from torch.utils.data import DataLoader
from pathlib import Path

# ─────────────────────────────────────────────
# Project paths
# ─────────────────────────────────────────────
PROJECT_ROOT = Path(r"e:\nitin\models\Garbage_ai_mobilenetv3")
CONFIG_PATH  = PROJECT_ROOT / "configs" / "model_config.yaml"


def load_config(path: Path) -> dict:
    with open(path, "r") as f:
        return yaml.safe_load(f)


def check_split(split_path: Path, split_name: str):
    """Validate a dataset split directory and print a summary."""
    print(f"\n[{split_name.upper()}] → {split_path}")

    if not split_path.exists():
        print(f"  ✗ Directory NOT found.")
        return False

    classes = sorted([d.name for d in split_path.iterdir() if d.is_dir()])
    if not classes:
        print("  ✗ No class sub-folders found.")
        return False

    total = 0
    valid_exts = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
    for cls in classes:
        cls_path = split_path / cls
        imgs = [f for f in cls_path.iterdir()
                if f.is_file() and f.suffix.lower() in valid_exts]
        print(f"  Class '{cls}': {len(imgs)} images")
        total += len(imgs)

    print(f"  Total: {total} images  |  Classes: {classes}")
    return True


def validate_dataloader(split_path: Path, split_name: str, cfg: dict):
    """Try building a DataLoader and loading one batch."""
    aug      = cfg["augmentation"]
    norm     = aug["normalize"]
    img_size = cfg["dataset"]["image_size"]

    transform = transforms.Compose([
        transforms.Resize((img_size, img_size)),
        transforms.ToTensor(),
        transforms.Normalize(mean=norm["mean"], std=norm["std"]),
    ])

    try:
        ds     = datasets.ImageFolder(root=str(split_path), transform=transform)
        loader = DataLoader(ds, batch_size=4, shuffle=False, num_workers=0)
        imgs, labels = next(iter(loader))
        print(f"  DataLoader OK  |  batch shape: {imgs.shape}  |  labels: {labels.tolist()}")
    except Exception as e:
        print(f"  DataLoader ERROR: {e}")


def run_validation():
    cfg         = load_config(CONFIG_PATH)
    dataset_cfg = cfg["dataset"]
    data_root   = Path(dataset_cfg["root"])

    print("=" * 60)
    print("   Garbage AI – MobileNetV3 Dataset Validator   ")
    print("=" * 60)
    print(f"Dataset root: {data_root}")

    all_ok = True
    for split in ["train", "val", "test"]:
        split_path = data_root / dataset_cfg[split]
        ok = check_split(split_path, split)
        if ok:
            validate_dataloader(split_path, split, cfg)
        else:
            all_ok = False

    print("\n" + "=" * 60)
    if all_ok:
        print("✓ All dataset splits validated successfully.")
    else:
        print("✗ Some splits have issues. Please check the paths above.")
    print("=" * 60)


if __name__ == "__main__":
    run_validation()
