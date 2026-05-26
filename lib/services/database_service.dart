import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/dtr_entry.dart';

class DatabaseService {
  static Database? _database;
  static bool _isInitializing = false;
  static Completer<Database>? _initCompleter;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    
    if (_isInitializing && _initCompleter != null) {
      return await _initCompleter!.future;
    }

    _isInitializing = true;
    _initCompleter = Completer<Database>();

    try {
      _database = await _initDatabase();
      _initCompleter!.complete(_database);
    } catch (e) {
      _initCompleter!.completeError(e);
    } finally {
      _isInitializing = false;
    }
    
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    // We try multiple directories to ensure we can write the database.
    // 1. AppSupportDirectory (preferred for app data)
    // 2. DocumentsDirectory (fallback if AppSupport fails)
    // 3. getDatabasesPath (sqflite default)

    final dirsToTry = <Future<Directory> Function()>[
      () => getApplicationSupportDirectory(),
      () => getApplicationDocumentsDirectory(),
    ];

    for (var getDir in dirsToTry) {
      try {
        final Directory baseDir = await getDir();
        final String dbDir = join(baseDir.path, 'DTR_Automator');
        await Directory(dbDir).create(recursive: true);
        
        // Normalize path and replace backslashes with forward slashes for SQLite
        String path = join(dbDir, 'dtr_automator.db').replaceAll('\\', '/');

        return await openDatabase(
          path,
          version: 2,
          onCreate: _createDb,
          onUpgrade: _onUpgrade,
        );
      } catch (e) {
        // If this directory fails, we continue to the next one
        debugPrint('Failed to open database at directory: $e');
      }
    }

    // Final fallback using sqflite's default
    try {
      String dbDir = await getDatabasesPath();
      await Directory(dbDir).create(recursive: true);
      String path = join(dbDir, 'dtr_automator.db').replaceAll('\\', '/');
      
      return await openDatabase(
        path,
        version: 2,
        onCreate: _createDb,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      debugPrint('Fallback getDatabasesPath failed: $e');
      rethrow; // If all fail, throw the error
    }
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add unique constraint by creating an index (SQLite doesn't allow adding UNIQUE to existing table via ALTER easily)
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_name_month_year ON monthly_dtrs (name, month, year)');
    }
  }

  static Future<void> _createDb(Database db, int version) async {
    // Table for Monthly DTR Records
    await db.execute('''
      CREATE TABLE monthly_dtrs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT,
        name TEXT,
        month INTEGER,
        year INTEGER,
        supervisor TEXT,
        amInTime TEXT,
        amOutTime TEXT,
        pmInTime TEXT,
        pmOutTime TEXT,
        UNIQUE(name, month, year)
      )
    ''');

    // Table for Individual Daily Entries
    await db.execute('''
      CREATE TABLE dtr_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        monthlyDtrId INTEGER,
        day INTEGER,
        amArrival TEXT,
        amDeparture TEXT,
        pmArrival TEXT,
        pmDeparture TEXT,
        FOREIGN KEY (monthlyDtrId) REFERENCES monthly_dtrs (id) ON DELETE CASCADE
      )
    ''');

    // Table for Saved Employee Names (for autocomplete/suggestions)
    await db.execute('''
      CREATE TABLE saved_names (
        name TEXT PRIMARY KEY
      )
    ''');
  }

  // --- CRUD Operations ---

  static Future<void> saveMonthlyDtrs(List<MonthlyDtr> dtrs) async {
    final db = await database;
    await db.transaction((txn) async {
      // Clear existing to overwrite (or we could do more complex merging)
      await txn.delete('monthly_dtrs');
      await txn.delete('dtr_entries');

      for (var dtr in dtrs) {
        final id = await txn.insert('monthly_dtrs', {
          'userId': dtr.userId,
          'name': dtr.name,
          'month': dtr.month,
          'year': dtr.year,
          'supervisor': dtr.supervisor,
          'amInTime': dtr.amInTime,
          'amOutTime': dtr.amOutTime,
          'pmInTime': dtr.pmInTime,
          'pmOutTime': dtr.pmOutTime,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        for (var entry in dtr.entries.values) {
          await txn.insert('dtr_entries', {
            'monthlyDtrId': id,
            'day': entry.day,
            'amArrival': entry.amArrival?.toIso8601String(),
            'amDeparture': entry.amDeparture?.toIso8601String(),
            'pmArrival': entry.pmArrival?.toIso8601String(),
            'pmDeparture': entry.pmDeparture?.toIso8601String(),
          });
        }
      }
    });
  }

  static Future<List<MonthlyDtr>> loadMonthlyDtrs() async {
    final db = await database;
    final List<Map<String, dynamic>> dtrMaps = await db.query('monthly_dtrs');
    
    List<MonthlyDtr> dtrs = [];
    for (var map in dtrMaps) {
      final int id = map['id'];
      final List<Map<String, dynamic>> entryMaps = await db.query(
        'dtr_entries',
        where: 'monthlyDtrId = ?',
        whereArgs: [id],
      );

      final Map<int, DtrEntry> entries = {};
      for (var entryMap in entryMaps) {
        final day = entryMap['day'] as int;
        final entry = DtrEntry(day);
        if (entryMap['amArrival'] != null) entry.amArrival = DateTime.parse(entryMap['amArrival']);
        if (entryMap['amDeparture'] != null) entry.amDeparture = DateTime.parse(entryMap['amDeparture']);
        if (entryMap['pmArrival'] != null) entry.pmArrival = DateTime.parse(entryMap['pmArrival']);
        if (entryMap['pmDeparture'] != null) entry.pmDeparture = DateTime.parse(entryMap['pmDeparture']);
        entries[day] = entry;
      }

      dtrs.add(MonthlyDtr(
        userId: map['userId'],
        name: map['name'],
        month: map['month'],
        year: map['year'],
        entries: entries,
        supervisor: map['supervisor'],
        amInTime: map['amInTime'],
        amOutTime: map['amOutTime'],
        pmInTime: map['pmInTime'],
        pmOutTime: map['pmOutTime'],
      ));
    }
    return dtrs;
  }

  static Future<void> saveNames(List<String> names) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('saved_names');
      for (var name in names) {
        await txn.insert('saved_names', {'name': name});
      }
    });
  }

  static Future<List<String>> loadNames() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('saved_names');
    return maps.map((m) => m['name'] as String).toList();
  }
}
