import os
import sys
import hashlib
from pathlib import Path

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

BASE_DIR = Path(r"e:\nitin\model2")

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

positive_entries = [v for v in master_entries.values() if v["is_positive"]]
positive_entries.sort(key=lambda x: x["total_area"])
flagged_entries = positive_entries[:19]

print("\n| # | Image Filename | Source Dataset | Bounding Boxes | Image Area Coverage (%) |")
print("| :--- | :--- | :--- | :---: | :---: |")

for idx, entry in enumerate(flagged_entries, start=1):
    fname = entry["img_path"].name
    src = entry["source"]
    n_boxes = len(entry["bboxes"])
    cov_pct = f"{entry['total_area'] * 100:.3f}%"
    print(f"| {idx} | `{fname}` | `{src}` | {n_boxes} | {cov_pct} |")
