@echo off
echo Starting Garbage AI Tunnel (ngrok on port 5001)...
start cmd /k "ngrok http 5001"

echo Starting Road Health AI Tunnel (ngrok on port 5002)...
start cmd /k "ngrok http 5002"

echo Both ngrok tunnels launched in separate windows!
echo NOTE: If you are on a free Ngrok plan, one of these may fail. 
echo If that happens, you will need a paid Ngrok account or to use a different service for the second one.
pause
