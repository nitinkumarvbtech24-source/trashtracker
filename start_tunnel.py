import subprocess
import re
import sys
import os
import time
import json
import urllib.request
import shutil
import threading
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).parent.resolve()
CLOUDFLARED_EXE = BASE_DIR / "New folder" / "cloudflared.exe"
FIRESTORE_URL = "https://firestore.googleapis.com/v1/projects/takemytrash/databases/(default)/documents/settings/server_config?updateMask.fieldPaths=active_backend_url&updateMask.fieldPaths=ngrok_url&updateMask.fieldPaths=cloudflare_url&updateMask.fieldPaths=connect_code&updateMask.fieldPaths=updated_at"

STATIC_NGROK_DOMAIN = "divided-headache-slogan.ngrok-free.dev"
QUICK_CONNECT_CODE = "5002"

active_urls = {
    "ngrok": f"https://{STATIC_NGROK_DOMAIN}",
    "cloudflare": None,
}

state_lock = threading.Lock()

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

def update_dart_constants(primary_url: str):
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
                f'String CLOUDFLARE_URL = "{primary_url}";',
                content
            )
            target.write_text(new_content, encoding="utf-8")
            print(f"✅ Updated {target.relative_to(BASE_DIR)}")
        except Exception as e:
            print(f"⚠️ Error updating {target}: {e}")

def broadcast_to_firestore():
    """Publishes both Ngrok and Cloudflare URLs + Quick Connect Code to Firestore."""
    with state_lock:
        primary = active_urls["ngrok"] or active_urls["cloudflare"] or f"https://{STATIC_NGROK_DOMAIN}"
        ngrok_val = active_urls["ngrok"] or f"https://{STATIC_NGROK_DOMAIN}"
        cf_val = active_urls["cloudflare"] or ""

    try:
        fields = {
            "active_backend_url": {"stringValue": primary},
            "ngrok_url": {"stringValue": ngrok_val},
            "cloudflare_url": {"stringValue": cf_val},
            "connect_code": {"stringValue": QUICK_CONNECT_CODE},
            "updated_at": {"stringValue": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
        }
        payload = json.dumps({"fields": fields}).encode("utf-8")
        req = urllib.request.Request(
            FIRESTORE_URL,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="PATCH"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            print(f"📡 Broadcasted to Firestore -> Active: {primary} | PIN: {QUICK_CONNECT_CODE}")
            return True
    except Exception as e:
        print(f"⚠️ Firestore sync warning: {e}")
        return False

def print_connection_dashboard():
    """Prints a clear, easy-to-read connection guide."""
    with state_lock:
        ngrok = active_urls.get("ngrok")
        cf = active_urls.get("cloudflare")

    print("\n" + "=" * 68)
    print("  🎉 DUAL TUNNELS ACTIVE & READY TO CONNECT")
    print("=" * 68)
    print(f"  🔢 EASY CONNECT NUMBER / CODE:   {QUICK_CONNECT_CODE}")
    print("     (Enter '5002' or tap 'Auto-Sync' in the app on your phone)")
    print("-" * 68)
    if ngrok:
        print(f"  1️⃣  STATIC NGROK DOMAIN:      {ngrok}")
    if cf:
        print(f"  2️⃣  CLOUDFLARE LIVE TUNNEL:   {cf}")
    print("=" * 68 + "\n")

def run_ngrok_worker():
    """Worker thread running Ngrok tunnel with static domain."""
    ngrok_path = shutil.which("ngrok")
    if not ngrok_path:
        print("❌ ngrok CLI not found on PATH.")
        return

    print("🚀 Starting Ngrok tunnel...")
    cmd = [ngrok_path, "http", "5002", f"--url=https://{STATIC_NGROK_DOMAIN}", "--log=stdout"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, encoding="utf-8", errors="replace")

    url_pattern = re.compile(r"url=(https://[a-zA-Z0-9-_\.]+\.ngrok-free\.dev)")
    detected = False

    for line in iter(proc.stdout.readline, ""):
        if "ERR_NGROK" in line or "failed to start tunnel" in line:
            print("\n⚠️ Ngrok static domain reservation notice. Running standard tunnel...")
            proc.terminate()
            break

        if not detected:
            match = url_pattern.search(line)
            if match:
                url = match.group(1)
                with state_lock:
                    active_urls["ngrok"] = url
                detected = True
                print(f"✅ Ngrok online: {url}")
                update_dart_constants(url)
                broadcast_to_firestore()
                print_connection_dashboard()

    if not detected:
        cmd_fallback = [ngrok_path, "http", "5002", "--log=stdout"]
        proc = subprocess.Popen(cmd_fallback, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, encoding="utf-8", errors="replace")
        for line in iter(proc.stdout.readline, ""):
            if not detected:
                match = url_pattern.search(line)
                if match:
                    url = match.group(1)
                    with state_lock:
                        active_urls["ngrok"] = url
                    detected = True
                    print(f"✅ Ngrok online: {url}")
                    update_dart_constants(url)
                    broadcast_to_firestore()
                    print_connection_dashboard()

    proc.wait()

def run_cloudflare_worker():
    """Worker thread running Cloudflare tunnel with auto-recovery on disconnect."""
    if not CLOUDFLARED_EXE.exists():
        print(f"❌ cloudflared.exe not found at: {CLOUDFLARED_EXE}")
        return

    print("🚀 Starting Cloudflare tunnel...")
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
        cf_detected = False

        for line in iter(proc.stdout.readline, ""):
            if not cf_detected:
                match = url_pattern.search(line)
                if match:
                    url = f"https://{match.group(1)}"
                    with state_lock:
                        active_urls["cloudflare"] = url
                    cf_detected = True
                    print(f"✅ Cloudflare online: {url}")
                    broadcast_to_firestore()
                    print_connection_dashboard()

            if any(p in line for p in dead_patterns):
                print("⚠️ Cloudflare session dropped. Auto-reconnecting in 3s...")
                proc.terminate()
                break

        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

        time.sleep(3)

def main():
    check_local_backend()

    mode = "both"
    if len(sys.argv) > 1:
        arg = sys.argv[1].lower()
        if "--ngrok" in arg:
            mode = "ngrok"
        elif "--cloudflare" in arg:
            mode = "cloudflare"
        elif "--both" in arg:
            mode = "both"

    if mode == "ngrok":
        run_ngrok_worker()
    elif mode == "cloudflare":
        run_cloudflare_worker()
    else:
        # Run BOTH tunnels simultaneously
        print("==================================================================")
        print("  🚀 STARTING DUAL TUNNELS: NGROK + CLOUDFLARE ON PORT 5002")
        print("==================================================================")
        t_ngrok = threading.Thread(target=run_ngrok_worker, daemon=True)
        t_cf = threading.Thread(target=run_cloudflare_worker, daemon=True)

        t_ngrok.start()
        t_cf.start()

        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nShutting down tunnels...")

if __name__ == "__main__":
    main()
