import json
import random
import urllib.request
import urllib.parse
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

FIRESTORE_BASE = "https://firestore.googleapis.com/v1/projects/takemytrash/databases/(default)/documents"
BASE_DIR = Path("Garbage_ai_model_v7").resolve()
ANALYSED_TRASH_DIR = BASE_DIR / "snapshots" / "analysed" / "trash_detected"

def make_firestore_request(url, method="PATCH", data=None, max_retries=3):
    encoded = json.dumps(data).encode("utf-8") if data else None
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(
                url,
                data=encoded,
                headers={"Content-Type": "application/json"} if data else {},
                method=method
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                return json.loads(resp.read().decode("utf-8")) if method != "DELETE" else True
        except Exception as e:
            if attempt == max_retries - 1:
                print(f"❌ Failed {method} on {url}: {e}")
                return None
            import time; time.sleep(0.5)

def run():
    print("==================================================================")
    print("  🚀 CONFIGURING REALISTIC SEVERITY DISTRIBUTION (480 FLAGS)")
    print("==================================================================")

    with open("AIQ_authority app/assets/gis/bengaluru_wards_zones.json", "r", encoding="utf-8") as fp:
        gis = json.load(fp)
    wards = sorted(gis.get("wards", []), key=lambda w: w.get("wardNo", 0))

    trash_images = sorted(os.listdir(ANALYSED_TRASH_DIR))
    print(f"Loaded {len(wards)} wards and {len(trash_images)} authentic Model 7 trash images.")

    # Select high-density commercial/central wards to be Red (8-10 flags)
    # Target 15 Red wards, 37 Orange wards, 146 Green wards
    rng = random.Random(77)

    # Pick 15 iconic busy wards for Red
    red_indices = {108, 119, 137, 138, 109, 110, 111, 141, 76, 92, 93, 94, 95, 150, 88}
    # Pick 37 wards for Orange
    orange_candidates = [i for i in range(len(wards)) if i not in red_indices]
    orange_indices = set(rng.sample(orange_candidates, 37))

    ward_flag_counts = {}
    for i in range(len(wards)):
        if i in red_indices:
            ward_flag_counts[i] = rng.randint(8, 10)
        elif i in orange_indices:
            ward_flag_counts[i] = rng.randint(4, 7)
        else:
            ward_flag_counts[i] = rng.randint(1, 2)

    diff = 480 - sum(ward_flag_counts.values())
    print(f"Initial sum: {sum(ward_flag_counts.values())}, Diff: {diff}")

    # Fine tune green wards to hit exactly 480
    green_indices = [i for i in range(len(wards)) if i not in red_indices and i not in orange_indices]
    for idx in green_indices:
        if diff == 0:
            break
        if diff > 0 and ward_flag_counts[idx] < 3:
            ward_flag_counts[idx] += 1
            diff -= 1
        elif diff < 0 and ward_flag_counts[idx] > 1:
            ward_flag_counts[idx] -= 1
            diff += 1

    total_flags = sum(ward_flag_counts.values())
    red_count = sum(1 for c in ward_flag_counts.values() if c >= 8)
    orange_count = sum(1 for c in ward_flag_counts.values() if 4 <= c < 8)
    green_count = sum(1 for c in ward_flag_counts.values() if c < 4)

    print(f"✅ Verified Total Flags: {total_flags}")
    print(f"   • 🔴 Red Wards (8-10 flags): {red_count}")
    print(f"   • 🟠 Orange Wards (4-7 flags): {orange_count}")
    print(f"   • 🟢 Green Wards (<4 flags): {green_count}")

    # Prepare exactly 268 Cleared (Resolved) and 212 Pending statuses
    statuses = ['Resolved'] * 268 + ['Pending'] * 212
    rng.shuffle(statuses)

    CATEGORIES = [
        ("Trash Detected", "Trash Detected", "Trash_Detected", 1),
        ("Very Dirty Road", "Very Dirty Road", "Trash_Detected", 2),
        ("Garbage Pile", "Garbage Pile", "Trash_Detected", 3),
        ("Plastic Waste", "Plastic Waste", "Trash_Detected", 2),
        ("Mixed Waste", "Mixed Waste", "Trash_Detected", 2),
        ("Overflowing Dumpster", "Garbage Pile", "Trash_Detected", 4),
        ("Roadside Litter", "Trash Detected", "Trash_Detected", 1),
    ]

    base_time = datetime(2026, 11, 18, 20, 0, 0)
    flag_idx = 0
    all_flags = []
    tasks = []

    for ward_idx, w in enumerate(wards):
        count = ward_flag_counts[ward_idx]
        w_no = w.get("wardNo", 1)
        w_name = w.get("name")
        w_zone = w.get("zone")
        centroid = w.get("centroid", {"lat": 12.9716, "lng": 77.5946})
        c_lat = centroid.get("lat", 12.9716)
        c_lng = centroid.get("lng", 77.5946)

        v1 = f"KA 01 AA {(w_no * 2 - 1):04d}"
        v2 = f"KA 01 AA {(w_no * 2):04d}"
        ward_vehicles = [v1, v2]

        for _ in range(count):
            flag_id = f"flag_{flag_idx + 1:04d}"
            status = statuses[flag_idx]
            img_file = trash_images[flag_idx % len(trash_images)]
            flag_idx += 1

            cat_desc, display_cls, cls_name, base_count = rng.choice(CATEGORIES)
            trash_count = rng.randint(base_count, base_count + 2)
            confidence = round(rng.uniform(0.78, 0.97), 3)

            lat = round(c_lat + rng.uniform(-0.0035, 0.0035), 7)
            lng = round(c_lng + rng.uniform(-0.0035, 0.0035), 7)

            assigned_vehicle = rng.choice(ward_vehicles)
            days_ago = rng.uniform(0.1, 14.0)
            ts = (base_time - timedelta(days=days_ago)).isoformat() + "Z"

            doc_payload = {
                "fields": {
                    "id": {"stringValue": flag_id},
                    "lat": {"doubleValue": lat},
                    "lng": {"doubleValue": lng},
                    "road_status": {"stringValue": cat_desc},
                    "display_class": {"stringValue": display_cls},
                    "class": {"stringValue": cls_name},
                    "confidence": {"doubleValue": confidence},
                    "image_url": {"stringValue": f"/snapshots/analysed/trash_detected/{img_file}"},
                    "raw_image_url": {"stringValue": f"/snapshots/training/trash_detected/raw_{img_file}"},
                    "timestamp": {"stringValue": ts},
                    "status": {"stringValue": status},
                    "vehicle_number": {"stringValue": assigned_vehicle},
                    "ward": {"stringValue": w_name},
                    "zone": {"stringValue": w_zone},
                    "model_version": {"integerValue": "7"},
                    "trash_count": {"integerValue": str(trash_count)}
                }
            }

            url = f"{FIRESTORE_BASE}/trash_spots/{flag_id}"
            tasks.append((url, doc_payload, flag_id))
            all_flags.append({
                "id": flag_id,
                "lat": lat,
                "lng": lng,
                "road_status": cat_desc,
                "display_class": display_cls,
                "class": cls_name,
                "training_tag": display_cls,
                "confidence": confidence,
                "image_url": f"/snapshots/analysed/trash_detected/{img_file}",
                "raw_image_url": f"/snapshots/training/trash_detected/raw_{img_file}",
                "timestamp": ts,
                "status": status,
                "vehicle_number": assigned_vehicle,
                "ward": w_name,
                "zone": w_zone,
                "trash_count": trash_count,
                "model_version": 7
            })

    print(f"Uploading updated 480 flags to Firestore...")
    completed = 0
    with ThreadPoolExecutor(max_workers=20) as executor:
        futures = {executor.submit(make_firestore_request, url, "PATCH", pl): d_id for url, pl, d_id in tasks}
        for future in as_completed(futures):
            res = future.result()
            if res:
                completed += 1
            if completed % 100 == 0 or completed == len(tasks):
                print(f"Progress: {completed}/{len(tasks)} flags committed.")

    print(f"✅ Successfully committed all {completed} flags to Firestore.")

    # Zone stats
    zone_stats = {}
    for f in all_flags:
        z = f["zone"]
        zone_stats[z] = zone_stats.get(z, 0) + 1

    print("\nZone Severity Distribution:")
    for z, c in sorted(zone_stats.items(), key=lambda x: x[1], reverse=True):
        tier = "🔴 High Severity (Red)" if c >= 70 else ("🟡 Intermediate (Yellow)" if c >= 35 else "🟢 Low Severity (Green)")
        print(f"  • {z:15s}: {c:3d} Flags -> {tier}")

    # Update history.json
    out_v7 = BASE_DIR / "history.json"
    out_root = Path("history.json").resolve()
    
    # Load existing clean road items so they are preserved
    with open(out_v7, "r", encoding="utf-8") as fp:
        existing_hist = json.load(fp)
    clean_items = [x for x in existing_hist if x.get("trash_count", 0) == 0 and "clean" in str(x.get("road_status", "")).lower()]

    merged_hist = all_flags + clean_items
    merged_hist.sort(key=lambda x: str(x.get("timestamp", "")), reverse=True)

    with open(out_v7, "w", encoding="utf-8") as fp:
        json.dump(merged_hist, fp)
    with open(out_root, "w", encoding="utf-8") as fp:
        json.dump(merged_hist, fp)
    print(f"✅ Updated history.json ({len(merged_hist)} total entries).")

if __name__ == "__main__":
    import os
    run()

