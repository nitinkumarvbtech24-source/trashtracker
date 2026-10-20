"""
train_mobilenetv3.py
────────────────────
Full training pipeline for binary road-cleanliness classification.

Techniques used for best accuracy on a small dataset:
  • MobileNetV3-Large with ImageNet pretrained backbone
  • Heavy augmentation: flips, rotation, affine, perspective, colour jitter,
    Gaussian blur, greyscale, random erasing
  • MixUp regularisation
  • Label smoothing in cross-entropy
  • Cosine LR schedule with linear warmup
  • AdamW optimiser
  • Progressive layer unfreezing (backbone unlocked after warm-up)
  • Class-weighted loss for any class imbalance
  • Early stopping + best-checkpoint saving
  • Final TTA (Test Time Augmentation) on test set
"""

import os
import sys
import copy
import math
import random
import shutil
import yaml
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.optim.lr_scheduler import LambdaLR, CosineAnnealingLR
from torch.utils.data import DataLoader, WeightedRandomSampler
from torchvision import transforms, datasets, models
from pathlib import Path
from collections import Counter

# ─────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(r"e:\nitin\models\Garbage_ai_mobilenetv3")
CONFIG_PATH  = PROJECT_ROOT / "configs" / "model_config.yaml"
WEIGHTS_DIR  = PROJECT_ROOT / "weights"
RUNS_DIR     = PROJECT_ROOT / "runs"
WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
RUNS_DIR.mkdir(parents=True, exist_ok=True)


# ─── helpers ─────────────────────────────────────────────────

def load_config(path: Path) -> dict:
    with open(path, "r") as f:
        return yaml.safe_load(f)


def set_seed(seed: int):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.backends.cudnn.deterministic = True
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def get_device(cfg: dict) -> torch.device:
    pref = cfg["training"].get("device", "auto").lower()
    if pref == "auto":
        return torch.device("cuda" if torch.cuda.is_available() else "cpu")
    return torch.device(pref)


# ─── transforms ──────────────────────────────────────────────

def build_train_transform(cfg: dict) -> transforms.Compose:
    aug  = cfg["augmentation"]["train"]
    norm = aug["normalize"]

    ops = [
        transforms.Resize(aug["resize"]),
        transforms.RandomCrop(aug["crop"]),
    ]

    if aug.get("random_horizontal_flip"):
        ops.append(transforms.RandomHorizontalFlip())
    if aug.get("random_vertical_flip"):
        ops.append(transforms.RandomVerticalFlip())

    ops.append(transforms.RandomRotation(aug["rotation_degrees"]))

    aff = aug.get("affine", {})
    if aff:
        ops.append(transforms.RandomAffine(
            degrees=aug["rotation_degrees"],
            translate=tuple(aff["translate"]),
            scale=tuple(aff["scale"]),
            shear=aff["shear"],
        ))

    persp = aug.get("perspective_distortion", 0)
    if persp:
        ops.append(transforms.RandomPerspective(distortion_scale=persp, p=0.5))

    cj = aug.get("color_jitter", {})
    if cj:
        ops.append(transforms.ColorJitter(
            brightness=cj["brightness"],
            contrast=cj["contrast"],
            saturation=cj["saturation"],
            hue=cj["hue"],
        ))

    gb = aug.get("gaussian_blur", {})
    if gb and gb.get("prob", 0):
        ks = gb["kernel_size"]
        ops.append(transforms.RandomApply(
            [transforms.GaussianBlur(kernel_size=ks[1], sigma=(0.1, 3.0))],
            p=gb["prob"]
        ))

    gs_prob = aug.get("random_grayscale_prob", 0)
    if gs_prob:
        ops.append(transforms.RandomGrayscale(p=gs_prob))

    ops += [
        transforms.ToTensor(),
        transforms.Normalize(mean=norm["mean"], std=norm["std"]),
    ]

    re_prob  = aug.get("random_erasing_prob", 0)
    re_scale = aug.get("random_erasing_scale", [0.02, 0.33])
    if re_prob:
        ops.append(transforms.RandomErasing(
            p=re_prob, scale=tuple(re_scale), ratio=(0.3, 3.3), value="random"
        ))

    return transforms.Compose(ops)


