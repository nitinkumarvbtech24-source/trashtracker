import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants.dart';

enum DeflagMode { auto, manual }

class ComndDeflagScreen extends StatefulWidget {
  final String documentId;
  final String collectionName;
  final String? initialVehicleNumber;
  final String? initialLocation;
  final double? lat;
  final double? lng;
  final String? ward;
  final String? zone;
  final DeflagMode initialMode;

  const ComndDeflagScreen({
    super.key,
    required this.documentId,
    this.collectionName = 'trash_spots',
    this.initialVehicleNumber,
    this.initialLocation,
    this.lat,
    this.lng,
    this.ward,
    this.zone,
    this.initialMode = DeflagMode.auto,
  });

  /// Displays the choice bottom sheet allowing user to select Manual or Auto Deflag
  static Future<bool?> showDeflagSelectionModal({
    required BuildContext context,
    required String documentId,
    String collectionName = 'trash_spots',
    String? initialVehicleNumber,
    String? initialLocation,
    double? lat,
    double? lng,
    String? ward,
    String? zone,
  }) async {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DeflagChoiceBottomSheet(
        documentId: documentId,
        collectionName: collectionName,
        initialVehicleNumber: initialVehicleNumber,
        initialLocation: initialLocation,
        lat: lat,
        lng: lng,
        ward: ward,
        zone: zone,
      ),
    );
  }

  @override
  State<ComndDeflagScreen> createState() => _ComndDeflagScreenState();
}

class _ComndDeflagScreenState extends State<ComndDeflagScreen> {
  late DeflagMode _currentMode;

  // Camera State (Matches AIQ_Fleet camera_screen.dart)
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  String? _cameraError;
  double _currentZoom = 1.0;
  final List<double> _supportedZoomLevels = [1.0, 2.0, 3.0];
  bool _showSnapAnimation = false;

  // AI & Rescan State
  bool _isAiConnected = false;
  Timer? _connectionTimer;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _lastAiResult;
  bool _isAutoScanning = false;
  Timer? _autoScanTimer;
  bool _isAutoDeflagged = false;

  // Settings
  String _aspectRatioMode = 'Full';
  double _intervalSeconds = 2.0;

