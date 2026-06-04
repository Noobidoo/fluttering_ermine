import 'revolt_file.dart';

class RevoltMember {
  final String serverId;
  final String userId;
  final String? nickname;
  final List<String> roles;
  final RevoltFile? avatar;

  RevoltMember({
    required this.serverId,
    required this.userId,
    this.nickname,
    this.roles = const [],
    this.avatar,
  });

  factory RevoltMember.fromJson(Map<String, dynamic> json) {
    final id = json['_id'] as Map<String, dynamic>;
    return RevoltMember(
      serverId: id['server'] as String,
      userId: id['user'] as String,
      nickname: json['nickname'] as String?,
      roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? [],
      avatar: json['avatar'] != null
          ? RevoltFile.fromJson(json['avatar'] as Map<String, dynamic>)
          : null,
    );
  }
}
