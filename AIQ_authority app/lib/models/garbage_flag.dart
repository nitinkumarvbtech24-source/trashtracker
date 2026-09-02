import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';

class GarbageFlag {
  final String id;
  final String filename;
  final String imageUrl;
  final String className;
  final String displayClass;
  final double confidence;
  final String timestamp;
  final double lat;
  final double lng;
  final String vehicleNumber;
  final String ward;
  final String? sessionId;
  final String? pointType;
  final String status;

  GarbageFlag({
    required this.id,
    required this.filename,
    required this.imageUrl,
    required this.className,
    required this.displayClass,
    required this.confidence,
    required this.timestamp,
    required this.lat,
    required this.lng,
    required this.vehicleNumber,
    required this.ward,
    this.sessionId,
    this.pointType,
    required this.status,
  });

  factory GarbageFlag.fromJson(Map<String, dynamic> json, [String? docId]) {
    String rawUrl = json['image_url']?.toString() ?? '';
    String resolvedUrl = '';
    
    if (rawUrl.isNotEmpty) {
      if (rawUrl.startsWith('/')) {
        resolvedUrl = '$activeGarbageAiUrl$rawUrl';
      } else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
        try {
          Uri parsed = Uri.parse(rawUrl);
          if (parsed.path.startsWith('/images/')) {
            resolvedUrl = '$activeGarbageAiUrl${parsed.path}';
          } else {
            resolvedUrl = rawUrl;
          }
        } catch (_) {
          resolvedUrl = rawUrl;
        }
      }
    }

    return GarbageFlag(
      id: docId ?? json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      filename: json['filename'] ?? 'snapshot',
      imageUrl: resolvedUrl,
      className: json['class'] ?? json['road_status']?.toString().replaceAll(' Road', '').replaceAll(' ', '_') ?? 'Unknown',
      displayClass: json['display_class'] ?? json['road_status']?.toString().replaceAll(' Road', '') ?? 'Unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] is Timestamp ? (json['timestamp'] as Timestamp).toDate().toIso8601String() : (json['timestamp']?.toString() ?? DateTime.now().toIso8601String()),
      lat: (json['lat'] as num?)?.toDouble() ?? 42.3601,
      lng: (json['lng'] as num?)?.toDouble() ?? -71.0589,
      vehicleNumber: json['vehicle_number'] ?? 'Unknown',
      ward: json['ward'] ?? 'Unknown',
      sessionId: json['session_id'],
      pointType: json['point_type'],
      status: json['status'] ?? 'Flagged',
    );
  }
}
