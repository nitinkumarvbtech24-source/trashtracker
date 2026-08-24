@echo off
echo ==============================================
echo   STARTING GARBAGE AI MODEL V3 (Port 5002)
echo ==============================================
cd /d "%~dp0garbage ai model v3\garbage_ai model"
python flask_app.py
pause
