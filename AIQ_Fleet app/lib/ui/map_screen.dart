import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/telemetry_service.dart';
import '../services/auth_service.dart';
import '../services/ai_estimation_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/camera_service.dart';
import '../constants.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
    start: LatLng(json['startLat'], json['startLng']),
    end: LatLng(json['endLat'], json['endLng']),
    color: Color(json['color']),
  );
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
  
  // Trash Spots State
  List<Map<String, dynamic>> _trashSpots = [];
  StreamSubscription<QuerySnapshot>? _trashSub;
  bool _showFlags = true;
  bool _isZoomedInForFlags = false; // Zoom >= 16.5

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
    
    // Listen to location updates to draw the trail
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TelemetryService>().addListener(_onLocationUpdate);
    });
  }

  void _onLocationUpdate() {
    if (!mounted || !_isNavigating) return;
    
    final telemetry = context.read<TelemetryService>();
    final currentPos = telemetry.currentPosition;
    
    if (currentPos != null) {
      final currentLoc = LatLng(currentPos.latitude, currentPos.longitude);
      
      if (_lastRecordedPosition != null) {
        final distance = const Distance().as(LengthUnit.Meter, _lastRecordedPosition!, currentLoc);
        
        // Add a segment if moved more than 5 meters to improve tracing accuracy
        if (distance > 5.0) {
          final cameraService = context.read<CameraService>();
          final status = cameraService.latestRoadStatus;
          
          Color segmentColor = Colors.blueAccent; // Default color
          if (status == 'Clean Road') segmentColor = Colors.greenAccent;
          else if (status == 'Slightly Dirty Road') segmentColor = Colors.orangeAccent;
          else if (status == 'Very Dirty Road') segmentColor = Colors.redAccent;

          final start = _lastRecordedPosition!;
          final end = currentLoc;
          _lastRecordedPosition = currentLoc;

          _fetchSnappedRoute(start, end, segmentColor);
        }
      } else {
        _lastRecordedPosition = currentLoc;
      }
    }
  }

  Future<void> _fetchSnappedRoute(LatLng start, LatLng end, Color color) async {
    try {
      final url = 'http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final coords = data['routes'][0]['geometry']['coordinates'] as List;
          final List<LatLng> snappedPoints = coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
          
          if (mounted) {
            List<TrailSegment> newSegments = [];
            for (int i = 0; i < snappedPoints.length - 1; i++) {
              newSegments.add(TrailSegment(
                start: snappedPoints[i],
                end: snappedPoints[i + 1],
                color: color
              ));
            }
            setState(() {
              _navigationTrail.addAll(newSegments);
            });
            
            // Save to Firestore
            final authService = context.read<AuthService>();
            final vehicleNo = authService.vehicleNumber;
            if (vehicleNo != null) {
              FirebaseFirestore.instance.collection('vehicles').doc(vehicleNo)
                .collection('daily_stats').doc(_todayDateString)
                .set({
                  'trail': FieldValue.arrayUnion(newSegments.map((s) => s.toJson()).toList())
                }, SetOptions(merge: true)).catchError((_) {});
            }
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("OSRM error: $e");
    }
    
    // Fallback to straight line if OSRM fails
    if (mounted) {
      final seg = TrailSegment(start: start, end: end, color: color);
      setState(() {
        _navigationTrail.add(seg);
      });
      final authService = context.read<AuthService>();
      final vehicleNo = authService.vehicleNumber;
      if (vehicleNo != null) {
        FirebaseFirestore.instance.collection('vehicles').doc(vehicleNo)
          .collection('daily_stats').doc(_todayDateString)
          .set({
            'trail': FieldValue.arrayUnion([seg.toJson()])
          }, SetOptions(merge: true)).catchError((_) {});
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
          }).toList();
        });
      }
    });
  }

  @override
  void dispose() {
    _routeSub?.cancel();
    _trashSub?.cancel();
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
      WakelockPlus.enable();
      if (currentLoc != null) {
        _mapController.moveAndRotate(currentLoc, 18.0, heading);
      }
    } else {
      WakelockPlus.disable();
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
                        displayUrl = '$GARBAGE_AI_URL${uri.path}';
                      }
                    } catch (_) {}
                  } else if (displayUrl.startsWith('/')) {
                    displayUrl = '$GARBAGE_AI_URL$displayUrl';
                  } else {
                    displayUrl = '$GARBAGE_AI_URL/$displayUrl';
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
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && _isFollowingUser) {
                  setState(() => _isFollowingUser = false);
                }
                final isZoomedIn = position.zoom >= 16.5;
                if (_isZoomedInForFlags != isZoomedIn) {
                  setState(() => _isZoomedInForFlags = isZoomedIn);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.street_aiq_tipper_app',
              ),
              
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
                  polylines: _navigationTrail.map((segment) => Polyline(
                    points: [segment.start, segment.end],
                    strokeWidth: 8,
                    color: segment.color,
                    borderStrokeWidth: 2,
                    borderColor: Colors.white.withOpacity(0.8),
                  )).toList(),
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
                
              if (_trashSpots.isNotEmpty && _showFlags && _isZoomedInForFlags)
                MarkerLayer(
                  markers: _trashSpots.map((spot) {
                    final lat = spot['lat'] as double;
                    final lng = spot['lng'] as double;
                    final isVeryDirty = spot['road_status'] == 'Very Dirty Road';
                    final markerColor = isVeryDirty ? Colors.redAccent : Colors.orangeAccent;
                    
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 60,
                      height: 80,
                      child: GestureDetector(
                        onTap: () => _showTrashPopup(spot),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Thumbnail above the flag
                            if (spot['image_url'] != null)
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
                                  image: DecorationImage(
                                    image: NetworkImage(spot['image_url']),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            // The flag symbol
                            Icon(
                              Icons.tour_rounded,
                              color: markerColor,
                              size: 32,
                              shadows: const [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
                            ),
                          ],
                        ),
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
          
          // Settings Menu
          Positioned(
            top: 40,
            right: 24,
            child: PopupMenuButton<String>(
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
              ],
            ),
          ),
          
          // Current Location Button
          Positioned(
            bottom: 210,
            right: 24,
            child: FloatingActionButton(
              heroTag: 'my_location',
              onPressed: _centerOnCurrentLocation,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location_rounded, color: Colors.blueAccent),
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
          

          
          // Navigation UI Overlay
          Positioned(
            bottom: 140, // Ensure it sits well above the floating dock on small screens
            right: 24,
            left: 24, // Stretch or center it better on small screens
            child: FloatingActionButton.extended(
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
