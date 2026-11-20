@echo off
TITLE Tunnel Auto-Sync
echo ========================================================
echo     STARTING TUNNEL (AUTO-SYNC TO MOBILE & WEB)
echo ========================================================
echo.
cd /d "%~dp0"
py -3.13 start_tunnel.py
pause
