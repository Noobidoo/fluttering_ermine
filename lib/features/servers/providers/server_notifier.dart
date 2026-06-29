import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/models.dart';
import '../../../services/revolt_service.dart';
import '../../core/providers/service_providers.dart';
import 'current_user_id_provider.dart';

// ---------------------------------------------------------------------------
// Pure data state (immutable)
// ---------------------------------------------------------------------------

@immutable
class ServerStateData {
  final List<RevoltServer> servers;
  final List<RevoltChannel> allChannels;
  final RevoltServer? selectedServer;
  final RevoltChannel? selectedChannel;
  final bool showDMs;
  final Map<String, String> channelErrors;
  final Set<String> loadingChannels;
  final Map<String, String> channelUnreads;
  final Map<String, List<String>> channelMentions;
  final Map<String, String> latestMessageIds;
  final Map<String, Map<String, RevoltRole>> rolesByServer;
  final Map<String, List<String>> memberIdsByServer;
  final bool loadingMembers;

  const ServerStateData({
    this.servers = const [],
    this.allChannels = const [],
    this.selectedServer,
    this.selectedChannel,
    this.showDMs = false,
    this.channelErrors = const {},
    this.loadingChannels = const {},
    this.channelUnreads = const {},
    this.channelMentions = const {},
    this.latestMessageIds = const {},
    this.rolesByServer = const {},
    this.memberIdsByServer = const {},
    this.loadingMembers = false,
  });

  // -- Derived getters -------------------------------------------------------

  List<RevoltChannel> get selectedServerChannels {
    if (selectedServer == null) return [];
    return allChannels.where((c) => c.serverId == selectedServer!.id).toList();
  }

  List<RevoltChannel> get dmChannels => allChannels
      .where(
        (c) =>
            c.type == ChannelType.directMessage ||
            c.type == ChannelType.group ||
            c.type == ChannelType.savedMessages,
      )
      .toList();

  Map<String, RevoltRole> get selectedServerRoles {
    if (selectedServer == null) return {};
    return rolesByServer[selectedServer!.id] ?? {};
  }

  List<String>? get currentServerMemberIds {
    if (selectedServer == null) return null;
    return memberIdsByServer[selectedServer!.id];
  }

  // -- Query methods ---------------------------------------------------------

  bool isChannelUnread(String channelId) {
    final unread = channelUnreads[channelId];
    final latest = latestMessageIds[channelId];
    if (latest != null) return unread != latest;
    if (unread == null) return false;
    final channel = allChannels.cast<RevoltChannel?>().firstWhere(
      (c) => c?.id == channelId,
      orElse: () => null,
    );
    if (channel == null || channel.lastMessageId == null) return false;
    return unread != channel.lastMessageId;
  }

  int mentionCountFor(String channelId) => channelMentions[channelId]?.length ?? 0;

  int serverUnreadCount(String serverId) {
    int count = 0;
    for (final channel in allChannels) {
      if (channel.serverId == serverId && isChannelUnread(channel.id)) {
        count++;
      }
    }
    return count;
  }

  String? latestMessageId(String channelId) => latestMessageIds[channelId];

  bool isMember(String serverId, String userId) =>
      memberIdsByServer[serverId]?.contains(userId) ?? false;

  int? roleColourFor(String serverId, List<String> userRoles) {
    final roles = rolesByServer[serverId];
    if (roles == null || roles.isEmpty) return null;
    final sorted =
        userRoles.map((rId) => roles[rId]).where((r) => r != null && r.colour != null).toList()
          ..sort((a, b) => b!.rank.compareTo(a!.rank));
    return sorted.isNotEmpty ? sorted.first!.colour : null;
  }

