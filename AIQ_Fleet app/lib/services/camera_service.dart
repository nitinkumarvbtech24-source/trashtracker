import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gal/gal.dart';
import 'database_service.dart';
import 'telemetry_service.dart';
import '../constants.dart';
import 'wake_manager.dart';

class CameraService extends ChangeNotifier {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  List<Map<String, dynamic>> _cachedWards = [];
  List<Map<String, dynamic>> _cachedZones = [];

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  int _currentCameraIndex = 0;
  Timer? _chunkTimer;
  Timer? _snapshotTimer;
  Timer? _healthCheckTimer;

  bool _isGarbageTunnelConnected = false;
  bool _isGarbageBackendConnected = false;
  bool _isHealthTunnelConnected = false;
  bool _isHealthBackendConnected = false;

  bool get isGarbageConnected => _isGarbageBackendConnected;
  bool get isHealthConnected => _isHealthBackendConnected;

  bool get isGarbageTunnelConnected => _isGarbageTunnelConnected;
  bool get isGarbageBackendConnected => _isGarbageBackendConnected;
  bool get isHealthTunnelConnected => _isHealthTunnelConnected;
  bool get isHealthBackendConnected => _isHealthBackendConnected;

  String _latestGarbageStatus = 'UNKNOWN';
  Map<String, dynamic>? latestResult;
  String _latestHealthStatus = 'UNKNOWN';
  String get latestRoadStatus => _latestGarbageStatus;

  // Offline Queue State (Sequential Delivery)
  int _pendingQueueCount = 0;
  int get pendingQueueCount => _pendingQueueCount;
  bool _isProcessingQueue = false;
  bool get isProcessingQueue => _isProcessingQueue;
  String _queueStatusMessage = 'Idle';
  String get queueStatusMessage => _queueStatusMessage;
  Timer? _queueWorkerTimer;

  Future<void> refreshPendingQueueCount() async {
    try {
      _pendingQueueCount = await DatabaseService().getQueuedSnapshotCount();
      notifyListeners();
    } catch (e) {
      debugPrint("Error refreshing queue count: $e");
    }
  }

