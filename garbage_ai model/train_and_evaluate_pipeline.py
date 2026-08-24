import os
import json
import time
from ultralytics import YOLO
import train_detector
import generate_final_report
import inference

def run_pipeline():
    print("=" * 80)
    print("STARTING COMPLETE ROAD CLEANLINESS MODEL RETRAINING & OPTIMIZATION PIPELINE")
    print("=" * 80)

    start_time = time.time()

    # Step 1: Run 50-Epoch Initial Retraining
    print("\n--- STEP 1: Executing 50-Epoch Target Training Pass ---")
    train_detector.train_garbage_detector(epochs=50)

    # Step 2: Check Validation Metrics
    metrics_json_path = "garbage_ai model/outputs/epoch_metrics.json"
    if os.path.exists(metrics_json_path):
        with open(metrics_json_path, "r", encoding="utf-8") as f:
            history = json.load(f)

        if history:
            best_ep = max(history, key=lambda x: x.get("mAP50", 0.0))
            p = best_ep.get("precision", 0.0)
            r = best_ep.get("recall", 0.0)
            map50 = best_ep.get("mAP50", 0.0)
            map50_95 = best_ep.get("mAP50-95", 0.0)

            print(f"\nTarget Validation Performance Check (Best Epoch {best_ep['epoch']}):")
            print(f"  - Precision: {p*100:.2f}% (Target ≥ 80.0%) -> {'✅ MET' if p >= 0.80 else '❌ NOT MET'}")
            print(f"  - Recall: {r*100:.2f}% (Target ≥ 80.0%) -> {'✅ MET' if r >= 0.80 else '❌ NOT MET'}")
            print(f"  - mAP@50: {map50*100:.2f}% (Target ≥ 80.0%) -> {'✅ MET' if map50 >= 0.80 else '❌ NOT MET'}")
            print(f"  - mAP@50-95: {map50_95*100:.2f}% (Target ≥ 80.0%) -> {'✅ MET' if map50_95 >= 0.80 else '❌ NOT MET'}")

            # Step 3: Trigger Fine-Tuning Pass if target metrics not fully met
            if p < 0.80 or r < 0.80 or map50 < 0.80 or map50_95 < 0.80:
                print("\n--- STEP 2: Target metrics not fully met. Triggering 15-epoch fine-tuning pass ---")
                train_detector.train_garbage_detector(epochs=15)

    # Step 4: Generate All Metric Graphs & Reports
    print("\n--- STEP 3: Generating Final Visualizations & Reports ---")
    generate_final_report.generate_final_report()

    # Step 5: Verification of Drop-In Inference Compatibility
    print("\n--- STEP 4: Verifying Drop-In Inference Pipeline Compatibility ---")
    try:
        classifier, detector, clip_model, clip_processor, device = inference.load_pipeline()
        print("✅ Pipeline loaded successfully with newly updated detector weights!")
    except Exception as e:
        print(f"Error validating inference pipeline: {e}")

    total_dur = time.time() - start_time
    print(f"\n========================================================================")
    print(f"🎉 PIPELINE COMPLETED SUCCESSFULLY IN {time.strftime('%H:%M:%S', time.gmtime(total_dur))}")
    print(f"Updated Model Weights: garbage_ai model/weights/garbage_detector.pt")
    print(f"Outputs & Reports: garbage_ai model/outputs/")
    print(f"========================================================================\n")

if __name__ == "__main__":
    run_pipeline()
