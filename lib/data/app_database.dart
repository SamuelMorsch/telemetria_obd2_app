import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Abre o banco local da versão 2 (arquivo separado do da versão 1).
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    final Database? existing = _db;
    if (existing != null) return existing;
    final String path = p.join(await getDatabasesPath(), 'telemetria_v2.db');
    final Database db = await openDatabase(path, version: 1, onCreate: _create);
    _db = db;
    return db;
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id              TEXT PRIMARY KEY,
        vehicle_id      TEXT NOT NULL,
        started_at      TEXT NOT NULL,
        ended_at        TEXT,
        last_reading_at TEXT,
        source          TEXT NOT NULL,
        app_version     TEXT,
        opened          INTEGER NOT NULL DEFAULT 0,
        end_sent        INTEGER NOT NULL DEFAULT 0,
        failed_reason   TEXT
      )''');
    await db.execute('''
      CREATE TABLE readings (
        session_id             TEXT NOT NULL,
        seq                    INTEGER NOT NULL,
        time                   TEXT NOT NULL,
        battery_voltage        REAL,
        control_module_voltage REAL,
        rpm                    INTEGER,
        speed_kmh              INTEGER,
        coolant_temp_c         INTEGER,
        PRIMARY KEY (session_id, seq)
      )''');
    await db.execute('''
      CREATE TABLE dtcs (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id  TEXT NOT NULL,
        code        TEXT NOT NULL,
        status      TEXT NOT NULL,
        detected_at TEXT NOT NULL,
        UNIQUE (session_id, code, status)
      )''');
    await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
  }
}
