import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;
  final List<Map<String, dynamic>> _inMemorySyncQueue = [];
  final List<Map<String, dynamic>> _inMemoryEvents = [];
  final List<Map<String, dynamic>> _inMemoryLocations = [];
  final List<Map<String, dynamic>> _inMemoryHelplines = [];

  Future<Database?> get database async {
    if (kIsWeb) return null;
    if (_db != null) return _db!;
    try {
      _db = await _initDb();
      return _db!;
    } catch (_) {
      return null;
    }
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'bhai_offline.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_events (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            status TEXT NOT NULL,
            start_time TEXT NOT NULL,
            initial_latitude REAL NOT NULL,
            initial_longitude REAL NOT NULL,
            initial_address TEXT,
            synced INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE offline_locations (
            id TEXT PRIMARY KEY,
            event_id TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            timestamp TEXT NOT NULL,
            battery_level REAL,
            network_status TEXT,
            synced INTEGER DEFAULT 0,
            FOREIGN KEY (event_id) REFERENCES offline_events (id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE helpline_cache (
            id TEXT PRIMARY KEY,
            state TEXT NOT NULL,
            category TEXT NOT NULL,
            number TEXT NOT NULL,
            name TEXT NOT NULL
          )
        ''');

        await _createEmergencySyncQueue(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createEmergencySyncQueue(db);
      },
    );
  }

  Future<void> _createEmergencySyncQueue(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS emergency_sync_queue (
        id TEXT PRIMARY KEY,
        local_emergency_id TEXT NOT NULL,
        remote_emergency_id TEXT,
        operation TEXT NOT NULL,
        encrypted_payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_emergency_sync_pending ON emergency_sync_queue(synced, created_at)');
  }

  // --- Offline Events Helpers ---

  Future<void> insertEvent(Map<String, dynamic> event) async {
    if (kIsWeb) {
      _inMemoryEvents.removeWhere((e) => e['id'] == event['id']);
      _inMemoryEvents.add(Map<String, dynamic>.from(event));
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.insert('offline_events', event, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedEvents() async {
    if (kIsWeb) {
      return _inMemoryEvents.where((e) => e['synced'] == 0).toList();
    }
    final db = await database;
    if (db == null) return [];
    return await db.query('offline_events', where: 'synced = 0');
  }

  Future<void> markEventSynced(String id) async {
    if (kIsWeb) {
      for (final e in _inMemoryEvents) {
        if (e['id'] == id) e['synced'] = 1;
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.update('offline_events', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // --- Offline Locations Helpers ---

  Future<void> insertLocation(Map<String, dynamic> location) async {
    if (kIsWeb) {
      _inMemoryLocations.add(Map<String, dynamic>.from(location));
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.insert('offline_locations', location, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedLocations() async {
    if (kIsWeb) {
      return _inMemoryLocations.where((l) => l['synced'] == 0).toList();
    }
    final db = await database;
    if (db == null) return [];
    return await db.query('offline_locations', where: 'synced = 0');
  }

  Future<void> markLocationSynced(String id) async {
    if (kIsWeb) {
      for (final l in _inMemoryLocations) {
        if (l['id'] == id) l['synced'] = 1;
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.update('offline_locations', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // --- Helpline Cache Helpers ---

  Future<void> cacheHelplines(List<Map<String, dynamic>> helplines) async {
    if (kIsWeb) {
      _inMemoryHelplines.clear();
      _inMemoryHelplines.addAll(helplines.map((h) => Map<String, dynamic>.from(h)));
      return;
    }
    final db = await database;
    if (db == null) return;
    final batch = db.batch();
    batch.delete('helpline_cache');
    for (var line in helplines) {
      batch.insert('helpline_cache', line, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> searchHelplines(String query) async {
    if (kIsWeb) {
      if (query.isEmpty) return List.from(_inMemoryHelplines);
      final q = query.toLowerCase();
      return _inMemoryHelplines.where((h) {
        final s = (h['state'] ?? '').toString().toLowerCase();
        final c = (h['category'] ?? '').toString().toLowerCase();
        final n = (h['name'] ?? '').toString().toLowerCase();
        return s.contains(q) || c.contains(q) || n.contains(q);
      }).toList();
    }
    final db = await database;
    if (db == null) return [];
    if (query.isEmpty) {
      return await db.query('helpline_cache');
    }
    return await db.query(
      'helpline_cache',
      where: 'state LIKE ? OR category LIKE ? OR name LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
    );
  }

  // --- Encrypted emergency offline queue ---

  Future<void> queueEmergencyOperation({
    required String id,
    required String localEmergencyId,
    required String operation,
    required String encryptedPayload,
    String? remoteEmergencyId,
  }) async {
    final item = {
      'id': id,
      'local_emergency_id': localEmergencyId,
      'remote_emergency_id': remoteEmergencyId,
      'operation': operation,
      'encrypted_payload': encryptedPayload,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'synced': 0,
    };
    if (kIsWeb) {
      _inMemorySyncQueue.removeWhere((x) => x['id'] == id);
      _inMemorySyncQueue.add(item);
      return;
    }
    try {
      final db = await database;
      if (db == null) {
        _inMemorySyncQueue.add(item);
        return;
      }
      await db.insert(
        'emergency_sync_queue',
        item,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {
      _inMemorySyncQueue.add(item);
    }
  }

  Future<List<Map<String, dynamic>>> getPendingEmergencyOperations() async {
    if (kIsWeb) {
      return _inMemorySyncQueue.where((x) => x['synced'] == 0).toList();
    }
    try {
      final db = await database;
      if (db == null) return _inMemorySyncQueue.where((x) => x['synced'] == 0).toList();
      return await db.query(
        'emergency_sync_queue',
        where: 'synced = 0',
        orderBy: "CASE operation WHEN 'CREATE' THEN 0 WHEN 'LOCATION' THEN 1 ELSE 2 END, created_at ASC",
      );
    } catch (_) {
      return _inMemorySyncQueue.where((x) => x['synced'] == 0).toList();
    }
  }

  Future<void> markEmergencyOperationSynced(String id, {String? remoteEmergencyId}) async {
    if (kIsWeb) {
      for (final item in _inMemorySyncQueue) {
        if (item['id'] == id) {
          item['synced'] = 1;
          if (remoteEmergencyId != null) item['remote_emergency_id'] = remoteEmergencyId;
        }
      }
      return;
    }
    try {
      final db = await database;
      if (db == null) return;
      await db.update(
        'emergency_sync_queue',
        {'synced': 1, if (remoteEmergencyId != null) 'remote_emergency_id': remoteEmergencyId},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (remoteEmergencyId != null) {
        final rows = await db.query('emergency_sync_queue', where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isNotEmpty) {
          final localId = rows.first['local_emergency_id'];
          await db.update(
            'emergency_sync_queue',
            {'remote_emergency_id': remoteEmergencyId},
            where: 'local_emergency_id = ?',
            whereArgs: [localId],
          );
        }
      }
    } catch (_) {}
  }
}
