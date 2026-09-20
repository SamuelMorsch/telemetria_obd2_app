import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('telemetria.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    return await openDatabase(
      join(dbPath, filePath),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE falhas(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            codigo TEXT,
            timestamp TEXT
          )
        ''');
      },
    );
  }

  Future<void> inserirFalha(String codigo) async {
    final db = await instance.database;
    await db.insert('falhas', {
      'codigo': codigo,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> listarFalhas() async {
    final db = await instance.database;
    return await db.query('falhas', orderBy: 'timestamp DESC');
  }

  Future<void> limparHistorico() async {
    final db = await instance.database;
    await db.delete('falhas'); // Deleta todas as linhas da tabela
  }

}