@echo off
echo ==============================================
echo   STARTING NGROK TUNNEL FOR AIQ V7 (Port 5001)
echo ==============================================
echo Tunnel Domain: https://pointer-staff-prodigy.ngrok-free.dev
echo.
ngrok http 5001 --domain=pointer-staff-prodigy.ngrok-free.dev
pause
