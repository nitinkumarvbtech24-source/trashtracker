import 'package:latlong2/latlong.dart';

// Original coordinates centered around Boston, MA (approx. 42.3601, -71.0589)
const LatLng originalCenter = LatLng(42.3601, -71.0589);
const LatLng mapCenter = originalCenter;
const double mapZoom = 15.0;

final Map<String, List<LatLng>> routes = {
  "Downtown Loop": [
    LatLng(42.3601, -71.0589),
    LatLng(42.3621, -71.0589),
    LatLng(42.3635, -71.0610),
    LatLng(42.3630, -71.0645),
    LatLng(42.3600, -71.0655),
    LatLng(42.3585, -71.0640),
    LatLng(42.3565, -71.0620),
    LatLng(42.3550, -71.0600),
    LatLng(42.3555, -71.0575),
    LatLng(42.3575, -71.0560),
    LatLng(42.3590, -71.0570),
    LatLng(42.3601, -71.0589)
  ],
  "Northside Sweep": [
    LatLng(42.3650, -71.0550),
    LatLng(42.3670, -71.0530),
    LatLng(42.3695, -71.0555),
    LatLng(42.3720, -71.0580),
    LatLng(42.3705, -71.0620),
    LatLng(42.3680, -71.0640),
    LatLng(42.3655, -71.0620),
    LatLng(42.3645, -71.0590),
    LatLng(42.3650, -71.0550)
  ],
  "Southside Transit": [
    LatLng(42.3520, -71.0650),
    LatLng(42.3500, -71.0680),
    LatLng(42.3480, -71.0700),
    LatLng(42.3450, -71.0730),
    LatLng(42.3430, -71.0700),
    LatLng(42.3450, -71.0650),
    LatLng(42.3485, -71.0615),
    LatLng(42.3505, -71.0630),
    LatLng(42.3520, -71.0650)
  ],
  "Westside Boulevard": [
    LatLng(42.3580, -71.0700),
    LatLng(42.3590, -71.0750),
    LatLng(42.3605, -71.0800),
    LatLng(42.3630, -71.0820),
    LatLng(42.3650, -71.0800),
    LatLng(42.3635, -71.0740),
    LatLng(42.3610, -71.0720),
    LatLng(42.3580, -71.0700)
  ]
};

class VehicleData {
  final String id;
  final String name;
  final String type;
  final String driver;
  final String route;
  final String status;
  final int speed;
  final int cleanliness;
  final int potholesFound;
  final int routeIndex;
  final String color;
  final String activeModel;

  VehicleData({
    required this.id,
    required this.name,
    required this.type,
    required this.driver,
    required this.route,
    required this.status,
    required this.speed,
    required this.cleanliness,
    required this.potholesFound,
    required this.routeIndex,
    required this.color,
    required this.activeModel,
  });
}

final List<VehicleData> initialVehicles = [
  VehicleData(
    id: "V-101",
    name: "EcoSweeper Pro",
    type: "Sweeper",
    driver: "David K.",
    route: "Downtown Loop",
    status: "Active",
    speed: 18,
    cleanliness: 94,
    potholesFound: 3,
    routeIndex: 0,
    color: "#10b981",
    activeModel: "CleanVision v2.5",
  ),
  VehicleData(
    id: "V-102",
    name: "CityScout Inspector",
    type: "Inspector",
    driver: "Elena R.",
    route: "Northside Sweep",
    status: "Active",
    speed: 28,
    cleanliness: 82,
    potholesFound: 11,
    routeIndex: 2,
    color: "#3b82f6",
    activeModel: "RoadScan AI v4.0",
  ),
  VehicleData(
    id: "V-103",
    name: "EcoSweeper Lite",
    type: "Sweeper",
    driver: "Marcus L.",
    route: "Southside Transit",
    status: "Warning",
    speed: 12,
    cleanliness: 68,
    potholesFound: 8,
    routeIndex: 4,
    color: "#f59e0b",
    activeModel: "CleanVision v2.5",
  ),
  VehicleData(
    id: "V-104",
    name: "RoadPatrol Heavy",
    type: "Pothole Repair",
    driver: "Sara M.",
    route: "Westside Boulevard",
    status: "Active",
    speed: 24,
    cleanliness: 79,
    potholesFound: 5,
    routeIndex: 1,
    color: "#a855f7",
    activeModel: "PotholeDetect v3",
  ),
];

class CleanlinessSegment {
  final String id;
  final String name;
  final List<LatLng> coordinates;
  final String level;
  final int score;
  final String lastScanned;

  CleanlinessSegment({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.level,
    required this.score,
    required this.lastScanned,
  });
}

