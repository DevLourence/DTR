import 'package:intl/intl.dart';

class DtrEntry {
  final int day;
  DateTime? amArrival;
  DateTime? amDeparture;
  DateTime? pmArrival;
  DateTime? pmDeparture;

  DtrEntry(this.day);

  Map<String, dynamic> toJson() => {
    'day': day,
    'amArrival': amArrival?.toIso8601String(),
    'amDeparture': amDeparture?.toIso8601String(),
    'pmArrival': pmArrival?.toIso8601String(),
    'pmDeparture': pmDeparture?.toIso8601String(),
  };

  factory DtrEntry.fromJson(Map<String, dynamic> json) {
    final entry = DtrEntry(json['day']);
    if (json['amArrival'] != null) entry.amArrival = DateTime.parse(json['amArrival']);
    if (json['amDeparture'] != null) entry.amDeparture = DateTime.parse(json['amDeparture']);
    if (json['pmArrival'] != null) entry.pmArrival = DateTime.parse(json['pmArrival']);
    if (json['pmDeparture'] != null) entry.pmDeparture = DateTime.parse(json['pmDeparture']);
    return entry;
  }

  String get amArrivalStr => amArrival != null ? DateFormat('h:mm').format(amArrival!) : '';
  String get amDepartureStr => amDeparture != null ? DateFormat('h:mm').format(amDeparture!) : '';
  String get pmArrivalStr => pmArrival != null ? DateFormat('h:mm').format(pmArrival!) : '';
  String get pmDepartureStr => pmDeparture != null ? DateFormat('h:mm').format(pmDeparture!) : '';

  // Logic for undertime can be complex, usually based on 8-hour shift.
  // Civil service often uses 8-12, 1-5.
  int get undertimeMinutes {
    // Basic calculation if needed
    return 0; 
  }
}

class MonthlyDtr {
  final String userId;
  final String name;
  final int month;
  final int year;
  final Map<int, DtrEntry> entries;
  final String? supervisor;
  final String? amInTime;
  final String? amOutTime;
  final String? pmInTime;
  final String? pmOutTime;

  MonthlyDtr({
    required this.userId,
    required this.name,
    required this.month,
    required this.year,
    required this.entries,
    this.supervisor,
    this.amInTime,
    this.amOutTime,
    this.pmInTime,
    this.pmOutTime,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'month': month,
    'year': year,
    'entries': entries.map((key, value) => MapEntry(key.toString(), value.toJson())),
    'supervisor': supervisor,
    'amInTime': amInTime,
    'amOutTime': amOutTime,
    'pmInTime': pmInTime,
    'pmOutTime': pmOutTime,
  };

  factory MonthlyDtr.fromJson(Map<String, dynamic> json) {
    return MonthlyDtr(
      userId: json['userId'],
      name: json['name'],
      month: json['month'],
      year: json['year'],
      entries: (json['entries'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), DtrEntry.fromJson(value)),
      ),
      supervisor: json['supervisor'],
      amInTime: json['amInTime'],
      amOutTime: json['amOutTime'],
      pmInTime: json['pmInTime'],
      pmOutTime: json['pmOutTime'],
    );
  }

  String get monthName => DateFormat('MMMM').format(DateTime(year, month));

  MonthlyDtr copyWith({
    String? userId,
    String? name,
    int? month,
    int? year,
    Map<int, DtrEntry>? entries,
    String? supervisor,
    String? amInTime,
    String? amOutTime,
    String? pmInTime,
    String? pmOutTime,
  }) {
    return MonthlyDtr(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      month: month ?? this.month,
      year: year ?? this.year,
      entries: entries ?? this.entries,
      supervisor: supervisor ?? this.supervisor,
      amInTime: amInTime ?? this.amInTime,
      amOutTime: amOutTime ?? this.amOutTime,
      pmInTime: pmInTime ?? this.pmInTime,
      pmOutTime: pmOutTime ?? this.pmOutTime,
    );
  }

  factory MonthlyDtr.template() {
    final now = DateTime.now();
    return MonthlyDtr(
      userId: '0000',
      name: '(NAME)',
      month: now.month,
      year: now.year,
      entries: {},
    );
  }
}
