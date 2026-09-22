import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';

class CameraCaptureScreen extends StatefulWidget {
  final String category;
  final double lat;
  final double lng;
  const CameraCaptureScreen({super.key, required this.category, required this.lat, required this.lng});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  bool _isCaptured = false;
  bool _isSubmitting = false;
  File? _capturedImage;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Auto-launch camera when screen is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureImage();
    });
  }

  Future<void> _captureImage() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
      
      if (photo != null) {
        setState(() {
          _capturedImage = File(photo.path);
          _isCaptured = true;
        });
      } else {
        // User cancelled, pop back if we don't have an image
        if (!_isCaptured && mounted) {
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to open camera.')),
        );
      }
    }
  }

  void _retakePhoto() {
    setState(() {
      _isCaptured = false;
      _capturedImage = null;
    });
    _captureImage();
  }

  Future<void> _submitReport() async {
    if (_capturedImage == null) return;
    
    setState(() => _isSubmitting = true);
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isSubmitting = false);
    
    if (!mounted) return;
    
    context.pop({
      'category': widget.category,
      'comment': _commentController.text.isEmpty ? 'No comments provided' : _commentController.text,
      'lat': widget.lat,
      'lng': widget.lng,
      'status': 'Submitted',
      'id': '#RP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
      'image': _capturedImage!.path,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Camera background is black
      body: Stack(
        children: [
          // 1. Camera View Finder or Captured Image
          Positioned.fill(
            child: _isCaptured && _capturedImage != null
                ? Image.file(
                    _capturedImage!,
                    fit: BoxFit.cover,
                  )
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),

          // 1.5 Location Watermark Overlay on Image
          if (_isCaptured && _capturedImage != null)
            Positioned(
              top: 120, // Below header
              left: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.my_location, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '${widget.lat.toStringAsFixed(5)}° N, ${widget.lng.toStringAsFixed(5)}° E\nLocation Captured',
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 2. Header
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
                Text(
                  'Report ${widget.category == "pothole" ? "Pothole" : widget.category == "garbage" ? "Garbage" : "Issue"}',
                  style: const TextStyle(fontFamily: 'Plus Jakarta Sans', color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                  child: const Icon(Icons.flash_off, color: Colors.white, size: 24),
                ),
              ],
            ),
          ),

          // 3. Bottom Controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _isCaptured ? _buildReviewPanel() : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Comment Box
              const Text('Additional details', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              TextField(
                controller: _commentController,
                maxLines: 3,
                maxLength: 300,
                decoration: InputDecoration(
                  hintText: 'Describe the issue or add any information that may help...',
                  hintStyle: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(16),
                ),
                style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 24),
              
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _retakePhoto,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: const BorderSide(color: AppColors.border, width: 1.5),
                        foregroundColor: AppColors.textPrimary,
                      ),
                      child: const Text('Retake', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitReport,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      child: _isSubmitting 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Submit Report', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20), // Space
            ],
          ),
        ),
      ),
    );
  }
}
