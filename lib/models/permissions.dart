/// Central definition of all permission bits used in the Stoat API.
///
/// Bit positions match the reference JavaScript SDK:
///   src/permissions/definitions.ts
///
/// Usage:
/// ```dart
/// if (auth.hasPermission(serverId, Permission.kickMembers)) { ... }
/// ```
/// UI lists use [kServerPermissions] or [kChannelPermissions].
class Permission {
  // -- Generic permissions ---------------------------------------------------
  /// Manage the channel or channels on the server
  static const int manageChannel = 1; // 2^0
  /// Manage the server
  static const int manageServer = 2; // 2^1
  /// Manage permissions on servers or channels
  static const int managePermissions = 4; // 2^2
  /// Manage roles on server
  static const int manageRole = 8; // 2^3
  /// Manage server customisation (includes emoji)
  static const int manageCustomisation = 16; // 2^4

  // 5 bits reserved (bits 5-9)

  // -- Member permissions ----------------------------------------------------
  /// Kick other members below their ranking
  static const int kickMembers = 64; // 2^6
  /// Ban other members below their ranking
  static const int banMembers = 128; // 2^7
  /// Timeout other members below their ranking
  static const int timeoutMembers = 256; // 2^8
  /// Assign roles to members below their ranking
  static const int assignRoles = 512; // 2^9
  /// Change own nickname
  static const int changeNickname = 1024; // 2^10
  /// Change or remove other's nicknames below their ranking
  static const int manageNicknames = 2048; // 2^11
  /// Change own avatar
  static const int changeAvatar = 4096; // 2^12
  /// Remove other's avatars below their ranking
  static const int removeAvatars = 8192; // 2^13

  // 7 bits reserved (bits 14-19)

  // -- Channel permissions ---------------------------------------------------
  /// View a channel
  static const int viewChannel = 1048576; // 2^20
  /// Read a channel's past message history
  static const int readMessageHistory = 2097152; // 2^21
  /// Send a message in a channel
  static const int sendMessage = 4194304; // 2^22
  /// Delete messages in a channel
  static const int manageMessages = 8388608; // 2^23
  /// Manage webhook entries on a channel
  static const int manageWebhooks = 16777216; // 2^24
  /// Create invites to this channel
  static const int inviteOthers = 33554432; // 2^25
  /// Send embedded content in this channel
  static const int sendEmbeds = 67108864; // 2^26
  /// Send attachments and media in this channel
  static const int uploadFiles = 134217728; // 2^27
  /// Masquerade messages using custom nickname and avatar
  static const int masquerade = 268435456; // 2^28
  /// React to messages with emoji
  static const int react = 536870912; // 2^29

  // -- Voice permissions -----------------------------------------------------
  /// Connect to a voice channel
  static const int connect = 1073741824; // 2^30
  /// Speak in a voice call
  static const int speak = 2147483648; // 2^31
  /// Share video in a voice call
  static const int video = 4294967296; // 2^32
  /// Mute other members with lower ranking in a voice call
  static const int muteMembers = 8589934592; // 2^33
  /// Deafen other members with lower ranking in a voice call
  static const int deafenMembers = 17179869184; // 2^34
  /// Move members between voice channels
  static const int moveMembers = 34359738368; // 2^35
  /// Listen to a voice channel
  static const int listen = 68719476736; // 2^36

  // -- Mention permissions ---------------------------------------------------
  /// Mention @everyone or @online
  static const int mentionEveryone = 137438953472; // 2^37
  /// Mention a role
  static const int mentionRoles = 274877906944; // 2^38

  // -- Misc ------------------------------------------------------------------
  /// Bypass slowmode
  static const int bypassSlowmode = 549755813888; // 2^39
  // Bits 40-52: free area
  // Bits 53-64: do not use

  /// Safely grant all permissions (bits 0-51 set).
  static const int grantAllSafe = 0x000fffffffffffff;

  /// All server-level permission bits.
  static const List<int> all = [
    manageChannel,
    manageServer,
    managePermissions,
    manageRole,
    manageCustomisation,
    kickMembers,
    banMembers,
    timeoutMembers,
    assignRoles,
    changeNickname,
    manageNicknames,
    changeAvatar,
    removeAvatars,
    viewChannel,
    readMessageHistory,
    sendMessage,
    manageMessages,
    manageWebhooks,
    inviteOthers,
    sendEmbeds,
    uploadFiles,
    masquerade,
    react,
    connect,
    speak,
    video,
    muteMembers,
    deafenMembers,
    moveMembers,
    listen,
    mentionEveryone,
    mentionRoles,
    bypassSlowmode,
  ];

  /// Channel-relevant subset of permissions (used in permission overrides).
  static const List<int> channelOverrides = [
    viewChannel,
    readMessageHistory,
    sendMessage,
    manageMessages,
    manageWebhooks,
    inviteOthers,
    sendEmbeds,
    uploadFiles,
    masquerade,
    react,
    connect,
    speak,
    video,
    muteMembers,
    deafenMembers,
    moveMembers,
    listen,
    bypassSlowmode,
  ];
}

