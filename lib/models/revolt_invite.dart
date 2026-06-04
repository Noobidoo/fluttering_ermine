class RevoltInvite {
  final String id;
  final String serverId;
  final String creatorId;
  final String channelId;

  const RevoltInvite({
    required this.id,
    required this.serverId,
    required this.creatorId,
    required this.channelId,
  });

  factory RevoltInvite.fromJson(Map<String, dynamic> json) => RevoltInvite(
        id: json['_id'] as String,
        serverId: json['server'] as String,
        creatorId: json['creator'] as String,
        channelId: json['channel'] as String,
      );
}
