import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

enum CollectionState {
  onTheWay,
  arrived,
  collecting,
  completed,
}

class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  final MapController _mapController = MapController();
  final LatLng _userLocation = const LatLng(12.9716, 77.5946); // Indiranagar
  LatLng _riderLocation = const LatLng(12.9650, 77.5900); // Starting point

  CollectionState _currentState = CollectionState.onTheWay;
  double _sheetHeight = 0.4;

  @override
  void initState() {
    super.initState();
    _simulateRide();
  }

  Future<void> _simulateRide() async {
    // 1. On the way (Move marker closer)
    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() {
        _riderLocation = LatLng(
          _riderLocation.latitude + 0.001,
          _riderLocation.longitude + 0.0008,
        );
      });
    }

    // 2. Arrived
    if (!mounted) return;
    setState(() => _currentState = CollectionState.arrived);
    await Future.delayed(const Duration(seconds: 3));

    // 3. Collecting
    if (!mounted) return;
    setState(() => _currentState = CollectionState.collecting);
    await Future.delayed(const Duration(seconds: 4));

    // 4. Completed
    if (!mounted) return;
    setState(() => _currentState = CollectionState.completed);
    await Future.delayed(const Duration(seconds: 2));

    // 5. Navigate to Payment
    if (!mounted) return;
    context.pushReplacement('/payment');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. Live Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userLocation,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.takemytrash.user',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [_riderLocation, _userLocation],
                    color: AppColors.primary,
                    strokeWidth: 4,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // User Location
                  Marker(
                    point: _userLocation,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.info,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                  ),
                  // Rider Location
                  Marker(
                    point: _riderLocation,
                    width: 50,
                    height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 2),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5)),
                        ],
                      ),
                      child: const Icon(Icons.local_shipping, color: AppColors.primary, size: 24),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Header
          Positioned(
            top: 50,
            left: 20,
            child: GestureDetector(
              onTap: () => context.go('/home'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                ),
                child: const Icon(Icons.close, color: AppColors.textPrimary),
              ),
            ),
          ),

          // 3. Draggable Bottom Sheet
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              setState(() {
                _sheetHeight = notification.extent;
              });
              return true;
            },
            child: DraggableScrollableSheet(
              initialChildSize: 0.45,
              minChildSize: 0.45,
              maxChildSize: 0.85,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, -10)),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    children: [
                      // Drag Handle
                      Center(
                        child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
                      ),
                      const SizedBox(height: 24),

                      // Dynamic Status Header
                      _buildStatusHeader(),
                      const SizedBox(height: 24),

                      // Rider Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Icon(Icons.person, color: AppColors.textSecondary),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Arun Kumar', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: const [
                                      Text('Mini Tipper', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, color: AppColors.textSecondary)),
                                      Text(' • ', style: TextStyle(color: AppColors.textMuted)),
                                      Text('KA 01 AB 1234', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                              child: const Icon(Icons.call, color: Colors.white, size: 20),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Progress Timeline
                      const Text('Pickup Progress', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            _buildTimelineNode(
                              title: 'Booking Confirmed',
                              isCompleted: true,
                              isCurrent: false,
                              isLast: false,
                            ),
                            _buildTimelineNode(
                              title: 'Rider Assigned',
                              isCompleted: true,
                              isCurrent: false,
                              isLast: false,
                            ),
                            _buildTimelineNode(
                              title: 'Rider on the way',
                              isCompleted: _currentState != CollectionState.onTheWay,
                              isCurrent: _currentState == CollectionState.onTheWay,
                              isLast: false,
                            ),
                            _buildTimelineNode(
                              title: 'Rider arrived',
                              isCompleted: _currentState == CollectionState.collecting || _currentState == CollectionState.completed,
                              isCurrent: _currentState == CollectionState.arrived,
                              isLast: false,
                            ),
                            _buildTimelineNode(
                              title: 'Waste being collected',
                              isCompleted: _currentState == CollectionState.completed,
                              isCurrent: _currentState == CollectionState.collecting,
                              isLast: false,
                            ),
                            _buildTimelineNode(
                              title: 'Collection Completed',
                              isCompleted: _currentState == CollectionState.completed,
                              isCurrent: false,
                              isLast: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Payment Summary
                      const Text('Estimated Fare', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('To be paid after collection', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, color: AppColors.textSecondary)),
                          Text('₹44', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusHeader() {
    switch (_currentState) {
      case CollectionState.onTheWay:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Arun is on the way', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
                SizedBox(height: 4),
                Text('0.4 km away', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, color: AppColors.textSecondary)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
              child: const Text('2 min', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        );
      case CollectionState.arrived:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Your rider has arrived', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.success, letterSpacing: -0.5)),
            SizedBox(height: 4),
            Text('Arun is waiting at your pickup location.', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, color: AppColors.textSecondary)),
          ],
        );
      case CollectionState.collecting:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Collection in Progress', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.warning, letterSpacing: -0.5)),
            SizedBox(height: 4),
            Text('Your waste is being loaded into the vehicle.', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, color: AppColors.textSecondary)),
          ],
        );
      case CollectionState.completed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Collection Complete ✓', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: -0.5)),
            SizedBox(height: 4),
            Text('Redirecting to payment...', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, color: AppColors.textSecondary)),
          ],
        );
    }
  }

  Widget _buildTimelineNode({required String title, required bool isCompleted, required bool isCurrent, required bool isLast}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isCompleted ? AppColors.success : (isCurrent ? AppColors.primary : Colors.white),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCompleted ? AppColors.success : (isCurrent ? AppColors.primary : AppColors.border),
                  width: 2,
                ),
              ),
              child: isCompleted ? const Icon(Icons.check, color: Colors.white, size: 14) : 
                     isCurrent ? Center(child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))) : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: isCompleted ? AppColors.success : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 15,
                  fontWeight: (isCompleted || isCurrent) ? FontWeight.bold : FontWeight.w500,
                  color: (isCompleted || isCurrent) ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
              if (!isLast) const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}
