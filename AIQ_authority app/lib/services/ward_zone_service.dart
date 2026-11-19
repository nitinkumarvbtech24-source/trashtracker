import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ward.dart';
import '../models/zone.dart';
import '../widgets/ward_3d_hierarchy_modal.dart';
import 'trash_spots_service.dart';

class WardZoneService {
  static final WardZoneService instance = WardZoneService._internal();
  WardZoneService._internal();

  static const double wardZoomThreshold = 13.0;
  static const double individualWardPinsZoomThreshold = 15.0;

  List<Zone> zones = [];
  List<Ward> wards = [];
  bool _initialized = false;
  final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  // --- Dynamic Flag Counts & Severity Mapping ---
  Map<String, int>? _cachedZoneCounts;
  Map<String, int>? _cachedWardCounts;
  final Map<String, int> _zoneLookup = {};
  final Map<String, int> _wardLookup = {};
  int _lastFlagsLength = -1;

  void _ensureCountsUpdated() {
    final flags = TrashSpotsService.instance.allFlags;
    if (_cachedZoneCounts != null && flags.length == _lastFlagsLength) return;
    _lastFlagsLength = flags.length;
    final Map<String, int> zc = {};
    final Map<String, int> wc = {};

    for (var f in flags) {
      final z = f.zone.trim().toLowerCase().replaceAll('zone', '').replaceAll(' ', '');
      if (z.isNotEmpty && z != 'unknown' && z != 'unknownzone') {
        zc[z] = (zc[z] ?? 0) + 1;
      }

      final w = f.ward.trim().toLowerCase().replaceAll(' ', '');
      if (w.isNotEmpty && w != 'unknown') {
        wc[w] = (wc[w] ?? 0) + 1;
      }
    }
    _cachedZoneCounts = zc;
    _cachedWardCounts = wc;

    // Instant O(1) Pre-indexed Lookups
    _zoneLookup.clear();
    for (var z in zones) {
      final clean = z.name.trim().toLowerCase().replaceAll('zone', '').replaceAll(' ', '');
      int count = 0;
      zc.forEach((key, val) {
        if (key == clean || key.contains(clean) || clean.contains(key)) count += val;
      });
      _zoneLookup[clean] = count;
    }

    _wardLookup.clear();
    for (var w in wards) {
      final clean = w.name.trim().toLowerCase().replaceAll(' ', '');
      int count = 0;
      wc.forEach((key, val) {
        if (key == clean || key.contains(clean) || clean.contains(key)) count += val;
      });
      _wardLookup[clean] = count;
    }
  }

  int getZoneFlagCount(String zoneName) {
    _ensureCountsUpdated();
    final clean = zoneName.trim().toLowerCase().replaceAll('zone', '').replaceAll(' ', '');
    return _zoneLookup[clean] ?? _cachedZoneCounts?[clean] ?? 0;
  }

  int getWardFlagCount(String wardName) {
    _ensureCountsUpdated();
    final clean = wardName.trim().toLowerCase().replaceAll(' ', '');
    return _wardLookup[clean] ?? _cachedWardCounts?[clean] ?? 0;
  }

  Color getZoneSeverityColor(String zoneName) {
    final count = getZoneFlagCount(zoneName);
    if (count >= 70) {
      return const Color(0xFFEF4444); // Red: High / Critical (e.g. West, East)
    } else if (count >= 35) {
      return const Color(0xFFFACC15); // Yellow: Intermediate (e.g. South)
    } else {
      return const Color(0xFF10B981); // Green: Low / Clean (< 35)
    }
  }

  Color getZoneBorderColor(String zoneName) {
    final count = getZoneFlagCount(zoneName);
    if (count >= 70) {
      return const Color(0xFFDC2626);
    } else if (count >= 35) {
      return const Color(0xFFD97706);
    } else {
      return const Color(0xFF059669);
    }
  }

  String getZoneSeverityLabel(String zoneName) {
    final count = getZoneFlagCount(zoneName);
    if (count >= 70) return 'Critical Hotspot';
    if (count >= 35) return 'Moderate Activity';
    return 'Clean Zone';
  }

