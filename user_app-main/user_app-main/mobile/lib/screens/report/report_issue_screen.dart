import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import 'camera_capture_screen.dart';

class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({super.key});

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final MapController _mapController = MapController();
  LatLng _userLocation = const LatLng(12.9716, 77.5946); // Indiranagar, Bengaluru
  bool _isLoadingLocation = true;
  
  // State for complaints
  List<Map<String, dynamic>> _complaints = [
    {
      'id': '#RP-10042',
      'category': 'pothole',
      'lat': 12.9750,
      'lng': 77.5980,
      'status': 'In Progress',
      'date': 'Yesterday, 14:30',
      'image': 'https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?auto=format&fit=crop&q=80',
      'comment': 'Huge pothole on the main road, very dangerous.',
      'reportCount': 3,
    },
    {
      'id': '#RP-10021',
      'category': 'garbage',
      'lat': 12.9700,
      'lng': 77.5900,
      'status': 'Resolved',
      'date': 'Oct 12, 09:15',
      'image': 'https://images.unsplash.com/photo-1532996122724-e3c354a0b15b?auto=format&fit=crop&q=80',
      'comment': 'Garbage dumped on the sidewalk.',
      'reportCount': 1,
    },
    {
      'id': '#RP-10088',
      'category': 'garbage',
      'lat': 12.9720,
      'lng': 77.5940,
      'status': 'Resolved',
      'date': 'Today, 10:00',
      'image': 'https://images.unsplash.com/photo-1605600659928-879857d47228?auto=format&fit=crop&q=80',
      'comment': 'Overflowing bin near the park entrance.',
      'reportCount': 5,
    },
    {
      'id': '#RP-10065',
      'category': 'others',
      'lat': 12.9735,
      'lng': 77.5960,
      'status': 'In Progress',
      'date': 'Yesterday, 18:20',
      'image': 'https://images.unsplash.com/photo-1598257006626-48b0c252070d?auto=format&fit=crop&q=80',
      'comment': 'Fallen tree branch blocking the pavement.',
      'reportCount': 2,
    },
    {
      'id': '#RP-10055',
      'category': 'pothole',
      'lat': 12.9690,
      'lng': 77.5955,
      'status': 'In Progress',
      'date': '2 days ago',
      'image': 'https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?auto=format&fit=crop&q=80',
      'comment': 'Deep pothole, multiple bikes slipped here.',
      'reportCount': 8,
    }
  ];

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _isLoadingLocation = false);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _isLoadingLocation = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _isLoadingLocation = false);
      return;
    }

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _userLocation = LatLng(position.latitude, position.longitude);
      _isLoadingLocation = false;
    });
    _mapController.move(_userLocation, 14.0);
  }

  final List<Map<String, dynamic>> _categories = [
    {'id': 'pothole', 'label': 'Pothole', 'icon': '🕳'},
    {'id': 'garbage', 'label': 'Garbage', 'icon': '🗑'},
    {'id': 'others', 'label': 'Other', 'icon': '⚠'},
  ];

  void _recenterMap() {
    _mapController.move(_userLocation, 14.0);
  }

  void _handleCategorySelection(String category) {
    bool foundNearby = false;
    Map<String, dynamic>? nearbyComplaint;
    int nearbyIndex = -1;

    for (int i = 0; i < _complaints.length; i++) {
      var comp = _complaints[i];
      if (comp['category'] == category) {
        double distanceInMeters = Geolocator.distanceBetween(
          _userLocation.latitude, _userLocation.longitude,
          comp['lat'], comp['lng']
        );
        if (distanceInMeters < 50.0) { // 50 meters radius
          foundNearby = true;
          nearbyComplaint = comp;
          nearbyIndex = i;
          break;
        }
      }
    }

    if (foundNearby && nearbyComplaint != null) {
      _showDuplicateReportDialog(nearbyComplaint, nearbyIndex, category);
    } else {
      _openCamera(category);
    }
  }

  void _showDuplicateReportDialog(Map<String, dynamic> comp, int index, String category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Existing Report Nearby', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('There is already a ${comp['category']} reported near your location. Are you trying to report the same issue?',
              style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14)),
            const SizedBox(height: 16),
            if (comp['image'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: comp['image'].toString().startsWith('http') 
                  ? Image.network(comp['image'], height: 120, width: double.infinity, fit: BoxFit.cover)
                  : Image.file(File(comp['image']), height: 120, width: double.infinity, fit: BoxFit.cover),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openCamera(category);
            },
            child: const Text('No, Report New', style: TextStyle(fontFamily: 'Plus Jakarta Sans', color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              setState(() {
                _complaints[index]['reportCount'] = (_complaints[index]['reportCount'] ?? 1) + 1;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Issue upvoted successfully!'),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: const Text('Yes, Upvote This', style: TextStyle(fontFamily: 'Plus Jakarta Sans', color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCategoryModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What would you like to report?',
              style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _categories.map((cat) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _handleCategorySelection(cat['id']);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Center(
                          child: Text(cat['icon'], style: const TextStyle(fontSize: 32)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cat['label'],
                        style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _openCamera(String category) async {
    // Navigate to camera screen and wait for result
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CameraCaptureScreen(category: category, lat: _userLocation.latitude, lng: _userLocation.longitude)),
    );

    if (result != null && result is Map<String, dynamic>) {
      // Offset if duplicate coordinates exist to prevent marker overlap
      double lat = result['lat'];
      double lng = result['lng'];
      
      bool overlap = true;
      while (overlap) {
        overlap = _complaints.any((c) => 
          (c['lat'] as double).toStringAsFixed(5) == lat.toStringAsFixed(5) && 
          (c['lng'] as double).toStringAsFixed(5) == lng.toStringAsFixed(5)
        );
        if (overlap) {
          lat += 0.00015; // Offset by ~15 meters
          lng += 0.00015;
        }
      }

      setState(() {
        _complaints.add({
          'id': result['id'] ?? '#RP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
          'category': result['category'],
          'lat': lat,
          'lng': lng,
          'status': result['status'],
          'date': 'Just now',
          'image': result['image'],
          'comment': result['comment'],
          'reportCount': 1,
        });
      });
      
      // Move map to new complaint
      _mapController.move(LatLng(result['lat'], result['lng']), 15.0);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Complaint reported successfully!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showComplaintDetails(Map<String, dynamic> comp) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          comp['category'].toString().toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Complaint ${comp['id']}',
                            style: const TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.info.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.people, size: 14, color: AppColors.info),
                                const SizedBox(width: 4),
                                Text(
                                  '${comp['reportCount'] ?? 1}',
                                  style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.info),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        comp['comment'] ?? 'No additional comments provided.',
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${(comp['lat'] as double).toStringAsFixed(4)}, ${(comp['lng'] as double).toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                if (comp['image'] != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: comp['image'].toString().startsWith('http') 
                      ? Image.network(
                          comp['image'],
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        )
                      : Image.file(
                          File(comp['image']),
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                  )
                else
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.image_not_supported, color: AppColors.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCategoryModal,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Report Issue', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: Stack(
        children: [
          // 1. Map Layer
          if (_isLoadingLocation)
            const Center(child: CircularProgressIndicator(color: AppColors.primary))
          else
            FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userLocation,
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.takemytrash.user',
              ),
              MarkerLayer(
                markers: [
                  // User Location Marker
                  Marker(
                    point: _userLocation,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.info.withOpacity(0.3),
                      ),
                      child: Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.info,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Complaint Markers
                  ..._complaints.map((comp) {
                    final isPothole = comp['category'] == 'pothole';
                    final isGarbage = comp['category'] == 'garbage';
                    
                    IconData iconData = Icons.warning;
                    Color color = AppColors.warning;
                    
                    if (isPothole) {
                      iconData = Icons.remove_circle; // Pothole looking icon
                      color = AppColors.error;
                    } else if (isGarbage) {
                      iconData = Icons.delete;
                      color = AppColors.primary;
                    }
                    
                    return Marker(
                      point: LatLng(comp['lat'], comp['lng']),
                      width: 50,
                      height: 50,
                      child: GestureDetector(
                        onTap: () => _showComplaintDetails(comp),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: color, width: 2),
                          ),
                          child: Center(
                            child: Icon(iconData, color: color, size: 24),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ],
          ),

          // 2. Header Layer (Glassmorphism)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Scaffold.of(context).openDrawer(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.menu, color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Civic Reports',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 22,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // 3. Floating Recenter Button
          Positioned(
            right: 24,
            top: 140, 
            child: GestureDetector(
              onTap: _recenterMap,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.my_location, color: AppColors.textPrimary, size: 22),
              ),
            ),
          ),
          
          // 4. Past Complaints List Overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 250,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent Civic Reports',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 80), // Space for FAB
                      itemCount: _complaints.length,
                      separatorBuilder: (context, index) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final comp = _complaints.reversed.toList()[index];
                        final isPothole = comp['category'] == 'pothole';
                        final isGarbage = comp['category'] == 'garbage';
                        
                        return Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isPothole ? AppColors.error.withOpacity(0.1) : (isGarbage ? AppColors.primary.withOpacity(0.1) : AppColors.warning.withOpacity(0.1)),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                isPothole ? Icons.remove_circle_outline : (isGarbage ? Icons.delete_outline : Icons.warning_amber),
                                color: isPothole ? AppColors.error : (isGarbage ? AppColors.primary : AppColors.warning),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        isPothole ? 'Pothole Issue' : (isGarbage ? 'Garbage Dump' : 'Other Issue'),
                                        style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                      ),
                                      Text(
                                        comp['date'],
                                        style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 12, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${comp['id']} • ${comp['reportCount'] ?? 1} reported',
                                        style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, color: AppColors.textSecondary),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: comp['status'] == 'Resolved' ? AppColors.success.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          comp['status'],
                                          style: TextStyle(
                                            fontFamily: 'Plus Jakarta Sans',
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: comp['status'] == 'Resolved' ? AppColors.success : AppColors.warning,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
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