  // Manual Mode State
  XFile? _manualPickedFile;
  Uint8List? _manualImageBytes;
  bool _isManualSubmitting = false;
  final TextEditingController _noteController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
    _initCamera();
    _checkAiConnection();
    _connectionTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkAiConnection());
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = "No camera hardware detected on device");
        return;
      }

      // Default to back camera
      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _cameraError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraError = "Failed to initialize camera: $e";
          _isCameraReady = false;
        });
      }
    }
  }

  Future<void> _checkAiConnection() async {
    try {
      final res = await http.get(
        Uri.parse(activeGarbageAiUrl),
        headers: {'ngrok-skip-browser-warning': 'true'},
      ).timeout(const Duration(seconds: 4));
      if (mounted) {
        setState(() => _isAiConnected = res.statusCode == 200 || res.statusCode == 404);
      }
    } catch (_) {
      if (mounted) setState(() => _isAiConnected = false);
    }
  }

  @override
  void dispose() {
    _connectionTimer?.cancel();
    _autoScanTimer?.cancel();
    _cameraController?.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _triggerSnapAnimation() {
    if (!mounted) return;
    setState(() => _showSnapAnimation = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _showSnapAnimation = false);
    });
  }

  Future<void> _setZoomLevel(double zoom) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final maxZoom = await _cameraController!.getMaxZoomLevel();
      final minZoom = await _cameraController!.getMinZoomLevel();
      final clamped = zoom.clamp(minZoom, maxZoom);
      await _cameraController!.setZoomLevel(clamped);
      setState(() => _currentZoom = zoom);
    } catch (e) {
      debugPrint("Error setting zoom: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // AUTO AI RESCAN LOGIC (Calls activeGarbageAiUrl/process_frame & Auto-Deflags)
  // ---------------------------------------------------------------------------
  Future<void> _handleCaptureAndRescan({Uint8List? directBytes}) async {
    if (_isAnalyzing || _isAutoDeflagged) return;

    Uint8List bytes;
    if (directBytes != null) {
      bytes = directBytes;
    } else {
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        // Fallback: Pick from gallery to test rescan
        _pickGalleryForAiRescan();
        return;
      }
      try {
        _triggerSnapAnimation();
        SystemSound.play(SystemSoundType.click);
        final pic = await _cameraController!.takePicture();
        bytes = await pic.readAsBytes();
      } catch (e) {
        debugPrint("Error capturing frame: $e");
        return;
      }
    }

    setState(() {
      _isAnalyzing = true;
      _lastAiResult = null;
    });

    try {
      final base64Image = base64Encode(bytes);
      final response = await http.post(
        Uri.parse('$activeGarbageAiUrl/process_frame'),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: json.encode({
          'image': 'data:image/jpeg;base64,$base64Image',
          'lat': widget.lat ?? 12.9716,
          'lng': widget.lng ?? 77.5946,
          'vehicle_number': widget.initialVehicleNumber ?? 'Authority_App_Deflag',
          'ward': widget.ward ?? '',
          'zone': widget.zone ?? '',
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final resBody = json.decode(response.body);
        final String roadStatus = resBody['road_status']?.toString() ?? 'UNKNOWN';
        final int trashCount = (resBody['trash_count'] as num?)?.toInt() ?? 0;
        final double confidence = (resBody['road_confidence'] as num?)?.toDouble() ?? 
                                  ((resBody['confidence'] as num?)?.toDouble() ?? 0.0);
        final String? imageUrl = resBody['image_url']?.toString();

        final isVeryDirty = roadStatus == 'Very Dirty Road' || roadStatus == 'Very Dirty';
        final isClean = (roadStatus == 'No Trash Detected' || roadStatus == 'Clean Road') || 
                        (!isVeryDirty && roadStatus != 'Trash Detected' && roadStatus != 'Slightly Dirty Road' && trashCount == 0);

        if (mounted) {
          setState(() {
            _isAnalyzing = false;
            _lastAiResult = {
              'road_status': roadStatus,
              'trash_count': trashCount,
              'confidence': confidence,
              'image_url': imageUrl,
              'is_clean': isClean,
              'is_very_dirty': isVeryDirty,
              'mobilenet_result': resBody['mobilenet_result'],
            };
          });
        }

        // AUTOMATIC DEFLAG TRIGGER!
        if (isClean) {
          await _executeAutoDeflag(roadStatus, confidence, imageUrl);
        }
      } else {
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
            _lastAiResult = {
              'error': 'AI server responded with status ${response.statusCode}',
              'is_clean': false,
            };
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _lastAiResult = {
            'error': 'Connection timed out or failed ($e)',
            'is_clean': false,
          };
        });
      }
    }
  }

  Future<void> _executeAutoDeflag(String roadStatus, double confidence, String? imageUrl) async {
    _stopAutoScanning();
    setState(() => _isAutoDeflagged = true);
    SystemSound.play(SystemSoundType.click);

    try {
      await FirebaseFirestore.instance.collection(widget.collectionName).doc(widget.documentId).update({
        'status': 'Deflagged',
        'deflagged_at': FieldValue.serverTimestamp(),
        'deflag_method': 'AI Rescan Auto-Deflag',
        'deflag_ai_status': roadStatus,
        'deflag_confidence': confidence,
        'deflag_note': 'Automatically deflagged by AI Rescan: Verified Clean / No Trash Detected',
        if (imageUrl != null) 'deflag_photo_url': imageUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(LucideIcons.checkCheck, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🎉 AI Rescan Confirmed Clean! Spot Automatically Deflagged!',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Close screen after celebration
      await Future.delayed(const Duration(milliseconds: 2200));
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Error auto-deflagging spot: $e");
    }
  }

  void _toggleAutoScanning() {
    if (_isAutoScanning) {
      _stopAutoScanning();
    } else {
      _startAutoScanning();
    }
  }

  void _startAutoScanning() {
    setState(() => _isAutoScanning = true);
    _handleCaptureAndRescan();
    _autoScanTimer?.cancel();
    _autoScanTimer = Timer.periodic(Duration(milliseconds: (_intervalSeconds * 1000).toInt()), (_) {
      if (mounted && !_isAnalyzing && !_isAutoDeflagged) {
        _handleCaptureAndRescan();
      }
    });
  }

  void _stopAutoScanning() {
    _autoScanTimer?.cancel();
    if (mounted) setState(() => _isAutoScanning = false);
  }

  Future<void> _pickGalleryForAiRescan() async {
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        _handleCaptureAndRescan(directBytes: bytes);
      }
    } catch (e) {
      debugPrint("Error picking image for AI: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // MANUAL DEFLAG LOGIC (Gallery / Instant Photo Upload)
  // ---------------------------------------------------------------------------
  Future<void> _pickManualImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(source: source, imageQuality: 85);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _manualPickedFile = picked;
          _manualImageBytes = bytes;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _submitManualDeflag() async {
    setState(() => _isManualSubmitting = true);

    try {
      String? base64Photo;
      if (_manualImageBytes != null) {
        base64Photo = base64Encode(_manualImageBytes!);
      }

      final note = _noteController.text.trim().isNotEmpty
          ? _noteController.text.trim()
          : 'Manual Verification by Authority Officer';

      await FirebaseFirestore.instance.collection(widget.collectionName).doc(widget.documentId).update({
        'status': 'Deflagged',
        'deflagged_at': FieldValue.serverTimestamp(),
        'deflag_method': 'Manual Verification',
        'deflag_note': note,
        if (base64Photo != null) 'deflag_photo_base64': base64Photo,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(LucideIcons.checkCheck, color: Colors.white),
                SizedBox(width: 10),
                Text('Spot marked as Deflagged / Cleaned!', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isManualSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD METHOD (Switches between Auto AI Camera & Manual Deflag)
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_currentMode == DeflagMode.manual) {
      return _buildManualDeflagView();
    }
    return _buildAutoAiCameraView();
  }

  // ===========================================================================
  // 1. AUTO AI CAMERA VIEW (Exact Fleet App Camera Screen Match)
  // ===========================================================================
  Widget _buildAutoAiCameraView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full Screen Camera Preview
          if (_isCameraReady && _cameraController != null)
            Center(
              child: AspectRatio(
                aspectRatio: 1 / _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.cameraOff, color: Colors.white38, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _cameraError ?? "Camera Offline",
                      style: const TextStyle(color: Colors.redAccent, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _pickGalleryForAiRescan,
                      icon: const Icon(LucideIcons.image, size: 18),
                      label: const Text('Browse Photo for AI Rescan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5132),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 2. Focus Box Overlay
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.lightBlue.withValues(alpha: 0.35), width: 1.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 8, left: 8,
                    child: Container(width: 14, height: 14, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF00F2FE), width: 2), left: BorderSide(color: Color(0xFF00F2FE), width: 2)))),
                  ),
                  Positioned(
                    top: 8, right: 8,
                    child: Container(width: 14, height: 14, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF00F2FE), width: 2), right: BorderSide(color: Color(0xFF00F2FE), width: 2)))),
                  ),
                  Positioned(
                    bottom: 8, left: 8,
                    child: Container(width: 14, height: 14, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF00F2FE), width: 2), left: BorderSide(color: Color(0xFF00F2FE), width: 2)))),
                  ),
                  Positioned(
                    bottom: 8, right: 8,
                    child: Container(width: 14, height: 14, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF00F2FE), width: 2), right: BorderSide(color: Color(0xFF00F2FE), width: 2)))),
                  ),
                ],
              ),
            ),
          ),

          // 3. Snap Animation Flash
          if (_showSnapAnimation)
            Container(color: Colors.white.withValues(alpha: 0.6)),

          // 4. Header Bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black54,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 10,
                left: 16,
                right: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI DEFLAG RESCAN',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8),
                          ),
                          Text(
                            'Target: #${widget.documentId.length > 8 ? widget.documentId.substring(0, 8) : widget.documentId}',
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Mode Switch & Connection Indicator
                  Row(
                    children: [
                      // Toggle to Manual Mode
                      InkWell(
                        onTap: () => setState(() => _currentMode = DeflagMode.manual),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: const Row(
                            children: [
                              Icon(LucideIcons.fileText, color: Colors.white, size: 13),
                              SizedBox(width: 6),
                              Text('Manual', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // AI Model Status Dot
                      Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isAiConnected ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isAiConnected ? 'AI Live' : 'AI Offline',
                            style: TextStyle(
                              color: _isAiConnected ? Colors.greenAccent : Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 5. Result HUD Overlay (Matches Fleet App Overlay)
          Positioned(
            bottom: 180,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161822).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isAutoDeflagged
                        ? Colors.greenAccent
                        : (_lastAiResult?['is_clean'] == false ? Colors.redAccent : Colors.white24),
                    width: _isAutoDeflagged ? 2 : 1,
                  ),
                ),
                child: _isAnalyzing
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Color(0xFF00F2FE), strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text("Scanning road surface with Street AIQ...", style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      )
                    : _buildAiResultContent(),
              ),
            ),
          ),

          // 6. Zoom Controls
          if (_isCameraReady)
            Positioned(
              bottom: 125,
              left: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: _supportedZoomLevels.map((zoom) {
                    final isSelected = _currentZoom == zoom;
                    return GestureDetector(
                      onTap: () => _setZoomLevel(zoom),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? const Color(0xFF00F2FE) : Colors.transparent,
                        ),
                        child: Text(
                          "${zoom}x",
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          // 7. Footer Controls (Shutter, Gallery, Auto/Manual Toggle)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.75),
              padding: EdgeInsets.only(
                top: 14,
                bottom: MediaQuery.of(context).padding.bottom + 14,
                left: 24,
                right: 24,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Pick Gallery Image
                  IconButton(
                    icon: const Icon(Icons.photo_library, color: Colors.white, size: 28),
                    tooltip: 'Browse Gallery to scan',
                    onPressed: _pickGalleryForAiRescan,
                  ),

                  // Center: Shutter Button
                  GestureDetector(
                    onTap: _isAutoScanning ? _stopAutoScanning : () => _handleCaptureAndRescan(),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isAutoScanning
                            ? Colors.redAccent
                            : (_isAnalyzing ? Colors.grey : Colors.white),
                        border: Border.all(color: Colors.white30, width: 4),
                      ),
                      child: _isAutoScanning
                          ? const Icon(Icons.stop, color: Colors.white, size: 32)
                          : (_isAnalyzing
                              ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5)))
                              : const Icon(LucideIcons.camera, color: Colors.black87, size: 30)),
                    ),
                  ),

                  // Right: Continuous Auto-Rescan Toggle
                  GestureDetector(
                    onTap: _toggleAutoScanning,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isAutoScanning ? const Color(0xFF00F2FE).withValues(alpha: 0.25) : Colors.white12,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _isAutoScanning ? const Color(0xFF00F2FE) : Colors.white30),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.autorenew,
                            color: _isAutoScanning ? const Color(0xFF00F2FE) : Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isAutoScanning ? 'AUTO ON' : 'AUTO',
                            style: TextStyle(
                              color: _isAutoScanning ? const Color(0xFF00F2FE) : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildAiResultContent() {
    if (_isAutoDeflagged) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.checkCircle2, color: Colors.greenAccent, size: 20),
              SizedBox(width: 8),
              Text(
                "CLEAN ROAD CONFIRMED!",
                style: TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            "🎉 Spot Automatically Deflagged! Updating live map...",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      );
    }

    if (_lastAiResult != null) {
      final isClean = _lastAiResult!['is_clean'] == true;
      final isVeryDirty = _lastAiResult!['is_very_dirty'] == true;
      final status = _lastAiResult!['road_status']?.toString() ?? 'Unknown';
      final count = _lastAiResult!['trash_count'] ?? 0;
      final conf = ((_lastAiResult!['confidence'] ?? 0.0) as num).toDouble() * 100;
      final mobilenet = _lastAiResult!['mobilenet_result'];
      String mInfo = '';
      if (mobilenet is Map && mobilenet['invoked'] == true) {
        final mClass = (mobilenet['class'] ?? '').toString();
        final double p = ((mClass == 'very_dirty' ? mobilenet['prob_very_dirty'] : mobilenet['prob_clean']) as num?)?.toDouble() ?? 0.0;
        mInfo = ' • MobileNetV3: ${mClass == 'very_dirty' ? 'Very Dirty' : 'Clean'} (${(p * 100).toStringAsFixed(0)}%)';
      }

      String title;
      Color badgeColor;
      IconData badgeIcon;

      if (isClean) {
        title = "CLEAN ROAD CONFIRMED";
        badgeColor = Colors.greenAccent;
        badgeIcon = LucideIcons.checkCheck;
      } else if (isVeryDirty) {
        title = "VERY DIRTY ROAD ($count items)";
        badgeColor = Colors.redAccent;
        badgeIcon = LucideIcons.alertOctagon;
      } else {
        title = "TRASH DETECTED ($count items)";
        badgeColor = Colors.orangeAccent;
        badgeIcon = LucideIcons.alertTriangle;
      }

      String subText;
      if (isClean) {
        subText = "Status: $status$mInfo | Confidence: ${conf.toStringAsFixed(1)}%";
      } else if (isVeryDirty) {
        subText = "🚨 Very Dirty condition detected$mInfo. Clean area thoroughly and rescan.";
      } else {
        subText = "⚠️ Trash remains detected$mInfo. Clean area and rescan to auto-deflag.";
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(badgeIcon, color: badgeColor, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "Aim camera at road & press Shutter to rescan",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          "If model detects 'No Trash / Clean', spot automatically deflags!",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. MANUAL DEFLAG VIEW (Browse Gallery / Instant Photo + Resolution Note)
  // ===========================================================================
  Widget _buildManualDeflagView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Manual Deflag Verification', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF0F5132),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _currentMode = DeflagMode.auto),
            icon: const Icon(LucideIcons.camera, color: Color(0xFF4ADE80), size: 16),
            label: const Text('Auto AI Mode', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Card(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with Spot Info
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F5132).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(LucideIcons.uploadCloud, color: Color(0xFF0F5132), size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Manual Cleanup Proof', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                              Text(
                                'Spot #${widget.documentId.length > 8 ? widget.documentId.substring(0, 8) : widget.documentId} ${widget.initialLocation != null ? "• ${widget.initialLocation}" : ""}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'Attach a photo of the cleaned area as official verification proof. You can select from gallery or take an instant photo.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
                    ),
                    const SizedBox(height: 20),

                    // Photo Upload / Preview Box
                    if (_manualImageBytes == null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFCBD5E1), style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFFF1F5F9),
                        ),
                        child: Column(
                          children: [
                            const Icon(LucideIcons.imagePlus, size: 40, color: Color(0xFF64748B)),
                            const SizedBox(height: 12),
                            const Text('No verification photo selected', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _pickManualImage(ImageSource.gallery),
                                  icon: const Icon(LucideIcons.folderOpen, size: 16),
                                  label: const Text('Browse Gallery'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F5132),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _pickManualImage(ImageSource.camera),
                                  icon: const Icon(LucideIcons.camera, size: 16),
                                  label: const Text('Instant Photo'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF0F5132),
                                    side: const BorderSide(color: Color(0xFF0F5132)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Photo Preview
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _manualImageBytes!,
                              width: double.infinity,
                              height: 220,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8, right: 8,
                            child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              radius: 18,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                onPressed: () => setState(() {
                                  _manualPickedFile = null;
                                  _manualImageBytes = null;
                                }),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 8, left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                              child: const Row(
                                children: [
                                  Icon(LucideIcons.check, color: Colors.greenAccent, size: 14),
                                  SizedBox(width: 6),
                                  Text('Photo attached', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => _pickManualImage(ImageSource.gallery),
                            icon: const Icon(LucideIcons.refreshCw, size: 14),
                            label: const Text('Change Photo', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Officer Resolution Note
                    TextField(
                      controller: _noteController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Resolution / Officer Note (Optional)',
                        hintText: 'e.g. Cleared by BBMP sanitation crew at 3:30 PM',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Submit Deflag Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isManualSubmitting ? null : _submitManualDeflag,
                        icon: _isManualSubmitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(LucideIcons.check, size: 20),
                        label: Text(_isManualSubmitting ? 'Updating status...' : 'Confirm & Deflag Spot'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F5132),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// MODAL BOTTOM SHEET: Choice Between Manual & Auto AI Deflag
// =============================================================================
class _DeflagChoiceBottomSheet extends StatelessWidget {
  final String documentId;
  final String collectionName;
  final String? initialVehicleNumber;
  final String? initialLocation;
  final double? lat;
  final double? lng;
  final String? ward;
  final String? zone;

  const _DeflagChoiceBottomSheet({
    required this.documentId,
    required this.collectionName,
    this.initialVehicleNumber,
    this.initialLocation,
    this.lat,
    this.lng,
    this.ward,
    this.zone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F5132).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.shieldCheck, color: Color(0xFF0F5132), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose Deflag Method',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    Text(
                      'Spot #${documentId.length > 8 ? documentId.substring(0, 8) : documentId} • How do you want to verify cleanup?',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // OPTION 1: MANUAL DEFLAG
          _buildOptionCard(
            context: context,
            icon: LucideIcons.uploadCloud,
            iconBgColor: const Color(0xFFF0FDF4),
            iconColor: const Color(0xFF16A34A),
            title: 'Manual Deflag',
            badgeText: 'Gallery / Instant Photo',
            badgeColor: const Color(0xFFDCFCE7),
            badgeTextColor: const Color(0xFF15803D),
            description: 'Upload cleanup photo from gallery or snap an instant photo, write resolution notes, and confirm cleanup.',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ComndDeflagScreen(
                    documentId: documentId,
                    collectionName: collectionName,
                    initialVehicleNumber: initialVehicleNumber,
                    initialLocation: initialLocation,
                    lat: lat,
                    lng: lng,
                    ward: ward,
                    zone: zone,
                    initialMode: DeflagMode.manual,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 14),

          // OPTION 2: AUTO AI DEFLAG (Fleet Camera Screen)
          _buildOptionCard(
            context: context,
            icon: LucideIcons.sparkles,
            iconBgColor: const Color(0xFFEFF6FF),
            iconColor: const Color(0xFF2563EB),
            title: 'Auto AI Rescan (Fleet Camera)',
            badgeText: 'Street AIQ YOLOv8',
            badgeColor: const Color(0xFFDBEAFE),
            badgeTextColor: const Color(0xFF1D4ED8),
            description: 'Exact Fleet App camera scanner. Rescans the road in real-time — automatically deflags when Clean / No Trash Detected!',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ComndDeflagScreen(
                    documentId: documentId,
                    collectionName: collectionName,
                    initialVehicleNumber: initialVehicleNumber,
                    initialLocation: initialLocation,
                    lat: lat,
                    lng: lng,
                    ward: ward,
                    zone: zone,
                    initialMode: DeflagMode.auto,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String badgeText,
    required Color badgeColor,
    required Color badgeTextColor,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
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
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(color: badgeTextColor, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Color(0xFF94A3B8), size: 20),
          ],
        ),
      ),
    );
  }
}
