@echo off
title Road Cleanliness Analyzer Server
echo ==========================================================
echo Starting Road Cleanliness Analyzer Server...
echo (Using virtual environment Python)
echo ==========================================================
cd /d "%~dp0"
if exist "..\.venv\Scripts\python.exe" (
    ..\.venv\Scripts\python.exe flask_app.py
) else (
    python flask_app.py
)
pause
