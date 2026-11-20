import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/telemetry_service.dart';
import '../services/auth_service.dart';
import '../services/ai_estimation_service.dart';
import '../services/camera_service.dart';
import '../services/ward_zone_service.dart';
import '../constants.dart';
import 'route_assigner_screen.dart';
import '../widgets/trash_pinpoint_marker.dart';
import '../models/garbage_flag.dart';
import '../widgets/trash_flag_inspection_modal.dart';
import '../widgets/placeholder_map_switch.dart';

class TrailSegment {
  final LatLng start;
  final LatLng end;
  final Color color;
  TrailSegment({required this.start, required this.end, required this.color});

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

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  bool _isNavigating = false;
  bool _isFollowingUser = false;
  List<LatLng> _assignedRoute = [];
  List<LatLng> _assignedCheckpoints = [];
  StreamSubscription<DocumentSnapshot>? _routeSub;
  String get _todayDateString => DateTime.now().toIso8601String().split('T')[0];

  // Trail state
  List<TrailSegment> _navigationTrail = [];
  LatLng? _lastRecordedPosition;

  // Tracking state
  int? _activeCheckpointIndex;
  DateTime? _arrivalTime;
  final double _arrivalThresholdMeters = 50.0;
  LatLng? _lastKnownPosition;
  Set<int> _completedCheckpoints = {};
  
  List<Map<String, dynamic>> _trashSpots = [];
  StreamSubscription<QuerySnapshot>? _trashSub;
  bool _showFlags = true;
  bool _showPlaceholders = true;
  bool _isZoomedInForFlags = false; // Zoom >= 16.5

  Map<String, Map<String, dynamic>> _liveOtherVehicles = {};
  StreamSubscription<QuerySnapshot>? _liveTrackingSub;

  List<Map<String, dynamic>> get _filteredTrashSpots {
    if (_showPlaceholders) return _trashSpots;
    return _trashSpots.where((s) {
      final isPlaceholder = s['is_placeholder'] == true;
      final isReal = s['is_real'] == true || s['is_placeholder'] == false;
      return !isPlaceholder && isReal;
    }).toList();
  }

  int get _realFlagsCount => _trashSpots.where((s) {
    return s['is_placeholder'] != true && (s['is_real'] == true || s['is_placeholder'] == false);
  }).length;

  bool _allowRouteAssignment = false;
  StreamSubscription<DocumentSnapshot>? _permissionsSub;

  bool _showSnapAnimation = false;

