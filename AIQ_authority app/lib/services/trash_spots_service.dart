import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models/garbage_flag.dart';

class TrashSpotsService {
  TrashSpotsService._internal();
  static final TrashSpotsService instance = TrashSpotsService._internal();

  final ValueNotifier<List<GarbageFlag>> flagsNotifier = ValueNotifier<List<GarbageFlag>>([]);
  
  List<GarbageFlag> _firestoreFlags = [];
  List<GarbageFlag> _backendFlags = [];
  StreamSubscription? _firestoreSub;
  Timer? _backendPollTimer;
  bool _initialized = false;
  final Set<String> _syncedSnapshotIds = {};
  bool _isFetchingBackend = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    // 1. Listen to Firestore collection 'trash_spots'
    try {
      _firestoreSub = FirebaseFirestore.instance.collection('trash_spots').snapshots().listen(
        (snapshot) {
          _firestoreFlags = snapshot.docs.map((doc) {
            return GarbageFlag.fromJson(doc.data(), doc.id);
          }).where((f) => f.isTrashReport).toList();
          _mergeAndNotify();
        },
        onError: (err) {
          debugPrint("TrashSpotsService firestore error: $err");
        },
      );
    } catch (e) {
      debugPrint("TrashSpotsService firestore init error: $e");
    }

    // Cleanup any legacy 'No Trash Detected' or 'Clean Road' entries mistakenly stored in trash_spots
    try {
      FirebaseFirestore.instance.collection('trash_spots').get().then((snapshot) {
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final isTrash = GarbageFlag.isTrashDetectedSpot(
            roadStatus: data['road_status']?.toString(),
            displayClass: data['display_class']?.toString(),
            className: data['class']?.toString(),
            trashCount: (data['trash_count'] as num?)?.toInt(),
          );
          if (!isTrash) {
            doc.reference.delete().catchError((_) {});
          }
        }
      });
    } catch (_) {}

    // 2. Poll Backend API snapshots
    _fetchBackendSnapshots();
    _backendPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _fetchBackendSnapshots();
    });
  }

  Future<void> _fetchBackendSnapshots() async {
    if (_isFetchingBackend) return;
    _isFetchingBackend = true;
    try {
      final url = Uri.parse('$activeGarbageAiUrl/api/snapshots');
      final res = await http.get(url, headers: {'ngrok-skip-browser-warning': 'true'}).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List<dynamic> snaps = data['snapshots'] ?? [];
        List<GarbageFlag> detectedFromBackend = [];

        for (var s in snaps) {
          final flag = GarbageFlag.fromJson(Map<String, dynamic>.from(s), s['id']?.toString());
          detectedFromBackend.add(flag);

          final roadStatus = (s['road_status'] ?? '').toString();
          final displayClass = (s['display_class'] ?? '').toString();
          final className = (s['class'] ?? '').toString();
          final trashCount = (s['trash_count'] as num?)?.toInt();
          
          final isTrash = GarbageFlag.isTrashDetectedSpot(
            roadStatus: roadStatus,
            displayClass: displayClass,
            className: className,
            trashCount: trashCount,
          );

          if (isTrash) {
            // Sync to Firestore ONLY if actual trash is detected
            final docId = flag.id;
            if (docId.isNotEmpty && !_syncedSnapshotIds.contains(docId)) {
              _syncedSnapshotIds.add(docId);
              _syncSnapshotToFirestore(s, docId);
            }
          }
        }

        _backendFlags = detectedFromBackend;
        _mergeAndNotify();
      }
    } catch (_) {
      // Backend may be offline or URL changed; non-fatal
    } finally {
      _isFetchingBackend = false;
    }
  }

  Future<void> _syncSnapshotToFirestore(Map<String, dynamic> snap, String docId) async {
    try {
      final roadStatus = (snap['road_status'] ?? '').toString();
      final displayClass = (snap['display_class'] ?? '').toString();
      final className = (snap['class'] ?? '').toString();
      final trashCount = (snap['trash_count'] as num?)?.toInt() ?? 1;

      // Double check before saving: strictly never write clean/no trash to trash_spots
      if (!GarbageFlag.isTrashDetectedSpot(
        roadStatus: roadStatus,
        displayClass: displayClass,
        className: className,
        trashCount: trashCount,
      )) {
        return;
      }

      final docRef = FirebaseFirestore.instance.collection('trash_spots').doc(docId);
      final existing = await docRef.get();
      if (!existing.exists) {
        await docRef.set({
          'id': docId,
          'lat': (snap['lat'] as num?)?.toDouble() ?? 0.0,
          'lng': (snap['lng'] as num?)?.toDouble() ?? 0.0,
          'road_status': roadStatus.isNotEmpty ? roadStatus : 'Trash Detected',
          'display_class': displayClass.isNotEmpty ? displayClass : 'Trash Detected',
          'class': className.isNotEmpty ? className : 'Trash_Detected',
          'confidence': (snap['confidence'] as num?)?.toDouble() ?? 0.8,
          'image_url': snap['image_url'] ?? '',
          'raw_image_url': snap['raw_image_url'] ?? '',
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'Flagged',
          'vehicle_number': snap['vehicle_number'] ?? 'Unknown',
          'ward': snap['ward'] ?? 'Unknown',
          'zone': snap['zone'] ?? 'Unknown',
          'model_version': MODEL_VERSION,
          'trash_count': trashCount,
        });
      }
    } catch (e) {
      debugPrint("TrashSpotsService auto-sync error for $docId: $e");
    }
  }

  void _mergeAndNotify() {
    final Map<String, GarbageFlag> merged = {};

    // First add Firestore flags
    for (var f in _firestoreFlags) {
      merged[f.id] = f;
    }

    // Then add/overlay backend flags
    for (var f in _backendFlags) {
      if (!merged.containsKey(f.id)) {
        merged[f.id] = f;
      }
    }

    final list = merged.values.toList();
    // Sort descending by timestamp
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    flagsNotifier.value = list;
  }

  List<GarbageFlag> get allFlags => flagsNotifier.value;

  List<GarbageFlag> get activeFlags {
    return flagsNotifier.value.where((f) => f.isTrashDetected).toList();
  }

  List<GarbageFlag> getFlagsForVehicle(String vehicleNumber) {
    final v = vehicleNumber.trim().toLowerCase();
    return activeFlags.where((f) {
      final fv = f.vehicleNumber.trim().toLowerCase();
      return fv == v || (fv.isNotEmpty && v.isNotEmpty && (fv.contains(v) || v.contains(fv)));
    }).toList();
  }

  List<GarbageFlag> getAllFlagsForVehicle(String vehicleNumber) {
    final v = vehicleNumber.trim().toLowerCase();
    return allFlags.where((f) {
      final fv = f.vehicleNumber.trim().toLowerCase();
      return fv == v || (fv.isNotEmpty && v.isNotEmpty && (fv.contains(v) || v.contains(fv)));
    }).toList();
  }

  List<List<GarbageFlag>> clusterFlags(List<GarbageFlag> flags, [double clusterDist = 0.00018]) {
    final List<List<GarbageFlag>> clusters = [];
    for (var flag in flags) {
      bool added = false;
      for (var c in clusters) {
        if ((flag.lat - c.first.lat).abs() < clusterDist && (flag.lng - c.first.lng).abs() < clusterDist) {
          c.add(flag);
          added = true;
          break;
        }
      }
      if (!added) {
        clusters.add([flag]);
      }
    }
    return clusters;
  }

  void dispose() {
    _firestoreSub?.cancel();
    _backendPollTimer?.cancel();
  }
}
