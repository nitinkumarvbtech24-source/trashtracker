import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ComndDeflagScreen extends StatefulWidget {
  final String documentId;
  final String collectionName;
  final String? initialVehicleNumber;
  final String? initialLocation;

  const ComndDeflagScreen({
    super.key,
    required this.documentId,
    this.collectionName = 'trash_spots',
    this.initialVehicleNumber,
    this.initialLocation,
  });

  @override
  State<ComndDeflagScreen> createState() => _ComndDeflagScreenState();
}

class _ComndDeflagScreenState extends State<ComndDeflagScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  String? _statusMessage;
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _statusMessage = 'No camera available on this device');
        return;
      }
      _controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Camera not available: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _manualDeflag() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Updating flag status...';
    });

    try {
      await FirebaseFirestore.instance.collection(widget.collectionName).doc(widget.documentId).update({
        'status': 'Deflagged',
        'deflagged_at': FieldValue.serverTimestamp(),
        'deflag_method': 'Manual Verification',
        'deflag_note': _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : 'Verified Clean by Authority',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully deflagged spot! Status updated to Deflagged.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error updating status: $e';
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _deflagWithCamera() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      _manualDeflag();
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Analyzing cleanup verification photo with AI...';
    });

    try {
      final picture = await _controller!.takePicture();
      final bytes = await picture.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Hit the active AI model
      final response = await http.post(
        Uri.parse('$activeGarbageAiUrl/process_frame'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: json.encode({
          'image': 'data:image/jpeg;base64,$base64Image',
          'lat': 0.0,
          'lng': 0.0,
          'vehicle_number': 'Authority_App_Deflag',
        }),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final resBody = json.decode(response.body);
        final roadStatus = resBody['road_status'] ?? 'UNKNOWN';

        if (roadStatus == 'No Trash Detected' || roadStatus == 'Clean Road' || (roadStatus != 'Trash Detected' && roadStatus != 'Very Dirty Road' && roadStatus != 'Slightly Dirty Road')) { 
          await FirebaseFirestore.instance.collection(widget.collectionName).doc(widget.documentId).update({
            'status': 'Deflagged',
            'deflagged_at': FieldValue.serverTimestamp(),
            'deflag_method': 'AI Camera Verification',
            'deflag_ai_status': roadStatus,
            'deflag_note': _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : 'Verified Clean by Street AIQ',
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('AI Verified Clean! Successfully Deflagged!'),
                backgroundColor: Color(0xFF10B981),
              ),
            );
            Navigator.pop(context, true);
          }
        } else {
          setState(() {
            _statusMessage = 'AI detected trash remaining: $roadStatus. Clean further before deflagging or use Manual Deflag.';
            _isProcessing = false;
          });
        }
      } else {
        setState(() {
          _statusMessage = 'AI Server response ${response.statusCode}. You can still use Manual Deflag.';
          _isProcessing = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'AI verification timed out. You can use Manual Deflag.';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCamera = _controller != null && _controller!.value.isInitialized;

    if (!hasCamera) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text('Deflag Flagged Spot', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0F5132),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F5132).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(LucideIcons.checkCircle2, color: Color(0xFF0F5132), size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Deflag Verification',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                ),
                                Text(
                                  widget.initialVehicleNumber != null ? 'Vehicle: ${widget.initialVehicleNumber}' : 'ID: ${widget.documentId.substring(0, widget.documentId.length > 8 ? 8 : widget.documentId.length)}',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (widget.initialLocation != null) ...[
                        Text(
                          'Location: ${widget.initialLocation}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text(
                        'Confirm that this road/spot has been thoroughly cleaned and cleared of debris. Deflagging will update the live map and historical records.',
                        style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _noteController,
                        decoration: InputDecoration(
                          labelText: 'Resolution / Officer Note (Optional)',
                          hintText: 'e.g. Cleared by BBMP sweepers at 3 PM',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_statusMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: Text(_statusMessage!, style: const TextStyle(fontSize: 13, color: Color(0xFF92400E))),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _manualDeflag,
                          icon: _isProcessing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(LucideIcons.check, size: 20),
                          label: Text(_isProcessing ? 'Updating...' : 'Confirm & Deflag Spot'),
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('AI Deflag Camera', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: _manualDeflag,
            icon: const Icon(LucideIcons.checkCheck, color: Color(0xFF4ADE80), size: 18),
            label: const Text('Manual Deflag', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.65),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(_statusMessage ?? 'Processing with AI...', style: const TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),
          
          if (!_isProcessing && _statusMessage != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusMessage!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              ),
            ),
            
          if (!_isProcessing)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  const Text('Snap clean road to verify with AI and deflag', style: TextStyle(color: Colors.white70, fontSize: 13, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                  const SizedBox(height: 14),
                  Center(
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: FloatingActionButton(
                        onPressed: _deflagWithCamera,
                        backgroundColor: const Color(0xFF0F5132),
                        shape: const CircleBorder(),
                        heroTag: 'deflag_camera',
                        child: const Icon(LucideIcons.camera, color: Colors.white, size: 32),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
