import 'package:flutter/material.dart';

import 'revolt_file.dart';
import 'server_profile.dart';

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
      return UserPresence.invisible;
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
  final bool privileged;
  final Map<String, ServerProfile> serverProfiles;

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
    this.privileged = false,
    this.serverProfiles = const {},
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
    bool? privileged,
    Map<String, ServerProfile>? serverProfiles,
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
      privileged: privileged ?? this.privileged,
      serverProfiles: serverProfiles ?? this.serverProfiles,
    );
  }

  /// Returns a copy with [profile] stored under [serverId].
  RevoltUser copyWithServerProfile(String serverId, ServerProfile profile) {
    final updated = Map<String, ServerProfile>.from(serverProfiles);
    updated[serverId] = profile;
    return copyWith(serverProfiles: updated);
  }

  /// Returns the server-specific nickname, or null if none is set.
  String? serverNickname(String serverId) => serverProfiles[serverId]?.nickname;

  /// Returns the server-specific avatar, falling back to the global avatar.
  RevoltFile? serverAvatar(String? serverId) {
    if (serverId == null) return avatar;
    return serverProfiles[serverId]?.avatar ?? avatar;
  }

  /// Single point of truth for display name resolution.
  /// Prefers server nickname, then displayName, then username.
  /// Pass `null` for [serverId] to skip server-specific overrides.
  String resolveDisplayName(String? serverId) {
    if (serverId != null) {
      final n = serverNickname(serverId);
      if (n != null && n.isNotEmpty) return n;
    }
    return displayUsername;
  }

  /// Single point of truth for avatar URL resolution.
  /// Prefers server avatar, then global avatar, then default avatar.
  /// Pass `null` for [serverId] to skip server-specific overrides.
  String resolveAvatarUrl(String? serverId, String autumnBase, String apiBase) {
    final a = serverAvatar(serverId);
    return a != null ? a.urlFor(autumnBase) : '$apiBase/users/$id/default_avatar';
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
      privileged: json['privileged'] as bool? ?? false,
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
