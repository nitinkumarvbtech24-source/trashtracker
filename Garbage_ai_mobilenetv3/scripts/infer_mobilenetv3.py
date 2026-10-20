import os
import glob
import cv2
import torch
import torch.nn as nn
import yaml
import numpy as np
from torchvision import transforms, models
from pathlib import Path
from PIL import Image

# ─────────────────────────────────────────────
# Project paths
# ─────────────────────────────────────────────
PROJECT_ROOT  = Path(r"e:\nitin\models\Garbage_ai_mobilenetv3")
CONFIG_PATH   = PROJECT_ROOT / "configs" / "model_config.yaml"
MODEL_PATH    = PROJECT_ROOT / "weights" / "garbage_ai_mobilenetv3_best.pt"
TEST_IMG_DIR  = Path(r"e:\nitin\models\datasets\images\test")
OUTPUT_DIR    = PROJECT_ROOT / "runs" / "inference_samples"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def load_config(path: Path) -> dict:
    with open(path, "r") as f:
        return yaml.safe_load(f)


def build_model(cfg: dict, device: torch.device) -> nn.Module:
    model_cfg = cfg["model"]
    model = models.mobilenet_v3_large(weights=None)
    in_features = model.classifier[3].in_features
    model.classifier[3] = nn.Sequential(
        nn.Dropout(p=model_cfg["dropout"]),
        nn.Linear(in_features, model_cfg["num_classes"]),
    )
    state_dict = torch.load(MODEL_PATH, map_location=device)
    model.load_state_dict(state_dict)
    model.to(device)
    model.eval()
    return model


def build_transform(cfg: dict) -> transforms.Compose:
    aug      = cfg["augmentation"]
    norm     = aug["normalize"]
    img_size = cfg["dataset"]["image_size"]
    return transforms.Compose([
        transforms.Resize((img_size, img_size)),
        transforms.ToTensor(),
        transforms.Normalize(mean=norm["mean"], std=norm["std"]),
    ])


def overlay_result(img_bgr: np.ndarray, label: str, confidence: float) -> np.ndarray:
    """Draw a translucent banner with the prediction on the image."""
    h, w = img_bgr.shape[:2]
    banner_h = 40
    overlay  = img_bgr.copy()
    color    = (0, 200, 60) if label == "no_trash" else (30, 30, 220)
    cv2.rectangle(overlay, (0, 0), (w, banner_h), color, -1)
    cv2.addWeighted(overlay, 0.55, img_bgr, 0.45, 0, img_bgr)
    text = f"{label.upper()}  {confidence*100:.1f}%"
    cv2.putText(img_bgr, text, (10, 28),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
    return img_bgr


@torch.no_grad()
def run_inference(conf_thresh: float = 0.5):
    cfg    = load_config(CONFIG_PATH)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    print("=" * 60)
    print("   Garbage AI – MobileNetV3-Large Inference Verification   ")
    print("=" * 60)

    if not MODEL_PATH.exists():
        print(f"Error: Model weights not found at {MODEL_PATH}")
        print("Please run train_mobilenetv3.py first.")
        return

    print(f"Loading model    : {MODEL_PATH}")
    model     = build_model(cfg, device)
    transform = build_transform(cfg)

    test_imgs = sorted(glob.glob(str(TEST_IMG_DIR / "*.*")))
    print(f"Test images found: {len(test_imgs)}")
    print("-" * 60)

    trash_count    = 0
    no_trash_count = 0

    for idx, img_path in enumerate(test_imgs):
        # Load and preprocess
        pil_img = Image.open(img_path).convert("RGB")
        tensor  = transform(pil_img).unsqueeze(0).to(device)

        # Forward pass
        logit      = model(tensor)
        prob_trash = torch.sigmoid(logit).item()
        is_trash   = prob_trash >= conf_thresh
        label      = "trash" if is_trash else "no_trash"
        confidence = prob_trash if is_trash else (1.0 - prob_trash)

        # Annotate and save
        img_bgr    = cv2.imread(img_path)
        annotated  = overlay_result(img_bgr, label, confidence)
        out_name   = f"pred_{os.path.basename(img_path)}"
        cv2.imwrite(str(OUTPUT_DIR / out_name), annotated)

        if is_trash:
            trash_count += 1
        else:
            no_trash_count += 1

        if idx < 10:
            print(f" [{idx+1:>4}/{len(test_imgs)}] {os.path.basename(img_path):<40} "
                  f"→ {label}  ({confidence*100:.1f}%)")

    print(f"\nInference complete!")
    print(f"  Trash detected    : {trash_count}")
    print(f"  No-trash (clean)  : {no_trash_count}")
    print(f"  Annotated outputs → {OUTPUT_DIR}")


if __name__ == "__main__":
    run_inference(conf_thresh=0.5)