  int userEffectivePermissions(String serverId, List<String> userRoleIds) {
    final roles = rolesByServer[serverId];
    final server = servers.firstWhere((s) => s.id == serverId, orElse: () => servers.first);

    int perms = server.id == serverId ? server.defaultPermissions : 0;
    if (roles == null) return perms;

    final sortedRoles = userRoleIds.map((rId) => roles[rId]).where((r) => r != null).toList()
      ..sort((a, b) => a!.rank.compareTo(b!.rank));

    for (final role in sortedRoles) {
      if (role!.permissions != null) {
        perms = role.permissions!.applyTo(perms);
      }
    }
    return perms;
  }

  static const _omit = Object();

  // -- copyWith --------------------------------------------------------------

  ServerStateData copyWith({
    List<RevoltServer>? servers,
    List<RevoltChannel>? allChannels,
    Object? selectedServer = _omit,
    Object? selectedChannel = _omit,
    bool? showDMs,
    Map<String, String>? channelErrors,
    Set<String>? loadingChannels,
    Map<String, String>? channelUnreads,
    Map<String, List<String>>? channelMentions,
    Map<String, String>? latestMessageIds,
    Map<String, Map<String, RevoltRole>>? rolesByServer,
    Map<String, List<String>>? memberIdsByServer,
    bool? loadingMembers,
  }) => ServerStateData(
    servers: servers ?? this.servers,
    allChannels: allChannels ?? this.allChannels,
    selectedServer: selectedServer == _omit ? this.selectedServer : selectedServer as RevoltServer?,
    selectedChannel: selectedChannel == _omit ? this.selectedChannel : selectedChannel as RevoltChannel?,
    showDMs: showDMs ?? this.showDMs,
    channelErrors: channelErrors ?? this.channelErrors,
    loadingChannels: loadingChannels ?? this.loadingChannels,
    channelUnreads: channelUnreads ?? this.channelUnreads,
    channelMentions: channelMentions ?? this.channelMentions,
    latestMessageIds: latestMessageIds ?? this.latestMessageIds,
    rolesByServer: rolesByServer ?? this.rolesByServer,
    memberIdsByServer: memberIdsByServer ?? this.memberIdsByServer,
    loadingMembers: loadingMembers ?? this.loadingMembers,
  );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ServerNotifier extends AsyncNotifier<ServerStateData> {
  late RevoltService _service;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  late void Function(List<RevoltUser> users) _onUsersFetched;
  late void Function(String userId, String serverId, Map<String, dynamic>? data, List<String> clear)
      _onServerProfileUpdated;

  void setUsersFetchedCallback(void Function(List<RevoltUser> users) callback) {
    _onUsersFetched = callback;
  }

  void setServerProfileUpdatedCallback(
    void Function(String userId, String serverId, Map<String, dynamic>? data, List<String> clear)
        callback,
  ) {
    _onServerProfileUpdated = callback;
  }

  // -- build() ----------------------------------------------------------------

  @override
  Future<ServerStateData> build() async {
    _service = ref.watch(revoltServiceProvider);

    // Rule 3: Pull, Don't Push — watch currentUserId reactively
    ref.watch(currentUserIdProvider);

    _subscribeToEvents();

    ref.onDispose(() {
      _wsSub?.cancel();
    });

    return ServerStateData();
  }

  // -- WebSocket --------------------------------------------------------------

  void _subscribeToEvents() {
    _wsSub?.cancel();
    _wsSub = _service.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> event) {
    final existing = state.value;
    if (existing == null) return;

    final currentUserId = ref.read(currentUserIdProvider);
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
        _onServerRoleUpdate(event, currentUserId);
        break;
      case 'ChannelDelete':
        _onChannelDelete(event);
        break;
      default:
        break;
    }
  }

