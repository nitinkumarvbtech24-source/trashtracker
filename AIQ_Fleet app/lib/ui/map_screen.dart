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

class TrailSegment {
  final LatLng start;
  final LatLng end;
  final Color color;
  TrailSegment({required this.start, required this.end, required this.color});
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  bool _isNavigating = false;
  List<LatLng> _assignedRoute = [];
  List<LatLng> _assignedCheckpoints = [];
  StreamSubscription<DocumentSnapshot>? _routeSub;

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
        
        // Add a segment if moved more than 2 meters
        if (distance > 2.0) {
          final cameraService = context.read<CameraService>();
          final status = cameraService.latestRoadStatus;
          
          Color segmentColor = Colors.blueAccent; // Default color
          if (status == 'Clean Road') segmentColor = Colors.greenAccent;
          else if (status == 'Slightly Dirty Road') segmentColor = Colors.orangeAccent; // Orange is more visible than yellow on map
          else if (status == 'Very Dirty Road') segmentColor = Colors.redAccent;

          setState(() {
            _navigationTrail.add(TrailSegment(
              start: _lastRecordedPosition!,
              end: currentLoc,
              color: segmentColor
            ));
            _lastRecordedPosition = currentLoc;
          });
        }
      } else {
        _lastRecordedPosition = currentLoc;
      }
    }
  }

  void _startRouteSync() {
    final authService = context.read<AuthService>();
    final vehicleNo = authService.vehicleNumber;
    
    if (vehicleNo != null && vehicleNo.isNotEmpty) {
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
              }
              if (data['assignedCheckpoints'] != null) {
                final List<dynamic> rawCheckpoints = data['assignedCheckpoints'];
                _assignedCheckpoints = rawCheckpoints.map((e) => LatLng(e['lat'], e['lng'])).toList();
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
    // In case we want to clean up listener safely later, though typically Provider takes care of it
  }

  void _toggleNavigation(LatLng? currentLoc, double heading) {
    setState(() {
      _isNavigating = !_isNavigating;
      if (_isNavigating) {
        _navigationTrail.clear();
        _lastRecordedPosition = currentLoc;
      } else {
        _lastRecordedPosition = null;
      }
    });
    
    // Update telemetry state so it syncs to Firebase
    context.read<TelemetryService>().setNavigating(_isNavigating);

    if (_isNavigating && currentLoc != null) {
      _mapController.moveAndRotate(currentLoc, 18.0, heading);
    } else {
      _mapController.rotate(0);
    }
  }

  void _centerOnCurrentLocation() {
    final currentPos = context.read<TelemetryService>().currentPosition;
    if (currentPos != null) {
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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(spot['image_url'], height: 200, width: double.infinity, fit: BoxFit.cover),
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
      if (_isNavigating) {
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
                if (hasGesture && _isNavigating) {
                  setState(() => _isNavigating = false);
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
                
              if (_trashSpots.isNotEmpty)
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
