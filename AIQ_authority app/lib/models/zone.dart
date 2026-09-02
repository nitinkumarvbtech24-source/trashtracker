import 'package:latlong2/latlong.dart';

class Zone {
  final String id;
  final String name;
  final List<LatLng> boundary; // Polygon points

  Zone({
    required this.id,
    required this.name,
    required this.boundary,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'boundary': boundary.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
    };
  }

  factory Zone.fromJson(String id, Map<String, dynamic> json) {
    List<LatLng> bound = [];
    if (json['boundary'] != null) {
      final List<dynamic> rawBound = json['boundary'];
      bound = rawBound.map((e) => LatLng(e['lat'], e['lng'])).toList();
    }
    
    return Zone(
      id: id,
      name: json['name'] ?? '',
      boundary: bound,
    );
  }
}
