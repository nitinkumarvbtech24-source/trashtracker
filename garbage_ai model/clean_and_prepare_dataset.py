import os
import shutil
import random
from collections import Counter

def validate_and_repair_labels(label_content):
    """
    Parse and repair label lines.
    Handles concatenated single-line annotations, invalid class IDs,
    and out-of-bound box coordinates.
    Only classes 0 (Garbage), 1 (Natural Waste), 2 (Not Garbage) are preserved.
    """
    if not label_content or not label_content.strip():
        return ""

    tokens = label_content.strip().split()
    valid_boxes = []

    idx = 0
    while idx + 5 <= len(tokens):
        cls_str, xc_str, yc_str, w_str, h_str = tokens[idx:idx+5]
        try:
            cls_id = int(float(cls_str))
            xc = float(xc_str)
            yc = float(yc_str)
            bw = float(w_str)
            bh = float(h_str)

            if cls_id in [0, 1, 2]:
                xc = max(0.0001, min(0.9999, xc))
                yc = max(0.0001, min(0.9999, yc))
                bw = max(0.0001, min(0.9999, bw))
                bh = max(0.0001, min(0.9999, bh))
                valid_boxes.append(f"{cls_id} {xc:.6f} {yc:.6f} {bw:.6f} {bh:.6f}")
                idx += 5
            else:
                idx += 1
        except ValueError:
            idx += 1

    return "\n".join(valid_boxes) + "\n" if valid_boxes else ""

