import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import '../services/authority_directory_service.dart';

class NgrokImage extends StatefulWidget {
  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;

  const NgrokImage({Key? key, required this.url, this.fit, this.width, this.height}) : super(key: key);

  @override
  _NgrokImageState createState() => _NgrokImageState();
}

class _NgrokImageState extends State<NgrokImage> {
  Future<Uint8List>? _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _fetchImage(widget.url);
  }

  @override
  void didUpdateWidget(NgrokImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _imageFuture = _fetchImage(widget.url);
    }
  }

  Future<Uint8List> _fetchImage(String url) async {
    try {
      final cleanUrl = url.trim();
      final targetUrl = AuthorityDirectoryService.instance.resolveImageUrl(cleanUrl);
      final response = await http.get(Uri.parse(targetUrl), headers: {'ngrok-skip-browser-warning': 'true'}).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (_) {}

    // Fallback: guaranteed load from random 882 trash images pool
    try {
      final fallbackUrl = AuthorityDirectoryService.instance.getFallbackTrashImageUrl(url.hashCode);
      final response = await http.get(Uri.parse(fallbackUrl), headers: {'ngrok-skip-browser-warning': 'true'}).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (_) {}

    throw Exception('Failed to load image');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(width: widget.width, height: widget.height, color: Colors.black26, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
        } else if (snapshot.hasError || !snapshot.hasData) {
          return Container(width: widget.width, height: widget.height, color: Colors.black26, child: const Icon(Icons.image_not_supported, color: Colors.white24));
        }
        return Image.memory(snapshot.data!, fit: widget.fit, width: widget.width, height: widget.height);
      },
    );
  }
}
