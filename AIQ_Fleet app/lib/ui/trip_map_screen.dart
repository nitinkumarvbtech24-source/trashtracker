import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/ward_zone_service.dart';
import '../constants.dart';
import '../widgets/trash_pinpoint_marker.dart';

class TrailSegment {
  final LatLng start;
  final LatLng end;
  final Color color;
  TrailSegment({required this.start, required this.end, required this.color});

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

  /// Combines consecutive segments into continuous, smooth road polylines
  static List<Polyline> toSmoothPolylines(List<TrailSegment> segments, {double strokeWidth = 6.0}) {
    if (segments.isEmpty) return [];
    List<Polyline> polylines = [];
    List<LatLng> currentPoints = [];
    Color? currentColor;

    for (var seg in segments) {
      final dist = const Distance().as(LengthUnit.Meter, seg.start, seg.end);
      // Discard stationary micro-jitter (< 2m) and cross-town jumps (> 80m)
      if (dist < 2.0 || dist > 80.0) continue;

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
}

class TripMapScreen extends StatefulWidget {
  final String vehicleNo;
  final String date;
  final DateTime? startTime;
  final DateTime? endTime;

  const TripMapScreen({
    super.key,
    required this.vehicleNo,
    required this.date,
    this.startTime,
    this.endTime,
  });

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends State<TripMapScreen> {
  final MapController _mapController = MapController();
  List<TrailSegment> _trail = [];
  List<Polyline> _cachedPolylines = [];
  List<Marker> _cachedMarkers = [];
  List<Map<String, dynamic>> _trashSpots = [];
  bool _isLoading = true;
  double _currentZoom = 13.0;

  @override
  void initState() {
    super.initState();
    _fetchTripData();
  }

  Future<void> _fetchTripData() async {
    try {
      // Fetch Trail
      final doc = await FirebaseFirestore.instance
          .collection('vehicles')
          .doc(widget.vehicleNo)
          .collection('daily_stats')
          .doc(widget.date)
          .get();

      if (doc.exists && doc.data() != null && doc.data()!['trail'] != null) {
        final trailList = doc.data()!['trail'] as List;
        _trail = trailList.map((e) => TrailSegment.fromJson(e)).toList();
      }

      // Fetch Trash Spots (flags)
      final spotsSnapshot = await FirebaseFirestore.instance
          .collection('trash_spots')
          .where('vehicle_number', isEqualTo: widget.vehicleNo)
          .get();

      final List<Map<String, dynamic>> filteredSpots = [];
      for (var spotDoc in spotsSnapshot.docs) {
        final data = spotDoc.data();
        if (data['status'] == 'Resolved' || data['status'] == 'Deflagged') continue; 
        
        // Filter by active model version
        final mv = data['model_version'] ?? data['modelVersion'];
        if (mv == null) continue;
        final s = mv.toString().toLowerCase().trim();
        if (s != MODEL_VERSION.toString() && s != 'v$MODEL_VERSION' && !(MODEL_VERSION == 7 && (s.contains('7') || s.contains('mobilenet')))) continue;

        // Filter by timestamp range for this specific trip
        if (data['timestamp'] != null) {
          final spotTime = (data['timestamp'] as Timestamp).toDate();
          if (widget.startTime != null && spotTime.isBefore(widget.startTime!)) continue;
          if (widget.endTime != null && spotTime.isAfter(widget.endTime!)) continue;
        }

        // Only flag actual trash detections
        final roadStatus = (data['road_status'] ?? '').toString().toLowerCase().trim();
        final displayClass = (data['display_class'] ?? '').toString().toLowerCase().trim();
        final className = (data['class'] ?? '').toString().toLowerCase().trim();

        if (roadStatus.contains('no trash') || roadStatus.contains('no_trash') || roadStatus.contains('clean') || roadStatus.contains('not a road') ||
            displayClass.contains('no trash') || displayClass.contains('no_trash') || displayClass.contains('clean') || displayClass.contains('not a road') ||
            className.contains('no trash') || className.contains('no_trash') || className.contains('clean') || className.contains('not a road')) {
          continue;
        }

        final trashCount = (data['trash_count'] as num?)?.toInt();
        if (trashCount != null && trashCount <= 0 && !roadStatus.contains('dirty') && !displayClass.contains('dirty') && !className.contains('dirty')) {
          continue;
        }

        final isTrash = roadStatus.contains('trash') || roadStatus.contains('dirty') ||
            displayClass.contains('trash') || displayClass.contains('dirty') ||
            className.contains('trash') || className.contains('dirty') ||
            (trashCount != null && trashCount > 0);

        if (!isTrash) continue;

        data['id'] = spotDoc.id;
        filteredSpots.add(data);
      }
      _trashSpots = filteredSpots;

    } catch (e) {
      debugPrint("Error fetching trip data: $e");
    } finally {
      if (mounted) {
        _cachedPolylines = _trail.isNotEmpty ? TrailSegment.toSmoothPolylines(_trail) : [];
        _cachedMarkers = _trashSpots.map((spot) {
          final lat = spot['lat'] as double;
          final lng = spot['lng'] as double;
          final isVeryDirty = spot['road_status'] == 'Very Dirty Road' || spot['road_status'] == 'Very_Dirty';
          
          return Marker(
            point: LatLng(lat, lng),
            width: 38,
            height: 46,
            alignment: Alignment.topCenter,
            child: TrashPinpointWidget(
              isVeryDirty: isVeryDirty,
              onTap: () => _showTrashPopup(spot),
            ),
          );
        }).toList();

        setState(() {
          _isLoading = false;
        });
        _fitMap();
      }
    }
  }

  void _fitMap() {
    if (_trail.isNotEmpty) {
      _mapController.move(_trail.first.start, 15.0);
    } else if (_trashSpots.isNotEmpty) {
      final lat = _trashSpots.first['lat'] as double;
      final lng = _trashSpots.first['lng'] as double;
      _mapController.move(LatLng(lat, lng), 15.0);
    }
  }

  void _showTrashPopup(Map<String, dynamic> spot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          spot['road_status'] ?? 'Dirty Spot',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spot['image_url'] != null)
              Builder(
                builder: (context) {
                  String displayUrl = spot['image_url'];
                  if (displayUrl.startsWith('http')) {
                    try {
                      final uri = Uri.parse(displayUrl);
                      if (uri.host.contains('ngrok-free.dev')) {
                        displayUrl = '$activeGarbageAiUrl${uri.path}';
                      }
                    } catch (_) {}
                  } else if (displayUrl.startsWith('/')) {
                    displayUrl = '$activeGarbageAiUrl$displayUrl';
                  } else {
                    displayUrl = '$activeGarbageAiUrl/$displayUrl';
                  }
                  
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 400,
                      child: Image.network(
                        displayUrl,
                        headers: const {"ngrok-skip-browser-warning": "true"},
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 200,
                            color: Colors.black26,
                            child: const Center(
                              child: Icon(Icons.image_not_supported, color: Colors.white24, size: 50),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }
              ),
            const SizedBox(height: 16),
            Text(
              "Confidence: ${((spot['confidence'] ?? 0.0) * 100).toStringAsFixed(1)}%",
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('Trip Map - ${widget.date}', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF111827),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(12.9716, 77.5946),
                initialZoom: 13.0,
                onPositionChanged: (camera, hasGesture) {
                  if ((camera.zoom >= 15.0) != (_currentZoom >= 15.0)) {
                    setState(() {
                      _currentZoom = camera.zoom;
                    });
                  }
                },
                onPointerHover: (event, point) => WardZoneService.instance.handleHover(point, zoom: _mapController.camera.zoom),
                onTap: (tapPosition, point) => WardZoneService.instance.handleHover(point, zoom: _mapController.camera.zoom),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.nitin.trashtracker',
                ),
                ...WardZoneService.instance.buildLayers(),
                if (_cachedPolylines.isNotEmpty)
                  PolylineLayer(
                    polylines: _cachedPolylines,
                  ),
                Builder(
                  builder: (context) {
                    final camera = MapCamera.of(context);
                    final bool showPins = camera.zoom >= 14.8;
                    if (!showPins || _cachedMarkers.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return MarkerLayer(
                      markers: _cachedMarkers,
                    );
                  },
                ),
              ],
            ),
    );
  }
}