/// An OverrideField holds an allow (`a`) and deny (`d`) bitmask, used for
/// role permissions and channel default overrides in the Stoat API.
class OverrideField {
  final int allow;
  final int deny;

  const OverrideField(this.allow, this.deny);

  /// Parse from JSON — accepts `{a: int, d: int}`, plain int bitfield string,
  /// or `null`.
  factory OverrideField.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return OverrideField(
        _parseBitfield(json['a']),
        _parseBitfield(json['d']),
      );
    }
    // plain int / string — treat as allow-only
    final v = _parseBitfield(json);
    return OverrideField(v, 0);
  }

  /// Serialize to the API format `{"a": allow, "d": deny}`.
  Map<String, dynamic> toJson() => {'a': allow, 'd': deny};

  /// Apply this override to a base permission value:
  ///   result = (base | allow) & ~deny
  int applyTo(int base) => (base | allow) & ~deny;

  static int _parseBitfield(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is OverrideField && other.allow == allow && other.deny == deny;

  @override
  int get hashCode => Object.hash(allow, deny);

  @override
  String toString() => 'OverrideField(a: $allow, d: $deny)';
}

/// Describes a single permission for UI display (checkboxes, labels, etc.).
class PermissionDef {
  final String key;
  final String label;
  final String description;
  final int bit;

  const PermissionDef(this.key, this.label, this.description, this.bit);
}

/// Every server permission with display metadata.
const List<PermissionDef> kServerPermissions = [
  PermissionDef(
    'manage_channel',
    'Manage Channel',
    'Manage the channel or channels on the server',
    Permission.manageChannel,
  ),
  PermissionDef(
    'manage_server',
    'Manage Server',
    'Edit server name, description, icon',
    Permission.manageServer,
  ),
  PermissionDef(
    'manage_permissions',
    'Manage Permissions',
    'Override channel permissions',
    Permission.managePermissions,
  ),
  PermissionDef(
    'manage_role',
    'Manage Roles',
    'Create, edit, and delete roles',
    Permission.manageRole,
  ),
  PermissionDef(
    'manage_customisation',
    'Manage Customisation',
    'Manage server emoji and customisation',
    Permission.manageCustomisation,
  ),
  PermissionDef(
    'kick_members',
    'Kick Members',
    'Remove members from the server',
    Permission.kickMembers,
  ),
  PermissionDef(
    'ban_members',
    'Ban Members',
    'Ban members from the server',
    Permission.banMembers,
  ),
  PermissionDef(
    'timeout_members',
    'Timeout Members',
    'Timeout other members below their ranking',
    Permission.timeoutMembers,
  ),
  PermissionDef(
    'assign_roles',
    'Assign Roles',
    'Assign roles to members below their ranking',
    Permission.assignRoles,
  ),
  PermissionDef(
    'change_nickname',
    'Change Nickname',
    'Change own nickname',
    Permission.changeNickname,
  ),
  PermissionDef(
    'manage_nicknames',
    'Manage Nicknames',
    "Change or remove other's nicknames",
    Permission.manageNicknames,
  ),
  PermissionDef(
    'change_avatar',
    'Change Avatar',
    'Change own avatar',
    Permission.changeAvatar,
  ),
  PermissionDef(
    'remove_avatars',
    'Remove Avatars',
    "Remove other's avatars",
    Permission.removeAvatars,
  ),
  PermissionDef(
    'view_channel',
    'View Channel',
    'View a channel',
    Permission.viewChannel,
  ),
  PermissionDef(
    'read_message_history',
    'Read Message History',
    "Read a channel's past message history",
    Permission.readMessageHistory,
  ),
  PermissionDef(
    'send_message',
    'Send Messages',
    'Send messages in text channels',
    Permission.sendMessage,
  ),
  PermissionDef(
    'manage_messages',
    'Manage Messages',
    'Delete messages by other members',
    Permission.manageMessages,
  ),
  PermissionDef(
    'manage_webhooks',
    'Manage Webhooks',
    'Manage webhook entries on a channel',
    Permission.manageWebhooks,
  ),
  PermissionDef(
    'invite_others',
    'Invite Others',
    'Create invites to this channel',
    Permission.inviteOthers,
  ),
  PermissionDef(
    'send_embeds',
    'Send Embeds',
    'Send embedded content in this channel',
    Permission.sendEmbeds,
  ),
  PermissionDef(
    'upload_files',
    'Upload Files',
    'Upload images and files',
    Permission.uploadFiles,
  ),
  PermissionDef(
    'masquerade',
    'Masquerade',
    'Masquerade messages using custom nickname and avatar',
    Permission.masquerade,
  ),
  PermissionDef(
    'react',
    'React',
    'React to messages with emoji',
    Permission.react,
  ),
  PermissionDef(
    'connect',
    'Connect to Voice',
    'Join voice channels',
    Permission.connect,
  ),
  PermissionDef(
    'speak',
    'Speak',
    'Speak in a voice call',
    Permission.speak,
  ),
  PermissionDef(
    'video',
    'Video',
    'Share video in a voice call',
    Permission.video,
  ),
  PermissionDef(
    'mute_members',
    'Mute Members',
    'Mute other voice participants',
    Permission.muteMembers,
  ),
  PermissionDef(
    'deafen_members',
    'Deafen Members',
    'Deafen other voice participants',
    Permission.deafenMembers,
  ),
  PermissionDef(
    'move_members',
    'Move Members',
    'Move members between voice channels',
    Permission.moveMembers,
  ),
  PermissionDef(
    'listen',
    'Listen',
    'Listen to a voice channel',
    Permission.listen,
  ),
  PermissionDef(
    'mention_everyone',
    'Mention Everyone',
    'Mention @everyone or @online',
    Permission.mentionEveryone,
  ),
  PermissionDef(
    'mention_roles',
    'Mention Roles',
    'Mention a role',
    Permission.mentionRoles,
  ),
  PermissionDef(
    'bypass_slowmode',
    'Bypass Slowmode',
    'Bypass slowmode in channels',
    Permission.bypassSlowmode,
  ),
];