def build_eval_transform(cfg: dict) -> transforms.Compose:
    aug  = cfg["augmentation"]["val_test"]
    norm = aug["normalize"]
    return transforms.Compose([
        transforms.Resize(aug["resize"]),
        transforms.CenterCrop(aug["center_crop"]),
        transforms.ToTensor(),
        transforms.Normalize(mean=norm["mean"], std=norm["std"]),
    ])


def build_tta_transforms(cfg: dict) -> list:
    """Returns 5 deterministic TTA views of an image."""
    aug  = cfg["augmentation"]["val_test"]
    norm = aug["normalize"]
    size = aug["center_crop"]

    base = [
        transforms.Resize(aug["resize"]),
        transforms.ToTensor(),
        transforms.Normalize(mean=norm["mean"], std=norm["std"]),
    ]

    views = []
    for flip_h in [False, True]:
        for rot in [0, 90]:
            ops = [transforms.Resize(aug["resize"]), transforms.CenterCrop(size)]
            if flip_h:
                ops.append(transforms.RandomHorizontalFlip(p=1.0))
            if rot:
                ops.append(transforms.RandomRotation((rot, rot)))
            ops += [transforms.ToTensor(),
                    transforms.Normalize(mean=norm["mean"], std=norm["std"])]
            views.append(transforms.Compose(ops))

    # original centre crop (5th view)
    views.append(transforms.Compose([
        transforms.Resize(aug["resize"]),
        transforms.CenterCrop(size),
        transforms.ToTensor(),
        transforms.Normalize(mean=norm["mean"], std=norm["std"]),
    ]))
    return views


# ─── model ───────────────────────────────────────────────────

def build_model(cfg: dict, device: torch.device, num_classes: int) -> nn.Module:
    model_cfg = cfg["model"]
    weights   = models.MobileNet_V3_Large_Weights.IMAGENET1K_V2 if model_cfg["pretrained"] else None
    model     = models.mobilenet_v3_large(weights=weights)

    # Freeze backbone initially – only train classifier head during warmup
    for param in model.features.parameters():
        param.requires_grad = False

    in_features = model.classifier[3].in_features
    model.classifier[3] = nn.Sequential(
        nn.Dropout(p=model_cfg["dropout"]),
        nn.Linear(in_features, num_classes),
    )
    return model.to(device)


def unfreeze_backbone(model: nn.Module):
    """Unfreeze all parameters after warmup phase."""
    for param in model.parameters():
        param.requires_grad = True
    print("  [OK] Backbone unfrozen - full fine-tuning enabled.")


# ─── MixUp ───────────────────────────────────────────────────

def mixup_data(x, y, alpha: float, device):
    """Returns mixed inputs, mixed target pairs and lambda."""
    if alpha > 0:
        lam = np.random.beta(alpha, alpha)
    else:
        lam = 1.0
    batch_size = x.size(0)
    index = torch.randperm(batch_size, device=device)
    mixed_x = lam * x + (1 - lam) * x[index]
    y_a, y_b = y, y[index]
    return mixed_x, y_a, y_b, lam


def mixup_criterion(criterion, pred, y_a, y_b, lam):
    return lam * criterion(pred, y_a) + (1 - lam) * criterion(pred, y_b)


# ─── LR scheduler ────────────────────────────────────────────

def build_scheduler(optimizer, cfg: dict):
    train_cfg    = cfg["training"]
    total_epochs = train_cfg["epochs"]
    warmup       = train_cfg.get("warmup_epochs", 5)

    def lr_lambda(epoch):
        if epoch < warmup:
            return float(epoch + 1) / warmup
        progress = (epoch - warmup) / max(1, total_epochs - warmup)
        return 0.5 * (1.0 + math.cos(math.pi * progress))

    return LambdaLR(optimizer, lr_lambda=lr_lambda)


