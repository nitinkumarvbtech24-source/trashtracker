# Garbage AI – MobileNetV3 Model

A **PyTorch MobileNetV3-Large** pipeline for binary garbage / trash classification, structured to mirror `Garbage_ai_model_v6`.

---

## 📁 Folder Structure

```
Garbage_ai_mobilenetv3/
├── configs/
│   └── model_config.yaml          # All hyper-parameters, paths, and export settings
├── scripts/
│   ├── train_mobilenetv3.py       # Full training pipeline with early stopping
│   ├── infer_mobilenetv3.py       # Inference on test images with annotated output
│   ├── export_mobilenetv3.py      # Export to ONNX / TorchScript
│   └── dataset_validator.py       # Validate dataset splits before training
├── weights/                       # Saved .pt / .onnx model files (populated after training)
├── runs/                          # Training logs and inference outputs
└── README.md
```

---

## ⚙️ Configuration (`configs/model_config.yaml`)

All settings live in one YAML file — no need to edit scripts:

| Section | Key fields |
|---|---|
| `model` | variant, num_classes, dropout |
| `dataset` | root path, split dirs, image size |
| `training` | epochs, batch, lr, optimizer, scheduler, early stopping |
| `augmentation` | flips, rotation, colour jitter, normalisation |
| `export` | format (onnx/torchscript), opset, dynamic axes |

---

## 🚀 Quickstart

### 1. Validate your dataset
```bash
python scripts/dataset_validator.py
```

### 2. Train
```bash
python scripts/train_mobilenetv3.py
```
Best weights are saved to `weights/garbage_ai_mobilenetv3_best.pt`.

### 3. Run inference
```bash
python scripts/infer_mobilenetv3.py
```
Annotated images are saved to `runs/inference_samples/`.

### 4. Export
```bash
python scripts/export_mobilenetv3.py
```
Exports to `weights/garbage_ai_mobilenetv3_best.onnx` (and optionally `.torchscript`).

---

## 📦 Requirements

```
torch>=2.0
torchvision>=0.15
opencv-python
pyyaml
numpy
Pillow
```

---

## 🔍 Model Architecture

- **Backbone**: MobileNetV3-Large (ImageNet pretrained)
- **Classifier head**: `Dropout → Linear(960 → 1)` (binary classification)
- **Loss**: `BCEWithLogitsLoss`
- **Input**: 224 × 224 RGB

---

## 📊 Expected Dataset Layout

```
datasets/
└── images/
    ├── train/
    │   ├── trash/        ← images with garbage
    │   └── no_trash/     ← clean images (backgrounds)
    ├── val/
    │   ├── trash/
    │   └── no_trash/
    └── test/
        ├── trash/
        └── no_trash/
```

> **Tip**: If your dataset only has a single `trash` class (like v6), set `num_classes: 1` and place all images under a `trash/` sub-folder. The model will output a raw logit → sigmoid → probability of trash.
