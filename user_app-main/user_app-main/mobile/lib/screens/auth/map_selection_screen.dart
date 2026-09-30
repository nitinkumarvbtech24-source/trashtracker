import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class MapSelectionScreen extends StatefulWidget {
  const MapSelectionScreen({super.key});

  @override
  State<MapSelectionScreen> createState() => _MapSelectionScreenState();
}

class _MapSelectionScreenState extends State<MapSelectionScreen> {
  final MapController _mapController = MapController();
  LatLng _currentCenter = const LatLng(13.003, 77.564); // Default to Bangalore
  
  List<Polygon> _zonePolygons = [];
  List<Polygon> _wardPolygons = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMapData();
    _checkLocation();
  }

  Future<void> _checkLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _currentCenter = LatLng(pos.latitude, pos.longitude);
      _mapController.move(_currentCenter, 13);
    });
  }

  Future<void> _fetchMapData() async {
    try {
      final zonesSnap = await FirebaseFirestore.instance.collection('zones').get();
      final wardsSnap = await FirebaseFirestore.instance.collection('wards').get();
      
      final parsedZones = _parsePolygons(zonesSnap.docs, Colors.blue.withOpacity(0.1), Colors.blue);
      final parsedWards = _parsePolygons(wardsSnap.docs, Colors.orange.withOpacity(0.1), Colors.orange);

      if (mounted) {
        setState(() {
          _zonePolygons = parsedZones;
          _wardPolygons = parsedWards;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching map data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Polygon> _parsePolygons(List<QueryDocumentSnapshot> docs, Color fillColor, Color borderColor) {
    List<Polygon> polygons = [];
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final boundary = data['boundary'];
      if (boundary != null && boundary is List) {
        List<LatLng> points = [];
        for (var node in boundary) {
          if (node is GeoPoint) {
            points.add(LatLng(node.latitude, node.longitude));
          } else if (node is Map) {
            final lat = (node['lat'] ?? node['latitude'])?.toDouble();
            final lng = (node['lng'] ?? node['longitude'])?.toDouble();
            if (lat != null && lng != null) points.add(LatLng(lat, lng));
          }
        }
        if (points.isNotEmpty) {
          polygons.add(Polygon(
            points: points,
            color: fillColor,
            borderColor: borderColor,
            borderStrokeWidth: 2,
            isFilled: true,
          ));
        }
      }
    }
    return polygons;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F5132),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 12,
              onPositionChanged: (position, hasGesture) {
                if (position.center != null) {
                  _currentCenter = position.center!;
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),
              PolygonLayer(polygons: _zonePolygons),
              PolygonLayer(polygons: _wardPolygons),
            ],
          ),
          
          // Fixed Center Pin
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40), // offset for the pin tip
              child: Icon(
                Icons.location_on,
                size: 40,
                color: Colors.red,
              ),
            ),
          ),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
            
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context, _currentCenter);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5132),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Confirm Location', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}