# ─── weighted sampler for class balance ──────────────────────

def build_weighted_sampler(dataset):
    counts  = Counter(dataset.targets)
    n_total = len(dataset.targets)
    weights = [n_total / counts[t] for t in dataset.targets]
    return WeightedRandomSampler(weights, num_samples=n_total, replacement=True)


# ─── train / eval loops ──────────────────────────────────────

def train_one_epoch(model, loader, criterion, optimizer, device, mixup_alpha, num_classes):
    model.train()
    total_loss, correct, total = 0.0, 0, 0

    for imgs, labels in loader:
        imgs, labels = imgs.to(device), labels.to(device)

        if mixup_alpha > 0:
            imgs, labels_a, labels_b, lam = mixup_data(imgs, labels, mixup_alpha, device)
            preds = model(imgs)
            loss  = mixup_criterion(criterion, preds, labels_a, labels_b, lam)
            # accuracy: use original labels (label_a)
            _, predicted = preds.max(1)
            correct += (lam * predicted.eq(labels_a).float()
                        + (1 - lam) * predicted.eq(labels_b).float()).sum().item()
        else:
            preds = model(imgs)
            loss  = criterion(preds, labels)
            _, predicted = preds.max(1)
            correct += predicted.eq(labels).sum().item()

        optimizer.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        optimizer.step()

        total_loss += loss.item() * imgs.size(0)
        total      += imgs.size(0)

    return total_loss / total, correct / total


@torch.no_grad()
def evaluate(model, loader, criterion, device):
    model.eval()
    total_loss, correct, total = 0.0, 0, 0
    all_preds, all_labels = [], []

    for imgs, labels in loader:
        imgs, labels = imgs.to(device), labels.to(device)
        preds = model(imgs)
        loss  = criterion(preds, labels)

        total_loss += loss.item() * imgs.size(0)
        _, predicted = preds.max(1)
        correct += predicted.eq(labels).sum().item()
        total   += imgs.size(0)

        all_preds.extend(predicted.cpu().numpy())
        all_labels.extend(labels.cpu().numpy())

    return total_loss / total, correct / total, all_preds, all_labels


@torch.no_grad()
def evaluate_with_tta(model, dataset_path: Path, tta_transforms: list,
                      batch_size: int, device, num_classes: int):
    """Run TTA evaluation: average logits over multiple augmented views."""
    model.eval()
    correct, total = 0, 0

    # We need per-sample averaging, so we collect dataset by loading with each transform
    from PIL import Image
    import glob

    class_dirs = sorted([d for d in dataset_path.iterdir() if d.is_dir()])
    class_to_idx = {d.name: i for i, d in enumerate(class_dirs)}

    imgs_paths, img_labels = [], []
    for cls_dir in class_dirs:
        for ext in ["*.jpg", "*.jpeg", "*.png", "*.JPG", "*.JPEG", "*.PNG"]:
            for p in cls_dir.glob(ext):
                imgs_paths.append(p)
                img_labels.append(class_to_idx[cls_dir.name])

    for img_path, true_label in zip(imgs_paths, img_labels):
        pil_img   = Image.open(img_path).convert("RGB")
        logit_sum = torch.zeros(num_classes, device=device)

        for tfm in tta_transforms:
            tensor = tfm(pil_img).unsqueeze(0).to(device)
            logit  = model(tensor).squeeze(0)
            logit_sum += logit

        pred = logit_sum.argmax().item()
        correct += int(pred == true_label)
        total   += 1

    return correct / total


# ─── per-class metrics ────────────────────────────────────────

