enum ChannelType { textChannel, directMessage, group, savedMessages, unknown }

class RevoltChannel {
  final String id;
  final ChannelType type;
  final bool isVoice;
  final String? name;
  final String? serverId;
  final List<String>? recipientIds;
  final String? description;
  final String? lastMessageId;

  RevoltChannel({
    required this.id,
    required this.type,
    this.isVoice = false,
    this.name,
    this.serverId,
    this.recipientIds,
    this.description,
    this.lastMessageId,
  });

  factory RevoltChannel.fromJson(Map<String, dynamic> json) {
    final typeStr = json['channel_type'] as String? ?? '';
    final type = switch (typeStr) {
      'TextChannel' => ChannelType.textChannel,
      'DirectMessage' => ChannelType.directMessage,
      'Group' => ChannelType.group,
      'SavedMessages' => ChannelType.savedMessages,
      _ => ChannelType.unknown,
    };
    return RevoltChannel(
      id: json['_id'] as String,
      type: type,
      isVoice: json['voice'] != null,
      name: json['name'] as String?,
      serverId: json['server'] as String?,
      recipientIds: (json['recipients'] as List<dynamic>?)?.cast<String>(),
      description: json['description'] as String?,
      lastMessageId: json['last_message_id'] as String?,
    );
  }

  bool get isTextBased =>
      type == ChannelType.textChannel ||
      type == ChannelType.directMessage ||
      type == ChannelType.group ||
      type == ChannelType.savedMessages;
}
