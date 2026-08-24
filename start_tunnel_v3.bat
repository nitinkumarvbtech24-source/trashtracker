@echo off
echo Starting Ngrok tunnel for AIQ V3...
echo Please copy the Forwarding URL (https://...) from the terminal below.
echo Paste it into the "Connection Settings" as V3 URL in Authority app!
echo.
ngrok http 5002
pause
