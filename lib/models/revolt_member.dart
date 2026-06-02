class RevoltMember {
  final String serverId;
  final String userId;
  final String? nickname;
  final List<String> roles;

  RevoltMember({
    required this.serverId,
    required this.userId,
    this.nickname,
    this.roles = const [],
  });

  factory RevoltMember.fromJson(Map<String, dynamic> json) {
    final id = json['_id'] as Map<String, dynamic>;
    return RevoltMember(
      serverId: id['server'] as String,
      userId: id['user'] as String,
      nickname: json['nickname'] as String?,
      roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}
