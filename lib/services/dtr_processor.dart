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
          
          // Smart, adaptive chronological slotting
          entry.amArrival = null;
          entry.amDeparture = null;
          entry.pmArrival = null;
          entry.pmDeparture = null;

          final times = logs.map((l) => l.timestamp).toList();
          times.sort((a, b) => a.compareTo(b));

          if (times.isNotEmpty) {
            if (times.length == 1) {
              final t = times[0];
              if (t.hour < 12) {
                entry.amArrival = t;
              } else {
                if (t.hour >= 15) {
                  entry.pmDeparture = t;
                } else {
                  entry.pmArrival = t;
                }
              }
            } else if (times.length == 2) {
              final t1 = times[0];
              final t2 = times[1];
              
              if (t1.hour < 12) {
                entry.amArrival = t1;
                if (t2.hour < 12 || (t2.hour == 12 && t2.minute <= 30)) {
                  entry.amDeparture = t2;
                } else {
                  entry.pmDeparture = t2;
                }
              } else {
                entry.pmArrival = t1;
                entry.pmDeparture = t2;
              }
            } else if (times.length == 3) {
              final t1 = times[0];
              final t2 = times[1];
              final t3 = times[2];

              if (t1.hour < 12) {
                entry.amArrival = t1;
                if (t2.hour < 12 || (t2.hour == 12 && t2.minute <= 30)) {
                  entry.amDeparture = t2;
                  if (t3.hour >= 14) {
                    entry.pmDeparture = t3;
                  } else {
                    entry.pmArrival = t3;
                  }
                } else {
                  entry.pmArrival = t2;
                  entry.pmDeparture = t3;
                }
              } else {
                entry.pmArrival = t1;
                entry.pmDeparture = t3;
              }
            } else {
              // 4 or more punches: group them by closest target time
              const amInTarget = 8 * 60;     // 8:00 AM
              const amOutTarget = 12 * 60;   // 12:00 PM
              const pmInTarget = 13 * 60;    // 1:00 PM
              const pmOutTarget = 17 * 60;   // 5:00 PM

              final List<DateTime> amInCandidates = [];
              final List<DateTime> amOutCandidates = [];
              final List<DateTime> pmInCandidates = [];
              final List<DateTime> pmOutCandidates = [];

              for (var t in times) {
                final minutes = t.hour * 60 + t.minute;
                
                final diffAmIn = (minutes - amInTarget).abs();
                final diffAmOut = (minutes - amOutTarget).abs();
                final diffPmIn = (minutes - pmInTarget).abs();
                final diffPmOut = (minutes - pmOutTarget).abs();

                var minDiff = diffAmIn;
                var slot = 'amIn';

                if (diffAmOut < minDiff) {
                  minDiff = diffAmOut;
                  slot = 'amOut';
                }
                if (diffPmIn < minDiff) {
                  minDiff = diffPmIn;
                  slot = 'pmIn';
                }
                if (diffPmOut < minDiff) {
                  minDiff = diffPmOut;
                  slot = 'pmOut';
                }

                if (slot == 'amIn') {
                  amInCandidates.add(t);
                } else if (slot == 'amOut') {
                  amOutCandidates.add(t);
                } else if (slot == 'pmIn') {
                  pmInCandidates.add(t);
                } else if (slot == 'pmOut') {
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

              // Fallback: if we have exactly 4 punches but they got clustered into fewer slots,
              // enforce sequential order to avoid blanks.
              if (times.length == 4 && 
                  (entry.amArrival == null || entry.amDeparture == null || entry.pmArrival == null || entry.pmDeparture == null)) {
                entry.amArrival = times[0];
                entry.amDeparture = times[1];
                entry.pmArrival = times[2];
                entry.pmDeparture = times[3];
              }
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
