@echo off
echo ========================================================
echo Street AIQ YOLO Trash Detector Live Testing Dashboard
echo ========================================================
echo Loading YOLO Model: E:\nitin\model2\models\trash_detector\best.pt
echo Starting server at http://127.0.0.1:8080 ...
echo Press Ctrl+C to stop the dashboard.
echo ========================================================

cd /d E:\nitin\model2\trash_detection_dashboard
python app.py

pause
