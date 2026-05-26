import '../models/biometric_record.dart';
import '../models/dtr_entry.dart';

class DtrProcessor {
  static List<MonthlyDtr> processToMonthlyDtr(List<BiometricRecord> records) {
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
          
          // Simple logic for Form 48 Slots
          // Slot 1: AM Arrival (Earliest before 12:00)
          final amLogs = logs.where((l) => l.timestamp.hour < 12).toList();
          if (amLogs.isNotEmpty) {
            entry.amArrival = amLogs.first.timestamp;
            if (amLogs.length > 1) {
              entry.amDeparture = amLogs.last.timestamp;
            }
          }

          // Slot 2: PM Arrival/Departure (Logs after 12:00)
          final pmLogs = logs.where((l) => l.timestamp.hour >= 12).toList();
          if (pmLogs.isNotEmpty) {
            entry.pmArrival = pmLogs.first.timestamp;
            if (pmLogs.length > 1) {
              entry.pmDeparture = pmLogs.last.timestamp;
            } else if (amLogs.length == 1) {
              // If only one log in afternoon, and we have AM arrival, 
              // maybe this is PM departure? 
              // Often Form 48 users log 4 times.
              entry.pmDeparture = pmLogs.first.timestamp;
              entry.pmArrival = null;
            }
          }
          
          // Refined Slotting:
          // In many systems: 
          // Arrival AM: < 10:00
          // Departure AM: 10:00 - 13:00
          // Arrival PM: 13:00 - 15:00
          // Departure PM: > 15:00
          
          // Let's try a more robust approach based on actual time windows
          entry.amArrival = null;
          entry.amDeparture = null;
          entry.pmArrival = null;
          entry.pmDeparture = null;

          for (var log in logs) {
            final time = log.timestamp.hour * 60 + log.timestamp.minute;
            
            if (time < 11 * 60) { // Before 11 AM
              entry.amArrival ??= log.timestamp;
            } else if (time >= 11 * 60 && time < 13 * 60) { // 11 AM - 1 PM
              // Could be AM Departure or PM Arrival
              if (entry.amDeparture == null) {
                 entry.amDeparture = log.timestamp;
              } else {
                 entry.pmArrival = log.timestamp;
              }
            } else if (time >= 13 * 60 && time < 16 * 60) { // 1 PM - 4 PM
              entry.pmArrival ??= log.timestamp;
            } else if (time >= 16 * 60) { // After 4 PM
              entry.pmDeparture = log.timestamp;
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

        results.add(MonthlyDtr(
          userId: userId,
          name: bestName,
          month: month,
          year: year,
          entries: entries,
        ));
      });
    });

    return results;
  }
}
