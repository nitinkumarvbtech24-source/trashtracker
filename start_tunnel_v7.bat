@echo off
TITLE Tunnel Auto-Sync
echo ========================================================
echo     STARTING TUNNEL (AUTO-SYNC TO MOBILE & WEB)
echo ========================================================
echo.
cd /d "%~dp0"
set "PY_CMD=%LOCALAPPDATA%\Python\bin\python.exe"
if not exist "%PY_CMD%" set "PY_CMD=python"
"%PY_CMD%" start_tunnel.py
pause
