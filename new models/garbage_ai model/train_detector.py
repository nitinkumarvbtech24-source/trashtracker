import os
from ultralytics import YOLO

def train_garbage_detector():
    yaml_config = "C:/Users/yashw/.gemini/antigravity/scratch/trash_detection/garbage_data.yaml"
    
    if not os.path.exists(yaml_config):
        raise FileNotFoundError(f"Configuration file {yaml_config} does not exist. Run prepare_data.py first.")
        
    print("Loading pre-trained YOLOv8-nano detection model...")
    # Using yolov8n.pt (nano detector)
    model = YOLO("yolov8n.pt")
    
    print("Starting training of garbage detector...")
    # Train the model on the GPU
    results = model.train(
        data=yaml_config,
        epochs=15,          # 15 epochs is highly effective for transfer learning on binary detection
        imgsz=640,          # standard YOLO object detection size
        batch=32,           # batch size of 32 fits comfortably in 8GB VRAM for yolov8n
        device=0,           # use GPU (GeForce RTX 4060)
        workers=4,          # multi-threaded data loading
        project="road_trash_project",
        name="garbage_detector",
        plots=True
    )
    print("Garbage detector training completed successfully!")
    print(f"Results saved in: {results.save_dir}")

if __name__ == "__main__":
    train_garbage_detector()
