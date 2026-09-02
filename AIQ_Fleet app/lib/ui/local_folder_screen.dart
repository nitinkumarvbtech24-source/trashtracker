import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';

class LocalFolderScreen extends StatefulWidget {
  const LocalFolderScreen({super.key});

  @override
  State<LocalFolderScreen> createState() => _LocalFolderScreenState();
}

class _LocalFolderScreenState extends State<LocalFolderScreen> {
  List<File> _images = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLocalImages();
  }

  Future<void> _loadLocalImages() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final pendingDir = Directory('${directory.path}/pending_training_images');
      
      if (await pendingDir.exists()) {
        final entities = await pendingDir.list(recursive: true).toList();
        final imageFiles = entities.whereType<File>().where((e) => e.path.endsWith('.jpg')).toList();
        
        setState(() {
          _images = imageFiles;
          _isLoading = false;
        });
      } else {
        setState(() {
          _images = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading local images: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('Local Pending Images', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _images.isEmpty
              ? const Center(child: Text("No pending images found locally.", style: TextStyle(color: Colors.white54)))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _images.length,
                  itemBuilder: (context, index) {
                    final file = _images[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullScreenImageView(
                              images: _images,
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          color: const Color(0xFF1E293B),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(file, fit: BoxFit.cover),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  color: Colors.black54,
                                  child: Text(
                                    file.uri.pathSegments.last,
                                    style: const TextStyle(color: Colors.white, fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class FullScreenImageView extends StatelessWidget {
  final List<File> images;
  final int initialIndex;

  const FullScreenImageView({super.key, required this.images, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        itemCount: images.length,
        controller: PageController(initialPage: initialIndex),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            child: Image.file(
              images[index],
              fit: BoxFit.contain,
            ),
          );
        },
      ),
    );
  }
}