  void _triggerSnapAnimation() {
    if (!mounted) return;
    setState(() => _showSnapAnimation = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _showSnapAnimation = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _startRouteSync();
    _startLiveTrackingListener();
    
    // Listen to location updates to draw the trail
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TelemetryService>().addListener(_onLocationUpdate);
    });
  }

  void _startLiveTrackingListener() {
    _liveTrackingSub = FirebaseFirestore.instance.collection('live_tracking').snapshots().listen((snap) {
      if (!mounted) return;
      final auth = context.read<AuthService>();
      final myVeh = (auth.vehicleNumber ?? '').toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
      final Map<String, Map<String, dynamic>> map = {};
      for (var doc in snap.docs) {
        final cleanId = doc.id.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
        if (cleanId.isNotEmpty && cleanId == myVeh) continue; // Don't duplicate self
        map[doc.id] = doc.data();
      }
      setState(() => _liveOtherVehicles = map);
    });
  }

  void _onLocationUpdate() {
    // Only trace road when navigation is actively running
    if (!mounted || !_isNavigating) return;
    
    final telemetry = context.read<TelemetryService>();
    final currentPos = telemetry.currentPosition;
    
    if (currentPos != null) {
      // 1. Accuracy Filter: reject positions with > 18m uncertainty (prevents jumping into buildings)
      if (currentPos.accuracy > 18.0) return;

      final currentLoc = LatLng(currentPos.latitude, currentPos.longitude);
      
      if (_lastRecordedPosition != null) {
        final distance = const Distance().as(LengthUnit.Meter, _lastRecordedPosition!, currentLoc);
        
        // 2. Stationary / Idle Jitter Filter:
        // When vehicle is stopped/crawling (< 0.6 m/s) and moved < 6m, skip to prevent knots & triangles
        final isStationary = currentPos.speed < 0.6;
        if (isStationary && distance < 6.0) return;

        // Ignore tiny jitter
        if (distance < 3.5) return;

        // Protection against GPS jumps/teleports: do not draw straight line across town
        if (distance > 80.0) {
          _lastRecordedPosition = currentLoc;
          return;
        }

        final cameraService = context.read<CameraService>();

        // Road tracing condition color mapping:
        // - Very dirty road / Pothole detected: Vibrant Red (0xFFFF1744)
        // - Trash detected / Slightly dirty / Bad road: Vibrant Orange/Amber (0xFFFF9100)
        // - Clean road / No trash detected: Vibrant Green (0xFF00E676)
        final gStatus = cameraService.latestRoadStatus.toLowerCase().trim();
        final hStatus = cameraService.latestHealthStatus.toLowerCase().trim();
        
        final isClean = (gStatus.contains('clean') || gStatus.contains('no trash') || gStatus.contains('no_trash') || gStatus == 'unknown' || gStatus.isEmpty) &&
                        (hStatus.contains('good') || hStatus == 'unknown' || hStatus.isEmpty);

        Color segmentColor = const Color(0xFF00E676); // Clean Green
        if (gStatus.contains('very dirty') || gStatus.contains('very_dirty') || hStatus.contains('pothole')) {
          segmentColor = const Color(0xFFFF1744); // Critical Red
        } else if (!isClean && (gStatus.contains('trash') || gStatus.contains('dirty') || hStatus.contains('bad road') || hStatus.contains('bad_road'))) {
          segmentColor = const Color(0xFFFF9100); // Warning Amber/Orange
        }

        final start = _lastRecordedPosition!;
        final end = currentLoc;
        _lastRecordedPosition = currentLoc;

        _recordTrailSegment(start, end, segmentColor);
      } else {
        _lastRecordedPosition = currentLoc;
      }
    }
  }

  void _recordTrailSegment(LatLng start, LatLng end, Color color) {
    if (!mounted) return;
    final seg = TrailSegment(start: start, end: end, color: color);
    setState(() {
      _navigationTrail.add(seg);
    });

    final authService = context.read<AuthService>();
    final vehicleNo = authService.vehicleNumber;
    if (vehicleNo != null && vehicleNo.isNotEmpty) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      FirebaseFirestore.instance.collection('vehicles').doc(vehicleNo)
        .collection('daily_stats').doc(_todayDateString)
        .set({
          'trail': FieldValue.arrayUnion([seg.toJson()]),
          'route': FieldValue.arrayUnion([{
            'lat': end.latitude,
            'lng': end.longitude,
            'timestamp': nowMs,
            'color': color.value,
          }]),
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((_) {});

      final cameraService = context.read<CameraService>();
      FirebaseFirestore.instance.collection('live_tracking').doc(vehicleNo).set({
        'lat': end.latitude,
        'lng': end.longitude,
        'lastColor': color.value,
        'lastStatus': cameraService.latestRoadStatus,
        'isActive': true,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((_) {});
    }
  }

  Future<void> _clearTodayTrail() async {
    setState(() {
      _navigationTrail.clear();
      _lastRecordedPosition = null;
    });
    final authService = context.read<AuthService>();
    final vehicleNo = authService.vehicleNumber;
    if (vehicleNo != null && vehicleNo.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('vehicles').doc(vehicleNo)
          .collection('daily_stats').doc(_todayDateString)
          .set({
            'trail': [],
            'route': [],
            'distance_km': 0.0,
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Today's vehicle trail and route reset successfully!"),
              backgroundColor: Color(0xFF10B981),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint("Error resetting trail: $e");
      }
    }
  }


  void _startRouteSync() {
    final authService = context.read<AuthService>();
    final vehicleNo = authService.vehicleNumber;
    
    if (vehicleNo != null && vehicleNo.isNotEmpty) {
      // Load saved trail for today
      FirebaseFirestore.instance.collection('vehicles').doc(vehicleNo)
          .collection('daily_stats').doc(_todayDateString)
          .get().then((doc) {
            if (doc.exists && doc.data() != null && doc.data()!['trail'] != null) {
              final trailList = doc.data()!['trail'] as List;
              if (mounted) {
                setState(() {
                  _navigationTrail = trailList.map((e) => TrailSegment.fromJson(e)).toList();
                });
              }
            }
          }).catchError((_) {});

      _routeSub = FirebaseFirestore.instance
          .collection('vehicles')
          .doc(vehicleNo)
          .snapshots()
          .listen((doc) {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          if (mounted) {
            setState(() {
              if (data['assignedRoute'] != null) {
                final List<dynamic> rawRoute = data['assignedRoute'];
                _assignedRoute = rawRoute.map((e) => LatLng(e['lat'], e['lng'])).toList();
              } else {
                _assignedRoute = [];
              }
              if (data['assignedCheckpoints'] != null) {
                final List<dynamic> rawCheckpoints = data['assignedCheckpoints'];
                _assignedCheckpoints = rawCheckpoints.map((e) => LatLng(e['lat'], e['lng'])).toList();
              } else {
                _assignedCheckpoints = [];
              }
            });
          }
        }
      });
    }

    _trashSub = FirebaseFirestore.instance
        .collection('trash_spots')
        .where('status', isEqualTo: 'Flagged')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _trashSpots = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).where((spot) {
            final mv = spot['model_version'] ?? spot['modelVersion'];
            if (mv == null) return false;
            final s = mv.toString().toLowerCase().trim();
            final matchesModel = (mv == MODEL_VERSION || s == MODEL_VERSION.toString() || s == 'v$MODEL_VERSION' || (MODEL_VERSION == 7 && (s.contains('7') || s.contains('mobilenet'))));
            if (!matchesModel) return false;

            // Only flag actual trash detections
            final roadStatus = (spot['road_status'] ?? '').toString().toLowerCase().trim();
            final displayClass = (spot['display_class'] ?? '').toString().toLowerCase().trim();
            final className = (spot['class'] ?? '').toString().toLowerCase().trim();

            if (roadStatus.contains('no trash') || roadStatus.contains('no_trash') || roadStatus.contains('clean') || roadStatus.contains('not a road') ||
                displayClass.contains('no trash') || displayClass.contains('no_trash') || displayClass.contains('clean') || displayClass.contains('not a road') ||
                className.contains('no trash') || className.contains('no_trash') || className.contains('clean') || className.contains('not a road')) {
              return false;
            }

            final trashCount = (spot['trash_count'] as num?)?.toInt();
            if (trashCount != null && trashCount <= 0 && !roadStatus.contains('dirty') && !displayClass.contains('dirty') && !className.contains('dirty')) {
              return false;
            }

            return roadStatus.contains('trash') || roadStatus.contains('dirty') ||
                   displayClass.contains('trash') || displayClass.contains('dirty') ||
                   className.contains('trash') || className.contains('dirty') ||
                   (trashCount != null && trashCount > 0);
          }).toList();
        });
      }
    });

    _permissionsSub = FirebaseFirestore.instance
        .collection('settings')
        .doc('fleet_permissions')
        .snapshots()
        .listen((snapshot) {
      if (mounted && snapshot.exists && snapshot.data() != null) {
        setState(() {
          _allowRouteAssignment = snapshot.data()!['allowRouteAssignment'] ?? false;
        });
      }
    });
  }

  @override
  void dispose() {
    _routeSub?.cancel();
    _trashSub?.cancel();
    _permissionsSub?.cancel();
    _liveTrackingSub?.cancel();
    super.dispose();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }


  void _toggleNavigation(LatLng? currentLoc, double heading) {
    setState(() {
      _isNavigating = !_isNavigating;
      _isFollowingUser = _isNavigating;
      if (_isNavigating) {
        _lastRecordedPosition = currentLoc;
      } else {
        _lastRecordedPosition = null;
      }
    });
    
    // Update telemetry state so it syncs to Firebase
    context.read<TelemetryService>().setNavigating(_isNavigating);

    if (_isNavigating) {
      if (currentLoc != null) {
        _mapController.moveAndRotate(currentLoc, 18.0, heading);
      }
    } else {
      _mapController.rotate(0);
    }
  }

  void _centerOnCurrentLocation() {
    final currentPos = context.read<TelemetryService>().currentPosition;
    if (currentPos != null) {
      setState(() => _isFollowingUser = true);
      _mapController.move(LatLng(currentPos.latitude, currentPos.longitude), 18.0);
    }
  }

  void _checkGeofence(LatLng currentLoc) {
    if (_assignedCheckpoints.isEmpty) return;

    final distanceCalc = const Distance();
    
    for (int i = 0; i < _assignedCheckpoints.length; i++) {
      if (_completedCheckpoints.contains(i)) continue;

      final checkpoint = _assignedCheckpoints[i];
      final distance = distanceCalc.as(LengthUnit.Meter, currentLoc, checkpoint);

      if (distance <= _arrivalThresholdMeters) {
        if (_activeCheckpointIndex != i) {
          // Arrived at a new checkpoint
          _activeCheckpointIndex = i;
          _arrivalTime = DateTime.now();
          debugPrint("Arrived at checkpoint ${i + 1}");
        }
        return; // Currently at a checkpoint
      }
    }

    // If we get here, we are not within 50m of ANY active checkpoint.
    // Did we just leave a checkpoint?
    if (_activeCheckpointIndex != null && _arrivalTime != null) {
      final departureTime = DateTime.now();
      final waitDuration = departureTime.difference(_arrivalTime!);
      
      _recordStop(
        checkpointIndex: _activeCheckpointIndex!,
        arrivalTime: _arrivalTime!,
        departureTime: departureTime,
        waitDurationSeconds: waitDuration.inSeconds,
      );

      debugPrint("Left checkpoint ${_activeCheckpointIndex! + 1}. Waited for ${waitDuration.inSeconds} seconds.");
      
      _completedCheckpoints.add(_activeCheckpointIndex!);
      _activeCheckpointIndex = null;
      _arrivalTime = null;
    }
  }

  Future<void> _recordStop({
    required int checkpointIndex,
    required DateTime arrivalTime,
    required DateTime departureTime,
    required int waitDurationSeconds,
  }) async {
    final authService = context.read<AuthService>();
    final vehicleNo = authService.vehicleNumber;
    if (vehicleNo == null) return;

    try {
      await FirebaseFirestore.instance.collection('vehicles').doc(vehicleNo).collection('trip_reports').add({
        'checkpointIndex': checkpointIndex,
        'arrivalTime': arrivalTime.toIso8601String(),
        'departureTime': departureTime.toIso8601String(),
        'waitDurationSeconds': waitDurationSeconds,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error recording stop: $e");
    }
  }


  List<Marker> _buildUniformTrashMarkers(List<Map<String, dynamic>> spots) {
    const double clusterDist = 0.00018; // ~18-20 meters clustering to avoid clumping
    final List<List<Map<String, dynamic>>> clusters = [];

    for (var spot in spots) {
      final lat = (spot['lat'] as num?)?.toDouble() ?? 0.0;
      final lng = (spot['lng'] as num?)?.toDouble() ?? 0.0;
      if (lat == 0.0 && lng == 0.0) continue;

      bool added = false;
      for (var c in clusters) {
        final cLat = (c.first['lat'] as num).toDouble();
        final cLng = (c.first['lng'] as num).toDouble();
        if ((lat - cLat).abs() < clusterDist && (lng - cLng).abs() < clusterDist) {
          c.add(spot);
          added = true;
          break;
        }
      }
      if (!added) {
        clusters.add([spot]);
      }
    }

    return clusters.map((cluster) {
      final rep = cluster.first;
      final lat = (rep['lat'] as num).toDouble();
      final lng = (rep['lng'] as num).toDouble();
      final isVeryDirty = cluster.any((s) => s['road_status'] == 'Very Dirty Road' || s['road_status'] == 'Very_Dirty');

      return Marker(
        point: LatLng(lat, lng),
        width: 38,
        height: 46,
        alignment: Alignment.topCenter,
        child: TrashPinpointWidget(
          count: cluster.length,
          isVeryDirty: isVeryDirty,
          onTap: () {
            final flag = GarbageFlag.fromJson(rep, rep['id']?.toString() ?? '');
            TrashFlagInspectionModal.show(context, flag);
          },
        ),
      );
    }).toList();
  }

  List<Marker> _cachedFleetTrashMarkers = [];
  int _lastFleetTrashCount = -1;

  List<Marker> _getCachedUniformTrashMarkers(List<Map<String, dynamic>> spots) {
    if (_cachedFleetTrashMarkers.isNotEmpty && spots.length == _lastFleetTrashCount) {
      return _cachedFleetTrashMarkers;
    }
    _lastFleetTrashCount = spots.length;
    _cachedFleetTrashMarkers = _buildUniformTrashMarkers(spots);
    return _cachedFleetTrashMarkers;
  }

  List<Polyline> _cachedTrailPolylines = [];
  int _lastTrailLength = -1;

  List<Polyline> _getCachedTrailPolylines() {
    if (_cachedTrailPolylines.isNotEmpty && _navigationTrail.length == _lastTrailLength) {
      return _cachedTrailPolylines;
    }
    _lastTrailLength = _navigationTrail.length;
    _cachedTrailPolylines = TrailSegment.toSmoothPolylines(_navigationTrail);
    return _cachedTrailPolylines;
  }

  void _showAnalyticsPopup() {
    final telemetry = context.read<TelemetryService>();
    final camera = context.read<CameraService>();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.analytics_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Daily Analytics', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAnalyticRow(Icons.route, 'Total Distance:', '${telemetry.totalDistanceKm.toStringAsFixed(2)} km'),
            const SizedBox(height: 12),
            _buildAnalyticRow(Icons.camera_alt, 'Images Captured:', '${camera.imagesCapturedToday}'),
            const SizedBox(height: 12),
            _buildAnalyticRow(Icons.flag, 'Flagged Issues:', '${camera.imagesFlaggedToday}', color: Colors.redAccent),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticRow(IconData icon, String label, String value, {Color? color}) {
    return Row(
      children: [
        Icon(icon, color: color ?? Colors.white70, size: 20),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const Spacer(),
        Text(value, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final telemetry = context.watch<TelemetryService>();
    final currentPos = telemetry.currentPosition;
    final initialCenter = currentPos != null 
        ? LatLng(currentPos.latitude, currentPos.longitude) 
        : const LatLng(12.9716, 77.5946);
        
    final heading = currentPos?.heading ?? 0.0;
    String? etaText;
    int? nextCheckpointIndex;

    if (currentPos != null) {
      final currentLoc = LatLng(currentPos.latitude, currentPos.longitude);
      
      // Run geofencing check if position changed significantly
      if (_lastKnownPosition == null || const Distance().as(LengthUnit.Meter, _lastKnownPosition!, currentLoc) > 5) {
        _lastKnownPosition = currentLoc;
        _checkGeofence(currentLoc);
      }

      // Calculate ETA to next checkpoint if not currently at one
      if (_activeCheckpointIndex == null && _assignedCheckpoints.isNotEmpty) {
        for (int i = 0; i < _assignedCheckpoints.length; i++) {
          if (!_completedCheckpoints.contains(i)) {
            nextCheckpointIndex = i;
            break;
          }
        }

        if (nextCheckpointIndex != null) {
          final distance = const Distance().as(LengthUnit.Meter, currentLoc, _assignedCheckpoints[nextCheckpointIndex]);
          etaText = AIEstimationService().predictETA(
            distanceMeters: distance,
            currentSpeedMetersPerSec: currentPos.speed,
          );
        }
      }

      // Follow the user if navigating
      if (_isFollowingUser) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.moveAndRotate(currentLoc, 18.0, heading);
        });
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 15.0,
              onPointerHover: (event, point) => WardZoneService.instance.handleHover(point, zoom: _mapController.camera.zoom),
              onTap: (tapPosition, point) => WardZoneService.instance.handleHover(point, zoom: _mapController.camera.zoom),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && _isFollowingUser) {
                  setState(() => _isFollowingUser = false);
                }
                final isZoomedIn = position.zoom >= 15.0;
                if (_isZoomedInForFlags != isZoomedIn) {
                  setState(() => _isZoomedInForFlags = isZoomedIn);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nitin.trashtracker',
              ),
              ...WardZoneService.instance.buildLayers(),
              
              if (_assignedRoute.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _assignedRoute,
                      strokeWidth: 6,
                      color: Colors.blueAccent.withOpacity(0.5), // Make assigned route slightly transparent
                      borderStrokeWidth: 2,
                      borderColor: Colors.white.withOpacity(0.5),
                    ),
                  ],
                ),
                
              if (_navigationTrail.isNotEmpty)
                PolylineLayer(
                  polylines: _getCachedTrailPolylines(),
                ),

              if (_assignedCheckpoints.isNotEmpty)
                MarkerLayer(
                  markers: _assignedCheckpoints.asMap().entries.map((entry) {
                    final index = entry.key;
                    final point = entry.value;
                    final isActive = _activeCheckpointIndex == index;
                    final isCompleted = _completedCheckpoints.contains(index);
                    
                    Color markerColor = Colors.orangeAccent;
                    if (isActive) markerColor = Colors.greenAccent;
                    if (isCompleted) markerColor = Colors.grey;
                    
                    return Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: markerColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))
                          ]
                        ),
                        child: Center(
                          child: isCompleted 
                            ? const Icon(Icons.check, color: Colors.white, size: 20)
                            : Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                
              Builder(
                builder: (context) {
                  final camera = MapCamera.of(context);
                  final bool showPins = _showFlags && (camera.zoom >= 14.8);
                  final spotsToDisplay = _filteredTrashSpots;
                  if (!showPins || spotsToDisplay.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return MarkerLayer(
                    markers: _getCachedUniformTrashMarkers(spotsToDisplay),
                  );
                },
              ),

              // Live Other Fleet Vehicles Layer
              MarkerLayer(
                markers: _liveOtherVehicles.entries.where((e) {
                  final lat = (e.value['lat'] as num?)?.toDouble();
                  final lng = (e.value['lng'] as num?)?.toDouble();
                  return lat != null && lng != null && lat != 0.0 && lng != 0.0;
                }).map((e) {
                  final data = e.value;
                  final lat = (data['lat'] as num).toDouble();
                  final lng = (data['lng'] as num).toDouble();
                  final isActive = data['isActive'] as bool? ?? false;
                  final statusColor = isActive ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
                  final vNum = e.key.toUpperCase();

                  return Marker(
                    point: LatLng(lat, lng),
                    width: 90,
                    height: 55,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: statusColor, width: 1.5),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: Text(
                            vNum,
                            style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: const Icon(Icons.local_shipping, color: Colors.white, size: 13),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

              if (currentPos != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(currentPos.latitude, currentPos.longitude),
                      width: 40,
                      height: 40,
                      child: Transform.rotate(
                        angle: _isNavigating ? 0 : heading * (3.14159 / 180),
                        child: Icon(
                          Icons.navigation_rounded, 
                          color: _isNavigating ? Colors.blueAccent : Colors.redAccent, 
                          size: 40
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          
          if (_showSnapAnimation)
            IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.3),
              ),
            ),
          
          // Top Controls Bar: Placeholder Switch & Settings Menu
          Positioned(
            top: 50,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlaceholderMapSwitch(
                  showPlaceholders: _showPlaceholders,
                  realCount: _realFlagsCount,
                  totalCount: _trashSpots.length,
                  onChanged: (val) {
                    setState(() {
                      _showPlaceholders = val;
                      _cachedFleetTrashMarkers.clear();
                    });
                  },
                  isDark: true,
                  compact: true,
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: const Icon(Icons.settings, color: Colors.blueAccent),
                  ),
                  onSelected: (value) {
                    if (value == 'toggle_flags') {
                      setState(() {
                        _showFlags = !_showFlags;
                      });
                    } else if (value == 'route_assigner') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const RouteAssignerScreen()));
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'toggle_flags',
                      child: Row(
                        children: [
                          Icon(
                            _showFlags ? Icons.visibility_off : Icons.visibility,
                            color: Colors.blueAccent,
                          ),
                          const SizedBox(width: 12),
                          Text(_showFlags ? 'Hide Flags' : 'Show Flags', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    if (_allowRouteAssignment)
                      PopupMenuItem<String>(
                        value: 'route_assigner',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.edit_road_rounded,
                              color: Colors.orangeAccent,
                            ),
                            const SizedBox(width: 12),
                            const Text('Route Assign Mode', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          
          // Master-Dashboard Style Zoom in / Zoom out & Recenter
          Positioned(
            bottom: 210,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.black87),
                        tooltip: 'Zoom in',
                        onPressed: () => _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom + 1,
                        ),
                      ),
                      const SizedBox(
                        width: 32,
                        child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove, color: Colors.black87),
                        tooltip: 'Zoom out',
                        onPressed: () => _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom - 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'my_location',
                  onPressed: _centerOnCurrentLocation,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location_rounded, color: Colors.blueAccent),
                ),
              ],
            ),
          ),
          
          // Analytics Button
          Positioned(
            bottom: 280,
            right: 24,
            child: FloatingActionButton(
              heroTag: 'analytics',
              onPressed: _showAnalyticsPopup,
              backgroundColor: Colors.blueAccent,
              child: const Icon(Icons.analytics_rounded, color: Colors.white),
            ),
          ),
          
          // Auto Camera Button
          Positioned(
            bottom: 350,
            right: 24,
            child: Consumer<CameraService>(
              builder: (context, camera, child) {
                final isCapturing = camera.isAutoCapturing;
                return FloatingActionButton(
                  heroTag: 'auto_camera',
                  onPressed: () {
                    final telemetry = context.read<TelemetryService>();
                    if (!camera.isAutoMode) {
                      camera.setAutoMode(true);
                    }
                    camera.toggleAutoCapture(
                      () => telemetry.currentPosition?.latitude ?? 42.3601,
                      () => telemetry.currentPosition?.longitude ?? -71.0589,
                      onSnap: _triggerSnapAnimation,
                    );
                  },
                  backgroundColor: isCapturing ? Colors.redAccent : Colors.white,
                  child: Icon(
                    isCapturing ? Icons.stop_rounded : Icons.camera_alt_rounded,
                    color: isCapturing ? Colors.white : Colors.blueAccent,
                  ),
                );
              },
            ),
          ),
          

          
          // Road Tracing Mode Status Pill (when navigating)
          if (_isNavigating)
            Positioned(
              bottom: 200,
              left: 24,
              right: 24,
              child: Consumer<CameraService>(
                builder: (context, camera, _) {
                  final isCamOn = camera.isCameraOn;
                  final isModConn = camera.isModelConnected;
                  final isVisionActive = isCamOn && isModConn;

                  return Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isVisionActive ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isVisionActive ? const Color(0xFF10B981) : const Color(0xFF3B82F6)).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isVisionActive ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isVisionActive
                                ? 'AI Road Tracing: Clean (🟢) | Trash (🟠) | Dirty (🔴)'
                                : 'Navigation Tracing: Standard Blue (Camera/Model Off)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // Navigation UI Overlay
          Positioned(
            bottom: 140, // Ensure it sits well above the floating dock on small screens
            right: 24,
            left: 24, // Stretch or center it better on small screens
            child: Row(
              children: [
                Expanded(
                  child: FloatingActionButton.extended(
                    heroTag: 'navToggleBtn',
                    onPressed: () => _toggleNavigation(
                      currentPos != null ? LatLng(currentPos.latitude, currentPos.longitude) : null,
                      heading,
                    ),
                    backgroundColor: _isNavigating ? Colors.redAccent : Colors.blueAccent,
                    icon: Icon(_isNavigating ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white),
                    label: Text(
                      _isNavigating ? 'Stop Navigation' : 'Start Navigation', 
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                    ),
                  ),
                ),
                if (_navigationTrail.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  FloatingActionButton(
                    heroTag: 'clearTrailBtn',
                    onPressed: _clearTodayTrail,
                    backgroundColor: const Color(0xFF1E293B),
                    tooltip: "Reset Today's Route",
                    child: const Icon(Icons.refresh_rounded, color: Colors.white),
                  ),
                ],
              ],
            ),
          ),
          
          if (_isNavigating || _activeCheckpointIndex != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _activeCheckpointIndex != null ? Colors.greenAccent.withOpacity(0.9) : Colors.blueAccent.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
                ),
                child: Row(
                  children: [
                    Icon(_activeCheckpointIndex != null ? Icons.pause_circle_filled_rounded : Icons.directions_car_rounded, color: Colors.white, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _activeCheckpointIndex != null 
                              ? 'Waiting at Checkpoint ${_activeCheckpointIndex! + 1}' 
                              : (nextCheckpointIndex != null ? 'Heading to Checkpoint ${nextCheckpointIndex + 1}' : 'Following Assigned Route'), 
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                          ),
                          Text(telemetry.currentAddress, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (_activeCheckpointIndex != null && _arrivalTime != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('ATA', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                          Text(
                            "${_arrivalTime!.hour.toString().padLeft(2, '0')}:${_arrivalTime!.minute.toString().padLeft(2, '0')}",
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      )
                    else if (etaText != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('AI ETA', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                          Text(
                            etaText,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
