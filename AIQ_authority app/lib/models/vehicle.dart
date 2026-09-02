import 'package:latlong2/latlong.dart';

class Vehicle {
  final String id;
  final String vehicleNumber;
  final String driverName;
  final String? phoneNumber;
  final String? driverInfo;
  final String? password;
  String assignedWard;
  LatLng? currentLocation;
  bool isActive;
  List<LatLng>? assignedRoute;
  List<LatLng>? assignedCheckpoints;
  double? routeDistanceKm;
  DateTime? lastHeartbeat;
  String? currentDeviceId;

  bool get isRunning {
    if (lastHeartbeat == null) return false;
    final diff = DateTime.now().difference(lastHeartbeat!);
    return diff.inMinutes < 2;
  }

  // State 1: Navigating (Green)
  // State 2: Running but idle (Yellow)
  // State 3: Not running (Blue)
  int get stateColorValue {
    if (isRunning) {
      return isActive ? 0xFF10B981 : 0xFFF59E0B; // Green : Yellow
    }
    return 0xFF3B82F6; // Blue (Not running)
  }

  String get statusText {
    if (isRunning) {
      return isActive ? 'Active' : 'Online';
    }
    return 'Inactive';
  }

  Vehicle({
    required this.id,
    required this.vehicleNumber,
    required this.driverName,
    required this.assignedWard,
    this.phoneNumber,
    this.driverInfo,
    this.password,
    this.currentLocation,
    this.isActive = false,
    this.assignedRoute,
    this.assignedCheckpoints,
    this.routeDistanceKm,
    this.lastHeartbeat,
    this.currentDeviceId,
  });

  Map<String, dynamic> toJson() {
    return {
      'vehicleNumber': vehicleNumber,
      'driverName': driverName,
      'phoneNumber': phoneNumber,
      'driverInfo': driverInfo,
      'password': password,
      'assignedWard': assignedWard,
      'routeDistanceKm': routeDistanceKm,
      'assignedRoute': assignedRoute?.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
      'assignedCheckpoints': assignedCheckpoints?.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
      'currentDeviceId': currentDeviceId,
    };
  }

  factory Vehicle.fromJson(String id, Map<String, dynamic> json) {
    List<LatLng>? route;
    if (json['assignedRoute'] != null) {
      final List<dynamic> rawRoute = json['assignedRoute'];
      route = rawRoute.map((e) => LatLng(e['lat'], e['lng'])).toList();
    }
    
    List<LatLng>? checkpoints;
    if (json['assignedCheckpoints'] != null) {
      final List<dynamic> rawCheckpoints = json['assignedCheckpoints'];
      checkpoints = rawCheckpoints.map((e) => LatLng(e['lat'], e['lng'])).toList();
    }
    
    LatLng? currLoc;
    if (json['lat'] != null && json['lng'] != null) {
      currLoc = LatLng((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble());
    } else if (json['currentLocation'] != null) {
      // In case it's stored as a map {lat: 12.3, lng: 45.6}
      currLoc = LatLng((json['currentLocation']['lat'] as num).toDouble(), (json['currentLocation']['lng'] as num).toDouble());
    }

    return Vehicle(
      id: id,
      vehicleNumber: json['vehicleNumber'] ?? '',
      driverName: json['driverName'] ?? '',
      phoneNumber: json['phoneNumber'],
      driverInfo: json['driverInfo'],
      password: json['password'],
      assignedWard: json['assignedWard'] ?? 'Unassigned',
      assignedRoute: route,
      assignedCheckpoints: checkpoints,
      routeDistanceKm: (json['routeDistanceKm'] as num?)?.toDouble(),
      lastHeartbeat: json['lastHeartbeat'] != null ? DateTime.parse(json['lastHeartbeat']) : null,
      currentDeviceId: json['currentDeviceId'],
      currentLocation: currLoc,
      isActive: json['isActive'] ?? false,
    );
  }
}
