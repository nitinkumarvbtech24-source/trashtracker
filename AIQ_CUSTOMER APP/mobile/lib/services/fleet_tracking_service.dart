import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/garbage_vehicle_model.dart';

class FleetTrackingService {
  static final FleetTrackingService instance = FleetTrackingService._internal();
  FleetTrackingService._internal();

  static const String _liveTrackingUrl =
      'https://firestore.googleapis.com/v1/projects/takemytrash/databases/(default)/documents/live_tracking';
  static const String _vehiclesUrl =
      'https://firestore.googleapis.com/v1/projects/takemytrash/databases/(default)/documents/vehicles?pageSize=100';
  static const String _serverConfigUrl =
      'https://firestore.googleapis.com/v1/projects/takemytrash/databases/(default)/documents/settings/server_config';

  final ValueNotifier<List<GarbageVehicleModel>> vehiclesNotifier =
      ValueNotifier<List<GarbageVehicleModel>>(_sampleVehicles);

  final ValueNotifier<String?> activeBackendUrlNotifier = ValueNotifier<String?>(null);

  final Map<String, Map<String, dynamic>> _vehicleMetaCache = {};
  Timer? _pollingTimer;
  bool _isFetching = false;
  bool _hasStarted = false;

  static final List<GarbageVehicleModel> _sampleVehicles = [
    GarbageVehicleModel(
      vehicleId: 'KA-04-TR-102',
      vehicleNumber: 'KA-04-TR-102',
      currentLatitude: 12.9750,
      currentLongitude: 77.5980,
      status: 'In Route',
      etaMinutes: 4,
      assignedRoute: 'Ramesh Gowda • Ward 112',
      lastUpdatedTimestamp: DateTime.now(),
      driverName: 'Ramesh Gowda',
      phoneNumber: '+919876543210',
      ward: 'Ward 112 (Indiranagar)',
      zone: 'East Zone',
      speed: 24.5,
      isActive: true,
    ),
    GarbageVehicleModel(
      vehicleId: 'KA-04-TR-205',
      vehicleNumber: 'KA-04-TR-205',
      currentLatitude: 12.9680,
      currentLongitude: 77.5910,
      status: 'In Route',
      etaMinutes: 8,
      assignedRoute: 'Suresh Kumar • Ward 114',
      lastUpdatedTimestamp: DateTime.now(),
      driverName: 'Suresh Kumar',
      phoneNumber: '+919876543211',
      ward: 'Ward 114 (Shanthi Nagar)',
      zone: 'Central Zone',
      speed: 18.0,
      isActive: true,
    ),
    GarbageVehicleModel(
      vehicleId: 'KA-04-TR-318',
      vehicleNumber: 'KA-04-TR-318',
      currentLatitude: 12.9820,
      currentLongitude: 77.6050,
      status: 'In Route',
      etaMinutes: 12,
      assignedRoute: 'Anand Murthy • Ward 88',
      lastUpdatedTimestamp: DateTime.now(),
      driverName: 'Anand Murthy',
      phoneNumber: '+919876543212',
      ward: 'Ward 88 (Ulsoor)',
      zone: 'East Zone',
      speed: 21.0,
      isActive: true,
    ),
  ];

  List<GarbageVehicleModel> get liveVehicles => vehiclesNotifier.value;

