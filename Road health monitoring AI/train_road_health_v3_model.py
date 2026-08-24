import os
import time
import json
import shutil
from datetime import datetime
import torch
import numpy as np
from ultralytics import YOLO

# Enable maximum CPU parallelism
if hasattr(os, 'cpu_count') and os.cpu_count():
    torch.set_num_threads(os.cpu_count())

class RoadHealthV3EpochCallback:
    """
    Ultralytics YOLO callback to track, format, and report per-epoch metrics
    for the 10-class Road Health AI model.
    """
    def __init__(self, total_epochs=35, log_path=None):
        self.total_epochs = total_epochs
        if log_path is None:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            log_path = os.path.join(script_dir, "road_health_v3_epoch_metrics.json")
        self.log_path = log_path
        self.history = []
        self.epoch_start_time = None
        self.fit_start_time = None
        self.best_map50 = 0.0
        self.best_metrics = {}

        os.makedirs(os.path.dirname(self.log_path), exist_ok=True)

    def on_train_start(self, trainer):
        self.fit_start_time = time.time()
        self.epoch_start_time = time.time()
        print("\n" + "=" * 110)
        print(f"STARTING ROAD HEALTH V3 AI MODEL TRAINING ({self.total_epochs} EPOCHS)")
        print("Target Metrics: Precision > 85%, Recall > 85%")
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
        
        elapsed_hrs = elapsed_total / 3600.0
        eta_str = time.strftime("%H:%M:%S", time.gmtime(eta_seconds))

        metrics = getattr(trainer, 'metrics', {})
        map50 = float(metrics.get("metrics/mAP50(B)", 0.0))
        map50_95 = float(metrics.get("metrics/mAP50-95(B)", 0.0))
        precision = float(metrics.get("metrics/precision(B)", 0.0))
        recall = float(metrics.get("metrics/recall(B)", 0.0))

        f1_score = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 1e-6 else 0.0

        lr = 0.0
        if hasattr(trainer, 'optimizer') and trainer.optimizer is not None:
            try:
                lr = trainer.optimizer.param_groups[0]['lr']
            except Exception:
                pass

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
            trend = "🔴 Fluctuating"

        epoch_record = {
            "epoch": epoch_idx,
            "precision": precision,
            "recall": recall,
            "mAP50": map50,
            "mAP50-95": map50_95,
            "f1_score": f1_score,
            "learning_rate": lr,
            "epoch_duration_sec": epoch_dur,
            "elapsed_total_sec": elapsed_total,
            "elapsed_total_hrs": elapsed_hrs
        }
        self.history.append(epoch_record)

        try:
            with open(self.log_path, "w", encoding="utf-8") as f:
                json.dump(self.history, f, indent=2)
        except Exception as e:
            print(f"Warning: Could not save epoch metrics: {e}")

        print("\n" + f"📊 --- EPOCH {epoch_idx}/{self.total_epochs} REPORT ---")
        print(f"| Metric | Value | Best So Far (Epoch {self.best_metrics.get('epoch', 1)}) | Target Met (>85%) |")
        print(f"|---|---|---|---|")
        print(f"| **Precision** | {precision:.4f} ({precision*100:.1f}%) | {self.best_metrics.get('precision', 0):.4f} | {'✅ YES' if precision > 0.85 else '❌ NO'} |")
        print(f"| **Recall** | {recall:.4f} ({recall*100:.1f}%) | {self.best_metrics.get('recall', 0):.4f} | {'✅ YES' if recall > 0.85 else '❌ NO'} |")
        print(f"| **mAP@50** | {map50:.4f} ({map50*100:.2f}%) | {self.best_metrics.get('mAP50', 0):.4f} | {'✅ YES' if map50 > 0.85 else '❌ NO'} |")
        print(f"| **F1 Score** | {f1_score:.4f} ({f1_score*100:.2f}%) | {self.best_metrics.get('f1', 0):.4f} | {'✅ YES' if f1_score > 0.85 else '❌ NO'} |")
        print(f"| **Elapsed Time** | {elapsed_hrs:.2f} hours ({elapsed_total:.1f}s) | - | - |")
        print(f"| **ETA Remaining** | {eta_str} | - | - |")
        print(f"| **Trend** | **{trend}** | Best mAP@50: **{self.best_map50*100:.1f}%** | - |")
        print("-" * 110 + "\n")

