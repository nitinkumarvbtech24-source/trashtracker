import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../router/app_router.dart';
import '../../models/garbage_vehicle_model.dart';
import '../../services/fleet_tracking_service.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng _userLocation = const LatLng(12.9716, 77.5946); // Default location (Bangalore)
  bool _isLoadingLocation = true;
  bool _isFetchingGPS = false;
  GarbageVehicleModel? _selectedVehicle;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Initialize live fleet tracking from Firestore / REST service
    FleetTrackingService.instance.startLiveTracking();
    _determinePosition();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, (currentZoom + 1.0).clamp(3.0, 19.0));
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, (currentZoom - 1.0).clamp(3.0, 19.0));
  }

  Future<void> _recenterMap() async {
    setState(() => _isFetchingGPS = true);
    await _determinePosition();
    if (mounted) {
      setState(() => _isFetchingGPS = false);
      _mapController.move(_userLocation, 16.0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Centered to live GPS: ${_userLocation.latitude.toStringAsFixed(4)}, ${_userLocation.longitude.toStringAsFixed(4)}',
            style: const TextStyle(fontFamily: 'Plus Jakarta Sans'),
          ),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isLoadingLocation = false);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isLoadingLocation = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _isLoadingLocation = false);
      return;
    }

    Position position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
      });
      _mapController.move(_userLocation, 15.0);
    }
  }

  void _trackVehicle(GarbageVehicleModel vehicle) {
    setState(() => _selectedVehicle = vehicle);
    _mapController.move(LatLng(vehicle.currentLatitude, vehicle.currentLongitude), 16.5);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tracking ${vehicle.vehicleNumber} (${vehicle.driverName})',
          style: const TextStyle(fontFamily: 'Plus Jakarta Sans'),
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _focusNearestTipper() {
    final nearest = FleetTrackingService.instance.getNearestVehicle(_userLocation);
    if (nearest != null) {
      _trackVehicle(nearest);
    } else {
      final vehicles = FleetTrackingService.instance.liveVehicles;
      if (vehicles.isNotEmpty) {
        _trackVehicle(vehicles.first);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Scanning for active tippers in your zone...'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _callDriver(String? phoneNumber) async {
    final phone = phoneNumber ?? '+919876543210';
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Calling driver: $phone')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. Map Layer
          if (_isLoadingLocation)
            const Center(child: CircularProgressIndicator(color: AppColors.primary))
          else
            ValueListenableBuilder<List<GarbageVehicleModel>>(
              valueListenable: FleetTrackingService.instance.vehiclesNotifier,
              builder: (context, vehicles, _) {
                // Determine active markers
                final List<Marker> markers = [];

                // A. User Location Marker with Pulse Ring
                markers.add(
                  Marker(
                    point: _userLocation,
                    width: 60,
                    height: 60,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.info.withOpacity(0.3),
                            ),
                            child: Center(
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.info,
                                  border: Border.all(color: Colors.white, width: 3),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );

                // B. Real-time Live Fleet Truck Markers
                for (var v in vehicles) {
                  final bool isSelected = _selectedVehicle?.vehicleId == v.vehicleId;
                  markers.add(
                    Marker(
                      point: LatLng(v.currentLatitude, v.currentLongitude),
                      width: 72,
                      height: 72,
                      child: GestureDetector(
                        onTap: () => _trackVehicle(v),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Plate / Name badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.18),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : AppColors.border,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                v.vehicleNumber,
                                style: TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Vehicle truck icon circle
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (isSelected ? AppColors.primary : Colors.black)
                                        .withOpacity(isSelected ? 0.35 : 0.2),
                                    blurRadius: isSelected ? 12 : 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : (v.isActive ? const Color(0xFF10B981) : Colors.orange),
                                  width: isSelected ? 3 : 2,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.local_shipping,
                                  color: isSelected
                                      ? AppColors.primary
                                      : (v.isActive ? const Color(0xFF10B981) : Colors.orange),
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return FlutterMap(
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
                    MarkerLayer(markers: markers),
                  ],
                );
              },
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
                  padding: EdgeInsets.only(
                    top: MediaQuery.sizeOf(context).width >= 768
                        ? 18
                        : (MediaQuery.paddingOf(context).top + 10),
                    left: 20,
                    right: 20,
                    bottom: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    border: Border(
                      bottom: BorderSide(color: AppColors.border.withOpacity(0.6)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => MainShell.openDrawer(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.menu_rounded, color: AppColors.primary, size: 20),
                                  if (MediaQuery.sizeOf(context).width >= 600) ...[
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Menu',
                                      style: TextStyle(
                                        fontFamily: 'Plus Jakarta Sans',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Good morning 👋',
                                style: TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                MediaQuery.sizeOf(context).width >= 768
                                    ? 'Neighborhood Live Fleet & Tipper Map'
                                    : 'Live Fleet Tracking',
                                style: const TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 17,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(Icons.notifications_none, color: AppColors.textPrimary, size: 20),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => context.push('/profile'),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  context.watch<AuthProvider>().user?.name.isNotEmpty == true 
                                      ? context.watch<AuthProvider>().user!.name[0].toUpperCase() 
                                      : 'U',
                                  style: const TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Master Dashboard Style Floating Map Controls (Zoom +, Zoom -, Recenter, Focus Truck)
          Positioned(
            right: 16,
            bottom: 220,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Zoom Panel
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MapIconButton(
                        icon: Icons.add,
                        tooltip: 'Zoom in',
                        onTap: _zoomIn,
                      ),
                      Container(height: 1, width: 36, color: AppColors.border.withOpacity(0.6)),
                      _MapIconButton(
                        icon: Icons.remove,
                        tooltip: 'Zoom out',
                        onTap: _zoomOut,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Find Nearest Tipper Button
                _MapIconButtonStandalone(
                  icon: Icons.near_me_rounded,
                  tooltip: 'Focus nearest garbage tipper',
                  color: AppColors.primary,
                  iconColor: Colors.white,
                  onTap: _focusNearestTipper,
                ),
                const SizedBox(height: 10),

                // Recenter GPS Button
                _isFetchingGPS
                    ? Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: AppColors.primary, width: 1.5),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: const CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      )
                    : _MapIconButtonStandalone(
                        icon: Icons.my_location,
                        tooltip: 'Recenter to current live location',
                        onTap: _recenterMap,
                      ),
              ],
            ),
          ),

          // 4. Floating Real-time Fleet Tipper Card
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width >= 900 ? 760 : 540,
                ),
                child: ValueListenableBuilder<List<GarbageVehicleModel>>(
                  valueListenable: FleetTrackingService.instance.vehiclesNotifier,
                  builder: (context, vehicles, _) {
                    final nearest = FleetTrackingService.instance.getNearestVehicle(_userLocation);
                    final vehicle = _selectedVehicle ?? nearest ?? (vehicles.isNotEmpty ? vehicles.first : null);

                    final String title = vehicle?.vehicleNumber ?? 'Tipper #102';
                    final String driver = vehicle?.driverName ?? 'Ramesh Gowda';
                    final String routeInfo = vehicle?.assignedRoute ?? (vehicle?.ward ?? 'Ward 112 (Indiranagar)');
                    final double distMeters = vehicle?.distanceMeters ?? 800.0;
                    final String distStr = distMeters >= 1000
                        ? '${(distMeters / 1000.0).toStringAsFixed(1)} km away'
                        : '${distMeters.round()} m away';
                    final int eta = vehicle?.etaMinutes ?? 4;
                    final double speed = vehicle?.speed ?? 22.0;
                    final bool isActive = vehicle?.isActive ?? true;

                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header: Status and Active Fleet Count
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _selectedVehicle != null
                                        ? 'Selected Tipper'
                                        : 'Nearest Garbage Tipper',
                                    style: const TextStyle(
                                      fontFamily: 'Plus Jakarta Sans',
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (vehicles.length > 1) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceElevated,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${vehicles.length} Active',
                                        style: const TextStyle(
                                          fontFamily: 'Plus Jakarta Sans',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (isActive ? AppColors.success : AppColors.warning).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: isActive ? AppColors.success : AppColors.warning,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isActive ? 'Active • On Route' : 'Idle',
                                      style: TextStyle(
                                        fontFamily: 'Plus Jakarta Sans',
                                        fontSize: 11,
                                        color: isActive ? AppColors.success : AppColors.warning,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Vehicle Info Row
                          Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                ),
                                child: const Icon(Icons.local_shipping, color: AppColors.primary, size: 26),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontFamily: 'Plus Jakarta Sans',
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '• $driver',
                                          style: const TextStyle(
                                            fontFamily: 'Plus Jakarta Sans',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      routeInfo,
                                      style: const TextStyle(
                                        fontFamily: 'Plus Jakarta Sans',
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        _InfoChip(
                                          icon: Icons.place_rounded,
                                          label: distStr,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        _InfoChip(
                                          icon: Icons.timer_outlined,
                                          label: 'ETA $eta min',
                                          color: const Color(0xFF10B981),
                                        ),
                                        if (speed > 0) ...[
                                          const SizedBox(width: 8),
                                          _InfoChip(
                                            icon: Icons.speed,
                                            label: '${speed.toStringAsFixed(0)} km/h',
                                            color: Colors.orange,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Action Buttons: Track Vehicle & Call Driver
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.navigation_rounded, size: 18),
                                  label: const Text(
                                    'Track Tipper Live',
                                    style: TextStyle(
                                      fontFamily: 'Plus Jakarta Sans',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onPressed: () {
                                    if (vehicle != null) {
                                      _trackVehicle(vehicle);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: IconButton(
                                  tooltip: 'Call tipper driver',
                                  icon: const Icon(Icons.phone_in_talk_rounded, color: AppColors.primary, size: 20),
                                  onPressed: () => _callDriver(vehicle?.phoneNumber),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _MapIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: AppColors.textPrimary, size: 20),
          ),
        ),
      ),
    );
  }
}

class _MapIconButtonStandalone extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color? color;
  final Color? iconColor;

  const _MapIconButtonStandalone({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color ?? Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: color != null ? Colors.transparent : AppColors.border),
          ),
          child: Icon(icon, color: iconColor ?? AppColors.primary, size: 22),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
