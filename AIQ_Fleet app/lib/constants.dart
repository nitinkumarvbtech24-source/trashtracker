// Replace localhost with your computer's IP address (e.g. 192.168.1.5) 
// if you are running the app on a physical phone on the same WiFi network.
String GARBAGE_AI_URL = "https://grumbling-tattling-schilling.ngrok-free.dev";
String GARBAGE_AI_V2_URL = "https://pointer-staff-prodigy-v2.ngrok-free.dev";
String GARBAGE_AI_V3_URL = "https://pointer-staff-prodigy-v3.ngrok-free.dev";
String GARBAGE_AI_V4_URL = "https://grumbling-tattling-schilling.ngrok-free.dev";
int MODEL_VERSION = 4;

String get activeGarbageAiUrl {
  if (MODEL_VERSION == 4) return GARBAGE_AI_V4_URL;
  if (MODEL_VERSION == 3) return GARBAGE_AI_V3_URL;
  if (MODEL_VERSION == 2) return GARBAGE_AI_V2_URL;
  return GARBAGE_AI_URL;
}

String HEALTH_AI_URL = "https://pointer-staff-prodigy.ngrok-free.dev"; // Enter the Cloudflare/Pinggy URL here
