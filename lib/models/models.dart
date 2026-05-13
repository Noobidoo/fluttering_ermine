class RevoltFile {
  final String id;
  final String tag;
  final String filename;

  RevoltFile({required this.id, required this.tag, required this.filename});

  factory RevoltFile.fromJson(Map<String, dynamic> json) => RevoltFile(
        id: json['_id'] as String,
        tag: json['tag'] as String,
        filename: json['filename'] as String? ?? '',
      );

  String urlFor(String autumnBase) => '$autumnBase/$tag/$id';
}

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

class RevoltServer {
  final String id;
  final String name;
  final String? description;
  final List<String> channelIds;
  final RevoltFile? icon;

  RevoltServer({
    required this.id,
    required this.name,
    this.description,
    required this.channelIds,
    this.icon,
  });

  factory RevoltServer.fromJson(Map<String, dynamic> json) => RevoltServer(
        id: json['_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        channelIds:
            (json['channels'] as List<dynamic>?)?.cast<String>() ?? [],
        icon: json['icon'] != null
            ? RevoltFile.fromJson(json['icon'] as Map<String, dynamic>)
            : null,
      );

  String? iconUrlFor(String autumnBase) => icon?.urlFor(autumnBase);
}

enum ChannelType {
  textChannel,
  voiceChannel,
  directMessage,
  group,
  savedMessages,
  unknown,
}

class RevoltChannel {
  final String id;
  final ChannelType type;
  final String? name;
  final String? serverId;
  final List<String>? recipientIds;
  final String? description;
  final String? lastMessageId;

  RevoltChannel({
    required this.id,
    required this.type,
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
      'VoiceChannel' => ChannelType.voiceChannel,
      'DirectMessage' => ChannelType.directMessage,
      'Group' => ChannelType.group,
      'SavedMessages' => ChannelType.savedMessages,
      _ => ChannelType.unknown,
    };
    return RevoltChannel(
      id: json['_id'] as String,
      type: type,
      name: json['name'] as String?,
      serverId: json['server'] as String?,
      recipientIds:
          (json['recipients'] as List<dynamic>?)?.cast<String>(),
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

class RevoltMessage {
  final String id;
  final String channelId;
  final String authorId;
  final String? content;
  final String timestamp;
  final String? edited;
  final List<RevoltFile> attachments;

  RevoltMessage({
    required this.id,
    required this.channelId,
    required this.authorId,
    this.content,
    required this.timestamp,
    this.edited,
    this.attachments = const [],
  });

  factory RevoltMessage.fromJson(Map<String, dynamic> json) => RevoltMessage(
        id: json['_id'] as String,
        channelId: json['channel'] as String,
        authorId: json['author'] as String? ?? '',
        content: json['content'] as String?,
        timestamp: json['timestamp'] as String? ?? '',
        edited: json['edited'] as String?,
        attachments: (json['attachments'] as List<dynamic>?)
                ?.map((a) =>
                    RevoltFile.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