  void startLiveTracking() {
    if (_hasStarted) return;
    _hasStarted = true;
    _fetchVehicleMetadata();
    _fetchServerConfig();
    _pollLiveTracking();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollLiveTracking();
    });
  }

  void stopLiveTracking() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _hasStarted = false;
  }

  Future<void> refreshNow() async {
    await _pollLiveTracking();
  }

  Future<void> _fetchServerConfig() async {
    try {
      final res = await http.get(Uri.parse(_serverConfigUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final fields = data['fields'] as Map<String, dynamic>?;
        if (fields != null) {
          final activeUrl = fields['active_backend_url']?['stringValue'] ??
              fields['cloudflare_url']?['stringValue'];
          if (activeUrl != null && activeUrl.toString().isNotEmpty) {
            activeBackendUrlNotifier.value = activeUrl.toString();
          }
        }
      }
    } catch (e) {
      debugPrint('FleetTrackingService: server_config fetch warning: $e');
    }
  }

  Future<void> _fetchVehicleMetadata() async {
    try {
      final res = await http.get(Uri.parse(_vehiclesUrl)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final docs = (data['documents'] as List<dynamic>?) ?? [];
        for (var doc in docs) {
          final name = (doc['name'] as String).split('/').last;
          final fields = (doc['fields'] as Map<String, dynamic>?) ?? {};

          final driverName = fields['driverName']?['stringValue'] ?? 'Fleet Driver';
          final phone = fields['phoneNumber']?['stringValue'];
          final ward = fields['ward']?['stringValue'] ?? fields['assignedWard']?['stringValue'];
          final zone = fields['zone']?['stringValue'];
          final vehNum = fields['vehicleNumber']?['stringValue'] ?? name;

          final cleanKey = name.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
          _vehicleMetaCache[cleanKey] = {
            'driverName': driverName,
            'phoneNumber': phone,
            'ward': ward,
            'zone': zone,
            'vehicleNumber': vehNum,
          };
        }
      }
    } catch (e) {
      debugPrint('FleetTrackingService: vehicles meta fetch warning: $e');
    }
  }

  Future<void> _pollLiveTracking() async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      final res = await http.get(Uri.parse(_liveTrackingUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final docs = (data['documents'] as List<dynamic>?) ?? [];
        final List<GarbageVehicleModel> list = [];

        for (var doc in docs) {
          final docId = (doc['name'] as String).split('/').last;
          final fields = (doc['fields'] as Map<String, dynamic>?) ?? {};

          final latVal = fields['lat']?['doubleValue'] ?? fields['lat']?['integerValue'];
          final lngVal = fields['lng']?['doubleValue'] ?? fields['lng']?['integerValue'];
          if (latVal == null || lngVal == null) continue;

          final double lat = (latVal as num).toDouble();
          final double lng = (lngVal as num).toDouble();
          if (lat == 0.0 && lng == 0.0) continue;

          final bool isActive = fields['isActive']?['booleanValue'] ?? false;
          final double speed = ((fields['speed']?['doubleValue'] ?? fields['speed']?['integerValue'] ?? 0.0) as num).toDouble();
          final String? tsStr = fields['timestamp']?['timestampValue'];
          final DateTime ts = tsStr != null ? (DateTime.tryParse(tsStr) ?? DateTime.now()) : DateTime.now();

          final cleanId = docId.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
          final meta = _vehicleMetaCache[cleanId] ?? {};

          final String vehNum = meta['vehicleNumber'] ?? docId.toUpperCase();
          final String driver = meta['driverName'] ?? 'Fleet Driver';
          final String? phone = meta['phoneNumber'];
          final String? ward = meta['ward'];
          final String? zone = meta['zone'];

          final String status = isActive ? (speed > 0.6 ? 'In Route' : 'Idle') : 'Inactive';

          list.add(GarbageVehicleModel(
            vehicleId: docId,
            vehicleNumber: vehNum,
            currentLatitude: lat,
            currentLongitude: lng,
            status: status,
            etaMinutes: 5,
            assignedRoute: ward != null ? '$driver • $ward' : '$driver • Central Bangalore',
            lastUpdatedTimestamp: ts,
            driverName: driver,
            phoneNumber: phone,
            ward: ward,
            zone: zone,
            speed: speed,
            isActive: isActive,
          ));
        }

        if (list.isNotEmpty) {
          vehiclesNotifier.value = list;
        } else if (vehiclesNotifier.value.isEmpty) {
          vehiclesNotifier.value = _sampleVehicles;
        }
      }
    } catch (e) {
      debugPrint('FleetTrackingService: live_tracking poll warning: $e');
    } finally {
      _isFetching = false;
    }
  }

  /// Calculates the nearest vehicle to the customer location, with real distance and ETA.
  GarbageVehicleModel? getNearestVehicle(LatLng userLocation) {
    final list = vehiclesNotifier.value;
    if (list.isEmpty) return null;

    const distanceCalc = Distance();
    GarbageVehicleModel? nearest;
    double minDistance = double.infinity;

    for (var v in list) {
      final vLoc = LatLng(v.currentLatitude, v.currentLongitude);
      final distMeters = distanceCalc.as(LengthUnit.Meter, userLocation, vLoc);

      // Prioritize active/online vehicles
      final double weightedDist = v.isActive ? distMeters : distMeters + 2000.0;

      if (weightedDist < minDistance) {
        minDistance = weightedDist;
        // ETA assuming city tipper average speed of ~25 km/h (~400 m/min) + buffer
        final int eta = (distMeters / 350.0).clamp(1.0, 45.0).round();
        nearest = v.copyWith(
          distanceMeters: distMeters,
          etaMinutes: eta,
        );
      }
    }

    return nearest;
  }
}
