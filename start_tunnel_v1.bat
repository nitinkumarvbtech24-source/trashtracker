@echo off
echo Starting Ngrok tunnel for AIQ V1...
echo Please copy the Forwarding URL (https://...) from the terminal below.
echo Paste it into the "Connection Settings" as V1 URL in Authority app!
echo.
ngrok http 5000
pause
