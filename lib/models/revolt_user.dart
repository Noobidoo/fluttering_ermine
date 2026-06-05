import 'package:flutter/material.dart';

import 'revolt_file.dart';

enum UserPresence { online, idle, focus, invisible }

UserPresence parsePresence(String? raw) {
  if (raw == null) return UserPresence.invisible;
  switch (raw.toLowerCase()) {
    case 'online':
      return UserPresence.online;
    case 'idle':
      return UserPresence.idle;
    case 'focus':
      return UserPresence.focus;
    case 'invisible':
      return UserPresence.invisible;
    default:
      return UserPresence.online;
  }
}

String presenceToString(UserPresence p) => switch (p) {
      UserPresence.online => 'Online',
      UserPresence.idle => 'Idle',
      UserPresence.focus => 'Focus',
      UserPresence.invisible => 'Invisible',
    };

Color presenceColor(UserPresence p) => switch (p) {
      UserPresence.online => const Color(0xFF2CB67D),
      UserPresence.idle => const Color(0xFFFFAA33),
      UserPresence.focus => const Color(0xFF7F5AF0),
      UserPresence.invisible => Colors.grey,
    };

class RevoltUser {
  final String id;
  final String username;
  final String discriminator;
  final String? displayName;
  final RevoltFile? avatar;
  final UserPresence presence;
  final String? statusText;
  final String? profileContent;
  final RevoltFile? banner;

  RevoltUser({
    required this.id,
    required this.username,
    required this.discriminator,
    this.displayName,
    this.avatar,
    this.presence = UserPresence.online,
    this.statusText,
    this.profileContent,
    this.banner,
  });

  RevoltUser copyWith({
    String? username,
    String? discriminator,
    String? displayName,
    RevoltFile? avatar,
    UserPresence? presence,
    String? statusText,
    String? profileContent,
    RevoltFile? banner,
  }) {
    return RevoltUser(
      id: id,
      username: username ?? this.username,
      discriminator: discriminator ?? this.discriminator,
      displayName: displayName ?? this.displayName,
      avatar: avatar ?? this.avatar,
      presence: presence ?? this.presence,
      statusText: statusText ?? this.statusText,
      profileContent: profileContent ?? this.profileContent,
      banner: banner ?? this.banner,
    );
  }

  bool get online => presence == UserPresence.online || presence == UserPresence.focus;

  factory RevoltUser.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as Map<String, dynamic>?;
    final profile = json['profile'] as Map<String, dynamic>?;
    return RevoltUser(
      id: json['_id'] as String,
      username: json['username'] as String,
      discriminator: json['discriminator'] as String? ?? '0000',
      displayName: json['display_name'] as String?,
      avatar: json['avatar'] != null
          ? RevoltFile.fromJson(json['avatar'] as Map<String, dynamic>)
          : null,
      presence: parsePresence(status?['presence'] as String?),
      statusText: status?['text'] as String?,
      profileContent: profile?['content'] as String?,
      banner: profile?['background'] != null
          ? RevoltFile.fromJson(profile!['background'] as Map<String, dynamic>)
          : null,
    );
  }

  String get displayUsername => displayName ?? username;

  String avatarUrlFor(String autumnBase, String apiBase) =>
      avatar != null ? avatar!.urlFor(autumnBase) : '$apiBase/users/$id/default_avatar';

  String? bannerUrlFor(String autumnBase) => banner?.urlFor(autumnBase);

  /// Serialise status for `PATCH /users/@me`.
  Map<String, dynamic> statusToJson() {
    final s = <String, dynamic>{};
    if (statusText != null) s['text'] = statusText;
    s['presence'] = presenceToString(presence);
    return s;
  }
}