  void startQueueProcessor() {
    _queueWorkerTimer?.cancel();
    _queueWorkerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_pendingQueueCount > 0 && !_isProcessingQueue && _isGarbageBackendConnected) {
        processQueueSequentially();
      }
    });
  }

  // Analytics State
  int _imagesCapturedToday = 0;
  int _imagesFlaggedToday = 0;
  int get imagesCapturedToday => _imagesCapturedToday;
  int get imagesFlaggedToday => _imagesFlaggedToday;
  String get _todayDateString => DateTime.now().toIso8601String().split('T')[0];

  // Auto Capture State
  bool _isAutoMode = false;
  bool _isAutoCapturing = false;
  double _intervalSeconds = 1.0;
  Timer? _autoCaptureTimer;
  String? _currentSessionId;

  bool get isAutoMode => _isAutoMode;
  bool get isAutoCapturing => _isAutoCapturing;
  double get intervalSeconds => _intervalSeconds; // Legacy, but kept for fallback/UI if needed
  
  // Dynamic Speed Rules
  bool _isDynamicSpeedEnabled = false;
  bool get isDynamicSpeedEnabled => _isDynamicSpeedEnabled;
  List<Map<String, dynamic>> _speedRules = [];
  List<Map<String, dynamic>> get speedRules => _speedRules;
  double _accumulatedTime = 0.0;

  Future<void> loadSpeedRules() async {
    final prefs = await SharedPreferences.getInstance();
    _isDynamicSpeedEnabled = prefs.getBool('isDynamicSpeedEnabled') ?? false;
    final rulesStr = prefs.getString('speedRules');
    if (rulesStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(rulesStr);
        _speedRules = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        _setDefaultRules();
      }
    } else {
      _setDefaultRules();
    }
    notifyListeners();
  }

  void _setDefaultRules() {
    _speedRules = [
      {'min': 0.0, 'max': 2.0, 'interval': 0.0}, // 0 means Paused
      {'min': 2.0, 'max': 30.0, 'interval': 5.0},
      {'min': 30.0, 'max': 150.0, 'interval': 2.0},
    ];
  }

  Future<void> updateSpeedRules(List<Map<String, dynamic>> rules) async {
    _speedRules = rules;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('speedRules', jsonEncode(rules));
    notifyListeners();
  }

  Future<void> toggleDynamicSpeedEnabled(bool value) async {
    _isDynamicSpeedEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDynamicSpeedEnabled', value);
    notifyListeners();
  }

  // Training Mode State
  bool _isTrainingMode = false;
  bool _isTrainingCapturing = false;
  bool _isTrainingAutoMode = true; // New state for auto/manual training
  double _trainingIntervalSeconds = 1.0;
  Timer? _trainingCaptureTimer;

  bool get isTrainingMode => _isTrainingMode;
  bool get isTrainingCapturing => _isTrainingCapturing;
  bool get isTrainingAutoMode => _isTrainingAutoMode;
  double get trainingIntervalSeconds => _trainingIntervalSeconds;

  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  
  List<double> get supportedZoomLevels {
    return [0.5, 1.0, 2.0];
  }

  String _aspectRatioMode = 'Full';
  String get aspectRatioMode => _aspectRatioMode;

  void setAspectRatioMode(String mode) {
    _aspectRatioMode = mode;
    notifyListeners();
  }

  void setAutoMode(bool value) {
    _isAutoMode = value;
    if (value) {
      _isTrainingMode = false;
      if (_isTrainingCapturing) toggleTrainingCapture(() => 0.0, () => 0.0); // Stop training capture if switching
    }
    WakeManager.update();
    notifyListeners();
  }

  void setIntervalSeconds(double value) {
    _intervalSeconds = value;
    notifyListeners();
  }

  void setTrainingMode(bool value) {
    _isTrainingMode = value;
    if (value) {
      _isAutoMode = false;
      if (_isAutoCapturing) toggleAutoCapture(() => 0.0, () => 0.0); // Stop auto capture if switching
    }
    WakeManager.update();
    notifyListeners();
  }

  void setTrainingIntervalSeconds(double value) {
    _trainingIntervalSeconds = value;
    notifyListeners();
  }

  Future<void> setTrainingAutoMode(bool value) async {
    _isTrainingAutoMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trainingAutoMode', value);
    if (!value && _isTrainingCapturing) {
      _trainingCaptureTimer?.cancel();
      _isTrainingCapturing = false;
    }
    WakeManager.update();
    notifyListeners();
  }

  Future<void> toggleAutoCapture(double Function() getLat, double Function() getLng, {VoidCallback? onSnap}) async {
    if (_isAutoCapturing) {
      _autoCaptureTimer?.cancel();
      captureManualSnapshot(getLat(), getLng(), sessionId: _currentSessionId, pointType: 'end');
      _isAutoCapturing = false;
      _currentSessionId = null;
      _latestGarbageStatus = 'UNKNOWN';
      _latestHealthStatus = 'UNKNOWN';
      latestResult = null;
      WakeManager.update();
      notifyListeners();
    } else {
      if (!isInitialized) {
        await initialize();
      }
      
      _isAutoCapturing = true;
      _currentSessionId = const Uuid().v4();
      WakeManager.update();
      notifyListeners();
      
      captureManualSnapshot(getLat(), getLng(), sessionId: _currentSessionId, pointType: 'start');
      if (onSnap != null) onSnap();

      _autoCaptureTimer = Timer.periodic(
        Duration(milliseconds: (_intervalSeconds * 1000).toInt()),
        (timer) {
          captureManualSnapshot(getLat(), getLng(), sessionId: _currentSessionId, pointType: 'intermediate');
          if (onSnap != null) onSnap();
        },
      );
    }
  }

  Future<void> toggleTrainingCapture(double Function() getLat, double Function() getLng, {VoidCallback? onSnap}) async {
    if (_isTrainingCapturing) {
      _trainingCaptureTimer?.cancel();
      _isTrainingCapturing = false;
      WakeManager.update();
      notifyListeners();
    } else {
      if (!isInitialized) {
        await initialize();
      }
      
      _isTrainingCapturing = true;
      WakeManager.update();
      notifyListeners();
      
      _captureTrainingSnapshot(getLat(), getLng());
      if (onSnap != null) onSnap();

      // Only start timer if auto mode
      if (_isTrainingAutoMode) {
        _trainingCaptureTimer = Timer.periodic(
          Duration(milliseconds: (_trainingIntervalSeconds * 1000).toInt()),
          (timer) {
            _captureTrainingSnapshot(getLat(), getLng());
            if (onSnap != null) onSnap();
          },
        );
      } else {
        // If manual mode, it's just a single shot, so we turn off capturing immediately
        _isTrainingCapturing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _captureTrainingSnapshot(double lat, double lng) async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) return;
      
      final XFile picture = await _controller!.takePicture();

      final prefs = await SharedPreferences.getInstance();
      final vehicleNumber = prefs.getString('vehicleNumber') ?? 'UnknownVehicle';
      final driverName = prefs.getString('driverName') ?? 'UnknownDriver';
      
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final timestamp = now.millisecondsSinceEpoch.toString();
      final fileName = "$timestamp.jpg";

      final folderName = "${vehicleNumber}_$driverName";

      // ALWAYS save locally first
      final directory = await getApplicationDocumentsDirectory();
      final trainingDir = Directory('${directory.path}/pending_training_images/$folderName/$dateStr');
      if (!await trainingDir.exists()) {
        await trainingDir.create(recursive: true);
      }
      final localFile = File('${trainingDir.path}/$fileName');
      await localFile.writeAsBytes(await picture.readAsBytes());
      
      // Save to device gallery using gal package
      try {
        final hasAccess = await Gal.hasAccess(toAlbum: true);
        if (!hasAccess) {
          await Gal.requestAccess(toAlbum: true);
        }
        await Gal.putImage(localFile.path, album: 'AIQ_Fleet_$dateStr');
      } catch (e) {
        debugPrint("Error saving to device gallery: $e");
      }
      
      // Save metadata locally to know where it was captured
      final metaFile = File('${trainingDir.path}/$timestamp.json');
      await metaFile.writeAsString(jsonEncode({
        'lat': lat,
        'lng': lng,
        'vehicle_number': vehicleNumber,
        'driver_name': driverName,
      }));

      // Try uploading asynchronously
      _syncPendingTrainingImages();

    } catch (e) {
      debugPrint("Error taking training snapshot: $e");
    }
  }

  bool _isSyncingTraining = false;
  Future<void> _syncPendingTrainingImages() async {
    if (_isSyncingTraining) return;
    _isSyncingTraining = true;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final pendingDir = Directory('${directory.path}/pending_training_images');
      if (!await pendingDir.exists()) {
        _isSyncingTraining = false;
        return;
      }

      final entities = await pendingDir.list(recursive: true).toList();
      final imageFiles = entities.whereType<File>().where((e) => e.path.endsWith('.jpg')).toList();

      for (var imageFile in imageFiles) {
        try {
          final bytes = await imageFile.readAsBytes();
          final base64Image = base64Encode(bytes);

          final pathParts = imageFile.path.split(Platform.pathSeparator);
          final fileName = pathParts.last;
          final dateStr = pathParts[pathParts.length - 2];
          final folderName = pathParts[pathParts.length - 3];
          final metaFileName = fileName.replaceAll('.jpg', '.json');
          final metaFile = File(imageFile.parent.path + Platform.pathSeparator + metaFileName);

          Map<String, dynamic> metadata = {};
          if (await metaFile.exists()) {
            metadata = jsonDecode(await metaFile.readAsString());
          }

          final response = await http.post(
            Uri.parse('$activeGarbageAiUrl/upload_training'),
            headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
            body: json.encode({
              'image': 'data:image/jpeg;base64,$base64Image',
              'vehicle_number': metadata['vehicle_number'] ?? 'Unknown',
              'driver_name': metadata['driver_name'] ?? 'Unknown',
            }),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final resBody = json.decode(response.body);
            final serverImageUrl = resBody['image_url'];

            await FirebaseFirestore.instance.collection('training_data').add({
              'folder_name': folderName,
              'date': dateStr,
              'image_url': '$activeGarbageAiUrl$serverImageUrl',
              'timestamp': FieldValue.serverTimestamp(),
              'lat': metadata['lat'] ?? 0.0,
              'lng': metadata['lng'] ?? 0.0,
              'vehicle_number': metadata['vehicle_number'] ?? 'Unknown',
              'driver_name': metadata['driver_name'] ?? 'Unknown',
            });

            await imageFile.delete();
            if (await metaFile.exists()) {
              await metaFile.delete();
            }
          }
        } catch (e) {
          debugPrint("Sync error for ${imageFile.path}: $e");
        }
      }
    } catch (e) {
      debugPrint("Error syncing training images: $e");
    }
    _isSyncingTraining = false;
  }

  CameraController? get controller => _controller;
  bool get isRecording => _isRecording;
  bool get isInitialized => _controller != null && _controller!.value.isInitialized;
  String? errorMessage;

  Future<void> _fetchWardsAndZones() async {
    try {
      final wardsSnapshot = await FirebaseFirestore.instance.collection('wards').get();
      _cachedWards = wardsSnapshot.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      
      final zonesSnapshot = await FirebaseFirestore.instance.collection('zones').get();
      _cachedZones = zonesSnapshot.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint("Error fetching wards and zones: $e");
    }
  }

  bool _isPointInPolygon(double lat, double lng, dynamic boundary) {
    if (boundary == null || boundary is! List || boundary.length < 3) return false;
    bool isInside = false;
    for (int i = 0, j = boundary.length - 1; i < boundary.length; j = i++) {
      double? lat1, lng1, lat2, lng2;
      
      var node1 = boundary[i];
      if (node1 is GeoPoint) {
        lat1 = node1.latitude;
        lng1 = node1.longitude;
      } else if (node1 is Map) {
        lat1 = (node1['lat'] ?? node1['latitude'])?.toDouble();
        lng1 = (node1['lng'] ?? node1['longitude'])?.toDouble();
      }
      
      var node2 = boundary[j];
      if (node2 is GeoPoint) {
        lat2 = node2.latitude;
        lng2 = node2.longitude;
      } else if (node2 is Map) {
        lat2 = (node2['lat'] ?? node2['latitude'])?.toDouble();
        lng2 = (node2['lng'] ?? node2['longitude'])?.toDouble();
      }
      
      if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) continue;

      if (((lng1 > lng) != (lng2 > lng)) &&
          (lat < (lat2 - lat1) * (lng - lng1) / (lng2 - lng1) + lat1)) {
        isInside = !isInside;
      }
    }
    return isInside;
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isTrainingAutoMode = prefs.getBool('trainingAutoMode') ?? true;
      await loadSpeedRules();
      await _fetchWardsAndZones();
      await refreshPendingQueueCount();
      startQueueProcessor();

      startHealthCheck();
      errorMessage = null;
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        errorMessage = "No cameras found on this device.";
        notifyListeners();
        return;
      }
      await _initCamera(_cameras[_currentCameraIndex]);
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
      debugPrint("Error initializing cameras: $e");
    }
  }

  Future<void> _initCamera(CameraDescription description) async {
    try {
      _controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      try {
        _minZoomLevel = await _controller!.getMinZoomLevel();
        _maxZoomLevel = await _controller!.getMaxZoomLevel();
      } catch (e) {
        debugPrint("Zoom level fetching failed, setting defaults: $e");
        _minZoomLevel = 1.0;
        _maxZoomLevel = 1.0;
      }
      
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
      debugPrint("Error initializing camera controller: $e");
    }
  }

  void startHealthCheck() {
    _checkHealth();
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkHealth());
  }

  Future<void> _checkHealth() async {
    try {
      final resG = await http.get(Uri.parse('$activeGarbageAiUrl/api/snapshots'), headers: {'ngrok-skip-browser-warning': 'true'}).timeout(const Duration(seconds: 3));
      final tunnelUp = true;
      final backendUp = resG.statusCode == 200;
      if (_isGarbageTunnelConnected != tunnelUp || _isGarbageBackendConnected != backendUp) {
        _isGarbageTunnelConnected = tunnelUp;
        _isGarbageBackendConnected = backendUp;
        notifyListeners();
      }
      if (backendUp) {
        if (_pendingQueueCount > 0 && !_isProcessingQueue) {
          processQueueSequentially();
        }
        if (!_isSyncingTraining) {
          _syncPendingTrainingImages();
        }
      }
    } catch (e) {
      if (_isGarbageTunnelConnected || _isGarbageBackendConnected) {
        _isGarbageTunnelConnected = false;
        _isGarbageBackendConnected = false;
        notifyListeners();
      }
    }
    
    try {
      final resH = await http.get(Uri.parse('$HEALTH_AI_URL/api/snapshots'), headers: {'ngrok-skip-browser-warning': 'true'}).timeout(const Duration(seconds: 3));
      final tunnelUp = true;
      final backendUp = resH.statusCode == 200;
      if (_isHealthTunnelConnected != tunnelUp || _isHealthBackendConnected != backendUp) {
        _isHealthTunnelConnected = tunnelUp;
        _isHealthBackendConnected = backendUp;
        notifyListeners();
      }
    } catch (e) {
      if (_isHealthTunnelConnected || _isHealthBackendConnected) {
        _isHealthTunnelConnected = false;
        _isHealthBackendConnected = false;
        notifyListeners();
      }
    }
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;
    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
    await _initCamera(_cameras[_currentCameraIndex]);
  }

  Future<void> setZoomLevel(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final minZoom = await _controller!.getMinZoomLevel();
      final maxZoom = await _controller!.getMaxZoomLevel();
      final clampedZoom = zoom.clamp(minZoom, maxZoom);
      await _controller!.setZoomLevel(clampedZoom);
    } catch (e) {
      debugPrint("Error setting zoom: $e");
    }
  }

  Future<void> toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      await _controller!.startVideoRecording();
      _isRecording = true;
      notifyListeners();

      // Chunk recording every 20 seconds
      _chunkTimer = Timer.periodic(const Duration(seconds: 20), (timer) async {
        final file = await _controller!.stopVideoRecording();
        DatabaseService().insertVideoChunk(file.path, DateTime.now().millisecondsSinceEpoch);
        await _controller!.startVideoRecording();
      });

      // AI Snapshots: Manual snapshot now replaces periodic ones
      // We no longer trigger periodic snapshots to match the web app's manual behavior
    } catch (e) {
      debugPrint("Error starting recording: $e");
    }
  }

  Future<Map<String, dynamic>?> captureManualSnapshot(double lat, double lng, {String? sessionId, String? pointType}) async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) return null;
      
      final XFile picture = await _controller!.takePicture();
      final bytes = await picture.readAsBytes();

      // Get real vehicle and ward details
      final prefs = await SharedPreferences.getInstance();
      final vehicleNumber = prefs.getString('vehicleNumber') ?? 'Unknown Vehicle';
      final assignedWard = prefs.getString('assignedWard') ?? 'Unknown Ward';

      String calculatedWard = 'Unknown Ward';
      String calculatedZone = 'Unknown Zone';
      
      for (var w in _cachedWards) {
        if (_isPointInPolygon(lat, lng, w['boundary'])) {
          calculatedWard = w['name'];
          break;
        }
      }
      if (calculatedWard == 'Unknown Ward') calculatedWard = assignedWard;
      
      for (var z in _cachedZones) {
        if (_isPointInPolygon(lat, lng, z['boundary'])) {
          calculatedZone = z['name'];
          break;
        }
      }

      final now = DateTime.now();
      final timestamp = now.millisecondsSinceEpoch;

      // 1. FAST DIRECT ONLINE PATH (when queue is empty and internet/server is available)
      if (_pendingQueueCount == 0) {
        try {
          final base64Image = base64Encode(bytes);
          final garbageResponse = await http.post(
            Uri.parse('$activeGarbageAiUrl/process_frame'),
            headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
            body: json.encode({
              'image': 'data:image/jpeg;base64,$base64Image',
              'lat': lat,
              'lng': lng,
              'vehicle_number': vehicleNumber,
              'ward': calculatedWard,
              'zone': calculatedZone,
              if (sessionId != null) 'session_id': sessionId,
              if (pointType != null) 'point_type': pointType
            }),
          ).timeout(const Duration(seconds: 12));

          if (garbageResponse.statusCode == 200) {
            _isGarbageTunnelConnected = true;
            _isGarbageBackendConnected = true;

            final directResult = await _handleGarbageSuccess(
              responseBody: garbageResponse.body,
              rawBytes: bytes,
              base64Image: base64Image,
              lat: lat,
              lng: lng,
              vehicleNumber: vehicleNumber,
              ward: calculatedWard,
              zone: calculatedZone,
              sessionId: sessionId,
              pointType: pointType,
              timestamp: timestamp,
            );

            // Trigger non-blocking Health AI
            _sendToHealthAi(base64Image, lat, lng, vehicleNumber, calculatedWard, calculatedZone, sessionId, pointType);

            return directResult;
          }
        } catch (netErr) {
          debugPrint("Direct upload failed (unstable connection / server down): $netErr");
          _isGarbageBackendConnected = false;
          notifyListeners();
        }
      }

      // 2. OFFLINE / UNSTABLE FALLBACK: Save to persistent SQLite queue (strict FIFO)
      await _queueSnapshotLocally(
        bytes: bytes,
        lat: lat,
        lng: lng,
        vehicleNumber: vehicleNumber,
        ward: calculatedWard,
        zone: calculatedZone,
        sessionId: sessionId,
        pointType: pointType,
        timestamp: timestamp,
      );

      // If backend is active and worker not running, attempt queue sync
      if (_isGarbageBackendConnected && !_isProcessingQueue) {
        processQueueSequentially();
      }

      final offlineResult = {
        'offline': true,
        'queued': true,
        'pendingCount': _pendingQueueCount,
        'road_status': 'Queued (Offline)',
        'message': 'Saved locally. Will sync sequentially when server is online.',
      };
      latestResult = offlineResult;
      notifyListeners();
      return offlineResult;
    } catch (e) {
      debugPrint("Error taking snapshot: $e");
      return null;
    }
  }

  Future<void> _queueSnapshotLocally({
    required List<int> bytes,
    required double lat,
    required double lng,
    required String vehicleNumber,
    required String ward,
    required String zone,
    String? sessionId,
    String? pointType,
    required int timestamp,
  }) async {
    try {
      final uuidStr = const Uuid().v4();
      final directory = await getApplicationDocumentsDirectory();
      final queueDir = Directory('${directory.path}/queued_snapshots');
      if (!await queueDir.exists()) {
        await queueDir.create(recursive: true);
      }
      final queueFile = File('${queueDir.path}/snap_${timestamp}_${uuidStr.substring(0, 8)}.jpg');
      await queueFile.writeAsBytes(bytes);

      await DatabaseService().insertQueuedSnapshot({
        'filePath': queueFile.path,
        'lat': lat,
        'lng': lng,
        'vehicleNumber': vehicleNumber,
        'ward': ward,
        'zone': zone,
        'sessionId': sessionId,
        'pointType': pointType,
        'timestamp': timestamp,
        'status': 'pending',
        'retryCount': 0,
        'createdAt': timestamp,
      });

      await refreshPendingQueueCount();
    } catch (e) {
      debugPrint("Error enqueueing snapshot: $e");
    }
  }

  Future<Map<String, dynamic>> _handleGarbageSuccess({
    required String responseBody,
    required List<int> rawBytes,
    required String base64Image,
    required double lat,
    required double lng,
    required String vehicleNumber,
    required String ward,
    required String zone,
    String? sessionId,
    String? pointType,
    required int timestamp,
  }) async {
    final resBody = json.decode(responseBody);
    final roadStatus = resBody['road_status'] ?? 'UNKNOWN';
    final confidence = (resBody['road_confidence'] as num?)?.toDouble() ?? 0.0;
    final imageUrl = resBody['image_url'];

    if (_latestGarbageStatus != roadStatus) {
      _latestGarbageStatus = roadStatus;
    }

    // Analytics updates
    _imagesCapturedToday++;
    if (roadStatus == 'Very Dirty Road' || roadStatus == 'Slightly Dirty Road' || roadStatus == 'Trash Detected') {
      _imagesFlaggedToday++;
    }

    // Sync analytics to Firestore
    try {
      FirebaseFirestore.instance.collection('vehicles').doc(vehicleNumber)
        .collection('daily_stats').doc(_todayDateString)
        .set({
          'images_captured': _imagesCapturedToday,
          'images_flagged': _imagesFlaggedToday,
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    } catch (fbStatErr) {
      debugPrint("Firestore stats update error: $fbStatErr");
    }

    final combinedResult = <String, dynamic>{
      'garbage': {
        'road_status': roadStatus,
        'road_confidence': confidence,
      },
      'road_status': roadStatus,
      'confidence': confidence,
    };

    // Download annotated image or fallback to raw
    try {
      List<int> imageToSave = rawBytes;
      if (imageUrl != null) {
        final annotatedResponse = await http.get(
          Uri.parse('$activeGarbageAiUrl$imageUrl'),
          headers: {'ngrok-skip-browser-warning': 'true'},
        ).timeout(const Duration(seconds: 10));
        if (annotatedResponse.statusCode == 200) {
          imageToSave = annotatedResponse.bodyBytes;
        }
      }

      final directory = await getApplicationDocumentsDirectory();
      final dateStr = DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String().split('T')[0];
      final localFolder = Directory('${directory.path}/local_flags/$dateStr');
      if (!await localFolder.exists()) {
        await localFolder.create(recursive: true);
      }
      final localFile = File('${localFolder.path}/$timestamp.jpg');
      await localFile.writeAsBytes(imageToSave);

      // Save to device gallery
      try {
        final hasAccess = await Gal.hasAccess(toAlbum: true);
        if (!hasAccess) await Gal.requestAccess(toAlbum: true);
        await Gal.putImage(localFile.path, album: 'AIQ_Fleet_$dateStr');
      } catch (galErr) {
        debugPrint("Gallery save error: $galErr");
      }

      // Insert to local database if trash detected
      if (roadStatus == 'Trash Detected') {
        await DatabaseService().insertLocalFlag(localFile.path, roadStatus, confidence, timestamp, lat, lng);
      }
    } catch (e) {
      debugPrint("Error downloading/saving annotated image: $e");
    }

    if (imageUrl != null) {
      if (roadStatus == 'Trash Detected') {
        try {
          await FirebaseFirestore.instance.collection('trash_spots').add({
            'lat': lat,
            'lng': lng,
            'road_status': roadStatus,
            'confidence': confidence,
            'image_url': '$activeGarbageAiUrl$imageUrl',
            'timestamp': FieldValue.serverTimestamp(),
            'status': 'Flagged',
            'vehicle_number': vehicleNumber,
            'ward': ward,
            'zone': zone,
            'model_version': MODEL_VERSION,
            if (sessionId != null) 'session_id': sessionId,
            if (pointType != null) 'point_type': pointType,
          });
        } catch (fbErr) {
          debugPrint("Firestore Upload Error: $fbErr");
        }
      }
    }

    latestResult = combinedResult;
    notifyListeners();
    return combinedResult;
  }

  Future<void> _sendToHealthAi(
    String base64Image,
    double lat,
    double lng,
    String vehicleNumber,
    String ward,
    String zone,
    String? sessionId,
    String? pointType,
  ) async {
    try {
      final healthResponse = await http.post(
        Uri.parse('$HEALTH_AI_URL/process_frame'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: json.encode({
          'image': 'data:image/jpeg;base64,$base64Image',
          'lat': lat,
          'lng': lng,
          'vehicle_number': vehicleNumber,
          'ward': ward,
          'zone': zone,
          if (sessionId != null) 'session_id': sessionId,
          if (pointType != null) 'point_type': pointType
        }),
      ).timeout(const Duration(seconds: 4));

      if (healthResponse.statusCode == 200) {
        _isHealthTunnelConnected = true;
        _isHealthBackendConnected = true;

        final resBody = json.decode(healthResponse.body);
        final roadStatus = resBody['road_status'] ?? 'UNKNOWN';
        final imageUrl = resBody['image_url'];

        if (_latestHealthStatus != roadStatus) {
          _latestHealthStatus = roadStatus;
          notifyListeners();
        }

        if (imageUrl != null && (roadStatus == 'Pothole Detected' || roadStatus == 'Bad Road')) {
          await FirebaseFirestore.instance.collection('health_spots').add({
            'lat': lat,
            'lng': lng,
            'road_status': roadStatus,
            'image_url': '$HEALTH_AI_URL$imageUrl',
            'timestamp': FieldValue.serverTimestamp(),
            'vehicle_number': vehicleNumber,
            'ward': ward,
            'status': 'Flagged',
            'zone': zone,
          });
        }
      }
    } catch (_) {
      // Non-blocking fallback
    }
  }

  Future<Map<String, dynamic>?> processQueueSequentially() async {
    if (_isProcessingQueue) return null;
    _isProcessingQueue = true;
    Map<String, dynamic>? lastProcessedResult;

    try {
      while (true) {
        // Fetch next oldest snapshot (strict FIFO)
        final nextItem = await DatabaseService().getNextPendingQueuedSnapshot();
        if (nextItem == null) {
          _queueStatusMessage = 'Queue empty';
          break;
        }

        final id = nextItem['id'] as int;
        final filePath = nextItem['filePath'] as String?;
        if (filePath == null) {
          await DatabaseService().deleteQueuedSnapshot(id);
          continue;
        }

        final file = File(filePath);
        if (!await file.exists()) {
          // File missing from storage, clean up orphan DB row
          await DatabaseService().deleteQueuedSnapshot(id);
          await refreshPendingQueueCount();
          continue;
        }

        final bytes = await file.readAsBytes();
        final base64Image = base64Encode(bytes);
        final lat = (nextItem['lat'] as num?)?.toDouble() ?? 0.0;
        final lng = (nextItem['lng'] as num?)?.toDouble() ?? 0.0;
        final vehicleNumber = (nextItem['vehicleNumber'] ?? 'Unknown Vehicle').toString();
        final ward = (nextItem['ward'] ?? 'Unknown Ward').toString();
        final zone = (nextItem['zone'] ?? 'Unknown Zone').toString();
        final sessionId = nextItem['sessionId'] as String?;
        final pointType = nextItem['pointType'] as String?;
        final timestamp = (nextItem['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

        _queueStatusMessage = 'Uploading queued item #$id ($_pendingQueueCount remaining)...';
        notifyListeners();

        // 1. Send to Garbage AI
        try {
          final garbageResponse = await http.post(
            Uri.parse('$activeGarbageAiUrl/process_frame'),
            headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
            body: json.encode({
              'image': 'data:image/jpeg;base64,$base64Image',
              'lat': lat,
              'lng': lng,
              'vehicle_number': vehicleNumber,
              'ward': ward,
              'zone': zone,
              if (sessionId != null) 'session_id': sessionId,
              if (pointType != null) 'point_type': pointType
            }),
          ).timeout(const Duration(seconds: 15));

          if (garbageResponse.statusCode == 200) {
            _isGarbageTunnelConnected = true;
            _isGarbageBackendConnected = true;

            final itemResult = await _handleGarbageSuccess(
              responseBody: garbageResponse.body,
              rawBytes: bytes,
              base64Image: base64Image,
              lat: lat,
              lng: lng,
              vehicleNumber: vehicleNumber,
              ward: ward,
              zone: zone,
              sessionId: sessionId,
              pointType: pointType,
              timestamp: timestamp,
            );
            lastProcessedResult = itemResult;

            // Non-blocking Health AI
            _sendToHealthAi(base64Image, lat, lng, vehicleNumber, ward, zone, sessionId, pointType);

            // Successfully processed! Remove from SQLite queue and delete temp file
            await DatabaseService().deleteQueuedSnapshot(id);
            try {
              if (await file.exists()) {
                await file.delete();
              }
            } catch (e) {
              debugPrint("Queue file deletion error: $e");
            }

            await refreshPendingQueueCount();
          } else {
            _queueStatusMessage = 'Server error (${garbageResponse.statusCode}). Paused queue.';
            break;
          }
        } catch (e) {
          debugPrint("Garbage AI sync error: $e");
          _isGarbageTunnelConnected = false;
          _isGarbageBackendConnected = false;
          _queueStatusMessage = 'Waiting for network ($_pendingQueueCount pending)';
          await DatabaseService().incrementQueuedSnapshotRetry(id);
          // Break loop to preserve strict sequential FIFO order
          break;
        }
      }
    } catch (e) {
      debugPrint("Sequential queue processor error: $e");
    } finally {
      _isProcessingQueue = false;
      await refreshPendingQueueCount();
      notifyListeners();
    }

    return lastProcessedResult;
  }

  Future<void> _stopRecording() async {
    try {
      _chunkTimer?.cancel();
      _snapshotTimer?.cancel();
      final file = await _controller!.stopVideoRecording();
      DatabaseService().insertVideoChunk(file.path, DateTime.now().millisecondsSinceEpoch);
      _isRecording = false;
      _latestGarbageStatus = 'UNKNOWN';
      _latestHealthStatus = 'UNKNOWN';
      latestResult = null;
      notifyListeners();
    } catch (e) {
      debugPrint("Error stopping recording: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _chunkTimer?.cancel();
    _snapshotTimer?.cancel();
    _healthCheckTimer?.cancel();
    _autoCaptureTimer?.cancel();
    _trainingCaptureTimer?.cancel();
    _queueWorkerTimer?.cancel();
    super.dispose();
  }
}
