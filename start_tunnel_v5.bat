@echo off
echo Starting Ngrok tunnel for AIQ V5...
echo Please copy the Forwarding URL (https://...) from the terminal below.
echo Paste it into the "Connection Settings" as V5 URL in Authority app and Fleet app!
echo.
ngrok http 5001
pause
