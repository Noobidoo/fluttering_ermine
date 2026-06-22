import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/revolt_service.dart';

class ServerState extends ChangeNotifier with DiagnosticableTreeMixin {
  final RevoltService _service;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  /// The current user's ID, set by the UI layer after login.
  /// Used internally to fetch fresh role data on WS events.
  String? currentUserId;

  /// Called when fetchMembers receives user data that should be cached.
  void Function(List<RevoltUser> users)? onUsersFetched;

  /// Called when a member's server profile changes (ServerMemberUpdate).
  /// Passes raw data (fields that changed) and clear list so the receiver
  /// can merge with any existing profile.
  void Function(
    String userId,
    String serverId,
    Map<String, dynamic>? data,
    List<String> clear,
  )?
  onServerProfileUpdated;

  ServerState(this._service);

  List<RevoltServer> _servers = [];
  List<RevoltChannel> _allChannels = [];
  RevoltServer? _selectedServer;
  RevoltChannel? _selectedChannel;
  bool _showDMs = false;
  final Map<String, String> _channelErrors = {};
  final Set<String> _loadingChannels = {};

  // -- Unread tracking --------------------------------------------------------
  final Map<String, String> _channelUnreads = {};
  final Map<String, List<String>> _channelMentions = {};
  final Map<String, String> _latestMessageIds = {};

  // -- Roles ------------------------------------------------------------------
  final Map<String, Map<String, RevoltRole>> _rolesByServer = {};
  /// Returns roles for the selected server, or empty map.
  Map<String, RevoltRole> get selectedServerRoles {
    if (_selectedServer == null) return {};
    return _rolesByServer[_selectedServer!.id] ?? {};
  }

  /// Ensures roles are cached for the selected server.
  /// When [currentUserId] is provided, attempts to fetch fresh role data
  /// from the member endpoint as a fallback.
  Future<void> fetchRoles({
    bool force = false,
    String? currentUserId,
  }) async {
    final server = _selectedServer;
    if (server == null) return;
    if (!force && _rolesByServer.containsKey(server.id)) return;
    // Seed from the server object's embedded roles.
    if (server.roles != null) {
      _rolesByServer[server.id] = Map<String, RevoltRole>.from(server.roles!);
      notifyListeners();
    }
    // If we have a userId, try to get fresh roles from the member endpoint.
    if (currentUserId != null) {
      try {
        final (_, _, _, _, roleMap) =
            await _service.fetchMemberWithRoles(server.id, currentUserId);
        if (roleMap.isNotEmpty) {
          _rolesByServer[server.id] = roleMap;
        }
      } catch (e) {
        debugPrint('[fetchRoles] member endpoint failed: $e');
      }
    }
    notifyListeners();
  }

  /// Returns the highest-priority role colour for a user in the given server,
  /// or null if no colour role applies.
  int? roleColourFor(String serverId, List<String> userRoles) {
    final roles = _rolesByServer[serverId];
    if (roles == null || roles.isEmpty) return null;
    // Sort by rank descending, pick first one with a colour
    final sorted = userRoles
        .map((rId) => roles[rId])
        .where((r) => r != null && r.colour != null)
        .toList()
      ..sort((a, b) => b!.rank.compareTo(a!.rank));
    return sorted.isNotEmpty ? sorted.first!.colour : null;
  }

  /// Computes the effective permission bitmask for a user in the given server.
  ///
  /// Algorithm matches the Stoat JS SDK reference:
  ///   1. Start with server's [defaultPermissions].
  ///   2. For each role (sorted ascending by rank), apply:
  ///        perm = (perm | role.permissions.allow) & ~role.permissions.deny
  ///
  /// Returns 0 if the server has no roles or the user has no role assignments.
  int userEffectivePermissions(String serverId, List<String> userRoleIds) {
    final roles = _rolesByServer[serverId];
    final server = servers.firstWhere(
      (s) => s.id == serverId,
      orElse: () => servers.first,
    );

    int perms = server.id == serverId ? server.defaultPermissions : 0;
    if (roles == null) return perms;

    // Sort roles ascending by rank so higher-rank roles override lower ones.
    final sortedRoles = userRoleIds
        .map((rId) => roles[rId])
        .where((r) => r != null)
        .toList()
      ..sort((a, b) => a!.rank.compareTo(b!.rank));

    for (final role in sortedRoles) {
      if (role!.permissions != null) {
        perms = role.permissions!.applyTo(perms);
      }
    }
    return perms;
  }

