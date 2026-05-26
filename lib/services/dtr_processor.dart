import '../models/biometric_record.dart';
import '../models/dtr_entry.dart';

class DtrProcessor {
  static int _parseToMinutes(String? s, int fallbackMinutes) {
    if (s == null || !s.contains(':')) return fallbackMinutes;
    final parts = s.split(':');
    try {
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    } catch (_) {
      return fallbackMinutes;
    }
  }

  static List<MonthlyDtr> processToMonthlyDtr(
    List<BiometricRecord> records, {
    Map<String, MonthlyDtr>? existingDtrs,
  }) {
    // 1. Group by Person
    final personGroups = <String, List<BiometricRecord>>{};
    for (var r in records) {
      personGroups.putIfAbsent(r.userId, () => []).add(r);
    }

    final List<MonthlyDtr> results = [];

    personGroups.forEach((userId, personRecords) {
      // 2. Group by Month/Year
      final monthGroups = <String, List<BiometricRecord>>{};
      for (var r in personRecords) {
        final key = '${r.timestamp.year}-${r.timestamp.month}';
        monthGroups.putIfAbsent(key, () => []).add(r);
      }

      monthGroups.forEach((monthKey, monthRecords) {
        final parts = monthKey.split('-');
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);

        final entries = <int, DtrEntry>{};
        
        // Initialize days
        final daysInMonth = DateTime(year, month + 1, 0).day;
        for (int d = 1; d <= daysInMonth; d++) {
          entries[d] = DtrEntry(d);
        }

        // Group by Day
        final dayGroups = <int, List<BiometricRecord>>{};
        for (var r in monthRecords) {
          dayGroups.putIfAbsent(r.timestamp.day, () => []).add(r);
        }

        dayGroups.forEach((day, logs) {
          logs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          
          final entry = entries[day]!;
          
          // Smart, adaptive chronological slotting with 25-minute constraint from set times
          entry.amArrival = null;
          entry.amDeparture = null;
          entry.pmArrival = null;
          entry.pmDeparture = null;

          final times = logs.map((l) => l.timestamp).toList();
          times.sort((a, b) => a.compareTo(b));

          if (times.isNotEmpty) {
            // Resolve set times for this user
            final existing = existingDtrs?[userId];
            final amInTarget = _parseToMinutes(existing?.amInTime, 8 * 60);     // Default 8:00 AM
            final amOutTarget = _parseToMinutes(existing?.amOutTime, 12 * 60);   // Default 12:00 PM
            final pmInTarget = _parseToMinutes(existing?.pmInTime, 13 * 60);    // Default 1:00 PM
            final pmOutTarget = _parseToMinutes(existing?.pmOutTime, 17 * 60);   // Default 5:00 PM

            final List<DateTime> amInCandidates = [];
            final List<DateTime> amOutCandidates = [];
            final List<DateTime> pmInCandidates = [];
            final List<DateTime> pmOutCandidates = [];

            for (var t in times) {
              final minutes = t.hour * 60 + t.minute;
              
              // Distance to target times
              final diffAmIn = (minutes - amInTarget).abs();
              final diffAmOut = (minutes - amOutTarget).abs();
              final diffPmIn = (minutes - pmInTarget).abs();
              final diffPmOut = (minutes - pmOutTarget).abs();

              // Only read within 25 minutes of the set/target times
              if (diffAmIn <= 25) {
                amInCandidates.add(t);
              } else if (diffAmOut <= 25) {
                amOutCandidates.add(t);
              } else if (diffPmIn <= 25) {
                pmInCandidates.add(t);
              } else if (diffPmOut <= 25) {
                pmOutCandidates.add(t);
              }
            }

            if (amInCandidates.isNotEmpty) {
              amInCandidates.sort((a, b) => a.compareTo(b));
              entry.amArrival = amInCandidates.first;
            }
            if (amOutCandidates.isNotEmpty) {
              amOutCandidates.sort((a, b) => a.compareTo(b));
              entry.amDeparture = amOutCandidates.last;
            }
            if (pmInCandidates.isNotEmpty) {
              pmInCandidates.sort((a, b) => a.compareTo(b));
              entry.pmArrival = pmInCandidates.first;
            }
            if (pmOutCandidates.isNotEmpty) {
              pmOutCandidates.sort((a, b) => a.compareTo(b));
              entry.pmDeparture = pmOutCandidates.last;
            }
          }
        });

        // Find a name for this user from the records
        String bestName = userId;
        for (var r in monthRecords) {
          if (r.uName.isNotEmpty) {
            bestName = r.uName;
            break;
          }
        }

        final existing = existingDtrs?[userId];
        results.add(MonthlyDtr(
          userId: userId,
          name: bestName,
          month: month,
          year: year,
          entries: entries,
          supervisor: existing?.supervisor,
          amInTime: existing?.amInTime,
          amOutTime: existing?.amOutTime,
          pmInTime: existing?.pmInTime,
          pmOutTime: existing?.pmOutTime,
        ));
      });
    });

    return results;
  }
}
