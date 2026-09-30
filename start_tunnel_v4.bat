@echo off
echo Starting Ngrok tunnel for AIQ V4...
echo Please copy the Forwarding URL (https://...) from the terminal below.
echo Paste it into the "Connection Settings" as V4 URL in Authority app and Fleet app!
echo.
ngrok http 8050
pause
