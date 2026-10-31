import 'package:sqflite/sqflite.dart';

import '../capture/capture_store.dart';
import '../core/models.dart';
import '../core/sync/outbox.dart';
import 'app_database.dart';

/// Tudo que a captura produz é gravado aqui primeiro (SQLite) e só sai depois de confirmado pelo servidor.
class LocalStore implements OutboxStore, CaptureStore {
  LocalStore(this._appDb);

  final AppDatabase _appDb;

  Future<Database> get _db => _appDb.database;

  String _iso(DateTime t) => t.toUtc().toIso8601String();

  // ---------------- captura ----------------

  @override
  Future<void> createSession(PendingSession session) async {
    final Database db = await _db;
    await db.insert(
      'sessions',
      <String, Object?>{
        'id': session.id,
        'vehicle_id': session.vehicleId,
        'started_at': _iso(session.startedAt),
        'source': session.source,
        'app_version': session.appVersion,
        'opened': 0,
        'end_sent': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> addReading(String sessionId, Reading reading) async {
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      await txn.insert(
        'readings',
        <String, Object?>{
          'session_id': sessionId,
          'seq': reading.seq,
          'time': _iso(reading.time),
          'battery_voltage': reading.values.batteryVoltage,
          'control_module_voltage': reading.values.controlModuleVoltage,
          'rpm': reading.values.rpm,
          'speed_kmh': reading.values.speedKmh,
          'coolant_temp_c': reading.values.coolantTempC,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'sessions',
        <String, Object?>{'last_reading_at': _iso(reading.time)},
        where: 'id = ?',
        whereArgs: <Object?>[sessionId],
      );
    });
  }

  @override
  Future<void> addDtc(String sessionId, Dtc dtc, DateTime detectedAt) async {
    final Database db = await _db;
    await db.insert(
      'dtcs',
      <String, Object?>{
        'session_id': sessionId,
        'code': dtc.code,
        'status': dtc.status.apiName,
        'detected_at': _iso(detectedAt),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> endSession(String sessionId, DateTime endedAt) async {
    final Database db = await _db;
    await db.update(
      'sessions',
      <String, Object?>{'ended_at': _iso(endedAt)},
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );
  }

  /// Se o app fechou no meio de uma captura (bateria, falha), a sessão ficou sem fim.
  /// Ao abrir o app, encerramos no horário da última leitura gravada.
  Future<void> closeOrphanSessions() async {
    final Database db = await _db;
    await db.rawUpdate(
      'UPDATE sessions SET ended_at = COALESCE(last_reading_at, started_at) WHERE ended_at IS NULL',
    );
  }

  /// Leituras que ainda não foram enviadas ao servidor.
  Future<int> pendingReadingCount() async {
    final Database db = await _db;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM readings')) ?? 0;
  }

  // ---------------- envio ----------------

  @override
  Future<List<PendingSession>> sessionsToSync() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT s.* FROM sessions s
       WHERE s.failed_reason IS NULL AND (
             s.opened = 0
          OR (s.ended_at IS NOT NULL AND s.end_sent = 0)
          OR EXISTS (SELECT 1 FROM readings r WHERE r.session_id = s.id)
          OR EXISTS (SELECT 1 FROM dtcs d WHERE d.session_id = s.id))
       ORDER BY s.started_at ASC''');
    return <PendingSession>[
      for (final Map<String, Object?> row in rows)
        PendingSession(
          id: row['id']! as String,
          vehicleId: row['vehicle_id']! as String,
          startedAt: DateTime.parse(row['started_at']! as String),
          endedAt: row['ended_at'] == null ? null : DateTime.parse(row['ended_at']! as String),
          source: row['source']! as String,
          appVersion: row['app_version'] as String?,
          opened: (row['opened']! as int) == 1,
          endSent: (row['end_sent']! as int) == 1,
        ),
    ];
  }

  @override
  Future<void> markSessionOpened(String sessionId) async {
    final Database db = await _db;
    await db.update('sessions', <String, Object?>{'opened': 1}, where: 'id = ?', whereArgs: <Object?>[sessionId]);
  }

  @override
  Future<void> markEndSent(String sessionId) async {
    final Database db = await _db;
    await db.update('sessions', <String, Object?>{'end_sent': 1}, where: 'id = ?', whereArgs: <Object?>[sessionId]);
  }

  @override
  Future<void> markSessionFailed(String sessionId, String reason) async {
    final Database db = await _db;
    await db.update(
      'sessions',
      <String, Object?>{'failed_reason': reason},
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );
  }

  @override
  Future<List<Reading>> pendingReadings(String sessionId, int limit) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'readings',
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
      orderBy: 'seq ASC',
      limit: limit,
    );
    return <Reading>[
      for (final Map<String, Object?> row in rows)
        Reading(
          seq: row['seq']! as int,
          time: DateTime.parse(row['time']! as String),
          values: ObdValues(
            batteryVoltage: (row['battery_voltage'] as num?)?.toDouble(),
            controlModuleVoltage: (row['control_module_voltage'] as num?)?.toDouble(),
            rpm: row['rpm'] as int?,
            speedKmh: row['speed_kmh'] as int?,
            coolantTempC: row['coolant_temp_c'] as int?,
          ),
        ),
    ];
  }

  @override
  Future<void> deleteReadings(String sessionId, List<int> seqs) async {
    if (seqs.isEmpty) return;
    final Database db = await _db;
    final String marks = List<String>.filled(seqs.length, '?').join(',');
    await db.delete(
      'readings',
      where: 'session_id = ? AND seq IN ($marks)',
      whereArgs: <Object?>[sessionId, ...seqs],
    );
  }

  @override
  Future<List<PendingDtc>> pendingDtcs(String sessionId, int limit) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'dtcs',
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
      orderBy: 'id ASC',
      limit: limit,
    );
    return <PendingDtc>[
      for (final Map<String, Object?> row in rows)
        PendingDtc(
          id: row['id']! as int,
          dtc: Dtc(
            code: row['code']! as String,
            status: row['status'] == 'pending' ? DtcStatus.pending : DtcStatus.stored,
          ),
          detectedAt: DateTime.parse(row['detected_at']! as String),
        ),
    ];
  }

  @override
  Future<void> deleteDtcs(String sessionId, List<int> ids) async {
    if (ids.isEmpty) return;
    final Database db = await _db;
    final String marks = List<String>.filled(ids.length, '?').join(',');
    await db.delete('dtcs', where: 'session_id = ? AND id IN ($marks)', whereArgs: <Object?>[sessionId, ...ids]);
  }

  // ---------------- preferências simples ----------------

  Future<String?> getValue(String key) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows =
        await db.query('kv', where: 'key = ?', whereArgs: <Object?>[key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setValue(String key, String value) async {
    final Database db = await _db;
    await db.insert('kv', <String, Object?>{'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeValue(String key) async {
    final Database db = await _db;
    await db.delete('kv', where: 'key = ?', whereArgs: <Object?>[key]);
  }
}
