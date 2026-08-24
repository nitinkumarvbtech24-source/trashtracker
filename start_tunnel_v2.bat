@echo off
echo Starting Ngrok tunnel for AIQ V2...
echo Please copy the Forwarding URL (https://...) from the terminal below.
echo Paste it into the "Connection Settings" as V2 URL in Authority app!
echo.
ngrok http 5001
pause
