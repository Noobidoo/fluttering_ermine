class RevoltBan {
  final String id;
  final String userId;
  final String? reason;

  RevoltBan({
    required this.id,
    required this.userId,
    this.reason,
  });

  factory RevoltBan.fromJson(Map<String, dynamic> json) {
    final idObj = json['_id'] as Map<String, dynamic>?;
    final userId = idObj?['user'] as String? ?? json['user'] as String? ?? '';
    return RevoltBan(
      id: json['_id'] is String ? json['_id'] as String : (idObj?['server'] as String? ?? ''),
      userId: userId,
      reason: json['reason'] as String?,
    );
  }
}
