@echo off
TITLE Cloudflare Tunnel & Mobile Auto-Sync
echo ========================================================
echo     STARTING CLOUDFLARE TUNNEL (AUTO-SYNC TO PHONE)
echo ========================================================
echo.
cd /d "%~dp0"
py -3.13 start_tunnel.py
pause

