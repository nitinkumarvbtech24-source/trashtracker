import 'package:latlong2/latlong.dart';

class Ward {
  final String id;
  final String name;
  final List<LatLng> boundary; // Polygon points
  List<LatLng>? checkpoints; // The stops/checkpoints the vehicle must hit
  List<LatLng>? optimizedRoute; // The generated sweep route for this ward
  double? routeDistanceKm;
  String? zone;
  int? wardNo;
  String? shortName;
  String? constituency;
  LatLng? centroid;
  late final double minLat;
  late final double maxLat;
  late final double minLng;
  late final double maxLng;

  Ward({
    required this.id,
    required this.name,
    required this.boundary,
    this.checkpoints,
    this.optimizedRoute,
    this.routeDistanceKm,
    this.zone,
    this.wardNo,
    this.shortName,
    this.constituency,
    this.centroid,
  }) {
    if (boundary.isNotEmpty) {
      double minLa = boundary.first.latitude, maxLa = boundary.first.latitude;
      double minLo = boundary.first.longitude, maxLo = boundary.first.longitude;
      for (var p in boundary) {
        if (p.latitude < minLa) minLa = p.latitude;
        if (p.latitude > maxLa) maxLa = p.latitude;
        if (p.longitude < minLo) minLo = p.longitude;
        if (p.longitude > maxLo) maxLo = p.longitude;
      }
      minLat = minLa;
      maxLat = maxLa;
      minLng = minLo;
      maxLng = maxLo;
    } else {
      minLat = -90;
      maxLat = 90;
      minLng = -180;
      maxLng = 180;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'routeDistanceKm': routeDistanceKm,
      if (zone != null) 'zone': zone,
      if (wardNo != null) 'wardNo': wardNo,
      if (shortName != null) 'shortName': shortName,
      if (constituency != null) 'constituency': constituency,
      if (centroid != null) 'centroid': {'lat': centroid!.latitude, 'lng': centroid!.longitude},
      'boundary': boundary.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
      'checkpoints': checkpoints?.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
      'optimizedRoute': optimizedRoute?.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
    };
  }

  factory Ward.fromJson(String id, Map<String, dynamic> json) {
    List<LatLng> bound = [];
    if (json['boundary'] != null) {
      final List<dynamic> rawBound = json['boundary'];
      bound = rawBound.map((e) => LatLng(
        ((e['lat'] ?? 0.0) as num).toDouble(),
        ((e['lng'] ?? 0.0) as num).toDouble(),
      )).toList();
    }

    List<LatLng>? route;
    if (json['optimizedRoute'] != null) {
      final List<dynamic> rawRoute = json['optimizedRoute'];
      route = rawRoute.map((e) => LatLng(
        ((e['lat'] ?? 0.0) as num).toDouble(),
        ((e['lng'] ?? 0.0) as num).toDouble(),
      )).toList();
    }
    
    List<LatLng>? checks;
    if (json['checkpoints'] != null) {
      final List<dynamic> rawChecks = json['checkpoints'];
      checks = rawChecks.map((e) => LatLng(
        ((e['lat'] ?? 0.0) as num).toDouble(),
        ((e['lng'] ?? 0.0) as num).toDouble(),
      )).toList();
    }

    LatLng? cent;
    if (json['centroid'] != null && json['centroid'] is Map) {
      final cMap = json['centroid'] as Map;
      cent = LatLng(
        ((cMap['lat'] ?? 0.0) as num).toDouble(),
        ((cMap['lng'] ?? 0.0) as num).toDouble(),
      );
    }
    
    return Ward(
      id: id,
      name: json['name'] ?? '',
      boundary: bound,
      checkpoints: checks,
      routeDistanceKm: json['routeDistanceKm'] != null ? (json['routeDistanceKm'] as num).toDouble() : null,
      optimizedRoute: route,
      zone: json['zone'],
      wardNo: json['wardNo'] != null ? (json['wardNo'] as num).toInt() : null,
      shortName: json['shortName'],
      constituency: json['constituency'],
      centroid: cent,
    );
  }
}
