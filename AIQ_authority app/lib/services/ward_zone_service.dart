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

  bool isWardInZone(Ward ward, Zone zone) {
    if (ward.boundary.isEmpty || zone.boundary.isEmpty) return true;
    double cLat = 0, cLng = 0;
    for (var p in ward.boundary) {
      cLat += p.latitude;
      cLng += p.longitude;
    }
    final centroid = LatLng(cLat / ward.boundary.length, cLng / ward.boundary.length);

    int intersectCount = 0;
    for (int j = 0; j < zone.boundary.length - 1; j++) {
      if (_rayCastIntersect(centroid, zone.boundary[j], zone.boundary[j + 1])) {
        intersectCount++;
      }
    }
    if (_rayCastIntersect(centroid, zone.boundary.last, zone.boundary.first)) intersectCount++;
    return (intersectCount % 2) == 1;
  }

  bool _rayCastIntersect(LatLng point, LatLng vertA, LatLng vertB) {
    double aY = vertA.latitude, bY = vertB.latitude;
    double aX = vertA.longitude, bX = vertB.longitude;
    double pY = point.latitude, pX = point.longitude;
    if ((aY > pY && bY > pY) || (aY < pY && bY < pY) || (aX < pX && bX < pX)) return false;
    if (aY == bY) return false;
    double m = (aX - bX) / (aY - bY);
    double x = aX + m * (pY - aY);
    return x > pX;
  }

  bool isPointInPolygon(LatLng point, List<LatLng> boundary) {
    if (boundary.length < 3) return false;
    int intersectCount = 0;
    for (int j = 0; j < boundary.length - 1; j++) {
      if (_rayCastIntersect(point, boundary[j], boundary[j + 1])) {
        intersectCount++;
      }
    }
    if (_rayCastIntersect(point, boundary.last, boundary.first)) intersectCount++;
    return (intersectCount % 2) == 1;
  }

  Ward? findWardForPoint(LatLng point) {
    for (var w in wards) {
      if (isPointInPolygon(point, w.boundary)) return w;
    }
    return null;
  }

  Zone? findZoneForPoint(LatLng point) {
    for (var z in zones) {
      if (isPointInPolygon(point, z.boundary)) return z;
    }
    return null;
  }

  List<String> getWardsForZone(String zoneName) {
    if (zoneName == 'All Zones' || zoneName.isEmpty) {
      return wards.map((w) => w.name).toList();
    }
    Zone? matchedZone;
    final zClean = zoneName.trim().toLowerCase();
    for (var z in zones) {
      final name = z.name.trim().toLowerCase();
      if (name == zClean || name.contains(zClean) || zClean.contains(name)) {
        matchedZone = z;
        break;
      }
    }
    if (matchedZone == null) return wards.map((w) => w.name).toList();
    final matching = wards.where((w) => isWardInZone(w, matchedZone!)).map((w) => w.name).toList();
    return matching.isNotEmpty ? matching : wards.map((w) => w.name).toList();
  }

  bool matchesZone({required double lat, required double lng, String? docZone, required String targetZone}) {
    if (targetZone == 'All Zones' || targetZone.isEmpty) return true;
    final tClean = targetZone.trim().toLowerCase();
    final dClean = (docZone ?? '').trim().toLowerCase();
    if (dClean.isNotEmpty && dClean != 'unknown' && dClean != 'unassigned') {
      if (dClean == tClean || dClean.contains(tClean) || tClean.contains(dClean)) {
        return true;
      }
    }
    // GIS spatial boundary check
    if (lat != 0.0 && lng != 0.0) {
      for (var z in zones) {
        final zName = z.name.trim().toLowerCase();
        if (zName == tClean || zName.contains(tClean) || tClean.contains(zName)) {
          if (isPointInPolygon(LatLng(lat, lng), z.boundary)) return true;
        }
      }
    }
    return false;
  }

  bool matchesWard({required double lat, required double lng, String? docWard, required String targetWard}) {
    if (targetWard == 'All Wards' || targetWard.isEmpty) return true;
    final tClean = targetWard.trim().toLowerCase().replaceAll(' ', '');
    final dClean = (docWard ?? '').trim().toLowerCase().replaceAll(' ', '');
    if (dClean.isNotEmpty && dClean != 'unknown' && dClean != 'unassigned') {
      if (dClean == tClean || dClean.contains(tClean) || tClean.contains(dClean)) {
        return true;
      }
    }
    // GIS spatial boundary check
    if (lat != 0.0 && lng != 0.0) {
      for (var w in wards) {
        final wName = w.name.trim().toLowerCase().replaceAll(' ', '');
        if (wName == tClean || wName.contains(tClean) || tClean.contains(wName)) {
          if (isPointInPolygon(LatLng(lat, lng), w.boundary)) return true;
        }
      }
    }
    return false;
  }

  List<Polygon> buildPolygons({String? selectedZone, String? selectedWard, double? zoom}) {
    final hasSpecificZone = selectedZone != null && selectedZone != 'All Zones' && selectedZone.trim().isNotEmpty;
    final hasSpecificWard = selectedWard != null && selectedWard != 'All Wards' && selectedWard.trim().isNotEmpty;
    final showWards = (zoom != null && zoom >= 13.5) || hasSpecificZone || hasSpecificWard;

    Zone? matchedZone;
    if (hasSpecificZone) {
      for (var z in zones) {
        if (z.name.trim().toLowerCase() == selectedZone.trim().toLowerCase() ||
            z.name.trim().toLowerCase().contains(selectedZone.trim().toLowerCase()) ||
            selectedZone.trim().toLowerCase().contains(z.name.trim().toLowerCase())) {
          matchedZone = z;
          break;
        }
      }
    }

    final List<Polygon> polygons = [];

    // 1. Zone Polygons (LIGHT GREEN as in Roles & Access screen)
    for (var z in zones.where((z) => z.boundary.length >= 3)) {
      final isSelected = hasSpecificZone && (matchedZone?.id == z.id || z.name.trim().toLowerCase() == selectedZone.trim().toLowerCase());
      polygons.add(
        Polygon(
          points: z.boundary,
          color: isSelected ? Colors.green.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.15),
          borderColor: Colors.green,
          borderStrokeWidth: isSelected ? 3.0 : 1.5,
        ),
      );
    }

    // 2. Ward Polygons (BLUE, revealed when zoomed in >= 13.5 or filtered)
    if (showWards) {
      for (var w in wards.where((w) => w.boundary.length >= 3)) {
        if (matchedZone != null && !isWardInZone(w, matchedZone)) continue;

        final isSelected = hasSpecificWard && (
          w.name.trim().toLowerCase() == selectedWard.trim().toLowerCase() ||
          w.name.trim().toLowerCase().replaceAll(' ', '') == selectedWard.trim().toLowerCase().replaceAll(' ', '')
        );

        polygons.add(
          Polygon(
            points: w.boundary,
            color: isSelected ? Colors.blue.withValues(alpha: 0.4) : Colors.blue.withValues(alpha: 0.15),
            borderColor: Colors.blue,
            borderStrokeWidth: isSelected ? 3.0 : 1.5,
          ),
        );
      }
    }

    return polygons;
  }

  List<Marker> buildMarkers({String? selectedZone, String? selectedWard, double? zoom}) {
    final hasSpecificZone = selectedZone != null && selectedZone != 'All Zones' && selectedZone.trim().isNotEmpty;
    final hasSpecificWard = selectedWard != null && selectedWard != 'All Wards' && selectedWard.trim().isNotEmpty;
    final showWards = (zoom != null && zoom >= 13.5) || hasSpecificZone || hasSpecificWard;

    Zone? matchedZone;
    if (hasSpecificZone) {
      for (var z in zones) {
        if (z.name.trim().toLowerCase() == selectedZone.trim().toLowerCase() ||
            z.name.trim().toLowerCase().contains(selectedZone.trim().toLowerCase()) ||
            selectedZone.trim().toLowerCase().contains(z.name.trim().toLowerCase())) {
          matchedZone = z;
          break;
        }
      }
    }

    final List<Marker> labels = [];

    // When zoomed out, show Zone Labels in white/green box
    if (!showWards) {
      for (var z in zones.where((z) => z.boundary.length >= 3)) {
        final centroid = computeCentroid(z.boundary);
        labels.add(
          Marker(
            point: centroid,
            width: 140,
            height: 40,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.shade700, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Text(
                  z.name,
                  style: TextStyle(
                    color: Colors.green.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
      }
    }

    // When zoomed in (zoom >= 13.5 or filtered), show Ward Labels in white/blue box
    if (showWards) {
      for (var w in wards.where((w) => w.boundary.length >= 3)) {
        if (matchedZone != null && !isWardInZone(w, matchedZone)) continue;

        final centroid = computeCentroid(w.boundary);
        labels.add(
          Marker(
            point: centroid,
            width: 120,
            height: 40,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade700, width: 1),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
                  ],
                ),
                child: Text(
                  w.name,
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
      }
    }

    return labels;
  }

  PolygonLayer? buildPolygonLayer({String? selectedZone, String? selectedWard, double? zoom}) {
    final polys = buildPolygons(selectedZone: selectedZone, selectedWard: selectedWard, zoom: zoom);
    if (polys.isEmpty) return null;
    return PolygonLayer(polygons: polys);
  }

  MarkerLayer? buildMarkerLayer({String? selectedZone, String? selectedWard, double? zoom}) {
    final marks = buildMarkers(selectedZone: selectedZone, selectedWard: selectedWard, zoom: zoom);
    if (marks.isEmpty) return null;
    return MarkerLayer(markers: marks);
  }

  List<Widget> buildLayers({String? selectedZone, String? selectedWard}) {
    return [
      Builder(
        builder: (context) {
          final camera = MapCamera.of(context);
          final zoom = camera.zoom;
          final polys = buildPolygons(selectedZone: selectedZone, selectedWard: selectedWard, zoom: zoom);
          return PolygonLayer(polygons: polys);
        },
      ),
      Builder(
        builder: (context) {
          final camera = MapCamera.of(context);
          final zoom = camera.zoom;
          final marks = buildMarkers(selectedZone: selectedZone, selectedWard: selectedWard, zoom: zoom);
          return MarkerLayer(markers: marks);
        },
      ),
    ];
  }
}
