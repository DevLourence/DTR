import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dtr_entry.dart';
import 'database_service.dart';

class StorageService {
  static const String _migratedKey = 'sqlite_migrated';

  static Future<void> saveNames(List<String> names) async {
    await DatabaseService.saveNames(names);
  }

  static Future<List<String>> loadNames() async {
    await _checkMigration();
    return await DatabaseService.loadNames();
  }

  static Future<void> saveDtrs(List<MonthlyDtr> dtrs) async {
    await DatabaseService.saveMonthlyDtrs(dtrs);
  }

  static Future<List<MonthlyDtr>> loadDtrs() async {
    await _checkMigration();
    return await DatabaseService.loadMonthlyDtrs();
  }

  /// Migrates data from SharedPreferences to SQLite if not already done.
  static Future<void> _checkMigration() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isMigrated = prefs.getBool(_migratedKey) ?? false;

    if (!isMigrated) {
      // Legacy SharedPreferences keys
      const String legacyKey = 'saved_dtrs';
      const String legacyNamesKey = 'saved_names';

      // Load legacy names
      final List<String> legacyNames = prefs.getStringList(legacyNamesKey) ?? [];
      if (legacyNames.isNotEmpty) {
        await DatabaseService.saveNames(legacyNames);
      }

      // Load legacy DTRs
      final String? encodedDtrs = prefs.getString(legacyKey);
      if (encodedDtrs != null) {
        try {
          final List<dynamic> decoded = jsonDecode(encodedDtrs);
          final List<MonthlyDtr> dtrs = decoded.map((item) => MonthlyDtr.fromJson(item)).toList();
          await DatabaseService.saveMonthlyDtrs(dtrs);
        } catch (_) {
          // Ignore parse errors in legacy data
        }
      }

      // Mark migration as complete
      await prefs.setBool(_migratedKey, true);
    }
  }
}
