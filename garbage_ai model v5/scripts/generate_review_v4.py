import os
import sys
import shutil
import hashlib
from pathlib import Path
import cv2
import numpy as np

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")
REVIEW_V4_DIR = BASE_DIR / "annotation_review_v4"

if REVIEW_V4_DIR.exists():
    shutil.rmtree(REVIEW_V4_DIR)

raw_dir = REVIEW_V4_DIR / "raw_19"
vis_dir = REVIEW_V4_DIR / "visualized_19"

raw_dir.mkdir(parents=True, exist_ok=True)
vis_dir.mkdir(parents=True, exist_ok=True)

sources_priority = [
    ("box_annotations", BASE_DIR / "box annotations", True),
    ("Trash_v2i", BASE_DIR / "Trash.v2i.yolov8", True),
    ("aiq_v2i", BASE_DIR / "aiq trash detection 1.v2i.yolov8", True),
    ("root_split", BASE_DIR, True),
    ("Clean_road", BASE_DIR / "Clean road", False)
]

master_entries = {}

for tag, src_path, expected_positive in sources_priority:
    if not src_path.exists():
        continue

    if tag == "root_split":
        imgs = []
        for sub_name in ["train", "valid", "test"]:
            sub_dir = BASE_DIR / sub_name
            if sub_dir.exists():
                imgs.extend([p for p in sub_dir.rglob("*.*") if p.suffix.lower() in [".jpg", ".png", ".jpeg"] and not p.name.startswith("._")])
    else:
        imgs = [p for p in src_path.rglob("*.*") if p.suffix.lower() in [".jpg", ".png", ".jpeg"] and not p.name.startswith("._")]

    for img_p in imgs:
        try:
            with open(img_p, 'rb') as f:
                h = hashlib.md5(f.read()).hexdigest()
        except Exception:
            continue

        lbl_p = None
        if "images" in img_p.parts:
            parts = list(img_p.parts)
            idx = parts.index("images")
            parts[idx] = "labels"
            cand = Path(*parts).with_suffix(".txt")
            if cand.exists() and not cand.name.startswith("._"):
                lbl_p = cand
        if lbl_p is None:
            cand = img_p.with_suffix(".txt")
            if cand.exists() and not cand.name.startswith("._"):
                lbl_p = cand
        if lbl_p is None:
            matches = list(img_p.parent.rglob(f"{img_p.stem}.txt"))
            matches = [m for m in matches if not m.name.startswith("._") and not m.name.lower().startswith("readme")]
            if matches:
                lbl_p = matches[0]

        bboxes = []
        if lbl_p and lbl_p.exists():
            with open(lbl_p, 'r', encoding='utf-8', errors='ignore') as lf:
                for line in lf:
                    parts = line.strip().split()
                    if len(parts) >= 5:
                        try:
                            cx, cy, w, h_box = map(float, parts[1:5])
                            cx = max(0.0, min(1.0, cx))
                            cy = max(0.0, min(1.0, cy))
                            w = max(0.0, min(1.0, w))
                            h_box = max(0.0, min(1.0, h_box))
                            bboxes.append((0, cx, cy, w, h_box))
                        except ValueError:
                            pass

        is_pos = len(bboxes) > 0
        total_area = sum(w * h_box for _, cx, cy, w, h_box in bboxes)

        entry = {
            "source": tag,
            "img_path": img_p,
            "lbl_path": lbl_p,
            "bboxes": bboxes,
            "is_positive": is_pos,
            "total_area": total_area
        }

        if h not in master_entries:
            master_entries[h] = entry

# Get positive images sorted by bbox area ascending, take top 19
positive_entries = [v for v in master_entries.values() if v["is_positive"]]
positive_entries.sort(key=lambda x: x["total_area"])
flagged_entries = positive_entries[:19]

print("==================================================")
print(f"GENERATING REVIEW FOLDER FOR EXACTLY {len(flagged_entries)} FLAGGED IMAGES")
print("==================================================")

report_rows = []

for idx, entry in enumerate(flagged_entries, start=1):
    img_p = entry["img_path"]
    lbl_p = entry["lbl_path"]
    src = entry["source"]
    num_boxes = len(entry["bboxes"])
    area_pct = round(entry["total_area"] * 100, 3)

    raw_name = f"{idx:02d}_{src}_{img_p.name}"
    raw_img_dest = raw_dir / raw_name
    shutil.copy2(img_p, raw_img_dest)

    if lbl_p and lbl_p.exists():
        shutil.copy2(lbl_p, raw_dir / f"{raw_img_dest.stem}.txt")

    # Render bounding box visualization
    cv_img = cv2.imread(str(img_p))
    if cv_img is not None:
        h_img, w_img, _ = cv_img.shape
        vis_img = cv_img.copy()

        for _, cx, cy, w, h_box in entry["bboxes"]:
            x1 = int((cx - w/2) * w_img)
            y1 = int((cy - h_box/2) * h_img)
            x2 = int((cx + w/2) * w_img)
            y2 = int((cy + h_box/2) * h_img)

            x1 = max(0, min(w_img - 1, x1))
            y1 = max(0, min(h_img - 1, y1))
            x2 = max(0, min(w_img - 1, x2))
            y2 = max(0, min(h_img - 1, y2))

            cv2.rectangle(vis_img, (x1, y1), (x2, y2), (0, 0, 255), 3)
            cv2.putText(vis_img, "trash", (x1, max(15, y1 - 5)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2, cv2.LINE_AA)

        cv2.putText(vis_img, f"Boxes: {num_boxes} | Coverage: {area_pct}%", (20, 40),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2, cv2.LINE_AA)

        vis_dest = vis_dir / f"vis_{raw_name}"
        cv2.imwrite(str(vis_dest), vis_img)

    report_rows.append({
        "id": idx,
        "filename": img_p.name,
        "source": src,
        "num_boxes": num_boxes,
        "area_pct": area_pct
    })

print(f"Saved raw images + labels to: {raw_dir}")
print(f"Saved visual renders to:     {vis_dir}\n")
