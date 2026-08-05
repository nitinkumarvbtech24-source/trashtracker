import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'database_service.dart';
import '../constants.dart';

class CameraService extends ChangeNotifier {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  int _currentCameraIndex = 0;
  Timer? _chunkTimer;
  Timer? _snapshotTimer;
  Timer? _healthCheckTimer;

  bool _isBackendConnected = false;
  bool get isBackendConnected => _isBackendConnected;

  String _latestRoadStatus = 'UNKNOWN';
  String get latestRoadStatus => _latestRoadStatus;

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
  double get intervalSeconds => _intervalSeconds;

  void setAutoMode(bool value) {
    _isAutoMode = value;
    notifyListeners();
  }

  void setIntervalSeconds(double value) {
    _intervalSeconds = value;
    notifyListeners();
  }

  Future<void> toggleAutoCapture(double Function() getLat, double Function() getLng, {VoidCallback? onSnap}) async {
    if (_isAutoCapturing) {
      _autoCaptureTimer?.cancel();
      captureManualSnapshot(getLat(), getLng(), sessionId: _currentSessionId, pointType: 'end');
      _isAutoCapturing = false;
      _currentSessionId = null;
      _latestRoadStatus = 'UNKNOWN';
      notifyListeners();
    } else {
      if (!isInitialized) {
        await initialize();
      }
      
      _isAutoCapturing = true;
      _currentSessionId = const Uuid().v4();
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

  CameraController? get controller => _controller;
  bool get isRecording => _isRecording;
  bool get isInitialized => _controller != null && _controller!.value.isInitialized;
  String? errorMessage;

  Future<void> initialize() async {
    try {
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
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
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
      final response = await http.get(
        Uri.parse('$GARBAGE_AI_URL/api/snapshots'),
        headers: {'ngrok-skip-browser-warning': 'true'}
      ).timeout(const Duration(seconds: 3));
      final connected = response.statusCode == 200;
      if (_isBackendConnected != connected) {
        _isBackendConnected = connected;
        notifyListeners();
      }
    } catch (e) {
      if (_isBackendConnected) {
        _isBackendConnected = false;
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
      final base64Image = base64Encode(bytes);

      // Get real vehicle and ward details
      final prefs = await SharedPreferences.getInstance();
      final vehicleNumber = prefs.getString('vehicleNumber') ?? 'Unknown Vehicle';
      final ward = prefs.getString('assignedWard') ?? 'Unknown Ward';

      Map<String, dynamic> combinedResult = {};

      // 1. Send to Garbage AI
      try {
        final garbageResponse = await http.post(
          Uri.parse('$GARBAGE_AI_URL/process_frame'),
          headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
          body: json.encode({
            'image': 'data:image/jpeg;base64,$base64Image',
            'lat': lat,
            'lng': lng,
            'vehicle_number': vehicleNumber,
            'ward': ward,
            if (sessionId != null) 'session_id': sessionId,
            if (pointType != null) 'point_type': pointType
          }),
        ).timeout(const Duration(seconds: 30));

        if (garbageResponse.statusCode == 200) {
          if (!_isBackendConnected) {
            _isBackendConnected = true;
            notifyListeners();
          }
          final resBody = json.decode(garbageResponse.body);
          final roadStatus = resBody['road_status'] ?? 'UNKNOWN';
          final confidence = resBody['road_confidence'] ?? 0.0;
          final imageUrl = resBody['image_url'];
          
          if (_latestRoadStatus != roadStatus) {
            _latestRoadStatus = roadStatus;
            notifyListeners();
          }

          // Analytics updates
          _imagesCapturedToday++;
          if (roadStatus == 'Very Dirty Road' || roadStatus == 'Slightly Dirty Road') {
            _imagesFlaggedToday++;
          }
          
          // Sync analytics to Firestore
          FirebaseFirestore.instance.collection('vehicles').doc(vehicleNumber)
            .collection('daily_stats').doc(_todayDateString)
            .set({
              'images_captured': _imagesCapturedToday,
              'images_flagged': _imagesFlaggedToday,
              'last_updated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

          combinedResult['garbage'] = {
            'road_status': roadStatus,
            'road_confidence': confidence
          };
          
          if (imageUrl != null) {
            if (roadStatus == 'Very Dirty Road' || roadStatus == 'Slightly Dirty Road') {
              try {
                await FirebaseFirestore.instance.collection('trash_spots').add({
                  'lat': lat,
                  'lng': lng,
                  'road_status': roadStatus,
                  'confidence': confidence,
                  'image_url': imageUrl,
                  'timestamp': FieldValue.serverTimestamp(),
                  'status': 'Flagged',
                  'vehicle_number': vehicleNumber,
                  'ward': ward,
                  if (sessionId != null) 'session_id': sessionId,
                  if (pointType != null) 'point_type': pointType,
                });
              } catch (fbErr) {
                debugPrint("Firestore Upload Error: $fbErr");
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Garbage AI Error: $e");
        if (_isBackendConnected) {
          _isBackendConnected = false;
          notifyListeners();
        }
      }

      return combinedResult;
    } catch (e) {
      debugPrint("Error taking snapshot: $e");
      return null;
    }
  }

  Future<void> _stopRecording() async {
    try {
      _chunkTimer?.cancel();
      _snapshotTimer?.cancel();
      final file = await _controller!.stopVideoRecording();
      DatabaseService().insertVideoChunk(file.path, DateTime.now().millisecondsSinceEpoch);
      _isRecording = false;
      _latestRoadStatus = 'UNKNOWN';
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
    super.dispose();
  }
}
