import 'package:latlong2/latlong.dart';

class Zone {
  final String id;
  final String name;
  final List<LatLng> boundary; // Polygon points
  LatLng? centroid;
  late final double minLat;
  late final double maxLat;
  late final double minLng;
  late final double maxLng;

  Zone({
    required this.id,
    required this.name,
    required this.boundary,
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
      'boundary': boundary.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
      if (centroid != null) 'centroid': {'lat': centroid!.latitude, 'lng': centroid!.longitude},
    };
  }

  factory Zone.fromJson(String id, Map<String, dynamic> json) {
    List<LatLng> bound = [];
    if (json['boundary'] != null) {
      final List<dynamic> rawBound = json['boundary'];
      bound = rawBound.map((e) => LatLng(
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
    
    return Zone(
      id: id,
      name: json['name'] ?? '',
      boundary: bound,
      centroid: cent,
    );
  }
}
