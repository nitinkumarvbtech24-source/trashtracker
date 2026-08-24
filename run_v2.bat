@echo off
echo ==============================================
echo   STARTING GARBAGE AI MODEL V2 (Port 5001)
echo ==============================================
cd /d "%~dp0garbage ai v2\garbage_ai model"
python flask_app.py
pause
