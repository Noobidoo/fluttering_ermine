import 'revolt_file.dart';

import 'revolt_role.dart';

class RevoltServer {
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final int defaultPermissions;
  final List<String> channelIds;
  final RevoltFile? icon;
  final Map<String, RevoltRole>? roles;

  RevoltServer({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    this.defaultPermissions = 0,
    required this.channelIds,
    this.icon,
    this.roles,
  });

  factory RevoltServer.fromJson(Map<String, dynamic> json) {
    final rolesJson = json['roles'] as Map<String, dynamic>?;
    return RevoltServer(
      id: json['_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      ownerId: json['owner'] as String? ?? '',
      defaultPermissions:
          int.tryParse('${json['default_permissions']}') ?? 0,
      channelIds: (json['channels'] as List<dynamic>?)?.cast<String>() ?? [],
      icon: json['icon'] != null
          ? RevoltFile.fromJson(json['icon'] as Map<String, dynamic>)
          : null,
      roles: rolesJson?.map(
        (k, v) => MapEntry(k, RevoltRole.fromJson(k, v as Map<String, dynamic>)),
      ),
    );
  }

  String? iconUrlFor(String autumnBase) => icon?.urlFor(autumnBase);
}
