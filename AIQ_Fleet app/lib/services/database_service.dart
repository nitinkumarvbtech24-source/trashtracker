import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;
  bool _isWeb = kIsWeb;

  // In-memory fallback for web
  final List<Map<String, dynamic>> _memTelemetry = [];
  final List<Map<String, dynamic>> _memVideo = [];
  final List<Map<String, dynamic>> _memQueuedSnapshots = [];
  int _memTelemetryId = 0;
  int _memVideoId = 0;
  int _memQueueId = 0;

  Future<Database?> get database async {
    if (_isWeb) return null;
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database?> _initDb() async {
    if (_isWeb) return null;
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'street_aiq_tipper.db');

      return await openDatabase(
        path,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE telemetry (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              lat REAL,
              lng REAL,
              speed REAL,
              timestamp INTEGER
            )
          ''');

          await db.execute('''
            CREATE TABLE video_chunks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              filePath TEXT,
              timestamp INTEGER
            )
          ''');

          await db.execute('''
            CREATE TABLE local_flags (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              filePath TEXT,
              roadStatus TEXT,
              confidence REAL,
              timestamp INTEGER,
              lat REAL,
              lng REAL
            )
          ''');

          await db.execute('''
            CREATE TABLE queued_snapshots (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              filePath TEXT,
              lat REAL,
              lng REAL,
              vehicleNumber TEXT,
              ward TEXT,
              zone TEXT,
              sessionId TEXT,
              pointType TEXT,
              timestamp INTEGER,
              status TEXT,
              retryCount INTEGER DEFAULT 0,
              createdAt INTEGER
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS queued_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                filePath TEXT,
                lat REAL,
                lng REAL,
                vehicleNumber TEXT,
                ward TEXT,
                zone TEXT,
                sessionId TEXT,
                pointType TEXT,
                timestamp INTEGER,
                status TEXT,
                retryCount INTEGER DEFAULT 0,
                createdAt INTEGER
              )
            ''');
          }
        },
      );
    } catch (e) {
      debugPrint("Error initializing db: \$e");
      return null;
    }
  }

  Future<void> insertTelemetry(double lat, double lng, double speed, int timestamp) async {
    if (_isWeb) {
      _memTelemetry.add({
        'id': ++_memTelemetryId,
        'lat': lat,
        'lng': lng,
        'speed': speed,
        'timestamp': timestamp,
      });
      return;
    }
    
    final db = await database;
    if (db != null) {
      await db.insert('telemetry', {
        'lat': lat,
        'lng': lng,
        'speed': speed,
        'timestamp': timestamp,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedTelemetry() async {
    if (_isWeb) {
      return List.from(_memTelemetry);
    }
    final db = await database;
    if (db != null) {
      return await db.query('telemetry');
    }
    return [];
  }

  Future<void> deleteTelemetry(int id) async {
    if (_isWeb) {
      _memTelemetry.removeWhere((element) => element['id'] == id);
      return;
    }
    final db = await database;
    if (db != null) {
      await db.delete('telemetry', where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> insertVideoChunk(String filePath, int timestamp) async {
    if (_isWeb) {
      _memVideo.add({
        'id': ++_memVideoId,
        'filePath': filePath,
        'timestamp': timestamp,
      });
      return;
    }
    final db = await database;
    if (db != null) {
      await db.insert('video_chunks', {
        'filePath': filePath,
        'timestamp': timestamp,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedVideoChunks() async {
    if (_isWeb) {
      return List.from(_memVideo);
    }
    final db = await database;
    if (db != null) {
      return await db.query('video_chunks');
    }
    return [];
  }

  Future<void> deleteVideoChunk(int id) async {
    if (_isWeb) {
      _memVideo.removeWhere((element) => element['id'] == id);
      return;
    }
    final db = await database;
    if (db != null) {
      await db.delete('video_chunks', where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> insertLocalFlag(String filePath, String roadStatus, double confidence, int timestamp, double lat, double lng) async {
    if (_isWeb) return;
    final db = await database;
    if (db != null) {
      await db.insert('local_flags', {
        'filePath': filePath,
        'roadStatus': roadStatus,
        'confidence': confidence,
        'timestamp': timestamp,
        'lat': lat,
        'lng': lng,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getLocalFlags() async {
    if (_isWeb) return [];
    final db = await database;
    if (db != null) {
      return await db.query('local_flags', orderBy: 'timestamp DESC');
    }
    return [];
  }

  // --- Queued Snapshots (Offline Sequential Queue) ---
  Future<int> insertQueuedSnapshot(Map<String, dynamic> data) async {
    if (_isWeb) {
      final newId = ++_memQueueId;
      final copy = Map<String, dynamic>.from(data);
      copy['id'] = newId;
      _memQueuedSnapshots.add(copy);
      return newId;
    }
    final db = await database;
    if (db != null) {
      return await db.insert('queued_snapshots', data);
    }
    return -1;
  }

  Future<Map<String, dynamic>?> getNextPendingQueuedSnapshot() async {
    if (_isWeb) {
      if (_memQueuedSnapshots.isEmpty) return null;
      _memQueuedSnapshots.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      return Map<String, dynamic>.from(_memQueuedSnapshots.first);
    }
    final db = await database;
    if (db != null) {
      final list = await db.query(
        'queued_snapshots',
        orderBy: 'id ASC',
        limit: 1,
      );
      if (list.isNotEmpty) {
        return Map<String, dynamic>.from(list.first);
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getAllQueuedSnapshots() async {
    if (_isWeb) {
      return List<Map<String, dynamic>>.from(_memQueuedSnapshots);
    }
    final db = await database;
    if (db != null) {
      return await db.query('queued_snapshots', orderBy: 'id ASC');
    }
    return [];
  }

  Future<int> getQueuedSnapshotCount() async {
    if (_isWeb) {
      return _memQueuedSnapshots.length;
    }
    final db = await database;
    if (db != null) {
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM queued_snapshots'),
      );
      return count ?? 0;
    }
    return 0;
  }

  Future<void> deleteQueuedSnapshot(int id) async {
    if (_isWeb) {
      _memQueuedSnapshots.removeWhere((item) => item['id'] == id);
      return;
    }
    final db = await database;
    if (db != null) {
      await db.delete('queued_snapshots', where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> incrementQueuedSnapshotRetry(int id) async {
    if (_isWeb) {
      final idx = _memQueuedSnapshots.indexWhere((item) => item['id'] == id);
      if (idx != -1) {
        final current = _memQueuedSnapshots[idx];
        current['retryCount'] = (current['retryCount'] ?? 0) + 1;
        current['status'] = 'pending';
      }
      return;
    }
    final db = await database;
    if (db != null) {
      await db.rawUpdate('''
        UPDATE queued_snapshots 
        SET retryCount = retryCount + 1, status = 'pending'
        WHERE id = ?
      ''', [id]);
    }
  }
}