/// Channel-relevant permission definitions (for channel override UI).
const List<PermissionDef> kChannelPermissions = [
  PermissionDef(
    'view_channel',
    'View Channel',
    'View a channel',
    Permission.viewChannel,
  ),
  PermissionDef(
    'read_message_history',
    'Read Message History',
    "Read a channel's past message history",
    Permission.readMessageHistory,
  ),
  PermissionDef(
    'send_message',
    'Send Messages',
    'Send messages in text channels',
    Permission.sendMessage,
  ),
  PermissionDef(
    'manage_messages',
    'Manage Messages',
    'Delete messages by other members',
    Permission.manageMessages,
  ),
  PermissionDef(
    'manage_webhooks',
    'Manage Webhooks',
    'Manage webhook entries on a channel',
    Permission.manageWebhooks,
  ),
  PermissionDef(
    'invite_others',
    'Invite Others',
    'Create invites to this channel',
    Permission.inviteOthers,
  ),
  PermissionDef(
    'send_embeds',
    'Send Embeds',
    'Send embedded content in this channel',
    Permission.sendEmbeds,
  ),
  PermissionDef(
    'upload_files',
    'Upload Files',
    'Upload images and files',
    Permission.uploadFiles,
  ),
  PermissionDef(
    'masquerade',
    'Masquerade',
    'Masquerade messages using custom nickname and avatar',
    Permission.masquerade,
  ),
  PermissionDef(
    'react',
    'React',
    'React to messages with emoji',
    Permission.react,
  ),
  PermissionDef(
    'connect',
    'Connect to Voice',
    'Join voice channels',
    Permission.connect,
  ),
  PermissionDef(
    'speak',
    'Speak',
    'Speak in a voice call',
    Permission.speak,
  ),
  PermissionDef(
    'video',
    'Video',
    'Share video in a voice call',
    Permission.video,
  ),
  PermissionDef(
    'mute_members',
    'Mute Members',
    'Mute other voice participants',
    Permission.muteMembers,
  ),
  PermissionDef(
    'deafen_members',
    'Deafen Members',
    'Deafen other voice participants',
    Permission.deafenMembers,
  ),
  PermissionDef(
    'move_members',
    'Move Members',
    'Move members between voice channels',
    Permission.moveMembers,
  ),
  PermissionDef(
    'listen',
    'Listen',
    'Listen to a voice channel',
    Permission.listen,
  ),
  PermissionDef(
    'bypass_slowmode',
    'Bypass Slowmode',
    'Bypass slowmode in channels',
    Permission.bypassSlowmode,
  ),
];

/// Permissions allowed for a user while in timeout (matching the reference SDK).
const int allowInTimeout =
    Permission.viewChannel + Permission.readMessageHistory;

/// Default permissions if we can only view.
const int defaultPermissionViewOnly =
    Permission.viewChannel + Permission.readMessageHistory;

/// Parse a permission bitfield from a string or [OverrideField].
///
/// - If [permStr] is a plain integer string, returns its value.
/// - If [permStr] is an OverrideField JSON string like `{"a":64,"d":0}`,
///   returns the `a` (allow) value.
/// - If [permStr] is an [OverrideField], returns `.allow`.
int permValue(dynamic permStr) {
  if (permStr == null) return 0;

  // OverrideField object
  if (permStr is OverrideField) return permStr.allow;

  // Map — try OverrideField parsing
  if (permStr is Map) {
    final a = permStr['a'];
    if (a is int) return a;
    if (a is String) return int.tryParse(a) ?? 0;
    return 0;
  }

  // String
  if (permStr is String) {
    // Try parsing as JSON object first (OverrideField format)
    if (permStr.startsWith('{')) {
      try {
        // Import dart:convert is not available at top level here, so we
        // do a simple parse for the common case
        final aMatch = RegExp(r'"a"\s*:\s*(\d+)').firstMatch(permStr);
        if (aMatch != null) return int.parse(aMatch.group(1)!);
      } catch (_) {}
      return 0;
    }
    return int.tryParse(permStr) ?? 0;
  }

  return 0;
}
