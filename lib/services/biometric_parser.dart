import '../models/biometric_record.dart';

class BiometricParser {
  /// Universal parser supporting multiple formats from different biometric devices.
  /// Format 1: Line-per-punch (TXT/CSV/TSV) — each line is one punch event.
  /// Format 2: Grid (XLS) — each row is one person, columns are punch timestamps.
  /// Format 3: SpreadsheetML XML.
  static List<BiometricRecord> parseRawFile(String content) {
    if (content.trim().startsWith('<?xml') || content.contains('<Workbook')) {
      return _parseXmlPunchFormat(content);
    }

    final lines = content.split(RegExp(r'[\r\n]+'));
    final nonEmpty =
        lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    if (nonEmpty.isEmpty) return [];

    // Heuristic: if many rows have 3+ DateTime-like tokens, treat as grid format.
    int gridLikeRows = 0;
    final sample = nonEmpty.take(10).toList();
    for (var line in sample) {
      final parts = _splitLine(line);
      final dtCount = parts.where((p) => _isDateTimeish(p)).length;
      if (dtCount >= 3) gridLikeRows++;
    }

    if (sample.isNotEmpty && gridLikeRows >= (sample.length / 2).ceil()) {
      return _parseGridFormat(nonEmpty);
    }

    return _parseLinePunchFormat(nonEmpty);
  }

