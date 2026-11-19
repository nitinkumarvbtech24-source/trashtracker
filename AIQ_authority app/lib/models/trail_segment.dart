import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

class TrailSegment {
  final LatLng start;
  final LatLng end;
  final Color color;

  TrailSegment({
    required this.start,
    required this.end,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
    'startLat': start.latitude,
    'startLng': start.longitude,
    'endLat': end.latitude,
    'endLng': end.longitude,
    'color': color.value,
  };

  factory TrailSegment.fromJson(Map<String, dynamic> json) => TrailSegment(
    start: LatLng(
      ((json['startLat'] ?? json['start_lat'] ?? 0.0) as num).toDouble(),
      ((json['startLng'] ?? json['start_lng'] ?? 0.0) as num).toDouble(),
    ),
    end: LatLng(
      ((json['endLat'] ?? json['end_lat'] ?? 0.0) as num).toDouble(),
      ((json['endLng'] ?? json['end_lng'] ?? 0.0) as num).toDouble(),
    ),
    color: Color((json['color'] as num?)?.toInt() ?? 0xFF00E676),
  );

  Polyline toPolyline({double strokeWidth = 5.5}) {
    return Polyline(
      points: [start, end],
      color: color,
      strokeWidth: strokeWidth,
      borderColor: Colors.black26,
      borderStrokeWidth: 1.0,
    );
  }

  /// Combines a list of TrailSegments into continuous, smooth road polylines
  static List<Polyline> toSmoothPolylines(List<TrailSegment> segments, {double strokeWidth = 5.5}) {
    if (segments.isEmpty) return [];
    List<Polyline> polylines = [];
    List<LatLng> currentPoints = [];
    Color? currentColor;

    for (var seg in segments) {
      final dist = const Distance().as(LengthUnit.Meter, seg.start, seg.end);
      // Discard stationary micro-jitter (< 2.5m) and cross-town jumps (> 80m)
      if (dist < 2.5 || dist > 80.0) continue;

      if (currentColor == null ||
          seg.color.value != currentColor.value ||
          (currentPoints.isNotEmpty && const Distance().as(LengthUnit.Meter, currentPoints.last, seg.start) > 20.0)) {
        if (currentPoints.length >= 2 && currentColor != null) {
          polylines.add(Polyline(
            points: List<LatLng>.from(currentPoints),
            color: currentColor,
            strokeWidth: strokeWidth,
            borderColor: Colors.black26,
            borderStrokeWidth: 1.0,
          ));
        }
        currentPoints = [seg.start, seg.end];
        currentColor = seg.color;
      } else {
        currentPoints.add(seg.end);
      }
    }

    if (currentPoints.length >= 2 && currentColor != null) {
      polylines.add(Polyline(
        points: List<LatLng>.from(currentPoints),
        color: currentColor,
        strokeWidth: strokeWidth,
        borderColor: Colors.black26,
        borderStrokeWidth: 1.0,
      ));
    }

    return polylines;
  }

  /// Converts a raw route list or trail list from Firestore daily_stats into smooth Polylines
  static List<Polyline> listFromDailyStats(Map<String, dynamic>? data) {
    if (data == null) return [];
    List<TrailSegment> rawSegments = [];

    // 1. If 'trail' array exists, parse segments
    if (data['trail'] != null && data['trail'] is List) {
      final list = data['trail'] as List;
      for (var item in list) {
        if (item is Map) {
          rawSegments.add(TrailSegment.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    // 2. Fallback to 'route' coordinate points
    if (rawSegments.isEmpty && data['route'] != null && data['route'] is List) {
      final list = data['route'] as List;
      List<Map<String, dynamic>> points = [];
      for (var item in list) {
        if (item is Map) {
          points.add(Map<String, dynamic>.from(item));
        }
      }
      for (int i = 0; i < points.length - 1; i++) {
        final start = LatLng(
          (points[i]['lat'] as num).toDouble(),
          (points[i]['lng'] as num).toDouble(),
        );
        final end = LatLng(
          (points[i + 1]['lat'] as num).toDouble(),
          (points[i + 1]['lng'] as num).toDouble(),
        );
        final colVal = (points[i + 1]['color'] as num?)?.toInt() ?? 0xFF00E676;
        rawSegments.add(TrailSegment(start: start, end: end, color: Color(colVal)));
      }
    }

    return toSmoothPolylines(rawSegments);
  }
}
