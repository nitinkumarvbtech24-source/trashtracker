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
  int _memTelemetryId = 0;
  int _memVideoId = 0;

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
        version: 1,
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
}