  void _onReady(Map<String, dynamic> event) {
    final servers = (event['servers'] as List<dynamic>?) ?? [];
    final parsedServers = servers
        .map((s) => RevoltServer.fromJson(s as Map<String, dynamic>))
        .toList();

    final rolesByServer = <String, Map<String, RevoltRole>>{};
    for (final srv in parsedServers) {
      if (srv.roles != null && srv.roles!.isNotEmpty) {
        rolesByServer[srv.id] = Map<String, RevoltRole>.from(srv.roles!);
      }
    }

    final channels = (event['channels'] as List<dynamic>?) ?? [];
    final parsedChannels = channels
        .map((c) => RevoltChannel.fromJson(c as Map<String, dynamic>))
        .toList();

    final unreads = (event['channel_unreads'] as List<dynamic>?) ?? [];
    final channelUnreads = <String, String>{};
    final channelMentions = <String, List<String>>{};
    for (final u in unreads) {
      final data = u as Map<String, dynamic>;
      final channelId = data['_id'] as String;
      final lastId = data['last_id'] as String?;
      if (lastId != null) channelUnreads[channelId] = lastId;
      final mentions = (data['mentions'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [];
      if (mentions.isNotEmpty) channelMentions[channelId] = mentions;
    }

    final existing = state.value!;
    RevoltServer? selectedServer = existing.selectedServer;
    if (parsedServers.isNotEmpty && selectedServer == null && !existing.showDMs) {
      selectedServer = parsedServers.first;
    }

    state = AsyncData(
      existing.copyWith(
        servers: parsedServers,
        allChannels: parsedChannels,
        channelUnreads: channelUnreads,
        channelMentions: channelMentions,
        rolesByServer: rolesByServer,
        selectedServer: selectedServer,
        memberIdsByServer: const {},
      ),
    );

    if (selectedServer != null) {
      _fetchServerChannels(selectedServer);
      fetchMembers(force: true);
      final uid = ref.read(currentUserIdProvider);
      if (uid != null) fetchRoles(serverId: selectedServer.id, currentUserId: uid, force: true);
    }
  }

  void _onMessage(Map<String, dynamic> event) {
    final existing = state.value;
    if (existing == null) return;
    final channelId = event['channel'] as String?;
    final messageId = event['_id'] as String?;
    if (channelId != null && messageId != null) {
      state = AsyncData(
        existing.copyWith(latestMessageIds: {...existing.latestMessageIds, channelId: messageId}),
      );
    }
  }

  void _onChannelAck(Map<String, dynamic> event) {
    final existing = state.value;
    if (existing == null) return;
    final channelId = event['id'] as String?;
    final messageId = event['message_id'] as String?;
    if (channelId != null && messageId != null) {
      final newMentions = Map<String, List<String>>.from(existing.channelMentions)
        ..remove(channelId);
      state = AsyncData(
        existing.copyWith(
          channelUnreads: {...existing.channelUnreads, channelId: messageId},
          channelMentions: newMentions,
        ),
      );
    }
  }

  void _onServerMemberUpdate(Map<String, dynamic> event) {
    final existing = state.value;
    if (existing == null) return;
    final idMap = event['id'];
    if (idMap is! Map) return;
    final serverId = idMap['server'] as String?;
    final userId = idMap['user'] as String?;
    if (serverId == null || userId == null) return;
    final data = event['data'] as Map<String, dynamic>?;
    final clear = (event['clear'] as List<dynamic>?)?.cast<String>() ?? [];

    if (!existing.memberIdsByServer.containsKey(serverId)) return;
    if (!existing.memberIdsByServer[serverId]!.contains(userId)) return;

    _onServerProfileUpdated(userId, serverId, data, clear);
  }

  void _onServerRoleUpdate(Map<String, dynamic> event, String? currentUserId) {
    if (currentUserId != null && state.value?.selectedServer != null) {
      fetchRoles(
        serverId: state.value!.selectedServer!.id,
        currentUserId: currentUserId,
        force: true,
      );
    }
  }

  void _onChannelDelete(Map<String, dynamic> event) {
    final existing = state.value;
    if (existing == null) return;
    final channelId = event['id'] as String?;
    if (channelId == null) return;

    RevoltChannel? selectedChannel = existing.selectedChannel;
    if (selectedChannel?.id == channelId) selectedChannel = null;

    state = AsyncData(
      existing.copyWith(
        allChannels: existing.allChannels.where((c) => c.id != channelId).toList(),
        selectedChannel: selectedChannel,
      ),
    );
  }

  // -- Server CRUD helpers ----------------------------------------------------

  Future<RevoltServer> createServer(String name, {String? description}) async {
    final existing = state.value!;
    final server = await _service.createServer(name, description: description);
    state = AsyncData(existing.copyWith(servers: [...existing.servers, server]));
    if (!existing.showDMs) {
      selectServer(server);
    }
    return server;
  }

  Future<void> updateSelectedServer({
    String? name,
    String? description,
    String? icon,
    List<String>? remove,
  }) async {
    final existing = state.value!;
    final server = existing.selectedServer;
    if (server == null) return;
    await _service.updateServer(
      server.id,
      name: name,
      description: description,
      icon: icon,
      remove: remove,
    );
    final idx = existing.servers.indexWhere((s) => s.id == server.id);
    if (idx >= 0) {
      final newServers = [...existing.servers];
      newServers[idx] = RevoltServer(
        id: server.id,
        name: name ?? server.name,
        description: description ?? server.description,
        ownerId: server.ownerId,
        defaultPermissions: server.defaultPermissions,
        channelIds: server.channelIds,
        icon: icon != null
            ? RevoltFile(id: icon, tag: 'icons', filename: '')
            : (remove?.contains('Icon') == true ? null : server.icon),
      );
      state = AsyncData(existing.copyWith(servers: newServers));
    }
  }

  Future<void> deleteSelectedServer() async {
    final existing = state.value!;
    final server = existing.selectedServer;
    if (server == null) return;
    await _service.deleteServer(server.id);
    final newServers = existing.servers.where((s) => s.id != server.id).toList();
    final newRolesByServer = Map<String, Map<String, RevoltRole>>.from(existing.rolesByServer)
      ..remove(server.id);
    final newMemberIds = Map<String, List<String>>.from(existing.memberIdsByServer)
      ..remove(server.id);
    state = AsyncData(
      existing.copyWith(
        servers: newServers,
        selectedServer: newServers.isNotEmpty ? newServers.first : null,
        selectedChannel: null,
        allChannels: existing.allChannels.where((c) => c.serverId != server.id).toList(),
        rolesByServer: newRolesByServer,
        memberIdsByServer: newMemberIds,
      ),
    );
  }

  // -- Channel CRUD helpers --------------------------------------------------

  Future<RevoltChannel> createChannel(
    String name, {
    String? description,
    bool isVoice = false,
  }) async {
    final existing = state.value!;
    final server = existing.selectedServer;
    if (server == null) throw Exception('No server selected');
    final channel = await _service.createChannel(
      server.id,
      name,
      description: description,
      isVoice: isVoice,
    );
    state = AsyncData(existing.copyWith(allChannels: [...existing.allChannels, channel]));
    return channel;
  }

  Future<void> updateChannel(
    String channelId, {
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
    final existing = state.value!;
    final idx = existing.allChannels.indexWhere((c) => c.id == channelId);
    if (idx >= 0) {
      final old = existing.allChannels[idx];
      final newChannels = [...existing.allChannels];
      newChannels[idx] = RevoltChannel(
        id: old.id,
        type: old.type,
        isVoice: isVoice ?? old.isVoice,
        name: name ?? old.name,
        serverId: old.serverId,
        recipientIds: old.recipientIds,
        description: description ?? old.description,
        lastMessageId: old.lastMessageId,
      );
      state = AsyncData(existing.copyWith(allChannels: newChannels));
    }
  }

  Future<void> deleteChannel(String channelId) async {
    await _service.deleteChannel(channelId);
    final existing = state.value!;
    RevoltChannel? selectedChannel = existing.selectedChannel;
    if (selectedChannel?.id == channelId) selectedChannel = null;
    state = AsyncData(
      existing.copyWith(
        allChannels: existing.allChannels.where((c) => c.id != channelId).toList(),
        selectedChannel: selectedChannel,
      ),
    );
  }

  // -- Selection --------------------------------------------------------------

  void selectServer(RevoltServer server, {String? userId}) {
    final existing = state.value!;
    state = AsyncData(
      existing.copyWith(selectedServer: server, selectedChannel: null, showDMs: false),
    );
    _fetchServerChannels(server);
    fetchMembers(force: true);
    fetchRoles(serverId: server.id, currentUserId: userId ?? ref.read(currentUserIdProvider));
  }

  void selectDMs() {
    final existing = state.value!;
    state = AsyncData(
      existing.copyWith(selectedServer: null, selectedChannel: null, showDMs: true),
    );
  }

  void selectChannel(RevoltChannel channel) {
    final existing = state.value!;
    state = AsyncData(existing.copyWith(selectedChannel: channel));
  }

  void selectVoiceChannel(RevoltChannel channel) {
    final existing = state.value!;
    state = AsyncData(existing.copyWith(selectedChannel: channel));
  }

  // -- Members ----------------------------------------------------------------

  Future<void> fetchMembers({bool force = false}) async {
    final server = state.value?.selectedServer;
    if (server == null) return;
    if (!force && state.value!.memberIdsByServer.containsKey(server.id)) return;

    state = AsyncData(state.value!.copyWith(loadingMembers: true));

    try {
      final (memberProfiles, users) = await _service.fetchServerMembers(server.id);
      final memberIds = memberProfiles.map((m) => m.userId).toList();

      final profileByUserId = {for (final m in memberProfiles) m.userId: m};
      final updatedUsers = users.map((u) {
        final p = profileByUserId[u.id];
        if (p == null) return u;
        return u.copyWithServerProfile(
          server.id,
          ServerProfile(nickname: p.nickname, roles: p.roles, avatar: p.avatar),
        );
      }).toList();

      _onUsersFetched(updatedUsers);

      final current = state.value!;
      state = AsyncData(
        current.copyWith(
          memberIdsByServer: {...current.memberIdsByServer, server.id: memberIds},
          loadingMembers: false,
        ),
      );
    } catch (e) {
      debugPrint('[fetchMembers] ${server.id} failed: $e');
      final current = state.value;
      if (current != null) {
        state = AsyncData(current.copyWith(loadingMembers: false));
      }
    }
  }

  // -- Member actions ---------------------------------------------------------

  Future<void> kickMember(String userId) async {
    final existing = state.value!;
    final server = existing.selectedServer;
    if (server == null) return;
    await _service.kickMember(server.id, userId);
    final newMemberIds = Map<String, List<String>>.from(existing.memberIdsByServer);
    newMemberIds[server.id]?.remove(userId);
    state = AsyncData(existing.copyWith(memberIdsByServer: newMemberIds));
  }

  Future<void> banMember(String userId, {String? reason}) async {
    final existing = state.value!;
    final server = existing.selectedServer;
    if (server == null) return;
    await _service.banMember(server.id, userId, reason: reason);
    final newMemberIds = Map<String, List<String>>.from(existing.memberIdsByServer);
    newMemberIds[server.id]?.remove(userId);
    state = AsyncData(existing.copyWith(memberIdsByServer: newMemberIds));
  }

  Future<void> unbanMember(String userId) async {
    final server = state.value?.selectedServer;
    if (server == null) return;
    await _service.unbanMember(server.id, userId);
  }

  Future<List<RevoltBan>> fetchBans() async {
    final server = state.value?.selectedServer;
    if (server == null) return [];
    return _service.fetchBans(server.id);
  }

  // -- Roles ------------------------------------------------------------------

  Future<void> fetchRoles({
    required String serverId,
    String? currentUserId,
    bool force = false,
  }) async {
    final existing = state.value!;
    if (!force && existing.rolesByServer.containsKey(serverId)) return;

    var rolesMap = <String, RevoltRole>{};
    final server = existing.servers.firstWhere(
      (s) => s.id == serverId,
      orElse: () => existing.servers.first,
    );
    if (server.roles != null) {
      rolesMap = Map<String, RevoltRole>.from(server.roles!);
    }

    if (currentUserId != null) {
      try {
        final (_, _, _, _, roleMap) = await _service.fetchMemberWithRoles(serverId, currentUserId);
        if (roleMap.isNotEmpty) rolesMap = roleMap;
      } catch (e) {
        debugPrint('[fetchRoles] member endpoint failed: $e');
      }
    }

    state = AsyncData(
      existing.copyWith(rolesByServer: {...existing.rolesByServer, serverId: rolesMap}),
    );
  }

  Future<void> createRole(String name) async {
    final existing = state.value!;
    final server = existing.selectedServer;
    if (server == null) return;
    final role = await _service.createRole(server.id, name);
    final newRoles = Map<String, Map<String, RevoltRole>>.from(existing.rolesByServer);
    newRoles[server.id] = {...(newRoles[server.id] ?? {}), role.id: role};
    state = AsyncData(existing.copyWith(rolesByServer: newRoles));
  }

  Future<void> updateRole(
    String roleId, {
    String? name,
    int? colour,
    int? rank,
    bool? hoist,
    dynamic permissions,
  }) async {
    final existing = state.value!;
    final server = existing.selectedServer;
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
    final newRoles = Map<String, Map<String, RevoltRole>>.from(existing.rolesByServer);
    final currentRoles = Map<String, RevoltRole>.from(newRoles[server.id] ?? {});
    currentRoles[roleId] = updated;
    newRoles[server.id] = currentRoles;
    state = AsyncData(existing.copyWith(rolesByServer: newRoles));
  }

  Future<void> deleteRole(String roleId) async {
    final existing = state.value!;
    final server = existing.selectedServer;
    if (server == null) return;
    await _service.deleteRole(server.id, roleId);
    final newRoles = Map<String, Map<String, RevoltRole>>.from(existing.rolesByServer);
    final currentRoles = Map<String, RevoltRole>.from(newRoles[server.id] ?? {});
    currentRoles.remove(roleId);
    newRoles[server.id] = currentRoles;
    state = AsyncData(existing.copyWith(rolesByServer: newRoles));
  }

  Future<void> assignRoleToMember(String userId, String roleId) async {
    final server = state.value?.selectedServer;
    if (server == null) return;
    await _service.assignRole(server.id, userId, roleId);
  }

  Future<void> removeRoleFromMember(String userId, String roleId) async {
    final server = state.value?.selectedServer;
    if (server == null) return;
    await _service.removeRole(server.id, userId, roleId);
  }

  // -- Unread tracking --------------------------------------------------------

  void markChannelRead(String channelId, String messageId) {
    final existing = state.value!;
    final newMentions = Map<String, List<String>>.from(existing.channelMentions)..remove(channelId);
    state = AsyncData(
      existing.copyWith(
        channelUnreads: {...existing.channelUnreads, channelId: messageId},
        channelMentions: newMentions,
      ),
    );
  }

  // -- Invites ----------------------------------------------------------------

  Future<String> createInvite(String channelId) => _service.createInvite(channelId);

  Future<List<RevoltInvite>> fetchInvites(String serverId) => _service.fetchInvites(serverId);

  Future<void> joinInvite(String code) => _service.joinInvite(code);

  // -- Internal helpers -------------------------------------------------------

  Future<void> _fetchServerChannels(RevoltServer server) async {
    try {
      final channels = await _service.fetchChannels(server.channelIds);
      final existing = state.value!;
      state = AsyncData(
        existing.copyWith(
          allChannels: [...existing.allChannels.where((c) => c.serverId != server.id), ...channels],
        ),
      );
    } catch (e) {
      debugPrint('[fetchServerChannels] ${server.id} failed: $e');
    }
  }

  // -- Lifecycle --------------------------------------------------------------

  void clear() {
    _wsSub?.cancel();
    _wsSub = null;
    state = const AsyncData(ServerStateData());
  }
}

final serverStateProvider = AsyncNotifierProvider<ServerNotifier, ServerStateData>(
  ServerNotifier.new,
);
