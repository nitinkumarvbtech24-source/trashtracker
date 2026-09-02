import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/telemetry_service.dart';
import '../services/auth_service.dart';

class RouteAssignerScreen extends StatefulWidget {
  const RouteAssignerScreen({super.key});

  @override
  State<RouteAssignerScreen> createState() => _RouteAssignerScreenState();
}

class _RouteAssignerScreenState extends State<RouteAssignerScreen> {
  final MapController _mapController = MapController();
  bool _isRecording = false;
  bool _isEditMode = false;
  bool _isFollowingUser = true;
  
  List<LatLng> _recordedRoute = [];
  List<LatLng> _checkpoints = [];
  LatLng? _lastRecordedPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TelemetryService>().addListener(_onLocationUpdate);
    });
  }

  @override
  void dispose() {
    context.read<TelemetryService>().removeListener(_onLocationUpdate);
    _mapController.dispose();
    super.dispose();
  }

  void _onLocationUpdate() {
    if (!mounted) return;
    final currentPos = context.read<TelemetryService>().currentPosition;
    if (currentPos != null) {
      final currentLoc = LatLng(currentPos.latitude, currentPos.longitude);
      
      if (_isFollowingUser && !_isEditMode) {
        _mapController.move(currentLoc, 18.0);
      }

      if (_isRecording) {
        if (_lastRecordedPosition == null || 
            const Distance().as(LengthUnit.Meter, _lastRecordedPosition!, currentLoc) > 5) {
          setState(() {
            _recordedRoute.add(currentLoc);
            _lastRecordedPosition = currentLoc;
          });
        }
      }
    }
  }

  void _toggleRecording() {
    if (_isRecording) {
      setState(() {
        _isRecording = false;
        _lastRecordedPosition = null;
      });
    } else {
      if (_recordedRoute.isNotEmpty && !_isEditMode) {
        // Option to clear or resume
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text('Resume or Restart?', style: TextStyle(color: Colors.white)),
            content: const Text('Do you want to resume the current route or clear it and start fresh?', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _recordedRoute.clear();
                    _checkpoints.clear();
                    _isRecording = true;
                  });
                },
                child: const Text('Start Fresh', style: TextStyle(color: Colors.redAccent)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _isRecording = true);
                },
                child: const Text('Resume', style: TextStyle(color: Colors.blueAccent)),
              ),
            ],
          ),
        );
      } else {
        setState(() => _isRecording = true);
      }
    }
  }

  void _addStop() {
    final currentPos = context.read<TelemetryService>().currentPosition;
    if (currentPos != null) {
      setState(() {
        _checkpoints.add(LatLng(currentPos.latitude, currentPos.longitude));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stop added.'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _saveRoute() async {
    final auth = context.read<AuthService>();
    final vehicleNo = auth.vehicleNumber;
    
    if (vehicleNo == null || vehicleNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No vehicle assigned to driver.')));
      return;
    }
    
    if (_recordedRoute.isEmpty && _checkpoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route is empty!')));
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      
      final routeData = _recordedRoute.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
      final checkpointsData = _checkpoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();

      await FirebaseFirestore.instance.collection('vehicles').doc(vehicleNo).set({
        'assignedRoute': routeData,
        'assignedCheckpoints': checkpointsData,
      }, SetOptions(merge: true));
      
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route Saved Successfully!')));
        Navigator.pop(context); // Go back to Map
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save route: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPos = context.watch<TelemetryService>().currentPosition;
    final initialCenter = currentPos != null 
        ? LatLng(currentPos.latitude, currentPos.longitude) 
        : const LatLng(12.9716, 77.5946);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Route Assigner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_isEditMode ? Icons.check : Icons.edit_road_rounded, color: Colors.orangeAccent),
            tooltip: 'Toggle Edit Mode',
            onPressed: () {
              setState(() {
                _isEditMode = !_isEditMode;
                _isFollowingUser = !_isEditMode; // Stop following when editing
                if (_isEditMode) _isRecording = false; // Stop recording when editing
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.save_rounded, color: Colors.greenAccent),
            tooltip: 'Save Route',
            onPressed: _isRecording ? null : _saveRoute,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 17.0,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && _isFollowingUser) {
                  setState(() => _isFollowingUser = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.street_aiq_tipper_app',
              ),
              
              if (_recordedRoute.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _recordedRoute,
                      strokeWidth: 6,
                      color: Colors.blueAccent,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white.withOpacity(0.8),
                    ),
                  ],
                ),

              if (_checkpoints.isNotEmpty)
                MarkerLayer(
                  markers: _checkpoints.asMap().entries.map((entry) {
                    final index = entry.key;
                    final point = entry.value;
                    
                    return Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: _isEditMode ? () {
                          setState(() {
                            _checkpoints.removeAt(index);
                          });
                        } : null,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _isEditMode ? Colors.redAccent : Colors.orangeAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))
                            ]
                          ),
                          child: Center(
                            child: _isEditMode 
                              ? const Icon(Icons.close, color: Colors.white, size: 20)
                              : Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                          ),
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
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          if (_isEditMode)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Edit Mode Active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _recordedRoute.clear();
                          _checkpoints.clear();
                        });
                      },
                      child: const Text('Clear All', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (!_isEditMode)
                  FloatingActionButton.extended(
                    heroTag: 'record_btn',
                    backgroundColor: _isRecording ? Colors.redAccent : Colors.blueAccent,
                    icon: Icon(_isRecording ? Icons.stop_rounded : Icons.fiber_manual_record, color: Colors.white),
                    label: Text(_isRecording ? 'Stop Recording' : 'Start Recording', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: _toggleRecording,
                  ),
                
                if (!_isEditMode)
                  FloatingActionButton(
                    heroTag: 'add_stop_btn',
                    backgroundColor: Colors.orangeAccent,
                    onPressed: _addStop,
                    child: const Icon(Icons.add_location_alt_rounded, color: Colors.white),
                  ),
                  
                if (_isEditMode)
                   FloatingActionButton.extended(
                    heroTag: 'done_btn',
                    backgroundColor: Colors.greenAccent,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Done Editing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      setState(() {
                        _isEditMode = false;
                        _isFollowingUser = true;
                      });
                    },
                  ),
              ],
            ),
          ),
          
          Positioned(
            bottom: 100,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'center_btn',
              mini: true,
              backgroundColor: Colors.white,
              onPressed: () {
                setState(() => _isFollowingUser = true);
                if (currentPos != null) {
                  _mapController.move(LatLng(currentPos.latitude, currentPos.longitude), 18.0);
                }
              },
              child: const Icon(Icons.my_location, color: Colors.blueAccent),
            ),
          )
        ],
      ),
    );
  }
}