def train_road_health_v3_model(epochs=35, batch_size=16, imgsz=416):
    os.environ["OMP_NUM_THREADS"] = "8"
    os.environ["MKL_NUM_THREADS"] = "8"
    os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"
    torch.set_num_threads(8)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_root = os.path.abspath(os.path.join(script_dir, "..", ".."))

    yaml_path = os.path.join(script_dir, "dataset_road_health_v3", "road_health_v3.yaml")
    if not os.path.exists(yaml_path):
        raise FileNotFoundError(f"Dataset YAML config {yaml_path} does not exist!")

    starting_weights = "yolov8n.pt"
    existing_weights = os.path.join(script_dir, "pothole_detector", "road_health_v2_model.pt")
    if os.path.exists(existing_weights):
        starting_weights = existing_weights

    print(f"Initializing 10-class Road Health V3 model training from weights: {starting_weights}")
    model = YOLO(starting_weights)

    callback = RoadHealthV3EpochCallback(total_epochs=epochs)
    model.add_callback("on_train_start", callback.on_train_start)
    model.add_callback("on_train_epoch_start", callback.on_train_epoch_start)
    model.add_callback("on_fit_epoch_end", callback.on_fit_epoch_end)

    start_iso = datetime.now().isoformat()
    start_time_sec = time.time()
    print(f"⏰ Model Training Start Timestamp: {start_iso}")

    runs_project = os.path.join(workspace_root, "runs", "detect")

    train_args = dict(
        data=yaml_path,
        epochs=epochs,
        imgsz=imgsz,
        batch=batch_size,
        device="cpu",
        workers=8,
        cache="ram",
        project=runs_project,
        name="road_health_v3_model",
        exist_ok=True,
        save=True,
        plots=True,
        cos_lr=True,
        patience=50,
        cls=4.0,
        box=9.5,
        dfl=2.5,
        scale=0.7,
        mosaic=0.5,
        mixup=0.1,
        lr0=0.003,
        lrf=0.01,
        amp=False
    )

    results = model.train(**train_args)

    end_time_sec = time.time()
    end_iso = datetime.now().isoformat()
    duration_sec = end_time_sec - start_time_sec
    duration_hrs = duration_sec / 3600.0

    print("\n" + "=" * 80)
    print("ROAD HEALTH V3 MODEL TRAINING FINISHED SUCCESSFULLY")
    print(f"Start Timestamp:    {start_iso}")
    print(f"End Timestamp:      {end_iso}")
    print(f"Total Duration:     {duration_hrs:.3f} hours ({duration_sec:.1f} seconds)")
    print("=" * 80 + "\n")

    # Save duration report
    duration_report = {
        "start_timestamp": start_iso,
        "end_timestamp": end_iso,
        "total_duration_seconds": round(duration_sec, 2),
        "total_duration_hours": round(duration_hrs, 4),
        "epochs_completed": epochs,
        "batch_size": batch_size,
        "image_size": imgsz,
        "model_architecture": "YOLOv8n"
    }

    report_path = os.path.join(script_dir, "road_health_v3_duration_report.json")
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(duration_report, f, indent=2)

    # Save best weights to drop-in location
    save_dir = getattr(results, 'save_dir', os.path.join(runs_project, "road_health_v3_model"))
    best_pt = os.path.join(save_dir, "weights", "best.pt")
    target_weights_path = os.path.join(script_dir, "pothole_detector", "road_health_v3_model.pt")
    os.makedirs(os.path.dirname(target_weights_path), exist_ok=True)
    if os.path.exists(best_pt):
        shutil.copy2(best_pt, target_weights_path)
        print(f"🎯 Saved best model weights to drop-in location: {target_weights_path}")

    return results

if __name__ == "__main__":
    train_road_health_v3_model(epochs=35)
