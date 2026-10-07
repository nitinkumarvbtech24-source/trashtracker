import re

path = r'e:\vc code\.vscode\trash tracker\garbage_ai model v5\app.py'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add imports if missing
if 'from fastapi.staticfiles import StaticFiles' not in content:
    content = content.replace('from pydantic import BaseModel', 'from pydantic import BaseModel\nfrom fastapi.staticfiles import StaticFiles\nimport os\nimport uuid\nfrom datetime import datetime')

# Add static mount
if 'app.mount("/snapshots"' not in content:
    mount_code = """
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs("snapshots", exist_ok=True)
app.mount("/snapshots", StaticFiles(directory="snapshots"), name="snapshots")

history = []
"""
    content = re.sub(r'app\.add_middleware\([^)]+\)', mount_code.strip(), content, count=1)

# replace process_frame and api_snapshots
new_endpoints = """
@app.post("/process_frame")
async def process_frame(req: FrameRequest):
    header, encoded = req.image.split(",", 1)
    img_bytes = base64.b64decode(encoded)
    res = detect_road_trash(img_bytes)
    
    if res["trash_count"] == 0:
        road_status = "Clean Road"
    elif res["trash_count"] < 3:
        road_status = "Slightly Dirty Road"
    else:
        road_status = "Very Dirty Road"

    out_header, out_encoded = res["annotated_image"].split(",", 1)
    out_bytes = base64.b64decode(out_encoded)
    filename = f"{uuid.uuid4()}.jpg"
    with open(f"snapshots/{filename}", "wb") as f:
        f.write(out_bytes)

    snapshot = {
        "display_class": road_status,
        "road_status": road_status,
        "confidence": res["cleanliness_score"] / 100.0,
        "road_confidence": res["cleanliness_score"] / 100.0,
        "image_url": f"/snapshots/{filename}",
        "lat": req.lat,
        "lng": req.lng,
        "vehicle_number": req.vehicle_number,
        "ward": req.ward,
        "zone": req.zone,
        "timestamp": datetime.now().strftime("%Y-%m-%d %I:%M:%S %p")
    }
    history.append(snapshot)
    if len(history) > 100:
        history.pop(0)

    return snapshot

@app.get("/api/snapshots")
async def api_snapshots():
    return {"snapshots": history}
"""

content = re.sub(r'@app\.post\("/process_frame"\).*?def api_snapshots\(\):\s*return \{"snapshots": \[\]\}', new_endpoints.strip(), content, flags=re.DOTALL)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Patched app.py")
