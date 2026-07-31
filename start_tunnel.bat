@echo off
echo Starting Ngrok tunnel for AIQ...
echo Please copy the Forwarding URL (https://...) from the terminal below.
echo Paste it into the "Connection Settings" in both the Fleet and Authority apps!
echo.
ngrok http 5000
pause
