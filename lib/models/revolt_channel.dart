import 'permissions.dart';

enum ChannelType { textChannel, voiceChannel, directMessage, group, savedMessages, unknown }

class RevoltChannel {
  final String id;
  final ChannelType type;
  final bool isVoice;
  final String? name;
  final String? serverId;
  final String? ownerId;
  final List<String>? recipientIds;
  final String? description;
  final String? lastMessageId;
  final OverrideField? defaultPermissions;
  final Map<String, OverrideField>? rolePermissions;

  RevoltChannel({
    required this.id,
    required this.type,
    this.isVoice = false,
    this.name,
    this.serverId,
    this.ownerId,
    this.recipientIds,
    this.description,
    this.lastMessageId,
    this.defaultPermissions,
    this.rolePermissions,
  });

  factory RevoltChannel.fromJson(Map<String, dynamic> json) {
    final typeStr = json['channel_type'] as String? ?? '';
    final type = switch (typeStr) {
      'TextChannel' => ChannelType.textChannel,
      'VoiceChannel' => ChannelType.voiceChannel,
      'DirectMessage' => ChannelType.directMessage,
      'Group' => ChannelType.group,
      'SavedMessages' => ChannelType.savedMessages,
      _ => ChannelType.unknown,
    };
    Map<String, OverrideField>? parseRolePerms(Map<String, dynamic>? map) {
      if (map == null) return null;
      return map.map((k, v) => MapEntry(k, OverrideField.fromJson(v)));
    }

    return RevoltChannel(
      id: json['_id'] as String,
      type: type,
      isVoice: typeStr == 'VoiceChannel' || json['voice'] != null,
      name: json['name'] as String?,
      serverId: json['server'] as String?,
      ownerId: json['owner'] as String?,
      recipientIds: (json['recipients'] as List<dynamic>?)?.cast<String>(),
      description: json['description'] as String?,
      lastMessageId: json['last_message_id'] as String?,
      defaultPermissions: json['default_permissions'] != null
          ? OverrideField.fromJson(json['default_permissions'])
          : null,
      rolePermissions: parseRolePerms(
          json['role_permissions'] as Map<String, dynamic>?),
    );
  }

  bool get isTextBased =>
      type == ChannelType.textChannel ||
      type == ChannelType.voiceChannel ||
      type == ChannelType.directMessage ||
      type == ChannelType.group ||
      type == ChannelType.savedMessages;
}
