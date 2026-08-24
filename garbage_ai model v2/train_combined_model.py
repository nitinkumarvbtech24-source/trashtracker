import os
import torch
from ultralytics import YOLO

def train_combined_model(
    data_yaml="garbage_ai model/combined_data.yaml",
    weights_path="garbage_ai model/weights/garbage_detector.pt",
    output_dir="outputs_new/combined_model",
    epochs=25,
    batch_size=16,
    img_size=640
):
    print("=" * 60)
    print("Starting Combined YOLO Model Fine-Tuning...")
    print("=" * 60)

    device = "0" if torch.cuda.is_available() else "cpu"
    print(f"Training using device: {device} ({torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'})")

    if os.path.exists(weights_path):
        print(f"Loading pre-trained weights from: {weights_path}")
        model = YOLO(weights_path)
    else:
        print("Pre-trained weights not found. Initializing YOLOv8n base model.")
        model = YOLO("yolov8n.pt")

    # Train model
    results = model.train(
        data=data_yaml,
        epochs=epochs,
        batch=batch_size,
        imgsz=img_size,
        device=device,
        project=os.path.dirname(output_dir),
        name=os.path.basename(output_dir),
        exist_ok=True,
        workers=2
    )

    # Save final fine-tuned model copy to weights directory
    target_weights_dir = "garbage_ai model/weights"
    os.makedirs(target_weights_dir, exist_ok=True)
    best_weights_src = os.path.join(output_dir, "weights", "best.pt")
    combined_weights_dst = os.path.join(target_weights_dir, "combined_model.pt")
    
    if os.path.exists(best_weights_src):
        import shutil
        shutil.copy2(best_weights_src, combined_weights_dst)
        print(f"Saved fine-tuned best model to {combined_weights_dst}")

    print("\nTraining completed successfully!")
    return results

if __name__ == "__main__":
    train_combined_model()
