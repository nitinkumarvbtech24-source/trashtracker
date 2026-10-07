import os
import sys
from pathlib import Path
import cv2
import numpy as np

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")
REVIEW_DIR = BASE_DIR / "annotation_review"

print("==================================================")
print("RENDERING ANNOTATION VISUALIZATIONS FOR MANUAL REVIEW")
print("==================================================")

for sub in ["partial_annotations", "valid_annotated", "genuinely_clean"]:
    folder = REVIEW_DIR / sub
    if not folder.exists():
        continue
    
    vis_dir = REVIEW_DIR / f"visualized_{sub}"
    vis_dir.mkdir(parents=True, exist_ok=True)

    imgs = list(folder.glob("*.jpg")) + list(folder.glob("*.png")) + list(folder.glob("*.jpeg"))
    
    for img_p in imgs:
        lbl_p = img_p.with_suffix(".txt")
        cv_img = cv2.imread(str(img_p))
        if cv_img is None:
            continue
        
        h_img, w_img, _ = cv_img.shape
        annotated_bgr = cv_img.copy()

        box_count = 0
        if lbl_p.exists():
            with open(lbl_p, 'r', encoding='utf-8', errors='ignore') as f:
                lines = [l.strip() for l in f if l.strip()]
                for line in lines:
                    parts = line.split()
                    if len(parts) >= 5:
                        try:
                            cx, cy, w, h = map(float, parts[1:5])
                            x1 = int((cx - w/2) * w_img)
                            y1 = int((cy - h/2) * h_img)
                            x2 = int((cx + w/2) * w_img)
                            y2 = int((cy + h/2) * h_img)
                            
                            x1 = max(0, min(w_img - 1, x1))
                            y1 = max(0, min(h_img - 1, y1))
                            x2 = max(0, min(w_img - 1, x2))
                            y2 = max(0, min(h_img - 1, y2))

                            # Draw bbox
                            cv2.rectangle(annotated_bgr, (x1, y1), (x2, y2), (0, 0, 255), 3)
                            cv2.putText(annotated_bgr, "trash", (x1, max(15, y1 - 5)),
                                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2, cv2.LINE_AA)
                            box_count += 1
                        except ValueError:
                            pass

        # Draw banner showing bbox count
        cv2.putText(annotated_bgr, f"GT Bboxes: {box_count}", (20, 40),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 0) if box_count > 0 else (255, 255, 255), 2, cv2.LINE_AA)

        dest = vis_dir / f"vis_{img_p.name}"
        cv2.imwrite(str(dest), annotated_bgr)

    print(f"Rendered {len(imgs)} visualizations in: {vis_dir}")