  Color getWardSeverityColor(String wardName) {
    final count = getWardFlagCount(wardName);
    if (count >= 8) {
      return const Color(0xFFEF4444); // Red: 8 to 10 flags
    } else if (count >= 4) {
      return const Color(0xFFF97316); // Orange: 4 to 7 flags
    } else {
      return const Color(0xFF10B981); // Green: < 4 flags
    }
  }

  Color getWardBorderColor(String wardName) {
    final count = getWardFlagCount(wardName);
    if (count >= 8) {
      return const Color(0xFFDC2626);
    } else if (count >= 4) {
      return const Color(0xFFEA580C);
    } else {
      return const Color(0xFF059669);
    }
  }

  String getWardSeverityLabel(String wardName) {
    final count = getWardFlagCount(wardName);
    if (count >= 8) return 'Hotspot (8-10 Flags)';
    if (count >= 4) return 'Moderate (4-7 Flags)';
    return 'Clean (< 4 Flags)';
  }

  // --- Dynamic Hover & Highlight State ---
  Ward? hoveredWard;
  Zone? hoveredZone;
  LatLng? hoverPoint;
  final ValueNotifier<int> hoverNotifier = ValueNotifier<int>(0);
  int _lastHoverTimestamp = 0;

  void handleHover(LatLng point, {double? zoom}) {
    // Throttle to 35ms to ensure 60 FPS buttery smoothness
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastHoverTimestamp < 35) return;
    _lastHoverTimestamp = now;

    final showWards = (zoom != null && zoom >= wardZoomThreshold);
    Ward? nextWard;
    Zone? nextZone;

    if (showWards) {
      nextWard = findWardForPoint(point);
      if (nextWard != null) {
        final zClean = (nextWard.zone ?? '').trim().toLowerCase();
        for (var z in zones) {
          if (z.name.trim().toLowerCase() == zClean) {
            nextZone = z;
            break;
          }
        }
        nextZone ??= findZoneForPoint(point);
      } else {
        nextZone = findZoneForPoint(point);
      }
    } else {
      nextZone = findZoneForPoint(point);
      if (nextZone == null) {
        nextWard = findWardForPoint(point);
      }
    }

