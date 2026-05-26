import '../models/biometric_record.dart';

class BiometricParser {
  /// Universal parser that attempts to handle various formats from different biometric brands.
  /// Supports: CSV, TSV, TXT, Space-separated formats, and XML (SpreadsheetML).
  static List<BiometricRecord> parseRawFile(String content) {
    if (content.trim().startsWith('<?xml') || content.contains('<Workbook')) {
      return _parseXmlPunchFormat(content);
    }

    final List<BiometricRecord> records = [];
    final lines = content.split(RegExp(r'[\r\n]+'));

    for (var rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Detect delimiter: Tab, Comma, Semicolon, or Whitespace
      List<String> parts;
      if (line.contains('\t')) {
        parts = line.split('\t');
      } else if (line.contains(',')) {
        parts = line.split(',');
      } else if (line.contains(';')) {
        parts = line.split(';');
      } else {
        parts = line.split(RegExp(r'\s+'));
      }

      parts = parts.map((p) => p.trim().replaceAll('"', '')).where((p) => p.isNotEmpty).toList();

      // Heuristic: Need at least a UserID and a Timestamp (Date + Time)
      if (parts.length < 2) continue;

      String? foundUserId;
      DateTime? foundTimestamp;
      String? foundStatus;
      int idIndex = -1;
      int tsIndex = -1;

      // 1. Find User ID Index
      for (int i = 0; i < parts.length; i++) {
        if (_isNumeric(parts[i]) || (parts[i].length <= 10 && !_isDate(parts[i]))) {
          foundUserId = parts[i];
          idIndex = i;
          break;
        }
      }

      // 2. Find Timestamp
      for (int i = 0; i < parts.length; i++) {
        final part = parts[i];
        DateTime? dt = DateTime.tryParse(part);
        if (dt != null) {
          tsIndex = i;
          if (dt.hour == 0 && dt.minute == 0 && i + 1 < parts.length) {
            final nextPart = parts[i + 1];
            final fullDt = DateTime.tryParse('$part $nextPart');
            if (fullDt != null) {
              foundTimestamp = fullDt;
            } else {
              foundTimestamp = dt;
            }
          } else {
            foundTimestamp = dt;
          }
          break;
        }
      }

      // 3. Find Name
      // Heuristic: Parts between ID and Timestamp are likely the Name
      String foundName = '';
      if (idIndex != -1 && tsIndex != -1) {
        int start = idIndex < tsIndex ? idIndex + 1 : 0;
        int end = idIndex < tsIndex ? tsIndex : idIndex;
        final nameParts = parts.sublist(start, end).where((p) => !_isNumeric(p) && !_isDate(p)).toList();
        foundName = nameParts.join(' ');
      }

      // 4. Find Status (Optional)
      if (parts.isNotEmpty && _isNumeric(parts.last) && parts.indexOf(parts.last) != idIndex && parts.indexOf(parts.last) != tsIndex) {
        foundStatus = parts.last;
      }

      if (foundUserId != null && foundTimestamp != null) {
        records.add(BiometricRecord(
          userId: foundUserId,
          uName: foundName,
          timestamp: foundTimestamp,
          status: foundStatus,
        ));
      }
    }
    return records;
  }

  static List<BiometricRecord> _parseXmlPunchFormat(String content) {
    final List<BiometricRecord> records = [];

    // 1. Extract potential year and month from the document
    // Pattern: <Data ss:Type="String">2026:4/27-4/30  Punch</Data>
    int year = DateTime.now().year;
    int month = DateTime.now().month;
    final dateHeaderMatch = RegExp(r'<Data ss:Type="String">(\d{4}):(\d{1,2})/[\d-]+').firstMatch(content);
    if (dateHeaderMatch != null) {
      year = int.parse(dateHeaderMatch.group(1)!);
      month = int.parse(dateHeaderMatch.group(2)!);
    }

    // 2. Identify User blocks and their punch grids
    final userRegex = RegExp(r'ID:(\d+)\s+Name:([^\s]+)');
    
    // Split by Rows to process the grid
    final rowRegex = RegExp(r'<Row[^>]*>(.*?)</Row>', dotAll: true);
    final rows = rowRegex.allMatches(content).toList();

    String? currentUserId;
    String currentUserName = '';
    List<int> currentDays = [];

    for (int i = 0; i < rows.length; i++) {
      final rowContent = rows[i].group(1)!;

      // Check if this row has User ID
      final userMatch = userRegex.firstMatch(rowContent);
      if (userMatch != null) {
        currentUserId = userMatch.group(1);
        currentUserName = userMatch.group(2)!.replaceAll('_', ' ');
        currentDays = []; // Reset for new user
        continue;
      }

      // Check if this row contains Day numbers (StyleID="s40" in the sample)
      if (rowContent.contains('ss:StyleID="s40"') && rowContent.contains('ss:Type="Number"')) {
        final dayMatches = RegExp(r'<Data ss:Type="Number">(\d+)</Data>').allMatches(rowContent);
        currentDays = dayMatches.map((m) => int.parse(m.group(1)!)).toList();
        continue;
      }

      // Check if this row contains Timestamps (StyleID="s26" in the sample)
      if (currentUserId != null && currentDays.isNotEmpty && 
          rowContent.contains('ss:StyleID="s26"') && rowContent.contains('ss:Type="String"')) {
        
        final timeCellMatches = RegExp(r'<Cell ss:StyleID="s26"[^>]*><Data ss:Type="String">(.*?)</Data></Cell>', dotAll: true).allMatches(rowContent).toList();
        
        for (int j = 0; j < timeCellMatches.length && j < currentDays.length; j++) {
          final day = currentDays[j];
          final timeString = timeCellMatches[j].group(1)!;
          
          final times = timeString.trim().split(RegExp(r'\s+')).where((t) => t.contains(':')).toList();
          
          for (var time in times) {
            try {
              final timeParts = time.split(':');
              final hour = int.parse(timeParts[0]);
              final minute = int.parse(timeParts[1]);
              
              records.add(BiometricRecord(
                userId: currentUserId,
                uName: currentUserName,
                timestamp: DateTime(year, month, day, hour, minute),
              ));
            } catch (e) {
              // Skip invalid times
            }
          }
        }
      }
    }

    return records;
  }

  static bool _isNumeric(String s) {
    return double.tryParse(s) != null;
  }

  static bool _isDate(String s) {
    return DateTime.tryParse(s) != null || s.contains('/') || (s.contains('-') && s.length > 5);
  }

  static Map<String, List<BiometricRecord>> groupByPerson(List<BiometricRecord> records) {
    final Map<String, List<BiometricRecord>> groups = {};
    for (var record in records) {
      groups.putIfAbsent(record.userId, () => []).add(record);
    }
    return groups;
  }
}