def compute_per_class_metrics(all_preds, all_labels, class_names):
    from collections import defaultdict
    stats = defaultdict(lambda: {"tp": 0, "fp": 0, "fn": 0})
    for pred, label in zip(all_preds, all_labels):
        if pred == label:
            stats[class_names[label]]["tp"] += 1
        else:
            stats[class_names[pred]]["fp"] += 1
            stats[class_names[label]]["fn"] += 1

    print(f"\n  {'Class':<15} {'Precision':>10} {'Recall':>10} {'F1':>10}")
    print(f"  {'-'*47}")
    for cls in class_names:
        tp = stats[cls]["tp"]
        fp = stats[cls]["fp"]
        fn = stats[cls]["fn"]
        p  = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        r  = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = 2 * p * r / (p + r) if (p + r) > 0 else 0.0
        print(f"  {cls:<15} {p:>10.4f} {r:>10.4f} {f1:>10.4f}")


# ─── main ────────────────────────────────────────────────────

def train():
    cfg       = load_config(CONFIG_PATH)
    train_cfg = cfg["training"]
    ds_cfg    = cfg["dataset"]

    set_seed(train_cfg["seed"])
    device      = get_device(cfg)
    device_name = torch.cuda.get_device_name(0) if device.type == "cuda" else "CPU"

    print("=" * 60)
    print("  Garbage AI – MobileNetV3-Large Road Classification  ")
    print("  Classes: clean_road | very_dirty                   ")
    print("=" * 60)
    print(f"  Device        : {device} ({device_name})")
    print(f"  Image size    : {ds_cfg['image_size']}")
    print(f"  Batch size    : {train_cfg['batch_size']}")
    print(f"  Epochs        : {train_cfg['epochs']}")
    print(f"  LR            : {train_cfg['learning_rate']}")
    print(f"  Warmup epochs : {train_cfg.get('warmup_epochs', 5)}")
    print(f"  MixUp alpha   : {train_cfg.get('mixup_alpha', 0)}")
    print(f"  Label smooth  : {train_cfg.get('label_smoothing', 0.0)}")
    print("-" * 60)

    # ── Datasets ────────────────────────────────────────────
    data_root = Path(ds_cfg["root"])

    if not data_root.exists():
        print("\n✗ dataset_split/ not found!")
        print("  Run: python scripts/prepare_dataset.py  first.")
        sys.exit(1)

    train_ds = datasets.ImageFolder(data_root / "train", transform=build_train_transform(cfg))
    val_ds   = datasets.ImageFolder(data_root / "val",   transform=build_eval_transform(cfg))
    test_ds  = datasets.ImageFolder(data_root / "test",  transform=build_eval_transform(cfg))

    class_names = train_ds.classes
    num_classes = len(class_names)
    print(f"  Classes detected : {class_names}")
    print(f"  Train : {len(train_ds)}")
    print(f"  Val   : {len(val_ds)}")
    print(f"  Test  : {len(test_ds)}")
    print("-" * 60)

    # Weighted sampler ensures balanced mini-batches even if counts differ
    sampler = build_weighted_sampler(train_ds)
    train_loader = DataLoader(train_ds, batch_size=train_cfg["batch_size"],
                              sampler=sampler,
                              num_workers=ds_cfg["num_workers"], pin_memory=True)
    val_loader   = DataLoader(val_ds,   batch_size=train_cfg["batch_size"], shuffle=False,
                              num_workers=ds_cfg["num_workers"], pin_memory=True)
    test_loader  = DataLoader(test_ds,  batch_size=train_cfg["batch_size"], shuffle=False,
                              num_workers=ds_cfg["num_workers"], pin_memory=True)

    # ── Model ───────────────────────────────────────────────
    model     = build_model(cfg, device, num_classes)
    criterion = nn.CrossEntropyLoss(label_smoothing=train_cfg.get("label_smoothing", 0.0))
    optimizer = optim.AdamW(
        filter(lambda p: p.requires_grad, model.parameters()),
        lr=train_cfg["learning_rate"],
        weight_decay=train_cfg["weight_decay"],
    )
    scheduler    = build_scheduler(optimizer, cfg)
    mixup_alpha  = train_cfg.get("mixup_alpha", 0.0)
    warmup       = train_cfg.get("warmup_epochs", 5)
    patience     = train_cfg.get("early_stopping_patience", 15)

    best_val_acc  = 0.0
    best_weights  = None
    patience_ctr  = 0
    history       = []
    backbone_unfrozen = False

    print("  Phase 1: Classifier-only warmup (backbone frozen)")
    print("-" * 60)


    for epoch in range(1, train_cfg["epochs"] + 1):

        # Progressive unfreeze after warmup
        if epoch == warmup + 1 and not backbone_unfrozen:
            unfreeze_backbone(model)
            # Rebuild optimizer with lower LR for backbone layers
            optimizer = optim.AdamW([
                {"params": model.features.parameters(), "lr": train_cfg["learning_rate"] * 0.1},
                {"params": model.classifier.parameters(), "lr": train_cfg["learning_rate"]},
            ], weight_decay=train_cfg["weight_decay"])
            scheduler = build_scheduler(optimizer, cfg)
            backbone_unfrozen = True
            print(f"\n  Phase 2: Full fine-tuning (backbone LR x 0.1)")
            print("-" * 60)

        train_loss, train_acc = train_one_epoch(
            model, train_loader, criterion, optimizer, device, mixup_alpha, num_classes)
        val_loss, val_acc, val_preds, val_labels = evaluate(
            model, val_loader, criterion, device)

        scheduler.step()

        history.append({
            "epoch": epoch,
            "train_loss": train_loss, "train_acc": train_acc,
            "val_loss":   val_loss,   "val_acc":   val_acc,
            "lr": scheduler.get_last_lr()[0],
        })

        print(f"  Epoch [{epoch:>3}/{train_cfg['epochs']}] "
              f"train_loss={train_loss:.4f}  train_acc={train_acc:.4f} "
              f"| val_loss={val_loss:.4f}  val_acc={val_acc:.4f}"
              + (" <- best" if val_acc > best_val_acc else ""))

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            best_weights = copy.deepcopy(model.state_dict())
            patience_ctr = 0
        else:
            patience_ctr += 1
            if patience_ctr >= patience:
                print(f"\n  Early stopping at epoch {epoch}  (no improvement for {patience} epochs)")
                break

    # ── Save best checkpoint ─────────────────────────────────
    best_pt = WEIGHTS_DIR / "garbage_ai_mobilenetv3_best.pt"
    torch.save({
        "state_dict":  best_weights,
        "class_names": class_names,
        "num_classes": num_classes,
        "config_path": str(CONFIG_PATH),
    }, best_pt)
    print(f"\n  Best weights saved -> {best_pt}")
    print(f"  Best val accuracy  : {best_val_acc:.4f}")

    # ── Final test evaluation ────────────────────────────────
    model.load_state_dict(best_weights)
    test_loss, test_acc, test_preds, test_labels = evaluate(
        model, test_loader, criterion, device)

    print("\n  --- Standard Test Metrics ---")
    print(f"  Test Loss     : {test_loss:.4f}")
    print(f"  Test Accuracy : {test_acc:.4f}")
    compute_per_class_metrics(test_preds, test_labels, class_names)

    # ── TTA test evaluation ──────────────────────────────────
    print("\n  --- Test Time Augmentation (TTA x 5 views) ---")
    tta_tfms  = build_tta_transforms(cfg)
    tta_acc   = evaluate_with_tta(
        model, data_root / "test", tta_tfms,
        train_cfg["batch_size"], device, num_classes
    )
    print(f"  TTA Accuracy  : {tta_acc:.4f}")

    # ── Save training history ────────────────────────────────
    hist_path = RUNS_DIR / "training_history.csv"
    with open(hist_path, "w") as f:
        f.write("epoch,train_loss,train_acc,val_loss,val_acc,lr\n")
        for row in history:
            f.write(f"{row['epoch']},{row['train_loss']:.6f},{row['train_acc']:.6f},"
                    f"{row['val_loss']:.6f},{row['val_acc']:.6f},{row['lr']:.8f}\n")
    print(f"\n  Training history -> {hist_path}")
    print("=" * 60)


if __name__ == "__main__":
    train()
