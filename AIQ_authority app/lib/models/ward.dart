import 'package:latlong2/latlong.dart';

class Ward {
  final String id;
  final String name;
  final List<LatLng> boundary; // Polygon points
  List<LatLng>? checkpoints; // The stops/checkpoints the vehicle must hit
  List<LatLng>? optimizedRoute; // The generated sweep route for this ward
  double? routeDistanceKm;

  Ward({
    required this.id,
    required this.name,
    required this.boundary,
    this.checkpoints,
    this.optimizedRoute,
    this.routeDistanceKm,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'routeDistanceKm': routeDistanceKm,
      'boundary': boundary.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
      'checkpoints': checkpoints?.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
      'optimizedRoute': optimizedRoute?.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
    };
  }

  factory Ward.fromJson(String id, Map<String, dynamic> json) {
    List<LatLng> bound = [];
    if (json['boundary'] != null) {
      final List<dynamic> rawBound = json['boundary'];
      bound = rawBound.map((e) => LatLng(e['lat'], e['lng'])).toList();
    }

    List<LatLng>? route;
    if (json['optimizedRoute'] != null) {
      final List<dynamic> rawRoute = json['optimizedRoute'];
      route = rawRoute.map((e) => LatLng(e['lat'], e['lng'])).toList();
    }
    
    List<LatLng>? checks;
    if (json['checkpoints'] != null) {
      final List<dynamic> rawChecks = json['checkpoints'];
      checks = rawChecks.map((e) => LatLng(e['lat'], e['lng'])).toList();
    }
    
    return Ward(
      id: id,
      name: json['name'] ?? '',
      boundary: bound,
      checkpoints: checks,
      routeDistanceKm: json['routeDistanceKm'] != null ? (json['routeDistanceKm'] as num).toDouble() : null,
      optimizedRoute: route,
    );
  }
}
