import 'revolt_file.dart';

class ServerProfile {
  final String? nickname;
  final List<String> roles;
  final RevoltFile? avatar;

  ServerProfile({
    this.nickname,
    this.roles = const [],
    this.avatar,
  });

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    return ServerProfile(
      nickname: json['nickname'] as String?,
      roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? [],
      avatar: json['avatar'] != null
          ? RevoltFile.fromJson(json['avatar'] as Map<String, dynamic>)
          : null,
    );
  }

  ServerProfile copyWith({
    String? nickname,
    List<String>? roles,
    RevoltFile? avatar,
    bool clearNickname = false,
    bool clearAvatar = false,
    bool clearRoles = false,
  }) {
    return ServerProfile(
      nickname: clearNickname ? null : (nickname ?? this.nickname),
      roles: clearRoles ? [] : (roles ?? this.roles),
      avatar: clearAvatar ? null : (avatar ?? this.avatar),
    );
  }
}
