import os
import time
import json
import shutil
import torch
import numpy as np
from ultralytics import YOLO

class EpochReporterCallback:
    """
    Custom Ultralytics YOLO callback to track, format, and report complete
    per-epoch metrics after every epoch in a clear markdown table.
    """
    def __init__(self, total_epochs=50, metrics_log_path="garbage_ai model/outputs/epoch_metrics.json"):
        self.total_epochs = total_epochs
        self.metrics_log_path = metrics_log_path
        self.history = []
        self.epoch_start_time = None
        self.fit_start_time = None
        self.best_map50 = 0.0
        self.best_metrics = {}

        os.makedirs(os.path.dirname(self.metrics_log_path), exist_ok=True)

    def on_train_start(self, trainer):
        self.fit_start_time = time.time()
        self.epoch_start_time = time.time()
        print("\n" + "=" * 110)
        print(f"STARTING ROAD CLEANLINESS DETECTOR TRAINING ({self.total_epochs} EPOCHS)")
        print("Target Validation Metrics: Precision ≥ 80%, Recall ≥ 80%, mAP@50 ≥ 80%, mAP@50-95 ≥ 80%")
        print("=" * 110 + "\n")

    def on_train_epoch_start(self, trainer):
        self.epoch_start_time = time.time()

    def on_fit_epoch_end(self, trainer):
        epoch_idx = trainer.epoch + 1
        epoch_dur = time.time() - self.epoch_start_time
        elapsed_total = time.time() - self.fit_start_time
        avg_epoch_dur = elapsed_total / epoch_idx
        rem_epochs = self.total_epochs - epoch_idx
        eta_seconds = max(0, rem_epochs * avg_epoch_dur)
        eta_str = time.strftime("%H:%M:%S", time.gmtime(eta_seconds))

        # Extract losses
        train_loss = float(getattr(trainer, 'loss', 0) if not isinstance(getattr(trainer, 'loss', 0), torch.Tensor) else trainer.loss.item())
        if hasattr(trainer, 'loss_items') and trainer.loss_items is not None:
            try:
                train_loss = float(sum(trainer.loss_items))
            except Exception:
                pass

        # Extract validation metrics
        metrics = getattr(trainer, 'metrics', {})
        map50 = float(metrics.get("metrics/mAP50(B)", 0.0))
        map50_95 = float(metrics.get("metrics/mAP50-95(B)", 0.0))
        precision = float(metrics.get("metrics/precision(B)", 0.0))
        recall = float(metrics.get("metrics/recall(B)", 0.0))

        # Calculate F1 score
        if precision + recall > 1e-6:
            f1_score = 2 * (precision * recall) / (precision + recall)
        else:
            f1_score = 0.0

        # Extract learning rate
        lr = 0.0
        if hasattr(trainer, 'optimizer') and trainer.optimizer is not None:
            try:
                lr = trainer.optimizer.param_groups[0]['lr']
            except Exception:
                pass

        # Val loss
        val_loss = 0.0
        if hasattr(trainer, 'val_loss') and trainer.val_loss is not None:
            try:
                val_loss = float(sum(trainer.val_loss))
            except Exception:
                pass
        elif hasattr(trainer, 'validator') and hasattr(trainer.validator, 'loss') and trainer.validator.loss is not None:
            try:
                val_loss = float(sum(trainer.validator.loss))
            except Exception:
                pass

        # Trend analysis
        if map50 > self.best_map50 + 0.002:
            trend = "🟢 Improving"
            self.best_map50 = map50
            self.best_metrics = {
                "epoch": epoch_idx,
                "precision": precision,
                "recall": recall,
                "mAP50": map50,
                "mAP50-95": map50_95,
                "f1": f1_score
            }
        elif abs(map50 - self.best_map50) <= 0.002:
            trend = "🟡 Plateauing"
        else:
            trend = "🔴 Degrading"

        record = {
            "epoch": epoch_idx,
            "train_loss": train_loss,
            "val_loss": val_loss,
            "precision": precision,
            "recall": recall,
            "mAP50": map50,
            "mAP50-95": map50_95,
            "f1_score": f1_score,
            "learning_rate": lr,
            "epoch_time_sec": epoch_dur,
            "eta_str": eta_str,
            "best_mAP50_so_far": self.best_map50,
            "trend": trend
        }
        self.history.append(record)

        # Save history log to disk
        try:
            with open(self.metrics_log_path, "w", encoding="utf-8") as f:
                json.dump(self.history, f, indent=2)
        except Exception as e:
            print(f"Warning: Failed to log epoch metrics: {e}")

        # Print EPOCH REPORT TABLE
        print("\n" + f"📊 --- EPOCH {epoch_idx}/{self.total_epochs} REPORT ---")
        print(f"| Metric | Value | Best So Far (Epoch {self.best_metrics.get('epoch', 1)}) | Target Met (≥80%) |")
        print(f"|---|---|---|---|")
        print(f"| **Training Loss** | {train_loss:.4f} | - | - |")
        print(f"| **Validation Loss** | {val_loss:.4f} | - | - |")
        print(f"| **Precision** | {precision:.4f} ({precision*100:.1f}%) | {self.best_metrics.get('precision', 0):.4f} | {'✅ YES' if precision >= 0.80 else '❌ NO'} |")
        print(f"| **Recall** | {recall:.4f} ({recall*100:.1f}%) | {self.best_metrics.get('recall', 0):.4f} | {'✅ YES' if recall >= 0.80 else '❌ NO'} |")
        print(f"| **mAP@50** | {map50:.4f} ({map50*100:.1f}%) | {self.best_metrics.get('mAP50', 0):.4f} | {'✅ YES' if map50 >= 0.80 else '❌ NO'} |")
        print(f"| **mAP@50-95** | {map50_95:.4f} ({map50_95*100:.1f}%) | {self.best_metrics.get('mAP50-95', 0):.4f} | {'✅ YES' if map50_95 >= 0.80 else '❌ NO'} |")
        print(f"| **F1 Score** | {f1_score:.4f} ({f1_score*100:.1f}%) | {self.best_metrics.get('f1', 0):.4f} | {'✅ YES' if f1_score >= 0.80 else '❌ NO'} |")
        print(f"| **Learning Rate** | {lr:.6f} | - | - |")
        print(f"| **Epoch Time** | {epoch_dur:.2f}s | - | - |")
        print(f"| **ETA Remaining** | {eta_str} | - | - |")
        print(f"| **Performance Trend** | **{trend}** | Best mAP@50: **{self.best_map50*100:.1f}%** | - |")
        print("-" * 110 + "\n")

