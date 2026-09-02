 
echo Starting Road Health AI Tunnel (Account 2 on port 5002)...
start cmd /k "ngrok http --config=ngrok2.yml 5002"

echo ----------------------------------------------------------------------
echo Both Ngrok tunnels launched successfully!
echo The URLs will be printed in the new terminal windows.
echo ----------------------------------------------------------------------
pause
