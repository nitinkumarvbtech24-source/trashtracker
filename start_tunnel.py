import subprocess
import re
import sys
import os
import time
import json
import urllib.request
import shutil
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).parent.resolve()
CLOUDFLARED_EXE = BASE_DIR / "New folder" / "cloudflared.exe"
FIRESTORE_URL = "https://firestore.googleapis.com/v1/projects/takemytrash/databases/(default)/documents/settings/server_config?updateMask.fieldPaths=active_backend_url&updateMask.fieldPaths=updated_at"

STATIC_NGROK_DOMAIN = "divided-headache-slogan.ngrok-free.dev"

def check_local_backend():
    """Checks if Garbage AI backend is actively listening on port 5002."""
    try:
        req = urllib.request.Request("http://127.0.0.1:5002/api/health", headers={"User-Agent": "TunnelChecker/1.0"})
        with urllib.request.urlopen(req, timeout=2) as resp:
            data = json.loads(resp.read().decode())
            print(f"✅ Local backend detected on port 5002: {data.get('model', 'OK')}")
            return True
    except Exception:
        print("⚠️ Local backend on port 5002 is not responding yet.")
        print("   Make sure to start it: py -3.13 Garbage_ai_model_v7\\app.py")
        return False

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
    """Publishes the live URL to Firebase Firestore so mobile phones & web apps auto-connect."""
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

def test_tunnel_health(tunnel_url: str):
    """Verifies that the public tunnel URL successfully reaches the backend."""
    health_url = f"{tunnel_url.rstrip('/')}/api/health"
    print(f"🔍 Testing tunnel connectivity to {health_url}...")
    for attempt in range(1, 6):
        try:
            req = urllib.request.Request(health_url, headers={"ngrok-skip-browser-warning": "true"})
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status == 200:
                    print(f"🎉 Tunnel verified live & healthy! (HTTP 200 on attempt {attempt})")
                    return True
        except Exception as e:
            time.sleep(1.5)
    print("ℹ️ Note: DNS propagation may take up to 30 seconds for external clients.")
    return False

def run_ngrok():
    """Runs Ngrok using the account's static domain or auto-assigned URL."""
    ngrok_path = shutil.which("ngrok")
    if not ngrok_path:
        print("❌ ngrok CLI not found on PATH.")
        return False

    print("==================================================================")
    print("  🚀 STARTING NGROK TUNNEL (Static Domain with 0 DNS Delay)")
    print(f"  Domain: https://{STATIC_NGROK_DOMAIN}")
    print("==================================================================")

    # First attempt: Try using the account's static domain
    cmd = [ngrok_path, "http", "5002", f"--url=https://{STATIC_NGROK_DOMAIN}", "--log=stdout"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, encoding="utf-8", errors="replace")

    tunnel_url = None
    url_pattern = re.compile(r"url=(https://[a-zA-Z0-9-_\.]+\.ngrok-free\.dev)")

    for line in iter(proc.stdout.readline, ""):
        sys.stdout.write(line)
        sys.stdout.flush()

        if "ERR_NGROK" in line or "failed to start tunnel" in line:
            print("\n⚠️ Static domain reservation failed, falling back to dynamic ngrok URL...")
            proc.terminate()
            break

        if not tunnel_url:
            match = url_pattern.search(line)
            if match:
                tunnel_url = match.group(1)
                _on_tunnel_ready(tunnel_url)

    # Fallback attempt if static domain failed: Run standard ngrok
    if not tunnel_url:
        print("\nStarting standard ngrok tunnel on port 5002...")
        cmd_fallback = [ngrok_path, "http", "5002", "--log=stdout"]
        proc = subprocess.Popen(cmd_fallback, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, encoding="utf-8", errors="replace")
        for line in iter(proc.stdout.readline, ""):
            sys.stdout.write(line)
            sys.stdout.flush()
            if not tunnel_url:
                match = url_pattern.search(line)
                if match:
                    tunnel_url = match.group(1)
                    _on_tunnel_ready(tunnel_url)

    proc.wait()
    return True

def run_cloudflare():
    """Runs Cloudflare Tunnel with automated recovery and reconnection on disconnect."""
    if not CLOUDFLARED_EXE.exists():
        print(f"❌ cloudflared.exe not found at: {CLOUDFLARED_EXE}")
        return False

    print("==================================================================")
    print("  🚀 STARTING CLOUDFLARE TUNNEL (With Auto-Recovery & Live Sync)")
    print("==================================================================")

    url_pattern = re.compile(r"https://([a-zA-Z0-9-]+\.trycloudflare\.com)")
    dead_patterns = ["Unauthorized: Tunnel not found", "connection with edge closed", "Unable to establish connection"]

    while True:
        cmd = [
            str(CLOUDFLARED_EXE),
            "tunnel",
            "--protocol", "http2",
            "--edge-ip-version", "4",
            "--url", "http://127.0.0.1:5002",
            "--retries", "10"
        ]

        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, encoding="utf-8", errors="replace")
        tunnel_url = None

        for line in iter(proc.stdout.readline, ""):
            sys.stdout.write(line)
            sys.stdout.flush()

            if not tunnel_url:
                match = url_pattern.search(line)
                if match:
                    tunnel_url = f"https://{match.group(1)}"
                    _on_tunnel_ready(tunnel_url)

            # Detect dead tunnel session and auto-restart to get a fresh URL
            if any(p in line for p in dead_patterns):
                print("\n⚠️ Cloudflare edge session dropped or expired. Restarting fresh tunnel in 3s...")
                proc.terminate()
                break

        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

        print("\n🔄 Re-establishing Cloudflare tunnel...")
        time.sleep(3)

def _on_tunnel_ready(tunnel_url: str):
    print("\n" + "=" * 66)
    print(f"  🎉 LIVE TUNNEL DETECTED: {tunnel_url}")
    print("=" * 66 + "\n")
    update_dart_constants(tunnel_url)
    update_firestore(tunnel_url)
    print("📲 Mobile phones, web dashboards & Flutter apps now automatically connected!\n")
    test_tunnel_health(tunnel_url)

def main():
    check_local_backend()

    mode = "auto"
    if len(sys.argv) > 1:
        arg = sys.argv[1].lower()
        if "--ngrok" in arg:
            mode = "ngrok"
        elif "--cloudflare" in arg:
            mode = "cloudflare"

    if mode == "ngrok":
        run_ngrok()
    elif mode == "cloudflare":
        run_cloudflare()
    else:
        # Auto mode: Prefer Ngrok because static domain has zero DNS propagation delay,
        # but gracefully fall back to Cloudflare if Ngrok fails or is not authenticated.
        ngrok_path = shutil.which("ngrok")
        if ngrok_path:
            print("💡 Auto-detected ngrok installed. Starting ngrok...")
            success = run_ngrok()
            if not success:
                print("Falling back to Cloudflare...")
                run_cloudflare()
        else:
            print("💡 Starting Cloudflare tunnel...")
            run_cloudflare()

if __name__ == "__main__":
    main()