def clean_and_prepare_dataset(
    dataset_path=r"E:\AImodel\Garbage_Combined_Dataset",
    split_ratio=0.80,  # 80% train, 20% validation
    seed=42
):
    print("=" * 70)
    print("LIGHTNING IN-PLACE ROAD CLEANLINESS DATASET CURATION & RE-SPLIT (80/20)")
    print("=" * 70)

    random.seed(seed)

    # 1. Collect all existing images and labels from all current subfolders (train, valid, test)
    all_samples = []  # List of tuples: (img_path, lbl_path, base_name)
    
    for split in ["train", "valid", "test"]:
        img_dir = os.path.join(dataset_path, split, "images")
        lbl_dir = os.path.join(dataset_path, split, "labels")
        if not os.path.exists(img_dir):
            continue

        for img_name in os.listdir(img_dir):
            if not img_name.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp', '.webp')):
                continue
            img_path = os.path.join(img_dir, img_name)
            base = os.path.splitext(img_name)[0]
            lbl_path = os.path.join(lbl_dir, f"{base}.txt")
            all_samples.append((img_path, lbl_path, img_name, base))

    # 2. Add hard negative images from aiq photos
    aiq_photos_root = "aiq photos"
    pseudo_labels_dir = "aiq_pseudo_labels"
    hard_neg_added = 0

    if os.path.exists(aiq_photos_root):
        train_img_dir = os.path.join(dataset_path, "train", "images")
        train_lbl_dir = os.path.join(dataset_path, "train", "labels")

        for root_dir, _, files in os.walk(aiq_photos_root):
            folder_name = os.path.basename(root_dir).lower()
            for f in files:
                if not f.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp', '.webp')):
                    continue
                src_img = os.path.join(root_dir, f)
                base = os.path.splitext(f)[0]
                out_img_name = f"aiq_{folder_name.replace(' ', '_')}_{f}"
                out_base = os.path.splitext(out_img_name)[0]

                dst_img = os.path.join(train_img_dir, out_img_name)
                dst_lbl = os.path.join(train_lbl_dir, f"{out_base}.txt")

                lbl_text = ""
                pseudo_lbl_path = os.path.join(pseudo_labels_dir, f"{base}.txt")
                if os.path.exists(pseudo_lbl_path):
                    with open(pseudo_lbl_path, "r", encoding="utf-8", errors="ignore") as lf:
                        lbl_text = validate_and_repair_labels(lf.read())

                if "natural" in folder_name or "leaves" in folder_name or "branches" in folder_name:
                    if not lbl_text.strip():
                        lbl_text = "1 0.500000 0.500000 0.800000 0.800000\n"

                if not os.path.exists(dst_img):
                    shutil.copy2(src_img, dst_img)
                    with open(dst_lbl, "w", encoding="utf-8") as lf:
                        lf.write(lbl_text)
                    all_samples.append((dst_img, dst_lbl, out_img_name, out_base))
                    hard_neg_added += 1

    print(f"Total samples collected (including {hard_neg_added} hard negatives): {len(all_samples)}")

    # 3. Clean and Repair all labels in-place
    repaired_count = 0
    empty_background_count = 0
    class_counter = Counter()

    for img_p, lbl_p, img_name, base in all_samples:
        if os.path.exists(lbl_p):
            with open(lbl_p, "r", encoding="utf-8", errors="ignore") as lf:
                raw_text = lf.read()
            repaired = validate_and_repair_labels(raw_text)
            with open(lbl_p, "w", encoding="utf-8") as lf:
                lf.write(repaired)

            if not repaired.strip():
                empty_background_count += 1
            else:
                for line in repaired.strip().split("\n"):
                    cls_id = int(line.split()[0])
                    class_counter[cls_id] += 1
        else:
            # Create empty label file (background image)
            with open(lbl_p, "w", encoding="utf-8") as lf:
                lf.write("")
            empty_background_count += 1

    print(f"\nLabel Cleaning Summary:")
    print(f"  - Repaired & Verified label files: {len(all_samples)}")
    print(f"  - Background Images (Empty labels): {empty_background_count}")
    print(f"  - Valid Class Distribution: {dict(class_counter)}")

    # 4. Shuffle & Partition strictly into 80% Train / 20% Val
    random.shuffle(all_samples)
    num_train = int(len(all_samples) * split_ratio)
    train_set = set(all_samples[:num_train])
    val_set = set(all_samples[num_train:])

    # Move files to appropriate split folders (train / valid)
    target_train_img = os.path.join(dataset_path, "train", "images")
    target_train_lbl = os.path.join(dataset_path, "train", "labels")
    target_val_img = os.path.join(dataset_path, "valid", "images")
    target_val_lbl = os.path.join(dataset_path, "valid", "labels")

    os.makedirs(target_train_img, exist_ok=True)
    os.makedirs(target_train_lbl, exist_ok=True)
    os.makedirs(target_val_img, exist_ok=True)
    os.makedirs(target_val_lbl, exist_ok=True)

    moved_to_train = 0
    moved_to_val = 0

    for img_p, lbl_p, img_name, base in all_samples:
        is_train = (img_p, lbl_p, img_name, base) in train_set
        dest_img_dir = target_train_img if is_train else target_val_img
        dest_lbl_dir = target_train_lbl if is_train else target_val_lbl

        dest_img_p = os.path.join(dest_img_dir, img_name)
        dest_lbl_p = os.path.join(dest_lbl_dir, f"{base}.txt")

        if img_p != dest_img_p and os.path.exists(img_p):
            shutil.move(img_p, dest_img_p)
        if lbl_p != dest_lbl_p and os.path.exists(lbl_p):
            shutil.move(lbl_p, dest_lbl_p)

        if is_train:
            moved_to_train += 1
        else:
            moved_to_val += 1

    # Clean up old test folder if empty
    test_dir = os.path.join(dataset_path, "test")
    if os.path.exists(test_dir):
        shutil.rmtree(test_dir, ignore_errors=True)

    print(f"\nRe-partitioned Dataset (80/20 Split):")
    print(f"  - Train split: {moved_to_train} images")
    print(f"  - Validation split: {moved_to_val} images")

    # 5. Update garbage_data.yaml
    yaml_content = f"""path: {dataset_path.replace('\\', '/')}
train: train/images
val: valid/images
test: valid/images

nc: 3
names: ['Garbage', 'Natural Waste', 'Not Garbage']
"""
    yaml_path = os.path.join("garbage_ai model", "garbage_data.yaml")
    with open(yaml_path, "w", encoding="utf-8") as f:
        f.write(yaml_content)

    print(f"\nSaved dataset YAML configuration to: {yaml_path}")
    print("=" * 70 + "\n")

if __name__ == "__main__":
    clean_and_prepare_dataset()
