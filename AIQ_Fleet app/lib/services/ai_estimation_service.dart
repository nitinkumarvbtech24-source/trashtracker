import 'dart:math';

class AIEstimationService {
  static final AIEstimationService _instance = AIEstimationService._internal();
  factory AIEstimationService() => _instance;
  AIEstimationService._internal();

  /// Estimates the time of arrival in minutes based on distance and speed.
  /// Uses a heuristic approach simulating a non-linear ML prediction
  /// factoring in distance, speed, and simulated time-of-day traffic.
  String predictETA({
    required double distanceMeters,
    required double currentSpeedMetersPerSec,
  }) {
    if (distanceMeters <= 50) return "Arrived";
    
    // Baseline speed if the vehicle is stopped or moving very slow (e.g. traffic light)
    // Assume average city speed of 25 km/h -> ~6.9 m/s
    double effectiveSpeed = currentSpeedMetersPerSec;
    if (effectiveSpeed < 2.0) {
      effectiveSpeed = 6.9; 
    }

    // Base time calculation (Distance / Speed)
    double baseTimeSeconds = distanceMeters / effectiveSpeed;

    // Simulate ML Traffic Factor based on time of day
    // Rush hours (8-10 AM, 5-7 PM) have higher multipliers
    final now = DateTime.now();
    double trafficMultiplier = 1.0;
    
    if ((now.hour >= 8 && now.hour <= 10) || (now.hour >= 17 && now.hour <= 19)) {
      trafficMultiplier = 1.5 + (Random().nextDouble() * 0.5); // 1.5x to 2.0x
    } else {
      trafficMultiplier = 1.0 + (Random().nextDouble() * 0.2); // 1.0x to 1.2x
    }

    // Apply simulated ML weights
    double estimatedTimeSeconds = baseTimeSeconds * trafficMultiplier;
    
    // Convert to minutes
    int minutes = (estimatedTimeSeconds / 60).ceil();

    if (minutes < 1) {
      return "< 1 min";
    } else if (minutes == 1) {
      return "1 min";
    } else {
      return "\$minutes mins";
    }
  }
}