final List<CleanlinessSegment> cleanlinessSegments = [
  CleanlinessSegment(
    id: "c-seg-1",
    name: "Mahatma Gandhi Rd",
    coordinates: routes["Downtown Loop"]!.sublist(0, 5),
    level: "Clean",
    score: 95,
    lastScanned: "5 mins ago",
  ),
  CleanlinessSegment(
    id: "c-seg-2",
    name: "Brigade Rd Corridor",
    coordinates: routes["Downtown Loop"]!.sublist(4, 9),
    level: "Moderate",
    score: 72,
    lastScanned: "12 mins ago",
  ),
  CleanlinessSegment(
    id: "c-seg-3",
    name: "Outer Ring Rd",
    coordinates: routes["Downtown Loop"]!.sublist(8, 12),
    level: "Dirty",
    score: 38,
    lastScanned: "2 mins ago",
  ),
  CleanlinessSegment(
    id: "c-seg-4",
    name: "Residency Road Sweep",
    coordinates: routes["Northside Sweep"]!.sublist(0, 4),
    level: "Clean",
    score: 91,
    lastScanned: "15 mins ago",
  ),
  CleanlinessSegment(
    id: "c-seg-5",
    name: "Indiranagar 100ft Rd",
    coordinates: routes["Northside Sweep"]!.sublist(3, 7),
    level: "Dirty",
    score: 42,
    lastScanned: "1 min ago",
  ),
  CleanlinessSegment(
    id: "c-seg-6",
    name: "Koramangala Blvd",
    coordinates: routes["Southside Transit"]!.sublist(2, 6),
    level: "Moderate",
    score: 64,
    lastScanned: "8 mins ago",
  ),
];

class RoadHealthAnomaly {
  final String id;
  final String type;
  final String severity;
  final LatLng coordinates;
  final String street;
  final int confidence;
  final String status;
  final String detectedBy;
  final String time;

  RoadHealthAnomaly({
    required this.id,
    required this.type,
    required this.severity,
    required this.coordinates,
    required this.street,
    required this.confidence,
    required this.status,
    required this.detectedBy,
    required this.time,
  });
}

final List<RoadHealthAnomaly> roadHealthAnomalies = [
  RoadHealthAnomaly(
    id: "pothole-1",
    type: "Severe Pothole",
    severity: "High",
    coordinates: LatLng(42.3621, -71.0589),
    street: "MG Road Junction",
    confidence: 96,
    status: "Pending",
    detectedBy: "V-101",
    time: "2 mins ago",
  ),
  RoadHealthAnomaly(
    id: "crack-1",
    type: "Longitudinal Crack",
    severity: "Medium",
    coordinates: LatLng(42.3630, -71.0645),
    street: "Double Road (Near HSR Layout)",
    confidence: 84,
    status: "Pending",
    detectedBy: "V-101",
    time: "8 mins ago",
  ),
  RoadHealthAnomaly(
    id: "manhole-1",
    type: "Sunken Manhole",
    severity: "Low",
    coordinates: LatLng(42.3585, -71.0640),
    street: "Richmond Town Rd",
    confidence: 79,
    status: "Monitored",
    detectedBy: "V-103",
    time: "15 mins ago",
  ),
  RoadHealthAnomaly(
    id: "pothole-2",
    type: "Group of Potholes",
    severity: "High",
    coordinates: LatLng(42.3695, -71.0555),
    street: "Commercial Street",
    confidence: 92,
    status: "Scheduled",
    detectedBy: "V-102",
    time: "22 mins ago",
  ),
  RoadHealthAnomaly(
    id: "pothole-3",
    type: "Deep Asphalt Depression",
    severity: "High",
    coordinates: LatLng(42.3480, -71.0700),
    street: "Hosur Rd & Silk Board",
    confidence: 97,
    status: "Pending",
    detectedBy: "V-103",
    time: "10 mins ago",
  ),
  RoadHealthAnomaly(
    id: "crack-2",
    type: "Alligator Cracking",
    severity: "Medium",
    coordinates: LatLng(42.3605, -71.0800),
    street: "Bannerghatta Main Rd",
    confidence: 88,
    status: "Pending",
    detectedBy: "V-104",
    time: "4 mins ago",
  ),
];

class Blackspot {
  final String id;
  final LatLng coordinates;
  final String description;
  final String imageUrl;
  final String severity;

  Blackspot({
    required this.id,
    required this.coordinates,
    required this.description,
    required this.imageUrl,
    required this.severity,
  });
}

final List<Blackspot> mockBlackspots = [
  Blackspot(
    id: "bs-1",
    coordinates: LatLng(42.3615, -71.0580),
    description: "Illegal dumping of construction debris",
    imageUrl: "https://images.unsplash.com/photo-1595278069441-2cf29f8005a4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
    severity: "High",
  ),
  Blackspot(
    id: "bs-2",
    coordinates: LatLng(42.3640, -71.0630),
    description: "Overflowing garbage bins blocking the sidewalk",
    imageUrl: "https://images.unsplash.com/photo-1532996122724-e3c354a0b15b?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
    severity: "Critical",
  ),
  Blackspot(
    id: "bs-3",
    coordinates: LatLng(42.3595, -71.0725),
    description: "Heavy plastic waste accumulation near the drainage",
    imageUrl: "https://images.unsplash.com/photo-1611284446314-60a58ac0deb9?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
    severity: "High",
  ),
];