  /// Creates a role via the service and updates local cache.
  Future<void> createRole(String name) async {
    final server = _selectedServer;
    if (server == null) return;
    final role = await _service.createRole(server.id, name);
    _rolesByServer.putIfAbsent(server.id, () => {});
    _rolesByServer[server.id]![role.id] = role;
    notifyListeners();
  }

  /// Updates a role via the service and updates local cache.
  Future<void> updateRole(
    String roleId, {
    String? name,
    int? colour,
    int? rank,
    bool? hoist,
    dynamic permissions,
  }) async {
    final server = _selectedServer;
    if (server == null) return;
    final updated = await _service.updateRole(
      server.id,
      roleId,
      name: name,
      colour: colour,
      rank: rank,
      hoist: hoist,
      permissions: permissions,
    );
    _rolesByServer[server.id]?[roleId] = updated;
    notifyListeners();
  }

  /// Deletes a role via the service and updates local cache.
  Future<void> deleteRole(String roleId) async {
    final server = _selectedServer;
    if (server == null) return;
    await _service.deleteRole(server.id, roleId);
    _rolesByServer[server.id]?.remove(roleId);
    notifyListeners();
  }

  /// Assigns a role to a member.
  Future<void> assignRoleToMember(String userId, String roleId) async {
    final server = _selectedServer;
    if (server == null) return;
    await _service.assignRole(server.id, userId, roleId);
  }

  /// Removes a role from a member.
  Future<void> removeRoleFromMember(String userId, String roleId) async {
    final server = _selectedServer;
    if (server == null) return;
    await _service.removeRole(server.id, userId, roleId);
  }

  // -- Member actions --------------------------------------------------------

  /// Kicks a member from the selected server.
  Future<void> kickMember(String userId) async {
    final server = _selectedServer;
    if (server == null) return;
    await _service.kickMember(server.id, userId);
    _memberIdsByServer[server.id]?.remove(userId);
    notifyListeners();
  }

  /// Bans a member from the selected server.
  Future<void> banMember(String userId, {String? reason}) async {
    final server = _selectedServer;
    if (server == null) return;
    await _service.banMember(server.id, userId, reason: reason);
    _memberIdsByServer[server.id]?.remove(userId);
    notifyListeners();
  }

  /// Unbans a user from the selected server.
  Future<void> unbanMember(String userId) async {
    final server = _selectedServer;
    if (server == null) return;
    await _service.unbanMember(server.id, userId);
    notifyListeners();
  }

  /// Fetches all bans for the selected server.
  Future<List<RevoltBan>> fetchBans() async {
    final server = _selectedServer;
    if (server == null) return [];
    return _service.fetchBans(server.id);
  }

  // -- Members ----------------------------------------------------------------
  final Map<String, List<String>> _memberIdsByServer = {};
  bool _loadingMembers = false;

  // -- Getters ---------------------------------------------------------------

  List<RevoltServer> get servers => _servers;
  RevoltServer? get selectedServer => _selectedServer;
  RevoltChannel? get selectedChannel => _selectedChannel;
  bool get showDMs => _showDMs;

  List<RevoltChannel> get selectedServerChannels {
    if (_selectedServer == null) return [];
    return _allChannels
        .where((c) => c.serverId == _selectedServer!.id)
        .toList();
  }

  List<RevoltChannel> get dmChannels => _allChannels
      .where(
        (c) =>
            c.type == ChannelType.directMessage ||
            c.type == ChannelType.group ||
            c.type == ChannelType.savedMessages,
      )
      .toList();

  // -- Server CRUD helpers ---------------------------------------------------

  /// Creates a new server and adds it to the list.
  Future<RevoltServer> createServer(String name, {String? description}) async {
    final server = await _service.createServer(name, description: description);
    _servers.add(server);
    notifyListeners();
    if (!_showDMs) {
      selectServer(server);
    }
    return server;
  }

