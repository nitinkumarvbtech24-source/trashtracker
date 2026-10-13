import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ward.dart';
import '../models/zone.dart';

class WardZoneService {
  static final WardZoneService instance = WardZoneService._internal();
  WardZoneService._internal();

  List<Zone> zones = [];
  List<Ward> wards = [];
  bool _initialized = false;
  final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  void init() {
    if (_initialized) return;
    _initialized = true;

    FirebaseFirestore.instance.collection('zones').snapshots().listen((snap) {
      zones = snap.docs.map((d) => Zone.fromJson(d.id, d.data())).toList();
      notifier.value++;
    });

    FirebaseFirestore.instance.collection('wards').snapshots().listen((snap) {
      wards = snap.docs.map((d) => Ward.fromJson(d.id, d.data())).toList();
      notifier.value++;
    });
  }

  static LatLng computeCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    double lat = 0;
    double lng = 0;
    for (var p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  List<Polygon> buildPolygons({String? selectedZone, String? selectedWard}) {
    List<Polygon> polygons = [];

    // 1. Zone Polygons (Purple/Violet)
    final activeZones = zones.where((z) => z.boundary.length >= 3).toList();
    for (var z in activeZones) {
      bool isMatch = selectedZone == null || 
          selectedZone == 'All Zones' || 
          z.name.trim().toLowerCase() == selectedZone.trim().toLowerCase() ||
          z.name.trim().toLowerCase().contains(selectedZone.trim().toLowerCase());

      polygons.add(
        Polygon(
          points: z.boundary,
          color: isMatch ? const Color(0x227C3AED) : const Color(0x0A7C3AED),
          borderColor: isMatch ? const Color(0xFF7C3AED) : const Color(0x557C3AED),
          borderStrokeWidth: isMatch ? 2.5 : 1.2,
        ),
      );
    }

    // 2. Ward Polygons (Royal Blue)
    final activeWards = wards.where((w) => w.boundary.length >= 3).toList();
    for (var w in activeWards) {
      bool isMatch = selectedWard == null || 
          selectedWard == 'All Wards' || 
          w.name.trim().toLowerCase() == selectedWard.trim().toLowerCase() ||
          w.name.trim().toLowerCase().replaceAll(' ', '') == selectedWard.trim().toLowerCase().replaceAll(' ', '');

      polygons.add(
        Polygon(
          points: w.boundary,
          color: isMatch ? const Color(0x222563EB) : const Color(0x0A2563EB),
          borderColor: isMatch ? const Color(0xFF2563EB) : const Color(0x552563EB),
          borderStrokeWidth: isMatch ? 2.0 : 1.0,
        ),
      );
    }

    return polygons;
  }

  List<Marker> buildMarkers({String? selectedZone, String? selectedWard}) {
    List<Marker> markers = [];

    // 1. Zone Centroid Badges (Purple/Violet)
    final activeZones = zones.where((z) => z.boundary.length >= 3).toList();
    for (var z in activeZones) {
      bool isMatch = selectedZone == null || 
          selectedZone == 'All Zones' || 
          z.name.trim().toLowerCase() == selectedZone.trim().toLowerCase() ||
          z.name.trim().toLowerCase().contains(selectedZone.trim().toLowerCase());

      if (selectedZone != null && selectedZone != 'All Zones' && !isMatch) continue;

      final centroid = computeCentroid(z.boundary);
      markers.add(
        Marker(
          point: centroid,
          width: 120,
          height: 32,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xEE7C3AED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.layers_rounded, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    z.name.trim(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 2. Ward Centroid Badges (Royal Blue)
    final activeWards = wards.where((w) => w.boundary.length >= 3).toList();
    for (var w in activeWards) {
      bool isMatch = selectedWard == null || 
          selectedWard == 'All Wards' || 
          w.name.trim().toLowerCase() == selectedWard.trim().toLowerCase() ||
          w.name.trim().toLowerCase().replaceAll(' ', '') == selectedWard.trim().toLowerCase().replaceAll(' ', '');

      if (selectedWard != null && selectedWard != 'All Wards' && !isMatch) continue;

      final centroid = computeCentroid(w.boundary);
      markers.add(
        Marker(
          point: centroid,
          width: 110,
          height: 28,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: const Color(0xEE1E40AF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.pin_drop_rounded, size: 11, color: Colors.white),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    w.name.trim(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  PolygonLayer? buildPolygonLayer({String? selectedZone, String? selectedWard}) {
    final polys = buildPolygons(selectedZone: selectedZone, selectedWard: selectedWard);
    if (polys.isEmpty) return null;
    return PolygonLayer(polygons: polys);
  }

  MarkerLayer? buildMarkerLayer({String? selectedZone, String? selectedWard}) {
    final marks = buildMarkers(selectedZone: selectedZone, selectedWard: selectedWard);
    if (marks.isEmpty) return null;
    return MarkerLayer(markers: marks);
  }

  List<Widget> buildLayers({String? selectedZone, String? selectedWard}) {
    final polyLayer = buildPolygonLayer(selectedZone: selectedZone, selectedWard: selectedWard);
    final markLayer = buildMarkerLayer(selectedZone: selectedZone, selectedWard: selectedWard);

    final list = <Widget>[];
    if (polyLayer != null) list.add(polyLayer);
    if (markLayer != null) list.add(markLayer);
    return list;
  }
}
