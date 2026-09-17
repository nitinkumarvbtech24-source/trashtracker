// Replace localhost with your computer's IP address (e.g. 192.168.1.5) 
// if you are running the app on a physical phone on the same WiFi network.
String GARBAGE_AI_URL = "https://grumbling-tattling-schilling.ngrok-free.dev";
String GARBAGE_AI_V2_URL = "https://pointer-staff-prodigy-v2.ngrok-free.dev";
String GARBAGE_AI_V3_URL = "https://pointer-staff-prodigy-v3.ngrok-free.dev";
String HEALTH_AI_URL = "https://pointer-staff-prodigy.ngrok-free.dev"; // Or the ngrok URL for Health AI
int MODEL_VERSION = 1;

String get activeGarbageAiUrl {
  if (MODEL_VERSION == 3) return GARBAGE_AI_V3_URL;
  if (MODEL_VERSION == 2) return GARBAGE_AI_V2_URL;
  return GARBAGE_AI_URL;
}

String get activeHealthAiUrl {
  return HEALTH_AI_URL;
}

// Keeping for backward compatibility temporarily if needed
bool get USE_V2_MODEL => MODEL_VERSION == 2;
set USE_V2_MODEL(bool value) {
  MODEL_VERSION = value ? 2 : 1;
}