    // Only notify when hovered item actually changes (stops 120 FPS rebuild loop)
    if (hoveredWard?.id != nextWard?.id || hoveredZone?.id != nextZone?.id) {
      hoveredWard = nextWard;
      hoveredZone = nextZone;
      hoverPoint = point;
      hoverNotifier.value++;
    }
  }

  void clearHover() {
    if (hoveredWard != null || hoveredZone != null) {
      hoveredWard = null;
      hoveredZone = null;
      hoverPoint = null;
      hoverNotifier.value++;
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Immediately load bundled authentic Bengaluru wards & zones GIS data
    try {
      final jsonStr = await rootBundle.loadString('assets/gis/bengaluru_wards_zones.json');
      final Map<String, dynamic> data = json.decode(jsonStr);
      if (data['zones'] != null) {
        zones = (data['zones'] as List).map((z) => Zone.fromJson(z['id'] ?? '', z as Map<String, dynamic>)).toList();
      }
      if (data['wards'] != null) {
        wards = (data['wards'] as List).map((w) => Ward.fromJson(w['id'] ?? '', w as Map<String, dynamic>)).toList();
      }
      notifier.value++;
      debugPrint('WardZoneService: Loaded ${zones.length} zones and ${wards.length} wards from bundled GIS assets');
    } catch (e) {
      debugPrint('WardZoneService: Bundled GIS load note: $e');
    }

    // 2. Real-time Firestore sync (listens for custom routes, checkpoints, and admin edits)
    try {
      FirebaseFirestore.instance.collection('zones').snapshots().listen((snap) {
        if (snap.docs.isNotEmpty) {
          final firestoreZones = snap.docs.map((d) => Zone.fromJson(d.id, d.data())).toList();
          if (firestoreZones.length >= 8) {
            zones = firestoreZones;
          } else {
            final existingNames = zones.map((z) => z.name.trim().toLowerCase()).toSet();
            for (var fz in firestoreZones) {
              if (!existingNames.contains(fz.name.trim().toLowerCase())) {
                zones.add(fz);
              }
            }
          }
          notifier.value++;
        }
      });

      FirebaseFirestore.instance.collection('wards').snapshots().listen((snap) {
        if (snap.docs.isNotEmpty) {
          final firestoreWards = snap.docs.map((d) => Ward.fromJson(d.id, d.data())).toList();
          if (firestoreWards.length >= 198) {
            wards = firestoreWards;
          } else {
            final Map<String, Ward> wardMap = {for (var w in wards) w.name.toLowerCase(): w};
            for (var fw in firestoreWards) {
              final key = fw.name.toLowerCase();
              if (wardMap.containsKey(key)) {
                final existing = wardMap[key]!;
                existing.checkpoints = fw.checkpoints ?? existing.checkpoints;
                existing.optimizedRoute = fw.optimizedRoute ?? existing.optimizedRoute;
                existing.routeDistanceKm = fw.routeDistanceKm ?? existing.routeDistanceKm;
              } else {
                wards.add(fw);
              }
            }
          }
          notifier.value++;
        }
      });
    } catch (e) {
      debugPrint('WardZoneService: Firestore sync note: $e');
    }

    // 3. Listen to TrashSpotsService for real-time flag counts
    try {
      TrashSpotsService.instance.flagsNotifier.addListener(() {
        _cachedZoneCounts = null;
        _cachedWardCounts = null;
        notifier.value++;
      });
    } catch (e) {
      debugPrint('WardZoneService: Flag listener note: $e');
    }
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
    if (ward.zone != null && ward.zone!.isNotEmpty) {
      final wz = ward.zone!.trim().toLowerCase();
      final zn = zone.name.trim().toLowerCase();
      if (wz == zn || wz.contains(zn) || zn.contains(wz)) return true;
    }
    if (ward.boundary.isEmpty || zone.boundary.isEmpty) return true;
    final centroid = ward.centroid ?? computeCentroid(ward.boundary);

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
    final pLat = point.latitude;
    final pLng = point.longitude;
    for (var w in wards) {
      // Instant Bounding-Box spatial filter (4 float comparisons)
      if (pLat < w.minLat || pLat > w.maxLat || pLng < w.minLng || pLng > w.maxLng) {
        continue;
      }
      if (isPointInPolygon(point, w.boundary)) return w;
    }
    return null;
  }

  Zone? findZoneForPoint(LatLng point) {
    final pLat = point.latitude;
    final pLng = point.longitude;
    for (var z in zones) {
      // Instant Bounding-Box spatial filter
      if (pLat < z.minLat || pLat > z.maxLat || pLng < z.minLng || pLng > z.maxLng) {
        continue;
      }
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
    if (matchedZone == null) {
      final matching = wards.where((w) {
        final wz = (w.zone ?? '').trim().toLowerCase();
        return wz == zClean || wz.contains(zClean) || zClean.contains(wz);
      }).map((w) => w.name).toList();
      return matching.isNotEmpty ? matching : wards.map((w) => w.name).toList();
    }
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
    if (lat != 0.0 && lng != 0.0) {
      final pt = LatLng(lat, lng);
      for (var z in zones) {
        final zName = z.name.trim().toLowerCase();
        if (zName == tClean || zName.contains(tClean) || tClean.contains(zName)) {
          if (lat >= z.minLat && lat <= z.maxLat && lng >= z.minLng && lng <= z.maxLng) {
            if (isPointInPolygon(pt, z.boundary)) return true;
          }
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
    if (lat != 0.0 && lng != 0.0) {
      final pt = LatLng(lat, lng);
      for (var w in wards) {
        final wName = w.name.trim().toLowerCase().replaceAll(' ', '');
        if (wName == tClean || wName.contains(tClean) || tClean.contains(wName)) {
          if (lat >= w.minLat && lat <= w.maxLat && lng >= w.minLng && lng <= w.maxLng) {
            if (isPointInPolygon(pt, w.boundary)) return true;
          }
        }
      }
    }
    return false;
  }

  List<Polygon>? _cachedBasePolygons;
  String? _lastSelectedZone;
  String? _lastSelectedWard;
  bool? _lastShowWards;
  int _lastBasePolygonNotifier = -1;

  List<Polygon> buildPolygons({String? selectedZone, String? selectedWard, double? zoom}) {
    final hasSpecificZone = selectedZone != null && selectedZone != 'All Zones' && selectedZone.trim().isNotEmpty;
    final hasSpecificWard = selectedWard != null && selectedWard != 'All Wards' && selectedWard.trim().isNotEmpty;
    final showWards = (zoom != null && zoom >= wardZoomThreshold) || hasSpecificZone || hasSpecificWard;

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

    // Determine if base polygons need recreation
    if (_cachedBasePolygons == null ||
        _lastSelectedZone != selectedZone ||
        _lastSelectedWard != selectedWard ||
        _lastShowWards != showWards ||
        _lastBasePolygonNotifier != notifier.value) {
      _lastSelectedZone = selectedZone;
      _lastSelectedWard = selectedWard;
      _lastShowWards = showWards;
      _lastBasePolygonNotifier = notifier.value;

      final List<Polygon> base = [];

      // 1. Zone Polygons
      if (!showWards) {
        for (var z in zones.where((z) => z.boundary.length >= 3)) {
          final isSelected = hasSpecificZone && (matchedZone?.id == z.id || z.name.trim().toLowerCase() == selectedZone.trim().toLowerCase());
          final zoneColor = getZoneSeverityColor(z.name);
          final borderColor = getZoneBorderColor(z.name);

          base.add(
            Polygon(
              points: z.boundary,
              color: zoneColor.withValues(alpha: isSelected ? 0.38 : 0.20),
              borderColor: borderColor,
              borderStrokeWidth: isSelected ? 3.5 : 2.0,
            ),
          );
        }
      }

      // 2. Ward Polygons
      if (showWards) {
        for (var w in wards.where((w) => w.boundary.length >= 3)) {
          if (matchedZone != null && !isWardInZone(w, matchedZone)) continue;

          final isSelected = hasSpecificWard && (
            w.name.trim().toLowerCase() == selectedWard.trim().toLowerCase() ||
            w.name.trim().toLowerCase().replaceAll(' ', '') == selectedWard.trim().toLowerCase().replaceAll(' ', '')
          );
          final wardColor = getWardSeverityColor(w.name);
          final borderColor = getWardBorderColor(w.name);

          base.add(
            Polygon(
              points: w.boundary,
              color: wardColor.withValues(alpha: isSelected ? 0.42 : 0.22),
              borderColor: borderColor,
              borderStrokeWidth: isSelected ? 3.0 : 1.4,
            ),
          );
        }
      }

      _cachedBasePolygons = base;
    }

    Polygon? highlightedPolygon;
    if (hoveredZone != null && !showWards) {
      final zoneColor = getZoneSeverityColor(hoveredZone!.name);
      highlightedPolygon = Polygon(
        points: hoveredZone!.boundary,
        color: zoneColor.withValues(alpha: 0.45),
        borderColor: zoneColor,
        borderStrokeWidth: 4.5,
      );
    } else if (hoveredWard != null && showWards) {
      final wardColor = getWardSeverityColor(hoveredWard!.name);
      highlightedPolygon = Polygon(
        points: hoveredWard!.boundary,
        color: wardColor.withValues(alpha: 0.50),
        borderColor: wardColor,
        borderStrokeWidth: 4.5,
      );
    }

    if (highlightedPolygon != null) {
      return [...?_cachedBasePolygons, highlightedPolygon];
    }
    return _cachedBasePolygons ?? [];
  }

  List<Marker> buildMarkers({String? selectedZone, String? selectedWard, double? zoom, LatLngBounds? bounds}) {
    final hasSpecificZone = selectedZone != null && selectedZone != 'All Zones' && selectedZone.trim().isNotEmpty;
    final hasSpecificWard = selectedWard != null && selectedWard != 'All Wards' && selectedWard.trim().isNotEmpty;
    final showWards = (zoom != null && zoom >= wardZoomThreshold) || hasSpecificZone || hasSpecificWard;

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
    Marker? highlightedMarker;

    // When zoomed out, show Zone Labels with severity indicators
    if (!showWards) {
      for (var z in zones.where((z) => z.boundary.length >= 3)) {
        final centroid = z.centroid ?? computeCentroid(z.boundary);
        if (bounds != null && !bounds.contains(centroid)) continue;

        final count = getZoneFlagCount(z.name);
        final zoneColor = getZoneSeverityColor(z.name);
        final isHovered = (hoveredZone != null && (hoveredZone!.id == z.id || hoveredZone!.name.trim().toLowerCase() == z.name.trim().toLowerCase()));

        final String statusText;
        if (count >= 70) {
          statusText = 'Critical Hotspot';
        } else if (count >= 35) {
          statusText = 'Moderate';
        } else {
          statusText = 'Clean Zone';
        }

        if (isHovered) {
          highlightedMarker = Marker(
            point: centroid,
            width: 200,
            height: 60,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0F172A),
                      zoneColor.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: zoneColor, width: 2.5),
                  boxShadow: [
                    BoxShadow(color: zoneColor.withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 2, offset: const Offset(0, 3)),
                    const BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${z.name.toUpperCase()} ZONE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: zoneColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$count Flags • $statusText',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          labels.add(
            Marker(
              point: centroid,
              width: 160,
              height: 48,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: zoneColor, width: 2.0),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        z.name,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: zoneColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$count Flags',
                          style: TextStyle(
                            color: zoneColor == const Color(0xFFFACC15) ? const Color(0xFFB45309) : zoneColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    // When zoomed in, show Ward Labels with severity badges
    if (showWards) {
      for (var w in wards.where((w) => w.boundary.length >= 3)) {
        if (matchedZone != null && !isWardInZone(w, matchedZone)) continue;

        final centroid = w.centroid ?? computeCentroid(w.boundary);
        if (bounds != null && !bounds.contains(centroid)) continue;

        final count = getWardFlagCount(w.name);
        final wardColor = getWardSeverityColor(w.name);
        final isHovered = (hoveredWard != null && (hoveredWard!.id == w.id || hoveredWard!.name.trim().toLowerCase() == w.name.trim().toLowerCase()));

        final String statusLabel;
        if (count >= 8) {
          statusLabel = 'Hotspot';
        } else if (count >= 4) {
          statusLabel = 'Moderate';
        } else {
          statusLabel = 'Clean';
        }

        if (isHovered) {
          highlightedMarker = Marker(
            point: centroid,
            width: 190,
            height: 56,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0F172A),
                      wardColor.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: wardColor, width: 2.5),
                  boxShadow: [
                    BoxShadow(color: wardColor.withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 3, offset: const Offset(0, 3)),
                    const BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '📍 ${w.name}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$count Flags • $statusLabel',
                      style: TextStyle(
                        color: count >= 8 ? const Color(0xFFFCA5A5) : (count >= 4 ? const Color(0xFFFDBA74) : const Color(0xFF6EE7B7)),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          labels.add(
            Marker(
              point: centroid,
              width: 140,
              height: 44,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: wardColor, width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        w.name,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: wardColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$count Flags',
                            style: TextStyle(
                              color: wardColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    if (highlightedMarker != null) {
      labels.add(highlightedMarker);
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
      // 1. Reactive Polygons & Markers wrapped in hover and update listener
      Builder(
        builder: (context) {
          final camera = MapCamera.of(context);
          return ListenableBuilder(
            listenable: Listenable.merge([hoverNotifier, notifier]),
            builder: (context, child) {
              final polys = buildPolygons(selectedZone: selectedZone, selectedWard: selectedWard, zoom: camera.zoom);
              return PolygonLayer(polygons: polys);
            },
          );
        },
      ),
      Builder(
        builder: (context) {
          final camera = MapCamera.of(context);
          return ListenableBuilder(
            listenable: Listenable.merge([hoverNotifier, notifier]),
            builder: (context, child) {
              final marks = buildMarkers(
                selectedZone: selectedZone,
                selectedWard: selectedWard,
                zoom: camera.zoom,
                bounds: camera.visibleBounds,
              );
              return MarkerLayer(markers: marks);
            },
          );
        },
      ),

      // 2. Translucent Cursor & Touch Detector Layer
      Builder(
        builder: (context) {
          final camera = MapCamera.of(context);
          return SizedBox.expand(
            child: MouseRegion(
              hitTestBehavior: HitTestBehavior.translucent,
              onHover: (event) {
                final latLng = camera.screenOffsetToLatLng(event.localPosition);
                handleHover(latLng, zoom: camera.zoom);
              },
              onExit: (_) {
                clearHover();
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) {
                  final latLng = camera.screenOffsetToLatLng(details.localPosition);
                  handleHover(latLng, zoom: camera.zoom);
                },
                onDoubleTapDown: (details) {
                  final latLng = camera.screenOffsetToLatLng(details.localPosition);
                  Ward? targetWard = findWardForPoint(latLng);
                  if (targetWard == null) {
                    final targetZone = findZoneForPoint(latLng);
                    if (targetZone != null) {
                      try {
                        targetWard = wards.firstWhere(
                          (w) => (w.zone ?? '').toLowerCase() == targetZone.name.toLowerCase(),
                        );
                      } catch (_) {
                        targetWard = Ward(
                          id: targetZone.id,
                          name: '${targetZone.name} Zone HQ',
                          boundary: targetZone.boundary,
                          zone: targetZone.name,
                        );
                      }
                    }
                  }
                  if (targetWard != null) {
                    Ward3dHierarchyModal.show(context, targetWard);
                  }
                },
              ),
            ),
          );
        },
      ),

      // 3. Floating Highlight HUD Card at Top Center
      Builder(
        builder: (context) {
          return ValueListenableBuilder<int>(
            valueListenable: hoverNotifier,
            builder: (context, value, child) {
              if (hoveredWard == null && hoveredZone == null) {
                return const SizedBox.shrink();
              }
              final isWard = hoveredWard != null;
              final title = isWard ? hoveredWard!.name : '${hoveredZone!.name} Zone';
              final subtitle = isWard
                  ? (hoveredWard!.zone != null ? 'Zone: ${hoveredWard!.zone}' : 'BBMP Ward')
                  : 'BBMP Official Administrative Zone';

              return Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14, left: 20, right: 20),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () {
                        Ward? target = hoveredWard;
                        if (target == null && hoveredZone != null) {
                          try {
                            target = wards.firstWhere(
                              (w) => (w.zone ?? '').toLowerCase() == hoveredZone!.name.toLowerCase(),
                            );
                          } catch (_) {
                            target = Ward(
                              id: hoveredZone!.id,
                              name: '${hoveredZone!.name} Zone HQ',
                              boundary: hoveredZone!.boundary,
                              zone: hoveredZone!.name,
                            );
                          }
                        }
                        if (target != null) {
                          Ward3dHierarchyModal.show(context, target);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101928).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: isWard ? const Color(0xFF00E5FF) : const Color(0xFF00E676),
                            width: 2.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isWard ? const Color(0x6600B0FF) : const Color(0x6600E676),
                              blurRadius: 16,
                              spreadRadius: 2,
                              offset: const Offset(0, 4),
                            ),
                            const BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 6)),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isWard
                                    ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                                    : const Color(0xFF00E676).withValues(alpha: 0.2),
                              ),
                              child: Icon(
                                isWard ? Icons.apartment_rounded : Icons.map_rounded,
                                color: isWard ? const Color(0xFF00E5FF) : const Color(0xFF00E676),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                            letterSpacing: 0.3,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: isWard ? const Color(0x3300E5FF) : const Color(0x3300E676),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isWard ? const Color(0xFF00E5FF) : const Color(0xFF00E676),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.view_in_ar_rounded, size: 11, color: Colors.white),
                                            SizedBox(width: 4),
                                            Text(
                                              '3D Ward & Leadership Tree ↗',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 9.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '$subtitle • Double-click map or tap to view officials',
                                    style: TextStyle(
                                      color: isWard ? const Color(0xFF80D8FF) : const Color(0xFFB9F6CA),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ];
  }
}
