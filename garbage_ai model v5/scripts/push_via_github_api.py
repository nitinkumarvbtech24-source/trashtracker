import os
import base64
import json
import urllib.request
from pathlib import Path

TOKEN = "YOUR_GITHUB_TOKEN"
OWNER = "kokilacg30"
REPO = "model2"
BASE_DIR = Path(r"e:\nitin\model2")

# Files to upload to GitHub
FILES_TO_UPLOAD = [
    "README.md",
    "app.py",
    "models/yolo_trash_detector.pt",
    "scripts/train_yolo_trash_detector.py",
    "scripts/prepare_yolo_dataset.py",
    "scripts/predict_cleanliness.py"
]

def upload_file_to_github(rel_path):
    file_path = BASE_DIR / rel_path
    if not file_path.exists():
        print(f"[SKIP] Missing file: {rel_path}")
        return False

    with open(file_path, "rb") as f:
        content_bytes = f.read()

    base64_content = base64.b64encode(content_bytes).decode("utf-8")
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/contents/{rel_path}"
    
    headers = {
        "Authorization": f"token {TOKEN}",
        "User-Agent": "Mozilla/5.0",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json"
    }
    
    sha = None
    req_check = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req_check) as resp:
            data = json.loads(resp.read().decode())
            sha = data.get("sha")
    except Exception:
        pass

    payload = {
        "message": f"Update {rel_path} with YOLOv8 trash object detector model",
        "content": base64_content,
        "branch": "main"
    }
    if sha:
        payload["sha"] = sha

    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="PUT")
    
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            print(f"[SUCCESS] Uploaded to GitHub: {rel_path}")
            return True
    except Exception as e:
        print(f"[ERROR] Failed to upload {rel_path}: {e}")
        return False

def main():
    print(f"Uploading YOLO model and app updates to GitHub repository https://github.com/{OWNER}/{REPO}...")
    success_count = 0
    for file_rel in FILES_TO_UPLOAD:
        ok = upload_file_to_github(file_rel)
        if ok:
            success_count += 1
            
    print(f"\n==================================================")
    print(f"Uploaded {success_count}/{len(FILES_TO_UPLOAD)} files to https://github.com/{OWNER}/{REPO}")
    print(f"==================================================")

if __name__ == "__main__":
    main()
