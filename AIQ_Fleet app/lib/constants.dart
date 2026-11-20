// Auto-synced active tunnel URL (Ngrok or Cloudflare)
String CLOUDFLARE_URL = "https://api.trycloudflare.com";

String GARBAGE_AI_URL = CLOUDFLARE_URL;
String GARBAGE_AI_V2_URL = "https://pointer-staff-prodigy-v2.ngrok-free.dev";
String GARBAGE_AI_V3_URL = "https://pointer-staff-prodigy-v3.ngrok-free.dev";
String GARBAGE_AI_V5_URL = "https://pointer-staff-prodigy.ngrok-free.dev";
String GARBAGE_AI_V7_URL = CLOUDFLARE_URL;
int MODEL_VERSION = 7;

void updateBackendUrl(String newUrl) {
  if (newUrl.isEmpty) return;
  CLOUDFLARE_URL = newUrl;
  GARBAGE_AI_URL = newUrl;
  GARBAGE_AI_V7_URL = newUrl;
  HEALTH_AI_URL = newUrl;
}

String get activeGarbageAiUrl {
  if (MODEL_VERSION == 7) return GARBAGE_AI_V7_URL;
  if (MODEL_VERSION == 5) return GARBAGE_AI_V5_URL;
  if (MODEL_VERSION == 3) return GARBAGE_AI_V3_URL;
  if (MODEL_VERSION == 2) return GARBAGE_AI_V2_URL;
  return GARBAGE_AI_URL;
}

String HEALTH_AI_URL = CLOUDFLARE_URL;
