import os
import sys
import time

# Ensure garbage_ai model module import path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from pseudo_label import run_pseudo_labeling
from train_gan import train_gan_for_class
from generate_and_filter import generate_and_filter_synthetic_data
from prepare_combined_dataset import prepare_combined_dataset
from train_combined_model import train_combined_model
from evaluate_combined import evaluate_models

def main():
    print("=" * 70)
    print("      ROAD TRASH TRACKER - FULL ENHANCEMENT PIPELINE")
    print("=" * 70)
    start_time = time.time()

    # Step 1: Pseudo-labeling new AIQ photos
    print("\n>>> STEP 1: Generating Pseudo-Labels for AIQ Photos...")
    run_pseudo_labeling(
        aiq_root="aiq photos",
        weights_path="garbage_ai model/weights/garbage_detector.pt",
        output_dir="aiq_pseudo_labels"
    )

    # Step 2: GAN Training on Garbage class
    print("\n>>> STEP 2: Training FastGAN Generator...")
    # Prepare single folder for FastGAN training on garbage photos
    gan_train_dir = "aiq photos/road cleanliness"
    output_root = "outputs_new/gan"
    
    # Train FastGAN on 'garbage' class (355 images)
    train_gan_for_class(
        class_name="garbage",
        train_dir=gan_train_dir,
        output_root=output_root,
        epochs=30,
        batch_size=16,
        sample_interval=5
    )

    # Step 3: Generate and Filter Synthetic Images
    print("\n>>> STEP 3: Generating and Filtering Synthetic Images...")
    gan_weights = os.path.join(output_root, "checkpoints", "garbage", "generator_final.pt")
    filtered_syn_dir = os.path.join(output_root, "filtered_synthetic")
    generate_and_filter_synthetic_data(
        weights_path=gan_weights,
        output_dir=filtered_syn_dir,
        num_samples=50,
        variance_thresh=0.08,
        phash_distance_thresh=5
    )

    # Step 4: Prepare Combined Dataset (90% Train / 10% Validation Split)
    print("\n>>> STEP 4: Preparing Combined Dataset with 90/10 Split...")
    prepare_combined_dataset(
        original_dataset_path=r"E:\AImodel\Garbage.v36-garbage-11-05-2026.yolov8",
        aiq_photos_path="aiq photos",
        pseudo_labels_dir="aiq_pseudo_labels",
        synthetic_dir=filtered_syn_dir,
        output_dataset_path=r"E:\AImodel\Garbage_Combined_Dataset",
        split_ratio=0.90
    )

    # Step 5: Unified Model Fine-Tuning
    print("\n>>> STEP 5: Fine-Tuning Unified YOLO Model...")
    train_combined_model(
        data_yaml="garbage_ai model/combined_data.yaml",
        weights_path="garbage_ai model/weights/garbage_detector.pt",
        output_dir="outputs_new/combined_model",
        epochs=25,
        batch_size=16,
        img_size=640
    )

    # Step 6: Evaluation & Reporting
    print("\n>>> STEP 6: Running Final Evaluation on Test Set...")
    evaluate_models(
        original_weights="garbage_ai model/weights/garbage_detector.pt",
        combined_weights="garbage_ai model/weights/combined_model.pt",
        data_yaml="garbage_ai model/combined_data.yaml"
    )

    elapsed = time.time() - start_time
    print("=" * 70)
    print(f"      PIPELINE EXECUTED SUCCESSFULLY IN {elapsed/60:.2f} MINUTES")
    print("=" * 70)

if __name__ == "__main__":
    main()