  /// Updates the selected server.
  Future<void> updateSelectedServer({
    String? name,
    String? description,
    String? icon,
    List<String>? remove,
  }) async {
    final server = _selectedServer;
    if (server == null) return;
    await _service.updateServer(
      server.id,
      name: name,
      description: description,
      icon: icon,
      remove: remove,
    );
    // Refresh server data
    final idx = _servers.indexWhere((s) => s.id == server.id);
    if (idx >= 0) {
      _servers[idx] = RevoltServer(
        id: server.id,
        name: name ?? server.name,
        description: description != null ? description : server.description,
        ownerId: server.ownerId,
        defaultPermissions: server.defaultPermissions,
        channelIds: server.channelIds,
        icon: icon != null
            ? RevoltFile(id: icon, tag: 'icons', filename: '')
            : (remove?.contains('Icon') == true ? null : server.icon),
      );
    }
    notifyListeners();
  }

  /// Deletes a server and removes it from the list.
  Future<void> deleteSelectedServer() async {
    final server = _selectedServer;
    if (server == null) return;
    await _service.deleteServer(server.id);
    _servers.removeWhere((s) => s.id == server.id);
    _rolesByServer.remove(server.id);
    _memberIdsByServer.remove(server.id);
    _allChannels.removeWhere((c) => c.serverId == server.id);
    _selectedServer = _servers.isNotEmpty ? _servers.first : null;
    _selectedChannel = null;
    notifyListeners();
  }

  // -- Channel CRUD helpers --------------------------------------------------

  /// Creates a new channel in the selected server.
  Future<RevoltChannel> createChannel(
    String name, {
    String? description,
    bool isVoice = false,
  }) async {
    final server = _selectedServer;
    if (server == null) throw Exception('No server selected');
    final channel = await _service.createChannel(
      server.id,
      name,
      description: description,
      isVoice: isVoice,
    );
    _allChannels.add(channel);
    notifyListeners();
    return channel;
  }

  /// Updates a channel's properties.
  Future<void> updateChannel(String channelId, {
    String? name,
    String? description,
    String? icon,
    bool? isVoice,
    String? defaultPermissions,
    String? rolePermissions,
    String? userPermissions,
    List<String>? remove,
  }) async {
    await _service.updateChannel(
      channelId,
      name: name,
      description: description,
      icon: icon,
      isVoice: isVoice,
      defaultPermissions: defaultPermissions,
      rolePermissions: rolePermissions,
      userPermissions: userPermissions,
      remove: remove,
    );
    // Refresh locally
    final idx = _allChannels.indexWhere((c) => c.id == channelId);
    if (idx >= 0) {
      final old = _allChannels[idx];
      _allChannels[idx] = RevoltChannel(
        id: old.id,
        type: old.type,
        isVoice: isVoice ?? old.isVoice,
        name: name ?? old.name,
        serverId: old.serverId,
        recipientIds: old.recipientIds,
        description: description ?? old.description,
        lastMessageId: old.lastMessageId,
      );
    }
    notifyListeners();
  }

  /// Deletes a channel and removes it from the list.
  Future<void> deleteChannel(String channelId) async {
    await _service.deleteChannel(channelId);
    _allChannels.removeWhere((c) => c.id == channelId);
    if (_selectedChannel?.id == channelId) {
      _selectedChannel = null;
    }
    notifyListeners();
  }

  // -- WebSocket -------------------------------------------------------------