  // ---------------------------------------------------------------------------
  // FORMAT 1: Line-per-punch (TXT / CSV / TSV biometric export)
  // Each line: [UserID] [Name...] [DateTime] [Status?]
  // Multiple persons supported — each person appears on their own lines.
  // ---------------------------------------------------------------------------
  static List<BiometricRecord> _parseLinePunchFormat(List<String> lines) {
    final List<BiometricRecord> records = [];

    for (var line in lines) {
      final parts = _splitLine(line);
      if (parts.length < 2) continue;

      String? foundUserId;
      DateTime? foundTimestamp;
      String? foundStatus;
      int idIndex = -1;
      int tsIndex = -1;

      // 1. Find User ID — first short alphanumeric token that is not a date
      for (int i = 0; i < parts.length; i++) {
        if (_isUserId(parts[i])) {
          foundUserId = parts[i];
          idIndex = i;
          break;
        }
      }

      // 2. Find Timestamp — try combined "date time" pair if needed
      for (int i = 0; i < parts.length; i++) {
        final dt = DateTime.tryParse(parts[i]);
        if (dt != null) {
          tsIndex = i;
          if (dt.hour == 0 && dt.minute == 0 && i + 1 < parts.length) {
            final combined = DateTime.tryParse('${parts[i]} ${parts[i + 1]}');
            foundTimestamp = combined ?? dt;
          } else {
            foundTimestamp = dt;
          }
          break;
        }
      }

      // 3. Extract Name — tokens between ID and Timestamp
      String foundName = '';
      if (idIndex != -1 && tsIndex != -1 && idIndex < tsIndex) {
        final nameParts = parts
            .sublist(idIndex + 1, tsIndex)
            .where((p) => !_isNumeric(p) && !_isDateTimeish(p))
            .toList();
        foundName = nameParts.join(' ');
      }

      // 4. Optional punch status (last numeric token)
      if (parts.isNotEmpty && _isNumeric(parts.last)) {
        final lastIdx = parts.lastIndexOf(parts.last);
        if (lastIdx != idIndex && lastIdx != tsIndex) {
          foundStatus = parts.last;
        }
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

  // ---------------------------------------------------------------------------
  // FORMAT 2: Grid (XLS biometric export)
  // Each row = one person: [ID] [Name] [punch1] [punch2] [punch3] ...
  // Multiple persons supported — each row is a different person.
  // ---------------------------------------------------------------------------
  static List<BiometricRecord> _parseGridFormat(List<String> lines) {
    final List<BiometricRecord> records = [];

    for (var line in lines) {
      final parts = _splitLine(line);
      if (parts.length < 2) continue;

      // Find where the DateTime columns start
      int firstDtIndex = -1;
      for (int i = 0; i < parts.length; i++) {
        if (_isDateTimeish(parts[i])) {
          firstDtIndex = i;
          break;
        }
      }

      if (firstDtIndex == -1) continue; // No timestamps in this row — skip

      // Tokens before first DateTime = ID + Name metadata
      final meta = parts.sublist(0, firstDtIndex);
      if (meta.isEmpty) continue;

      String? userId;
      String userName = '';

      for (int i = 0; i < meta.length; i++) {
        if (_isUserId(meta[i])) {
          userId = meta[i];
          final nameTokens = meta
              .sublist(i + 1)
              .where((p) => !_isNumeric(p))
              .toList();
          userName = nameTokens.join(' ').replaceAll('_', ' ').trim();
          break;
        }
      }

      if (userId == null) continue;

      // Each remaining column is a punch timestamp for this person
      for (int i = firstDtIndex; i < parts.length; i++) {
        final dt = DateTime.tryParse(parts[i]);
        if (dt != null) {
          records.add(BiometricRecord(
            userId: userId,
            uName: userName,
            timestamp: dt,
          ));
        }
      }
    }
    return records;
  }

  // ---------------------------------------------------------------------------
  // FORMAT 3: SpreadsheetML XML
  // ---------------------------------------------------------------------------
  static List<BiometricRecord> _parseXmlPunchFormat(String content) {
    final List<BiometricRecord> records = [];

    int year = DateTime.now().year;
    int month = DateTime.now().month;
    final dateHeaderMatch = RegExp(
      r'<Data ss:Type="String">(\d{4}):(\d{1,2})/[\d-]+',
    ).firstMatch(content);
    if (dateHeaderMatch != null) {
      year = int.parse(dateHeaderMatch.group(1)!);
      month = int.parse(dateHeaderMatch.group(2)!);
    }

    final userRegex = RegExp(r'ID:(\d+)\s+Name:(.+?)(?=\s{2,}|Dept:|<)');
    final rowRegex = RegExp(r'<Row[^>]*>(.*?)</Row>', dotAll: true);
    final rows = rowRegex.allMatches(content).toList();

    String? currentUserId;
    String currentUserName = '';
    List<int> currentDays = [];

    for (int i = 0; i < rows.length; i++) {
      final rowContent = rows[i].group(1)!;

      final userMatch = userRegex.firstMatch(rowContent);
      if (userMatch != null) {
        currentUserId = userMatch.group(1);
        currentUserName = userMatch.group(2)!.replaceAll('_', ' ').trim();
        currentDays = [];
        continue;
      }

      if (rowContent.contains('ss:StyleID="s40"') &&
          rowContent.contains('ss:Type="Number"')) {
        final dayMatches =
            RegExp(r'<Data ss:Type="Number">(\d+)</Data>').allMatches(rowContent);
        currentDays = dayMatches.map((m) => int.parse(m.group(1)!)).toList();
        continue;
      }

      if (currentUserId != null &&
          currentDays.isNotEmpty &&
          rowContent.contains('ss:StyleID="s26"') &&
          rowContent.contains('ss:Type="String"')) {
        final timeCellMatches = RegExp(
          r'<Cell ss:StyleID="s26"[^>]*><Data ss:Type="String">(.*?)</Data></Cell>',
          dotAll: true,
        ).allMatches(rowContent).toList();

        for (int j = 0;
            j < timeCellMatches.length && j < currentDays.length;
            j++) {
          final day = currentDays[j];
          final timeString = timeCellMatches[j].group(1)!;
          final times = timeString
              .trim()
              .split(RegExp(r'\s+'))
              .where((t) => t.contains(':'))
              .toList();

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
            } catch (_) {
              // Skip invalid time entries
            }
          }
        }
      }
    }
    return records;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static List<String> _splitLine(String line) {
    List<String> parts;
    if (line.contains('\t')) {
      parts = line.split('\t');
    } else if (line.contains(',')) {
      parts = line.split(',');
    } else if (line.contains(';')) {
      parts = line.split(';');
    } else {
      // Fall back to splitting on 2+ spaces to preserve names with single spaces
      parts = line.split(RegExp(r'\s{2,}'));
    }
    return parts
        .map((p) => p.trim().replaceAll('"', ''))
        .where((p) => p.isNotEmpty)
        .toList();
  }

  /// A user ID is a short (≤10 chars) alphanumeric token that is not a date.
  static bool _isUserId(String s) {
    return s.length <= 10 &&
        !_isDateTimeish(s) &&
        RegExp(r'^[a-zA-Z0-9\-_]+$').hasMatch(s);
  }

  static bool _isNumeric(String s) => double.tryParse(s) != null;

  static bool _isDateTimeish(String s) {
    if (DateTime.tryParse(s) != null) return true;
    if (s.contains('/') && s.length >= 5) return true;
    if (s.contains('-') && s.length > 5 && RegExp(r'\d').hasMatch(s)) {
      return true;
    }
    return false;
  }

  static Map<String, List<BiometricRecord>> groupByPerson(
    List<BiometricRecord> records,
  ) {
    final Map<String, List<BiometricRecord>> groups = {};
    for (var record in records) {
      groups.putIfAbsent(record.userId, () => []).add(record);
    }
    return groups;
  }
}
