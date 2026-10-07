import argparse
import sys
from pathlib import Path
import cv2
import numpy as np
from PIL import Image
from ultralytics import YOLO

def main():
    parser = argparse.ArgumentParser(description="Street AIQ — Clean Style YOLOv8 Trash Detection Inference")
    parser.add_argument("--image", type=str, required=True, help="Path to input road image")
    parser.add_argument("--weights", type=str, default=r"E:\nitin\model2\models\trash_detector\best.pt", help="Path to trained YOLOv8 model weights")
    parser.add_argument("--conf", type=float, default=0.25, help="Confidence threshold (default: 0.25)")
    parser.add_argument("--output", type=str, default=None, help="Path to save annotated image (default: <input_stem>_annotated<ext>)")

    args = parser.parse_args()

    img_path = Path(args.image)
    if not img_path.exists():
        print(f"Error: Image path '{args.image}' does not exist.", file=sys.stderr)
        sys.exit(1)

    weights_path = Path(args.weights)
    if not weights_path.exists():
        fallback = Path(r"E:\nitin\model2\models\yolov8_street_aiq.pt")
        if fallback.exists():
            weights_path = fallback
        else:
            print(f"Error: Model weights file '{args.weights}' does not exist.", file=sys.stderr)
            sys.exit(1)

    model = YOLO(str(weights_path))

    # Read image
    img_bgr = cv2.imread(str(img_path))
    if img_bgr is None:
        print(f"Error: Could not read image from '{args.image}'", file=sys.stderr)
        sys.exit(1)

    # Run inference
    results = model(img_path, conf=args.conf, verbose=False)[0]
    boxes = results.boxes

    num_detections = len(boxes)

    print("==================================================")
    print("STREET AIQ TRASH DETECTION REPORT")
    print("==================================================")

    if num_detections > 0:
        print("Trash detected: YES\n")
        print(f"Number of detections: {num_detections}\n")

        annotated_bgr = img_bgr.copy()

        for idx, box in enumerate(boxes, start=1):
            x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
            conf = float(box.conf[0].item())
            cls_id = int(box.cls[0].item())
            cls_name = model.names.get(cls_id, "trash")

            print(f"Detection {idx}:")
            print(f"  Class: {cls_name}")
            print(f"  Confidence: {conf:.2f}")
            print(f"  Bounding box: [{x1}, {y1}, {x2}, {y2}]\n")

            # Draw ONLY a thin 2-pixel red bounding box around detected trash. ZERO text, ZERO labels, ZERO percentages.
            cv2.rectangle(annotated_bgr, (x1, y1), (x2, y2), (0, 0, 255), 2)

        if args.output:
            out_path = Path(args.output)
        else:
            out_path = img_path.parent / f"{img_path.stem}_annotated{img_path.suffix}"

        cv2.imwrite(str(out_path), annotated_bgr)
        print(f"Annotated clean copy saved to: {out_path}")

    else:
        print("Trash detected: NO\n")
        print("Number of detections: 0")
        print("\nNo trash bounding box created (Clean Road).")

if __name__ == "__main__":
    main()
