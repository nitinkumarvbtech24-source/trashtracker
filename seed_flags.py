import json
import random
import urllib.request
import urllib.parse
import time
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed

FIRESTORE_BASE = "https://firestore.googleapis.com/v1/projects/takemytrash/databases/(default)/documents"

CATEGORIES = [
    ("Trash Detected", "Trash Detected", "Trash_Detected", 1),
    ("Very Dirty Road", "Very Dirty Road", "Trash_Detected", 2),
    ("Garbage Pile", "Garbage Pile", "Trash_Detected", 3),
    ("Plastic Waste", "Plastic Waste", "Trash_Detected", 2),
    ("Mixed Waste", "Mixed Waste", "Trash_Detected", 2),
    ("Overflowing Dumpster", "Garbage Pile", "Trash_Detected", 4),
    ("Roadside Litter", "Trash Detected", "Trash_Detected", 1),
]

def make_request(url, method="PATCH", data=None, max_retries=3):
    encoded_data = json.dumps(data).encode("utf-8") if data else None
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(
                url,
                data=encoded_data,
                headers={"Content-Type": "application/json"} if data else {},
                method=method
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                return json.loads(resp.read().decode("utf-8")) if method != "DELETE" else True
        except Exception as e:
            if attempt == max_retries - 1:
                print(f"❌ Failed {method} on {url}: {e}")
                return None
            time.sleep(1)

def purge_old_trash_spots():
    print("🧹 Fetching existing trash_spots to purge...")
    all_docs = []
    page_token = None
    while True:
        url = f"{FIRESTORE_BASE}/trash_spots?pageSize=300"
        if page_token:
            url += f"&pageToken={page_token}"
        try:
            req = urllib.request.urlopen(url)
            data = json.loads(req.read().decode("utf-8"))
            docs = data.get("documents", [])
            all_docs.extend(docs)
            page_token = data.get("nextPageToken")
            if not page_token:
                break
        except Exception as e:
            print("Fetch error:", e)
            break

    print(f"Found {len(all_docs)} existing trash_spots to delete.")
    if all_docs:
        with ThreadPoolExecutor(max_workers=15) as executor:
            futures = [executor.submit(make_request, f"https://firestore.googleapis.com/v1/{d['name']}", "DELETE") for d in all_docs]
            for f in as_completed(futures):
                pass
        print("✅ Purged existing trash_spots.")

def seed():
    print("======================================================================")
    print("  🚀 SEEDING 480 FLAGS (268 CLEARED, 212 PENDING) OVER ALL WARDS")
    print("======================================================================")

    # 1. Purge old spots first
    purge_old_trash_spots()

    # 2. Load GIS wards
    with open("AIQ_authority app/assets/gis/bengaluru_wards_zones.json", "r", encoding="utf-8") as f:
        gis = json.load(f)

    wards = sorted(gis.get("wards", []), key=lambda w: w.get("wardNo", 0))
    print(f"Loaded {len(wards)} wards from GIS dataset.")

    # 3. Available sample images
    sample_images = [
        "04ea274c-2ccf-4771-80ac-e69f3703c588.jpg",
        "05d2cd37-edd3-4ce5-b822-9724c97cd509.jpg",
        "06b8a04a-5c37-48ef-83ef-e802a4b9e1a8.jpg",
        "06ba02a6-0683-433b-8255-0816ef066f27.jpg",
        "06ea5fe2-3cb5-455b-9d41-e9ee5fdf3ba3.jpg",
        "07be1fc6-d8f9-4470-8b43-4700b5ca3364.jpg",
        "0811b7df-ec1f-45a7-9e79-cb256b85cf4c.jpg",
        "0a34b6b6-3a5c-4eb2-a1f9-847be0aeece7.jpg"
    ]

    TOTAL_FLAGS = 480
    TARGET_CLEARED = 268
    TARGET_PENDING = TOTAL_FLAGS - TARGET_CLEARED # 212

    # Distribute flags across 198 wards
    # 198 * 2 = 396 flags. Remaining 84 flags assigned to first 84 wards.
    flag_allocations = []
    for i, w in enumerate(wards):
        count = 3 if i < (TOTAL_FLAGS - 198 * 2) else 2
        flag_allocations.append((w, count))

    # Pre-generate 480 status labels: exactly 268 'Resolved' (cleared) and 212 'Pending'
    statuses = ['Resolved'] * TARGET_CLEARED + ['Pending'] * TARGET_PENDING
    # Seed random for repeatable realism
    rng = random.Random(42)
    rng.shuffle(statuses)

    tasks = []
    records = []
    status_idx = 0

    base_time = datetime(2026, 11, 18, 18, 30, 0)

    for ward_data, count in flag_allocations:
        ward_no = ward_data.get("wardNo")
        ward_name = ward_data.get("name")
        zone_name = ward_data.get("zone")
        centroid = ward_data.get("centroid", {"lat": 12.9716, "lng": 77.5946})
        c_lat = centroid.get("lat", 12.9716)
        c_lng = centroid.get("lng", 77.5946)

        # Vehicles assigned to this ward: e.g. KA 01 AA (ward_no*2 - 1) and (ward_no*2)
        v1 = f"KA 01 AA {(ward_no * 2 - 1):04d}"
        v2 = f"KA 01 AA {(ward_no * 2):04d}"
        ward_vehicles = [v1, v2]

        for sub_i in range(count):
            flag_id = f"flag_{status_idx + 1:04d}"
            status = statuses[status_idx]
            status_idx += 1

            # Slight random offset around centroid (approx 100m - 400m)
            lat_offset = rng.uniform(-0.0035, 0.0035)
            lng_offset = rng.uniform(-0.0035, 0.0035)
            flag_lat = round(c_lat + lat_offset, 7)
            flag_lng = round(c_lng + lng_offset, 7)

            cat_desc, display_cls, cls_name, base_count = rng.choice(CATEGORIES)
            trash_count = rng.randint(base_count, base_count + 2)
            confidence = round(rng.uniform(0.78, 0.97), 3)

            # Random timestamp in the last 14 days
            days_ago = rng.uniform(0.2, 14.0)
            flag_time = (base_time - timedelta(days=days_ago)).isoformat() + "Z"

            assigned_vehicle = rng.choice(ward_vehicles)
            sample_img = rng.choice(sample_images)

            doc_payload = {
                "fields": {
                    "id": {"stringValue": flag_id},
                    "lat": {"doubleValue": flag_lat},
                    "lng": {"doubleValue": flag_lng},
                    "road_status": {"stringValue": cat_desc},
                    "display_class": {"stringValue": display_cls},
                    "class": {"stringValue": cls_name},
                    "confidence": {"doubleValue": confidence},
                    "image_url": {"stringValue": f"/snapshots/analysed/trash_detected/{sample_img}"},
                    "raw_image_url": {"stringValue": f"/snapshots/training/trash_detected/raw_{sample_img}"},
                    "timestamp": {"stringValue": flag_time},
                    "status": {"stringValue": status},
                    "vehicle_number": {"stringValue": assigned_vehicle},
                    "ward": {"stringValue": ward_name},
                    "zone": {"stringValue": zone_name},
                    "model_version": {"integerValue": "7"},
                    "trash_count": {"integerValue": str(trash_count)}
                }
            }

            url = f"{FIRESTORE_BASE}/trash_spots/{flag_id}"
            tasks.append((url, "PATCH", doc_payload, flag_id))
            records.append({
                "id": flag_id,
                "ward": ward_name,
                "zone": zone_name,
                "status": status,
                "lat": flag_lat,
                "lng": flag_lng,
                "vehicle": assigned_vehicle,
                "display_class": display_cls,
                "trash_count": trash_count
            })

    print(f"Queued {len(tasks)} flags to write to Firestore.")
    cleared_count = sum(1 for r in records if r["status"] == "Resolved")
    pending_count = sum(1 for r in records if r["status"] == "Pending")
    print(f"Audit before write: Cleared: {cleared_count}, Pending: {pending_count}, Total: {len(records)}")

    completed = 0
    errors = 0
    with ThreadPoolExecutor(max_workers=20) as executor:
        futures = {executor.submit(make_request, url, method, data): desc for url, method, data, desc in tasks}
        for future in as_completed(futures):
            res = future.result()
            if res:
                completed += 1
            else:
                errors += 1
            if completed % 60 == 0 or completed == len(tasks):
                print(f"Progress: {completed}/{len(tasks)} flags uploaded (Errors: {errors})")

    print("\n======================================================================")
    print("  ✅ 480 FLAGS SEEDING COMPLETED")
    print("======================================================================")
    print(f"Total Flags Seeded: {len(records)}")
    print(f"Cleared (Resolved): {cleared_count}")
    print(f"Pending (Action Required): {pending_count}")

    # Zone stats
    zone_stats = {}
    for r in records:
        z = r["zone"]
        if z not in zone_stats:
            zone_stats[z] = {"total": 0, "cleared": 0, "pending": 0}
        zone_stats[z]["total"] += 1
        if r["status"] == "Resolved":
            zone_stats[z]["cleared"] += 1
        else:
            zone_stats[z]["pending"] += 1

    print("\nZone Distribution:")
    for z, st in sorted(zone_stats.items()):
        rate = (st["cleared"] / st["total"]) * 100
        print(f"  • {z:15s}: Total: {st['total']:3d} | Cleared: {st['cleared']:3d} | Pending: {st['pending']:3d} | Clearance: {rate:.1f}%")

    with open("flags_seeded_summary.json", "w", encoding="utf-8") as f:
        json.dump({
            "total": len(records),
            "cleared": cleared_count,
            "pending": pending_count,
            "zone_breakdown": zone_stats,
            "sample_flags": records[:10]
        }, f, indent=2)

if __name__ == "__main__":
    seed()

