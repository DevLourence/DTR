class BiometricRecord {
  final String userId;
  final String uName;
  final DateTime timestamp;
  final String? status; // In, Out, etc.

  BiometricRecord({
    required this.userId,
    this.uName = '',
    required this.timestamp,
    this.status,
  });

  @override
  String toString() => '$userId - $timestamp - $status';
}
