import 'revolt_file.dart';

class RevoltMessage {
  final String id;
  final String channelId;
  final String authorId;
  final String? content;
  final String timestamp;
  final String? edited;
  final List<RevoltFile> attachments;
  /// IDs of messages this message is replying to.
  final List<String> replies;

  RevoltMessage({
    required this.id,
    required this.channelId,
    required this.authorId,
    this.content,
    required this.timestamp,
    this.edited,
    this.attachments = const [],
    this.replies = const [],
  });

  factory RevoltMessage.fromJson(Map<String, dynamic> json) => RevoltMessage(
        id: json['_id'] as String,
        channelId: json['channel'] as String,
        authorId: json['author'] as String? ?? '',
        content: json['content'] as String?,
        timestamp: json['timestamp'] as String? ?? '',
        edited: json['edited'] as String?,
        attachments: (json['attachments'] as List<dynamic>?)
                ?.map((a) => RevoltFile.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
        replies: (json['replies'] as List<dynamic>?)
                ?.map((r) => r as String)
                .toList() ??
            [],
      );
}
