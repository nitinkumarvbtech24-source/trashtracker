import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';

class TrailSegment {
  final LatLng start;
  final LatLng end;
  final Color color;
  TrailSegment({required this.start, required this.end, required this.color});

  factory TrailSegment.fromJson(Map<String, dynamic> json) => TrailSegment(
    start: LatLng(json['startLat'], json['startLng']),
    end: LatLng(json['endLat'], json['endLng']),
    color: Color(json['color']),
  );
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
  List<Map<String, dynamic>> _trashSpots = [];
  bool _isLoading = true;

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
        if (data['status'] == 'Resolved') continue; 
        
        // Filter by timestamp range for this specific trip
        if (data['timestamp'] != null) {
          final spotTime = (data['timestamp'] as Timestamp).toDate();
          if (widget.startTime != null && spotTime.isBefore(widget.startTime!)) continue;
          if (widget.endTime != null && spotTime.isAfter(widget.endTime!)) continue;
        }
        data['id'] = spotDoc.id;
        filteredSpots.add(data);
      }
      _trashSpots = filteredSpots;

    } catch (e) {
      debugPrint("Error fetching trip data: $e");
    } finally {
      if (mounted) {
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
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.street_aiq_tipper_app',
                ),
                if (_trail.isNotEmpty)
                  PolylineLayer(
                    polylines: _trail.map((segment) => Polyline(
                      points: [segment.start, segment.end],
                      strokeWidth: 8,
                      color: segment.color,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white.withOpacity(0.8),
                    )).toList(),
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
              ],
            ),
    );
  }
}
