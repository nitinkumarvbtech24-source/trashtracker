import subprocess
import re
import sys
import json
import urllib.request
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).parent.resolve()
CLOUDFLARED_EXE = BASE_DIR / "New folder" / "cloudflared.exe"
FIRESTORE_URL = "https://firestore.googleapis.com/v1/projects/takemytrash/databases/(default)/documents/settings/server_config?updateMask.fieldPaths=active_backend_url&updateMask.fieldPaths=updated_at"

def update_dart_constants(tunnel_url: str):
    """Updates constants.dart in both Authority and Fleet apps."""
    targets = [
        BASE_DIR / "AIQ_authority app" / "lib" / "constants.dart",
        BASE_DIR / "AIQ_Fleet app" / "lib" / "constants.dart",
    ]
    for target in targets:
        if not target.exists():
            continue
        try:
            content = target.read_text(encoding="utf-8")
            # Replace String CLOUDFLARE_URL = "...";
            new_content = re.sub(
                r'String CLOUDFLARE_URL = "[^"]+";',
                f'String CLOUDFLARE_URL = "{tunnel_url}";',
                content
            )
            target.write_text(new_content, encoding="utf-8")
            print(f"✅ Updated {target.relative_to(BASE_DIR)}")
        except Exception as e:
            print(f"⚠️ Error updating {target}: {e}")

def update_firestore(tunnel_url: str):
    """Publishes the live URL to Firebase Firestore so mobile phones auto-connect."""
    try:
        payload = json.dumps({
            "fields": {
                "active_backend_url": {"stringValue": tunnel_url},
                "updated_at": {"stringValue": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
            }
        }).encode("utf-8")
        req = urllib.request.Request(
            FIRESTORE_URL,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="PATCH"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            print(f"📡 Broadcasted to Firebase Firestore: {tunnel_url}")
            return True
    except Exception as e:
        print(f"⚠️ Firestore sync warning: {e}")
        return False

def main():
    if not CLOUDFLARED_EXE.exists():
        print(f"❌ cloudflared.exe not found at: {CLOUDFLARED_EXE}")
        sys.exit(1)

    print("==================================================================")
    print("  🚀 STARTING CLOUDFLARE TUNNEL (HTTP/2 + IPv4 for Mobile Stability)")
    print("==================================================================")

    cmd = [
        str(CLOUDFLARED_EXE),
        "tunnel",
        "--protocol", "http2",
        "--edge-ip-version", "4",
        "--url", "http://127.0.0.1:5002",
        "--retries", "10"
    ]

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        encoding="utf-8",
        errors="replace"
    )

    tunnel_url = None
    url_pattern = re.compile(r"https://([a-zA-Z0-9-]+\.trycloudflare\.com)")

    for line in iter(proc.stdout.readline, ""):
        sys.stdout.write(line)
        sys.stdout.flush()

        if not tunnel_url:
            match = url_pattern.search(line)
            if match:
                tunnel_url = f"https://{match.group(1)}"
                print("\n" + "=" * 66)
                print(f"  🎉 LIVE TUNNEL DETECTED: {tunnel_url}")
                print("=" * 66 + "\n")

                # Sync to constants.dart and Firestore
                update_dart_constants(tunnel_url)
                update_firestore(tunnel_url)
                print("📲 Mobile phones & Flutter apps now automatically connected!\n")

    proc.wait()

if __name__ == "__main__":
    main()

