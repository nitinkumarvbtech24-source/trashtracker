import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_apple/geolocator_apple.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_service.dart';
import 'auth_service.dart';
import 'wake_manager.dart';

class TelemetryService extends ChangeNotifier {
  static final TelemetryService _instance = TelemetryService._internal();
  factory TelemetryService() => _instance;
  TelemetryService._internal();

  Position? _currentPosition;
  String _currentAddress = "Resolving exact location...";
  StreamSubscription<Position>? _positionStream;
  bool _isNavigating = false;
  // Analytics State
  double _totalDistanceMeters = 0.0;
  List<Map<String, dynamic>> _dailyRoute = [];
  DateTime? _lastFirestoreWrite;
  String get _todayDateString => DateTime.now().toIso8601String().split('T')[0];

  // Trip State
  String? currentTripId;
  double tripDistanceMeters = 0.0;
  int tripFlags = 0;


  Position? get currentPosition => _currentPosition;
  String get currentAddress => _currentAddress;
  bool get isNavigating => _isNavigating;
  double get totalDistanceKm => _totalDistanceMeters / 1000.0;
  List<Map<String, dynamic>> get dailyRoute => _dailyRoute;
  void setNavigating(bool val) {
    _isNavigating = val;
    WakeManager.update();
    final auth = AuthService();
    if (auth.isLoggedIn && auth.vehicleNumber != null) {
      final db = FirebaseFirestore.instance;
      final vNum = auth.vehicleNumber!;

      if (_isNavigating) {
        currentTripId = 'trip_${DateTime.now().millisecondsSinceEpoch}';
        tripDistanceMeters = 0.0;
        tripFlags = 0;
        _dailyRoute.clear(); // Clear local route memory for the new trip
        db.collection('vehicles').doc(vNum).collection('trips').doc(currentTripId).set({
          'tripId': currentTripId,
          'vehicleNumber': vNum,
          'date': _todayDateString,
          'startTime': DateTime.now().toIso8601String(),
          'distanceKm': 0.0,
          'flags': 0,
        });
      } else {
        if (currentTripId != null) {
          db.collection('vehicles').doc(vNum).collection('trips').doc(currentTripId).update({
            'endTime': DateTime.now().toIso8601String(),
            'distanceKm': tripDistanceMeters / 1000.0,
            'flags': tripFlags,
          });
          currentTripId = null;
        }
      }

      db.collection('live_tracking').doc(vNum).set({
        'isActive': _isNavigating,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    notifyListeners();
  }

  void incrementTripFlags() {
    if (_isNavigating && currentTripId != null) {
      tripFlags++;
      final auth = AuthService();
      if (auth.isLoggedIn && auth.vehicleNumber != null) {
        FirebaseFirestore.instance.collection('vehicles').doc(auth.vehicleNumber!).collection('trips').doc(currentTripId).update({
          'flags': tripFlags,
        });
      }
    }
  }

  Future<void> initialize() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied, we cannot request permissions.');
    }

    _startTracking();
  }

  void _startTracking() {
    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 1),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }

    _positionStream?.cancel(); // Fix memory leak causing crashes
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _updateAddress(position);
      
      // Calculate Distance if navigating
      if (_isNavigating && _currentPosition != null) {
        final dist = Geolocator.distanceBetween(
          _currentPosition!.latitude, _currentPosition!.longitude,
          position.latitude, position.longitude
        );
        _totalDistanceMeters += dist;
        tripDistanceMeters += dist;
        if (currentTripId != null && _dailyRoute.length % 5 == 0) {
          final auth = AuthService();
          if (auth.vehicleNumber != null) {
            FirebaseFirestore.instance.collection('vehicles').doc(auth.vehicleNumber!).collection('trips').doc(currentTripId).update({
              'distanceKm': tripDistanceMeters / 1000.0,
            });
          }
        }
        _dailyRoute.add({
          'lat': position.latitude,
          'lng': position.longitude,
          'timestamp': position.timestamp.millisecondsSinceEpoch,
        });
      }
      
      _currentPosition = position;
      
      // Save to local DB for syncing
      DatabaseService().insertTelemetry(
        position.latitude,
        position.longitude,
        position.speed,
        position.timestamp.millisecondsSinceEpoch,
      );
      
      // Push live tracking and daily stats to Firestore throttled (every 5 seconds)
      final now = DateTime.now();
      if (_lastFirestoreWrite == null || now.difference(_lastFirestoreWrite!).inSeconds >= 5) {
        _lastFirestoreWrite = now;

        final auth = AuthService();
        if (auth.isLoggedIn && auth.vehicleNumber != null) {
          final db = FirebaseFirestore.instance;
          
          db.collection('live_tracking').doc(auth.vehicleNumber).set({
            'lat': position.latitude,
            'lng': position.longitude,
            'speed': position.speed,
            'timestamp': FieldValue.serverTimestamp(),
            'isActive': _isNavigating,
          }, SetOptions(merge: true));

          if (_isNavigating) {
            db.collection('vehicles').doc(auth.vehicleNumber!)
              .collection('daily_stats').doc(_todayDateString)
              .set({
                'distance_km': _totalDistanceMeters / 1000.0,
                'route': FieldValue.arrayUnion([{
                  'lat': position.latitude,
                  'lng': position.longitude,
                  'timestamp': position.timestamp.millisecondsSinceEpoch,
                }]),
                'last_updated': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
          }
        }
      }
      
      notifyListeners();
    });
  }

  Future<void> _updateAddress(Position position) async {
    try {
      final geocoder = Geocoding();
      List<Placemark> placemarks = await geocoder.placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        _currentAddress = "${place.street}, ${place.locality}, ${place.postalCode}";
        notifyListeners();
      }
    } catch (e) {
    }
  }

  void disposeService() {
    _positionStream?.cancel();
  }
}
