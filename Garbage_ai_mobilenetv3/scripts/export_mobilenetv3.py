import torch
import torch.nn as nn
import yaml
from torchvision import models
from pathlib import Path

# ─────────────────────────────────────────────
# Project paths
# ─────────────────────────────────────────────
PROJECT_ROOT = Path(r"e:\nitin\models\Garbage_ai_mobilenetv3")
CONFIG_PATH  = PROJECT_ROOT / "configs" / "model_config.yaml"
WEIGHTS_DIR  = PROJECT_ROOT / "weights"
MODEL_PATH   = WEIGHTS_DIR / "garbage_ai_mobilenetv3_best.pt"


def load_config(path: Path) -> dict:
    with open(path, "r") as f:
        return yaml.safe_load(f)


def build_model(cfg: dict) -> nn.Module:
    model_cfg = cfg["model"]
    model = models.mobilenet_v3_large(weights=None)
    in_features = model.classifier[3].in_features
    model.classifier[3] = nn.Sequential(
        nn.Dropout(p=model_cfg["dropout"]),
        nn.Linear(in_features, model_cfg["num_classes"]),
    )
    state_dict = torch.load(MODEL_PATH, map_location="cpu")
    model.load_state_dict(state_dict)
    model.eval()
    return model


def export_onnx(cfg: dict, model: nn.Module):
    export_cfg = cfg["export"]
    img_size   = cfg["dataset"]["image_size"]
    opset      = export_cfg.get("opset", 17)
    dynamic    = export_cfg.get("dynamic_axes", True)

    dummy_input = torch.randn(1, 3, img_size, img_size)
    onnx_path   = WEIGHTS_DIR / "garbage_ai_mobilenetv3_best.onnx"

    dynamic_axes = None
    if dynamic:
        dynamic_axes = {
            "input":  {0: "batch_size"},
            "output": {0: "batch_size"},
        }

    torch.onnx.export(
        model,
        dummy_input,
        str(onnx_path),
        opset_version=opset,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes=dynamic_axes,
    )
    print(f"ONNX model exported → {onnx_path}")
    return onnx_path


def export_torchscript(model: nn.Module, img_size: int):
    scripted    = torch.jit.script(model)
    script_path = WEIGHTS_DIR / "garbage_ai_mobilenetv3_best.torchscript"
    scripted.save(str(script_path))
    print(f"TorchScript model exported → {script_path}")
    return script_path


def export_model():
    print("=" * 60)
    print("   Garbage AI – MobileNetV3 Export Pipeline   ")
    print("=" * 60)

    if not MODEL_PATH.exists():
        print(f"Error: Model weights not found at {MODEL_PATH}")
        print("Please run train_mobilenetv3.py first.")
        return

    cfg      = load_config(CONFIG_PATH)
    fmt      = cfg["export"]["format"].lower()
    img_size = cfg["dataset"]["image_size"]

    print(f"Loading model from : {MODEL_PATH}")
    model = build_model(cfg)

    if fmt == "onnx":
        export_onnx(cfg, model)
    elif fmt == "torchscript":
        export_torchscript(model, img_size)
    else:
        # Export both by default
        export_onnx(cfg, model)
        export_torchscript(model, img_size)

    print("\nExport complete!")


if __name__ == "__main__":
    export_model()