def train_garbage_detector(epochs=50):
    yaml_config = "garbage_ai model/garbage_data.yaml"
    if not os.path.exists(yaml_config):
        yaml_config = "garbage_data.yaml"

    if not os.path.exists(yaml_config):
        raise FileNotFoundError(f"Configuration file {yaml_config} does not exist.")

    starting_weights = "garbage_ai model/weights/garbage_detector.pt"
    if not os.path.exists(starting_weights):
        starting_weights = "outputs_new/garbage_detector/weights/best.pt"
    if not os.path.exists(starting_weights):
        starting_weights = "yolov8m.pt"

    print(f"Initializing YOLO model starting weights from: {starting_weights}")
    model = YOLO(starting_weights)

    # Attach custom epoch reporter callback
    reporter = EpochReporterCallback(total_epochs=epochs)
    model.add_callback("on_train_start", reporter.on_train_start)
    model.add_callback("on_train_epoch_start", reporter.on_train_epoch_start)
    model.add_callback("on_fit_epoch_end", reporter.on_fit_epoch_end)

    print("Starting target training of Road Cleanliness Detector (80/20 Train/Val split)...")

    train_args = dict(
        data=yaml_config,
        epochs=epochs,
        imgsz=640,
        batch=16,
        device=0 if torch.cuda.is_available() else "cpu",
        workers=4 if torch.cuda.is_available() else 0,
        project="outputs_new",
        name="garbage_detector",
        exist_ok=True,
        save=True,
        plots=True,
        cos_lr=True,
        patience=20,
        mosaic=0.2,
        mixup=0.0,
        copy_paste=0.0,
        cls=1.2,
        lr0=0.003,
        amp=True
    )

    results = model.train(**train_args)
    print("\nGarbage detector training completed successfully!")

    best_pt = os.path.join(results.save_dir, "weights", "best.pt")
    dst_pt = "garbage_ai model/weights/garbage_detector.pt"
    if os.path.exists(best_pt):
        os.makedirs(os.path.dirname(dst_pt), exist_ok=True)
        shutil.copy2(best_pt, dst_pt)
        print(f"🎯 Successfully updated best detector weights to drop-in location: {dst_pt}")

    return results

if __name__ == "__main__":
    train_garbage_detector(epochs=50)
