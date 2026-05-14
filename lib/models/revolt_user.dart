import 'revolt_file.dart';

class RevoltUser {
  final String id;
  final String username;
  final String discriminator;
  final String? displayName;
  final RevoltFile? avatar;

  RevoltUser({
    required this.id,
    required this.username,
    required this.discriminator,
    this.displayName,
    this.avatar,
  });

  factory RevoltUser.fromJson(Map<String, dynamic> json) => RevoltUser(
        id: json['_id'] as String,
        username: json['username'] as String,
        discriminator: json['discriminator'] as String? ?? '0000',
        displayName: json['display_name'] as String?,
        avatar: json['avatar'] != null
            ? RevoltFile.fromJson(json['avatar'] as Map<String, dynamic>)
            : null,
      );

  String get displayUsername => displayName ?? username;

  String avatarUrlFor(String autumnBase, String apiBase) =>
      avatar != null ? avatar!.urlFor(autumnBase) : '$apiBase/users/$id/default_avatar';
}
