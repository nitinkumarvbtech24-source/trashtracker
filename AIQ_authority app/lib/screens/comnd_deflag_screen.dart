import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ComndDeflagScreen extends StatefulWidget {
  final String documentId;

  const ComndDeflagScreen({super.key, required this.documentId});

  @override
  State<ComndDeflagScreen> createState() => _ComndDeflagScreenState();
}

class _ComndDeflagScreenState extends State<ComndDeflagScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _statusMessage = 'No camera found');
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
      if (mounted) setState(() => _statusMessage = 'Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _deflag() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Analyzing image with AI...';
    });

    try {
      final picture = await _controller!.takePicture();
      final bytes = await picture.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Hit the AI model
      final response = await http.post(
        Uri.parse('$GARBAGE_AI_URL/process_frame'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: json.encode({
          'image': 'data:image/jpeg;base64,$base64Image',
          'lat': 0.0,
          'lng': 0.0,
          'vehicle_number': 'Authority_App_Deflag',
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final resBody = json.decode(response.body);
        final roadStatus = resBody['road_status'] ?? 'UNKNOWN';

        if (roadStatus != 'Very Dirty Road' && roadStatus != 'Slightly Dirty Road') { 
          await FirebaseFirestore.instance.collection('trash_spots').doc(widget.documentId).update({
            'status': 'Deflagged',
            'deflagged_at': FieldValue.serverTimestamp(),
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully deflagged!')));
            Navigator.pop(context);
          }
        } else {
          setState(() {
            _statusMessage = 'AI determined area is still: $roadStatus';
            _isProcessing = false;
          });
        }
      } else {
        setState(() {
          _statusMessage = 'Server error: ${response.statusCode}';
          _isProcessing = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error connecting to AI: $e';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Deflag Complaint', style: TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF0F5132), iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(
          child: _statusMessage != null ? Text(_statusMessage!) : const CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Deflag Complaint', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(_statusMessage ?? 'Processing...', style: const TextStyle(color: Colors.white, fontSize: 16)),
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
                  color: Colors.red.withOpacity(0.8),
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
              child: Center(
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: FloatingActionButton(
                    onPressed: _deflag,
                    backgroundColor: const Color(0xFF0F5132),
                    shape: const CircleBorder(),
                    heroTag: 'deflag_camera',
                    child: const Icon(LucideIcons.camera, color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
