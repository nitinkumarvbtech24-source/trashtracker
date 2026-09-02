import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:flutter/services.dart';
import '../services/camera_service.dart';
import '../services/telemetry_service.dart';
import '../services/sync_service.dart';
import 'settings_screen.dart';
import 'local_folder_screen.dart';
import '../services/sound_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _isAnalyzing = false;
  Map<String, dynamic>? _lastResult;
  Timer? _streamingTimer;
  bool _wasRecording = false;

  double _currentZoom = 1.0;
  bool _showSnapAnimation = false;
  DateTime _lastShutterPressTime = DateTime.fromMillisecondsSinceEpoch(0);

  void _triggerSnapAnimation() {
    if (!mounted) return;
    setState(() => _showSnapAnimation = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _showSnapAnimation = false);
    });
  }

  Future<void> _handleAutoCaptureBackground({String? pointType}) async {
    if (!mounted) return;
    final cameraService = context.read<CameraService>();
    final telemetryService = context.read<TelemetryService>();
    
    final lat = telemetryService.currentPosition?.latitude ?? 42.3601;
    final lng = telemetryService.currentPosition?.longitude ?? -71.0589;
    
    _triggerSnapAnimation();
    
    // Fire and forget (don't await or set state for analyzing)
    cameraService.captureManualSnapshot(lat, lng, sessionId: cameraService.isAutoCapturing ? const Uuid().v4() : null, pointType: pointType).catchError((e) {
      debugPrint("Auto capture error: $e");
      return null;
    });
  }

  Future<void> _handleCapture({String? pointType}) async {
    if (!mounted) return;
    final cameraService = context.read<CameraService>();
    final telemetryService = context.read<TelemetryService>();
    
    setState(() {
      _isAnalyzing = true;
      _lastResult = null;
    });

    final lat = telemetryService.currentPosition?.latitude ?? 42.3601;
    final lng = telemetryService.currentPosition?.longitude ?? -71.0589;
    final result = await cameraService.captureManualSnapshot(lat, lng, pointType: pointType);

    if (mounted) {
      setState(() {
        _isAnalyzing = false;
        if (result != null) {
          _lastResult = result;
        }
      });
    }

    // Automatically hide result after 4 seconds
    if (result != null) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _lastResult == result) {
          setState(() {
            _lastResult = null;
          });
        }
      });
    }
  }
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CameraService>().initialize();
      context.read<TelemetryService>().initialize();
      context.read<SyncService>().startSyncTimer();
    });
    
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.addListener((volume) {
      _handleShutterPress();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cameraService = context.watch<CameraService>();
    if (cameraService.isRecording && !_wasRecording) {
      _wasRecording = true;
      _streamingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (mounted && !cameraService.isAutoMode) {
          _handleAutoCaptureBackground();
        }
      });
    } else if (!cameraService.isRecording && _wasRecording) {
      _wasRecording = false;
      _streamingTimer?.cancel();
    }
  }

  @override
  void dispose() {
    VolumeController.instance.removeListener();
    _streamingTimer?.cancel();
    super.dispose();
  }

  void _handleShutterPress() {
    if (!mounted) return;
    
    final now = DateTime.now();
    if (now.difference(_lastShutterPressTime).inMilliseconds < 500) {
      return;
    }
    _lastShutterPressTime = now;

    final cameraService = context.read<CameraService>();
    if (!cameraService.isInitialized) return;
    
    if (cameraService.isAutoMode) {
      bool turningOn = !cameraService.isAutoCapturing;
      final telemetryService = context.read<TelemetryService>();
      cameraService.toggleAutoCapture(
        () => telemetryService.currentPosition?.latitude ?? 42.3601,
        () => telemetryService.currentPosition?.longitude ?? -71.0589,
        onSnap: _triggerSnapAnimation,
      );
      
      if (turningOn) {
        SoundService.playClick();
      } else {
        SoundService.playBeepLow();
      }
    } else if (cameraService.isTrainingMode) {
      bool turningOn = !cameraService.isTrainingCapturing;
      final telemetryService = context.read<TelemetryService>();
      cameraService.toggleTrainingCapture(
        () => telemetryService.currentPosition?.latitude ?? 42.3601,
        () => telemetryService.currentPosition?.longitude ?? -71.0589,
        onSnap: _triggerSnapAnimation,
      );
      
      if (turningOn) {
        SoundService.playClick();
      } else {
        SoundService.playBeepLow();
      }
    } else {
      SoundService.playClick();
      if (!_isAnalyzing) _handleCapture();
    }
  }

  double _getAspectValue(BuildContext context, String mode) {
    switch (mode) {
      case '16:9': return 9 / 16;
      case '4:3': return 3 / 4;
      case '1:1': return 1.0;
      case 'Full':
      default:
        return MediaQuery.of(context).size.aspectRatio;
    }
  }

  void _showSettingsModal(BuildContext context, CameraService cameraService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161822),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Camera Settings", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  const Text("Aspect Ratio", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['Full', '16:9', '4:3', '1:1'].map((mode) {
                      final isSelected = cameraService.aspectRatioMode == mode;
                      return ChoiceChip(
                        label: Text(mode, style: TextStyle(color: isSelected ? Colors.black : Colors.white)),
                        selected: isSelected,
                        selectedColor: const Color(0xFF00F2FE),
                        backgroundColor: Colors.transparent,
                        shape: StadiumBorder(side: BorderSide(color: isSelected ? Colors.transparent : Colors.white30)),
                        onSelected: (val) {
                          if (val) {
                            cameraService.setAspectRatioMode(mode);
                            setStateModal(() {});
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text("Capture Interval (seconds)", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Slider(
                    value: cameraService.isTrainingMode ? cameraService.trainingIntervalSeconds : cameraService.intervalSeconds,
                    min: 0.5,
                    max: 10.0,
                    divisions: 19,
                    activeColor: const Color(0xFF00F2FE),
                    label: "${cameraService.isTrainingMode ? cameraService.trainingIntervalSeconds : cameraService.intervalSeconds}s",
                    onChanged: (cameraService.isAutoCapturing || cameraService.isTrainingCapturing) ? null : (val) {
                      if (cameraService.isTrainingMode) {
                        cameraService.setTrainingIntervalSeconds(val);
                      } else {
                        cameraService.setIntervalSeconds(val);
                      }
                      setStateModal(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModeSelector(CameraService cameraService) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeIconButton(
            icon: Icons.school, // Training
            isSelected: cameraService.isTrainingMode,
            activeColor: Colors.orangeAccent,
            onTap: () {
              if (cameraService.isAutoCapturing) {
                final t = context.read<TelemetryService>();
                cameraService.toggleAutoCapture(() => t.currentPosition?.latitude ?? 42.3601, () => t.currentPosition?.longitude ?? -71.0589);
              }
              cameraService.setTrainingMode(true);
            },
          ),
          const SizedBox(width: 16),
          _buildModeIconButton(
            icon: Icons.camera, // Manual
            isSelected: !cameraService.isTrainingMode && !cameraService.isAutoMode,
            activeColor: Colors.white,
            onTap: () {
              if (cameraService.isAutoCapturing) {
                final t = context.read<TelemetryService>();
                cameraService.toggleAutoCapture(() => t.currentPosition?.latitude ?? 42.3601, () => t.currentPosition?.longitude ?? -71.0589);
              }
              if (cameraService.isTrainingCapturing) {
                final t = context.read<TelemetryService>();
                cameraService.toggleTrainingCapture(() => t.currentPosition?.latitude ?? 42.3601, () => t.currentPosition?.longitude ?? -71.0589);
              }
              cameraService.setAutoMode(false);
              cameraService.setTrainingMode(false);
            },
          ),
          const SizedBox(width: 16),
          _buildModeIconButton(
            icon: Icons.autorenew, // Auto
            isSelected: cameraService.isAutoMode,
            activeColor: const Color(0xFF00F2FE),
            onTap: () {
              if (cameraService.isTrainingCapturing) {
                final t = context.read<TelemetryService>();
                cameraService.toggleTrainingCapture(() => t.currentPosition?.latitude ?? 42.3601, () => t.currentPosition?.longitude ?? -71.0589);
              }
              cameraService.setAutoMode(true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeIconButton({
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        color: isSelected ? activeColor : Colors.white54,
        size: isSelected ? 28 : 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameraService = context.watch<CameraService>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full Screen Camera Preview
          if (cameraService.isInitialized)
            Container(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1 / cameraService.controller!.value.aspectRatio,
                  child: CameraPreview(cameraService.controller!),
                ),
              ),
            )
          else
            Center(
              child: Text(
                cameraService.errorMessage ?? "Camera Offline",
                style: const TextStyle(color: Colors.redAccent, fontSize: 16),
              ),
            ),

          // 2. Focus Box Overlay
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.lightBlue.withOpacity(0.3), width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // 3. Snap Animation Flash
          if (_showSnapAnimation)
            Container(color: Colors.white.withOpacity(0.6)),

          // 4. Header (Small portion at top)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black54,
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 8, left: 16, right: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ROAD SNAPSHOT',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showSettingsModal(context, cameraService),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.settings, color: Colors.white, size: 16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.cloud_sync, color: Colors.white70, size: 12),
                      const SizedBox(width: 4),
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (cameraService.isGarbageConnected || cameraService.isHealthConnected) ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.delete_outline, color: Colors.white70, size: 12),
                      const SizedBox(width: 4),
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cameraService.isGarbageConnected ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.add_road, color: Colors.white70, size: 12),
                      const SizedBox(width: 4),
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cameraService.isHealthConnected ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 5. Result Overlay (bottom of camera view)
          if (_isAnalyzing || _lastResult != null || cameraService.latestResult != null)
            Positioned(
              bottom: 230, // Lifted up to avoid bottom nav bar
              left: 20,
              right: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: BackdropFilter(
                  filter: ColorFilter.mode(Colors.black.withOpacity(0.0), BlendMode.srcOver),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161822).withOpacity(0.8),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: _isAnalyzing
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Color(0xFF00F2FE), strokeWidth: 2)),
                              SizedBox(width: 12),
                              Text("Analyzing...", style: TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Builder(
                                builder: (context) {
                                  Map<String, dynamic>? res = _lastResult ?? cameraService.latestResult;
                                  String garbageStatus = (res?['garbage']?['road_status']?.toString() ?? 'UNKNOWN').replaceAll('_', ' ').toUpperCase();
                                  String healthStatus = (res?['health']?['road_status']?.toString() ?? 'UNKNOWN').replaceAll('_', ' ').toUpperCase();
                                  String displayStatus = "$garbageStatus / $healthStatus";
                                  if (garbageStatus == 'NOT A ROAD') displayStatus = "NOT A ROAD";
                                  
                                  return Column(
                                    children: [
                                      Text(
                                        displayStatus,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Confidence: ${((res?['garbage']?['road_confidence'] ?? 0.0) * 100).toStringAsFixed(1)}%",
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),

          // 6. Zoom Controls (Small at left corner above footer)
          if (cameraService.isInitialized)
            Positioned(
              bottom: 200, // Lifted up to avoid bottom nav bar
              left: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: cameraService.supportedZoomLevels.map((zoom) {
                    final isSelected = _currentZoom == zoom;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _currentZoom = zoom);
                        cameraService.setZoomLevel(zoom);
                      },
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
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          // 7. Footer (Bottom Controls)
          Positioned(
            bottom: 80, // Lifted up to avoid bottom nav bar
            left: 0, right: 0,
            child: Container(
              color: Colors.black.withOpacity(0.7),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Gallery / Locate Folder Icon
                  IconButton(
                    icon: const Icon(Icons.photo_library, color: Colors.white, size: 28),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const LocalFolderScreen()));
                    },
                  ),

                  // Center: Shutter Button
                  GestureDetector(
                    onTap: _handleShutterPress,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (cameraService.isAutoMode && cameraService.isAutoCapturing) || (cameraService.isTrainingMode && cameraService.isTrainingCapturing)
                               ? Colors.redAccent 
                               : (_isAnalyzing && !cameraService.isAutoMode && !cameraService.isTrainingMode ? Colors.grey : Colors.white),
                        border: Border.all(color: Colors.white30, width: 4),
                      ),
                      child: (cameraService.isAutoMode && cameraService.isAutoCapturing) || (cameraService.isTrainingMode && cameraService.isTrainingCapturing)
                          ? const Icon(Icons.stop, color: Colors.white, size: 30)
                          : null,
                    ),
                  ),

                  // Right: Mode Switch (Symbols)
                  _buildModeSelector(cameraService),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

