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
  final String zone;
  final String? sessionId;
  final String? pointType;
  final String status;
  final dynamic modelVersion;
  final int trashCount;

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
    this.zone = 'Unknown',
    this.sessionId,
    this.pointType,
    required this.status,
    this.modelVersion,
    this.trashCount = 1,
  });

  bool matchesModelVersion(int version) {
    if (modelVersion == null) return true;
    if (modelVersion == version) return true;
    final s = modelVersion.toString().toLowerCase().trim();
    return s == version.toString() || s == 'v$version' || (version == 7 && (s.contains('7') || s.contains('mobilenet')));
  }

  static bool isTrashDetectedSpot({
    String? roadStatus,
    String? displayClass,
    String? className,
    int? trashCount,
  }) {
    final rs = (roadStatus ?? '').toLowerCase().trim();
    final dc = (displayClass ?? '').toLowerCase().trim();
    final cn = (className ?? '').toLowerCase().trim();

    // 1. Explicit clean / no trash exclusions
    if (rs.contains('no trash') || rs.contains('no_trash') || rs.contains('clean') || rs.contains('not a road') ||
        dc.contains('no trash') || dc.contains('no_trash') || dc.contains('clean') || dc.contains('not a road') ||
        cn.contains('no trash') || cn.contains('no_trash') || cn.contains('clean') || cn.contains('not a road')) {
      return false;
    }

    // 2. If trashCount is 0, it's clean unless marked dirty
    if (trashCount != null && trashCount <= 0 && !rs.contains('dirty') && !dc.contains('dirty') && !cn.contains('dirty')) {
      return false;
    }

    // 3. Positive trash indicators
    final hasTrashStatus = rs == 'trash detected' ||
        rs.contains('trash detected') ||
        rs == 'trash' ||
        rs.contains('dirty');
    final hasDisplayTrash = dc == 'trash detected' ||
        dc.contains('trash detected') ||
        dc == 'trash' ||
        dc.contains('dirty');
    final hasClassTrash = cn == 'trash_detected' ||
        cn == 'trash' ||
        cn.contains('dirty');

    return hasTrashStatus || hasDisplayTrash || hasClassTrash || (trashCount != null && trashCount > 0);
  }

  bool get isTrashReport {
    return isTrashDetectedSpot(
      roadStatus: displayClass,
      displayClass: displayClass,
      className: className,
      trashCount: trashCount,
    );
  }

  bool get isTrashDetected {
    final s = status.toLowerCase();
    if (s == 'resolved' || s == 'deflagged') return false;
    return isTrashReport;
  }

  factory GarbageFlag.fromJson(Map<String, dynamic> json, [String? docId]) {
    String rawUrl = json['image_url']?.toString() ?? '';
    String resolvedUrl = '';
    
    if (rawUrl.isNotEmpty) {
      if (rawUrl.startsWith('/')) {
        resolvedUrl = '$activeGarbageAiUrl$rawUrl';
      } else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
        try {
          Uri parsed = Uri.parse(rawUrl);
          if (parsed.path.startsWith('/images/') || parsed.path.startsWith('/snapshots/')) {
            resolvedUrl = '$activeGarbageAiUrl${parsed.path}';
          } else {
            resolvedUrl = rawUrl;
          }
        } catch (_) {
          resolvedUrl = rawUrl;
        }
      }
    }

    final rawRoadStatus = (json['road_status'] ?? '').toString();
    final rawDisplayClass = (json['display_class'] ?? json['road_status']?.toString().replaceAll(' Road', '') ?? 'Unknown').toString();
    final rawClass = (json['class'] ?? json['road_status']?.toString().replaceAll(' Road', '').replaceAll(' ', '_') ?? 'Unknown').toString();
    final tCount = (json['trash_count'] as num?)?.toInt();
    final isClean = rawRoadStatus.toLowerCase().contains('no trash') ||
        rawRoadStatus.toLowerCase().contains('clean') ||
        rawDisplayClass.toLowerCase().contains('no trash') ||
        rawDisplayClass.toLowerCase().contains('clean');

    return GarbageFlag(
      id: docId ?? json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      filename: json['filename'] ?? 'snapshot',
      imageUrl: resolvedUrl,
      className: rawClass,
      displayClass: rawDisplayClass,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] is Timestamp ? (json['timestamp'] as Timestamp).toDate().toIso8601String() : (json['timestamp']?.toString() ?? DateTime.now().toIso8601String()),
      lat: (json['lat'] as num?)?.toDouble() ?? 42.3601,
      lng: (json['lng'] as num?)?.toDouble() ?? -71.0589,
      vehicleNumber: json['vehicle_number'] ?? 'Unknown',
      ward: json['ward'] ?? 'Unknown',
      zone: json['zone'] ?? 'Unknown',
      sessionId: json['session_id'],
      pointType: json['point_type'],
      status: json['status'] ?? 'Flagged',
      modelVersion: json['model_version'] ?? json['modelVersion'],
      trashCount: tCount ?? (isClean ? 0 : 1),
    );
  }
}
