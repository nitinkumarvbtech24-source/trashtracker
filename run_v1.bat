@echo off
echo ==============================================
echo   STARTING GARBAGE AI MODEL V1 (Port 5000)
echo ==============================================
cd /d "%~dp0garbage_ai model"
python flask_app.py
pause