  void subscribeToEvents() {
    _wsSub?.cancel();
    _wsSub = _service.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'Ready':
        _onReady(event);
        break;
      case 'Message':
        _onMessage(event);
        break;
      case 'ChannelAck':
        _onChannelAck(event);
        break;
      case 'ServerMemberUpdate':
        _onServerMemberUpdate(event);
        break;
      case 'ServerRoleUpdate':
        _onServerRoleUpdate(event);
        break;
      case 'ChannelDelete':
        _onChannelDelete(event);
        break;
      default:
        break;
    }
  }

  void _onServerRoleUpdate(Map<String, dynamic> event) {
    if (currentUserId != null && _selectedServer != null) {
      fetchRoles(currentUserId: currentUserId, force: true);
    }
  }

  void _onChannelDelete(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    if (channelId == null) return;
    _allChannels.removeWhere((c) => c.id == channelId);
    if (_selectedChannel?.id == channelId) {
      _selectedChannel = null;
    }
    notifyListeners();
  }

  void _onReady(Map<String, dynamic> event) {
    final servers = (event['servers'] as List<dynamic>?) ?? [];
    _servers = servers
        .map((s) => RevoltServer.fromJson(s as Map<String, dynamic>))
        .toList();

    // Cache roles from server objects.
    for (final srv in _servers) {
      if (srv.roles != null && srv.roles!.isNotEmpty) {
        _rolesByServer[srv.id] = Map<String, RevoltRole>.from(srv.roles!);
      }
    }

    final channels = (event['channels'] as List<dynamic>?) ?? [];
    _allChannels = channels
        .map((c) => RevoltChannel.fromJson(c as Map<String, dynamic>))
        .toList();

    final unreads = (event['channel_unreads'] as List<dynamic>?) ?? [];
    _channelUnreads.clear();
    _channelMentions.clear();
    for (final u in unreads) {
      final data = u as Map<String, dynamic>;
      final channelId = data['_id'] as String;
      final lastId = data['last_id'] as String?;
      if (lastId != null) _channelUnreads[channelId] = lastId;
      final mentions =
          (data['mentions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [];
      if (mentions.isNotEmpty) _channelMentions[channelId] = mentions;
    }

    if (_servers.isNotEmpty && _selectedServer == null && !_showDMs) {
      _selectedServer = _servers.first;
      _memberIdsByServer.clear();
      fetchMembers(force: true);
    }
    notifyListeners();
  }

  void _onMessage(Map<String, dynamic> event) {
    final channelId = event['channel'] as String?;
    final messageId = event['_id'] as String?;
    if (channelId != null && messageId != null) {
      _latestMessageIds[channelId] = messageId;
      notifyListeners();
    }
  }

  void _onChannelAck(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    final messageId = event['message_id'] as String?;
    if (channelId != null && messageId != null) {
      _channelUnreads[channelId] = messageId;
      _channelMentions.remove(channelId);
      notifyListeners();
    }
  }

  void selectServer(RevoltServer server, {String? userId}) {
    _selectedServer = server;
    _selectedChannel = null;
    _showDMs = false;
    _fetchServerChannels(server);
    fetchMembers(force: true);
    fetchRoles(currentUserId: userId ?? currentUserId);
    notifyListeners();
  }

  void selectDMs() {
    _selectedServer = null;
    _selectedChannel = null;
    _showDMs = true;
    notifyListeners();
  }

  void selectChannel(RevoltChannel channel) {
    _selectedChannel = channel;
    notifyListeners();
  }

  void selectVoiceChannel(RevoltChannel channel) {
    _selectedChannel = channel;
    notifyListeners();
  }

  // -- Members ----------------------------------------------------------------

  /// Returns the list of user IDs for the selected server's members, or null.
  List<String>? get currentServerMemberIds {
    if (_selectedServer == null) return null;
    return _memberIdsByServer[_selectedServer!.id];
  }

  bool get isLoadingMembers => _loadingMembers;

  Future<void> fetchMembers({bool force = false}) async {
    final server = _selectedServer;
    if (server == null) return;
    if (!force && _memberIdsByServer.containsKey(server.id)) return;
    _loadingMembers = true;
    notifyListeners();
    try {
      final (memberProfiles, users) = await _service.fetchServerMembers(
        server.id,
      );
      _memberIdsByServer[server.id] = memberProfiles
          .map((m) => m.userId)
          .toList();

      // Attach server profiles to each user
      final profileByUserId = {for (final m in memberProfiles) m.userId: m};
      final updatedUsers = users.map((u) {
        final p = profileByUserId[u.id];
        if (p == null) return u;
        return u.copyWithServerProfile(
          server.id,
          ServerProfile(nickname: p.nickname, roles: p.roles, avatar: p.avatar),
        );
      }).toList();

      onUsersFetched?.call(updatedUsers);
    } catch (e) {
      debugPrint('[fetchMembers] ${server.id} failed: $e');
    } finally {
      _loadingMembers = false;
      notifyListeners();
    }
  }

  void _onServerMemberUpdate(Map<String, dynamic> event) {
    debugPrint(
      '[ServerMemberUpdate] raw: ${String.fromCharCodes(utf8.encode(event.toString()))}',
    );
    final idMap = event['id'];
    if (idMap is! Map) return;
    final serverId = idMap['server'] as String?;
    final userId = idMap['user'] as String?;
    if (serverId == null || userId == null) return;
    final data = event['data'] as Map<String, dynamic>?;
    final clear = (event['clear'] as List<dynamic>?)?.cast<String>() ?? [];

    // Keep the member list consistent
    if (!_memberIdsByServer.containsKey(serverId)) return;
    if (!_memberIdsByServer[serverId]!.contains(userId)) return;

    onServerProfileUpdated?.call(userId, serverId, data, clear);
    notifyListeners();
  }

  /// Returns whether [userId] is a member of [serverId].
  bool isMember(String serverId, String userId) =>
      _memberIdsByServer[serverId]?.contains(userId) ?? false;

  // -- Unread queries ---------------------------------------------------------

  /// Whether [channelId] has messages newer than the user's last read position.
  bool isChannelUnread(String channelId) {
    final unread = _channelUnreads[channelId];
    final latest = _latestMessageIds[channelId];
    if (latest != null) return unread != latest;
    if (unread == null) return false;
    final channel = _allChannels.cast<RevoltChannel?>().firstWhere(
      (c) => c?.id == channelId,
      orElse: () => null,
    );
    if (channel == null || channel.lastMessageId == null) return false;
    return unread != channel.lastMessageId;
  }

  /// Number of unread @mentions in [channelId].
  int mentionCountFor(String channelId) =>
      _channelMentions[channelId]?.length ?? 0;

  /// Number of channels in [serverId] that have unread messages.
  int serverUnreadCount(String serverId) {
    int count = 0;
    for (final channel in _allChannels) {
      if (channel.serverId == serverId && isChannelUnread(channel.id)) {
        count++;
      }
    }
    return count;
  }

  /// Latest known message ID for [channelId] (from WS), or null.
  String? latestMessageId(String channelId) => _latestMessageIds[channelId];

  /// Mark [channelId] as read up to [messageId].
  void markChannelRead(String channelId, String messageId) {
    _channelUnreads[channelId] = messageId;
    _channelMentions.remove(channelId);
    notifyListeners();
  }

  // -- Invites ---------------------------------------------------------------

  Future<String> createInvite(String channelId) =>
      _service.createInvite(channelId);

  Future<List<RevoltInvite>> fetchInvites(String serverId) =>
      _service.fetchInvites(serverId);

  Future<void> joinInvite(String code) => _service.joinInvite(code);

  Future<void> _fetchServerChannels(RevoltServer server) async {
    notifyListeners();
    try {
      final channels = await _service.fetchChannels(server.channelIds);
      _allChannels = [
        ..._allChannels.where((c) => c.serverId != server.id),
        ...channels,
      ];
    } catch (e) {
      debugPrint('[fetchServerChannels] ${server.id} failed: $e');
      _channelErrors[server.id] = e.toString().replaceAll('Exception: ', '');
    } finally {
      _loadingChannels.remove(server.id);
      notifyListeners();
    }
  }

  // -- Lifecycle -------------------------------------------------------------

  void clear() {
    _wsSub?.cancel();
    _wsSub = null;
    _servers = [];
    _allChannels = [];
    _selectedServer = null;
    _selectedChannel = null;
    _showDMs = false;
    currentUserId = null;
    _channelErrors.clear();
    _loadingChannels.clear();
    _channelUnreads.clear();
    _channelMentions.clear();
    _latestMessageIds.clear();
    _memberIdsByServer.clear();
    _loadingMembers = false;
    _rolesByServer.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}
