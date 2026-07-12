import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';

const _defaultApiBase = 'https://api.revolt.chat';
const _defaultWsUrl = 'wss://ws.revolt.chat';
const _defaultAutumnBase = 'https://autumn.revolt.chat';

class RevoltService {
  String _apiBase = _defaultApiBase;
  String _wsUrl = _defaultWsUrl;
  String _autumnBase = _defaultAutumnBase;
  String? _voiceNode;
  String? _token;
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsStreamSub;
  StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  Timer? _pingTimer;

  void setToken(String token) => _token = token;

  void setServerUrl(String apiBase, String wsUrl) {
    _apiBase = apiBase;
    _wsUrl = wsUrl;
  }

  void setAutumnUrl(String autumnBase) => _autumnBase = autumnBase;

  void setVoiceNode(String? node) => _voiceNode = node;

  String get apiBase => _apiBase;
  String get autumnBase => _autumnBase;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    // ignore: use_null_aware_elements
    if (_token != null) 'x-session-token': _token!,
  };

  // -- Node config -----------------------------------------------------------

  /// Fetches GET / and returns the node configuration.
  /// The 'ws' field contains the correct WebSocket URL for this instance.
  Future<Map<String, dynamic>> fetchNodeConfig() async {
    final response = await http.get(Uri.parse(_apiBase));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch server config');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Resolves a user-supplied URL to the canonical API base URL.
  ///
  /// Strategy:
  /// 1. Try `GET <base>/.well-known/revolt` - if it returns `{"api": "..."}`,
  ///    use that URL as the API base.
  /// 2. Fall back to treating the input URL as the API base directly.
  ///
  /// Returns a record of (resolvedApiBase, nodeConfig).
  Future<(String, Map<String, dynamic>)> discoverApiUrl(String input) async {
    // Normalise: strip trailing slash, ensure scheme
    var base = input.trim().replaceAll(RegExp(r'/+$'), '');
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }

    // 1. Try .well-known/revolt
    try {
      final wellKnownResponse = await http
          .get(Uri.parse('$base/.well-known/revolt'))
          .timeout(const Duration(seconds: 8));
      if (wellKnownResponse.statusCode == 200) {
        final data = jsonDecode(wellKnownResponse.body);
        if (data is Map && data.containsKey('api')) {
          final apiBase = data['api'] as String;
          final configResponse = await http
              .get(Uri.parse(apiBase))
              .timeout(const Duration(seconds: 8));
          if (configResponse.statusCode == 200) {
            final config =
                jsonDecode(configResponse.body) as Map<String, dynamic>;
            if (config.containsKey('revolt')) {
              return (apiBase, config);
            }
          }
        }
      }
    } catch (_) {}

    // 2. Fall back: treat the input as the API base directly
    final configResponse = await http
        .get(Uri.parse(base))
        .timeout(const Duration(seconds: 8));
    if (configResponse.statusCode != 200) {
      throw Exception('Could not find a Revolt API at "$input"');
    }
    final config = jsonDecode(configResponse.body) as Map<String, dynamic>;
    if (!config.containsKey('revolt')) {
      throw Exception('"$input" does not appear to be a Revolt server');
    }
    return (base, config);
  }

  // -- Auth ------------------------------------------------------------------

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$_apiBase/auth/session/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['type'] ?? 'Login failed');
    }
    return data;
  }

  Future<void> logout() async {
    await http.post(
      Uri.parse('$_apiBase/auth/session/logout'),
      headers: _headers,
    );
  }

  // -- Users -----------------------------------------------------------------

  Future<RevoltUser> fetchSelf() async {
    final response = await http.get(
      Uri.parse('$_apiBase/users/@me'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch current user');
    }
    return RevoltUser.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<RevoltUser> fetchUser(String userId) async {
    final response = await http.get(
      Uri.parse('$_apiBase/users/$userId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch user $userId');
    }
    return RevoltUser.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<UserProfile> fetchUserProfile(String userId) async {
    final response = await http.get(
      Uri.parse('$_apiBase/users/$userId/profile'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch user profile for $userId');
    }
    return UserProfile.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<RevoltUser> updateProfile({
    String? displayName,
    String? presence,
    String? statusText,
    String? profileContent,
    String? avatar,
    String? background,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (presence != null || statusText != null) {
      final status = <String, dynamic>{};
      if (presence != null) status['presence'] = presence;
      if (statusText != null) status['text'] = statusText;
      body['status'] = status;
    }
    if (profileContent != null || background != null) {
      final profile = <String, dynamic>{};
      if (profileContent != null) profile['content'] = profileContent;
      if (background != null) profile['background'] = background;
      body['profile'] = profile;
    }
    if (avatar != null) body['avatar'] = avatar;
    final encoded = jsonEncode(body);
    final response = await http.patch(
      Uri.parse('$_apiBase/users/@me'),
      headers: _headers,
      body: encoded,
    );
    if (response.statusCode != 200) {
      debugPrint(
        'updateProfile response (${response.statusCode}): ${response.body}',
      );
      throw Exception(
        'updateProfile(${response.statusCode}): ${response.body}',
      );
    }
    return RevoltUser.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // -- Messages --------------------------------------------------------------

  Future<List<RevoltMessage>> fetchMessages(
    String channelId, {
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$_apiBase/channels/$channelId/messages?limit=$limit&sort=Latest',
      ),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('fetchMessages ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body);
    final List<dynamic> list = body is List
        ? body
        : (body as Map<String, dynamic>)['messages'] as List;
    return list
        .map((m) => RevoltMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<RevoltMessage> sendMessage(
    String channelId,
    String content, {
    String? replyToId,
    List<String> attachmentIds = const [],
  }) async {
    final body = <String, dynamic>{'content': content};
    if (replyToId != null) {
      body['replies'] = [
        {'id': replyToId, 'mention': true},
      ];
    }
    if (attachmentIds.isNotEmpty) {
      body['attachments'] = attachmentIds;
    }
    final response = await http.post(
      Uri.parse('$_apiBase/channels/$channelId/messages'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send message');
    }
    return RevoltMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> editMessage(
    String channelId,
    String messageId,
    String content,
  ) async {
    final response = await http.patch(
      Uri.parse('$_apiBase/channels/$channelId/messages/$messageId'),
      headers: _headers,
      body: jsonEncode({'content': content}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to edit message');
    }
  }

  Future<void> deleteMessage(String channelId, String messageId) async {
    final response = await http.delete(
      Uri.parse('$_apiBase/channels/$channelId/messages/$messageId'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete message');
    }
  }

  /// Sends a BeginTyping pulse over the WebSocket.
  void sendTyping(String channelId) {
    _ws?.sink.add(jsonEncode({'type': 'BeginTyping', 'channel': channelId}));
  }

  Future<void> addReaction(
    String channelId,
    String messageId,
    String emoji,
  ) async {
    final response = await http.put(
      Uri.parse(
        '$_apiBase/channels/$channelId/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}',
      ),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('addReaction ${response.statusCode}: ${response.body}');
    }
  }

  Future<void> removeReaction(
    String channelId,
    String messageId,
    String emoji,
  ) async {
    final response = await http.delete(
      Uri.parse(
        '$_apiBase/channels/$channelId/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}',
      ),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception(
        'removeReaction ${response.statusCode}: ${response.body}',
      );
    }
  }

  /// Uploads a file to Autumn and returns the file ID.
  Future<String> uploadAttachment(Uint8List bytes, String filename) async {
    final uri = Uri.parse('$_autumnBase/attachments');
    final request = http.MultipartRequest('POST', uri)
      ..headers['x-session-token'] = _token ?? ''
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final streamed = await request.send();
    if (streamed.statusCode != 200) {
      throw Exception('Upload failed (${streamed.statusCode})');
    }
    final body = await streamed.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  /// Uploads an avatar image to Autumn and returns the file ID.
  Future<String> uploadAvatar(Uint8List bytes, String filename) async {
    final uri = Uri.parse('$_autumnBase/avatars');
    final request = http.MultipartRequest('POST', uri)
      ..headers['x-session-token'] = _token ?? ''
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final streamed = await request.send();
    if (streamed.statusCode != 200) {
      throw Exception('Avatar upload failed (${streamed.statusCode})');
    }
    final body = await streamed.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  /// Uploads a background/banner image to Autumn and returns the file ID.
  Future<String> uploadBackground(Uint8List bytes, String filename) async {
    final uri = Uri.parse('$_autumnBase/backgrounds');
    final request = http.MultipartRequest('POST', uri)
      ..headers['x-session-token'] = _token ?? ''
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final streamed = await request.send();
    if (streamed.statusCode != 200) {
      throw Exception('Background upload failed (${streamed.statusCode})');
    }
    final body = await streamed.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  /// Updates the current user's per-server member profile.
  Future<void> updateServerMember(
    String serverId,
    String userId, {
    String? nickname,
    String? avatar,
    List<String> remove = const [],
  }) async {
    final body = <String, dynamic>{};
    if (nickname != null) body['nickname'] = nickname;
    if (avatar != null) body['avatar'] = avatar;
    if (remove.isNotEmpty) body['remove'] = remove;
    final response = await http.patch(
      Uri.parse('$_apiBase/servers/$serverId/members/$userId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('updateServerMember: ${response.statusCode}');
    }
  }

  /// Marks a channel as read up to [messageId].
  Future<void> ackMessage(String channelId, String messageId) async {
    final response = await http.put(
      Uri.parse('$_apiBase/channels/$channelId/ack/$messageId'),
      headers: _headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('ackMessage ${response.statusCode}: ${response.body}');
    }
  }

  // -- Invites ---------------------------------------------------------------

  /// Creates a server invite for [channelId]. Returns the invite code.
  Future<String> createInvite(String channelId) async {
    final response = await http.post(
      Uri.parse('$_apiBase/channels/$channelId/invites'),
      headers: _headers,
      body: '{}',
    );
    if (response.statusCode != 200) {
      throw Exception('createInvite ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['_id'] as String;
  }

  /// Fetches existing invites for [serverId]. Returns empty list on 401.
  Future<List<RevoltInvite>> fetchInvites(String serverId) async {
    final response = await http.get(
      Uri.parse('$_apiBase/servers/$serverId/invites'),
      headers: _headers,
    );
    if (response.statusCode == 401 || response.statusCode == 403) return [];
    if (response.statusCode != 200) {
      throw Exception('fetchInvites ${response.statusCode}: ${response.body}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => RevoltInvite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Joins a server using an invite [code].
  Future<void> joinInvite(String code) async {
    final response = await http.post(
      Uri.parse('$_apiBase/invites/$code'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('joinInvite ${response.statusCode}: ${response.body}');
    }
  }

  // -- Channels --------------------------------------------------------------
  Future<RevoltChannel> fetchChannel(String channelId) async {
    final response = await http.get(
      Uri.parse('$_apiBase/channels/$channelId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch channel $channelId');
    }
    return RevoltChannel.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<RevoltChannel>> fetchChannels(List<String> channelIds) async {
    final responses = await Future.wait(
      channelIds.map(
        (id) =>
            http.get(Uri.parse('$_apiBase/channels/$id'), headers: _headers),
      ),
    );
    return responses.map((response) {
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch channel: ${response.body}');
      }
      return RevoltChannel.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }).toList();
  }

  // -- Members ---------------------------------------------------------------

  /// Fetches all members of a server, returning (memberProfiles, users).
  Future<
    (
      List<
        ({
          String userId,
          String? nickname,
          List<String> roles,
          RevoltFile? avatar,
        })
      >,
      List<RevoltUser>,
    )
  >
  fetchServerMembers(String serverId) async {
    final response = await http.get(
      Uri.parse('$_apiBase/servers/$serverId/members'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception(
        'fetchServerMembers ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final members = (body['members'] as List<dynamic>).map((m) {
      final json = m as Map<String, dynamic>;
      final id = json['_id'] as Map<String, dynamic>;
      final userId = id['user'] as String;
      return (
        userId: userId,
        nickname: json['nickname'] as String?,
        roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? [],
        avatar: json['avatar'] != null
            ? RevoltFile.fromJson(json['avatar'] as Map<String, dynamic>)
            : null,
      );
    }).toList();
    final users = (body['users'] as List<dynamic>)
        .map((u) => RevoltUser.fromJson(u as Map<String, dynamic>))
        .toList();
    return (members, users);
  }

  // -- Voice -----------------------------------------------------------------

  /// Returns {'token': '...', 'url': 'wss://...'} for LiveKit.
  Future<Map<String, dynamic>> joinVoiceChannel(String channelId) async {
    if (_voiceNode == null) {
      throw Exception('No voice node available for this server');
    }
    final response = await http.post(
      Uri.parse('$_apiBase/channels/$channelId/join_call'),
      headers: _headers,
      body: jsonEncode({'node': _voiceNode, 'force_disconnect': true}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'joinVoiceChannel ${response.statusCode}: ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // -- Roles ------------------------------------------------------------------

  /// Fetches all roles for a server. Returns `Map<roleId, RevoltRole>`.
  Future<Map<String, RevoltRole>> fetchRoles(String serverId) async {
    final response = await http.get(
      Uri.parse('$_apiBase/servers/$serverId/roles'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('fetchRoles ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final roles = body['roles'] as Map<String, dynamic>? ?? {};
    return roles.map(
      (k, v) => MapEntry(k, RevoltRole.fromJson(k, v as Map<String, dynamic>)),
    );
  }

  /// Creates a new role on a server.
  Future<RevoltRole> createRole(String serverId, String name) async {
    final response = await http.post(
      Uri.parse('$_apiBase/servers/$serverId/roles'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode != 200) {
      throw Exception('createRole ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final roleId = body['id'] as String? ?? '';
    final roleData = body['role'] as Map<String, dynamic>? ?? body;
    return RevoltRole.fromJson(roleId, roleData);
  }

  /// Updates a role on a server. Returns the updated role.
  Future<RevoltRole> updateRole(
    String serverId,
    String roleId, {
    String? name,
    int? colour,
    int? rank,
    bool? hoist,
    dynamic permissions,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (colour != null) {
      body['colour'] = '#${colour.toRadixString(16).padLeft(6, '0')}';
    }
    if (rank != null) body['rank'] = rank;
    if (hoist != null) body['hoist'] = hoist;
    if (permissions != null) {
      // Accept plain int, string, or OverrideField map.
      if (permissions is int) {
        body['permissions'] = {'a': permissions, 'd': 0};
      } else if (permissions is String && !permissions.startsWith('{')) {
        body['permissions'] = {'a': int.tryParse(permissions) ?? 0, 'd': 0};
      } else {
        body['permissions'] = permissions;
      }
    }
    if (body.isEmpty) throw Exception('updateRole: no fields to update');
    final response = await http.patch(
      Uri.parse('$_apiBase/servers/$serverId/roles/$roleId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('updateRole ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RevoltRole.fromJson(roleId, data);
  }

  /// Deletes a role from a server.
  Future<void> deleteRole(String serverId, String roleId) async {
    final response = await http.delete(
      Uri.parse('$_apiBase/servers/$serverId/roles/$roleId'),
      headers: _headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('deleteRole ${response.statusCode}: ${response.body}');
    }
  }

  // -- Server CRUD -----------------------------------------------------------

  /// Creates a new server.
  Future<RevoltServer> createServer(String name, {String? description}) async {
    final body = <String, dynamic>{'name': name};
    if (description != null) body['description'] = description;
    final response = await http.post(
      Uri.parse('$_apiBase/servers/create'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('createServer ${response.statusCode}: ${response.body}');
    }
    return RevoltServer.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Updates a server.
  Future<void> updateServer(
    String serverId, {
    String? name,
    String? description,
    String? icon,
    List<String>? remove,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (icon != null) body['icon'] = icon;
    if (remove != null) body['remove'] = remove;
    if (body.isEmpty) return;
    final response = await http.patch(
      Uri.parse('$_apiBase/servers/$serverId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('updateServer ${response.statusCode}: ${response.body}');
    }
  }

  /// Deletes a server.
  Future<void> deleteServer(String serverId) async {
    final response = await http.delete(
      Uri.parse('$_apiBase/servers/$serverId'),
      headers: _headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('deleteServer ${response.statusCode}: ${response.body}');
    }
  }

  // -- Channel CRUD ----------------------------------------------------------

  /// Creates a new channel in a server.
  Future<RevoltChannel> createChannel(
    String serverId,
    String name, {
    String? description,
    bool isVoice = false,
  }) async {
    final body = <String, dynamic>{
      'server': serverId,
      'channel_type': isVoice ? 'VoiceChannel' : 'TextChannel',
      'name': name,
    };
    if (description != null) body['description'] = description;
    final response = await http.post(
      Uri.parse('$_apiBase/servers/$serverId/channels'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('createChannel ${response.statusCode}: ${response.body}');
    }
    return RevoltChannel.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Updates a channel.
  Future<void> updateChannel(
    String channelId, {
    String? name,
    String? description,
    String? icon,
    bool? isVoice,
    String? rolePermissions,
    String? userPermissions,
    String? defaultPermissions,
    List<String>? remove,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (icon != null) body['icon'] = icon;
    if (isVoice != null) body['voice'] = isVoice ? {'type': 'voice'} : null;
    if (rolePermissions != null) body['role_permissions'] = rolePermissions;
    if (userPermissions != null) body['user_permissions'] = userPermissions;
    if (defaultPermissions != null) {
      body['default_permissions'] = defaultPermissions;
    }
    if (remove != null) body['remove'] = remove;
    if (body.isEmpty) return;
    final response = await http.patch(
      Uri.parse('$_apiBase/channels/$channelId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('updateChannel ${response.statusCode}: ${response.body}');
    }
  }

  /// Deletes a channel.
  Future<void> deleteChannel(String channelId) async {
    final response = await http.delete(
      Uri.parse('$_apiBase/channels/$channelId'),
      headers: _headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('deleteChannel ${response.statusCode}: ${response.body}');
    }
  }

  // -- Member actions --------------------------------------------------------

  /// Kicks a member from a server.
  Future<void> kickMember(String serverId, String userId) async {
    final response = await http.delete(
      Uri.parse('$_apiBase/servers/$serverId/members/$userId'),
      headers: _headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('kickMember ${response.statusCode}: ${response.body}');
    }
  }

  /// Bans a user from a server.
  Future<void> banMember(
    String serverId,
    String userId, {
    String? reason,
  }) async {
    final body = <String, dynamic>{};
    if (reason != null) body['reason'] = reason;
    final response = await http.put(
      Uri.parse('$_apiBase/servers/$serverId/bans/$userId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('banMember ${response.statusCode}: ${response.body}');
    }
  }

  /// Removes a ban from a user on a server.
  Future<void> unbanMember(String serverId, String userId) async {
    final response = await http.delete(
      Uri.parse('$_apiBase/servers/$serverId/bans/$userId'),
      headers: _headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('unbanMember ${response.statusCode}: ${response.body}');
    }
  }

  /// Fetches all bans for a server.
  Future<List<RevoltBan>> fetchBans(String serverId) async {
    final response = await http.get(
      Uri.parse('$_apiBase/servers/$serverId/bans'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('fetchBans ${response.statusCode}: ${response.body}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => RevoltBan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Assigns a role to a member.
  Future<void> assignRole(String serverId, String userId, String roleId) async {
    // Uses PATCH /servers/{serverId}/members/{userId} with roles
    final member = await fetchServerMember(serverId, userId);
    final currentRoles = member.$2;
    if (currentRoles.contains(roleId)) return;
    await http.patch(
      Uri.parse('$_apiBase/servers/$serverId/members/$userId'),
      headers: _headers,
      body: jsonEncode({
        'roles': [...currentRoles, roleId],
      }),
    );
  }

  /// Removes a role from a member.
  Future<void> removeRole(String serverId, String userId, String roleId) async {
    final member = await fetchServerMember(serverId, userId);
    final currentRoles = member.$2;
    if (!currentRoles.contains(roleId)) return;
    await http.patch(
      Uri.parse('$_apiBase/servers/$serverId/members/$userId'),
      headers: _headers,
      body: jsonEncode({
        'roles': currentRoles.where((r) => r != roleId).toList(),
      }),
    );
  }

  /// Fetches a single server member, returning (userId, roles, nickname, avatar).
  Future<(String, List<String>, String?, RevoltFile?)> fetchServerMember(
    String serverId,
    String userId,
  ) async {
    final response = await http.get(
      Uri.parse('$_apiBase/servers/$serverId/members/$userId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception(
        'fetchServerMember ${response.statusCode}: ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final id = json['_id'] as Map<String, dynamic>?;
    final uid = id?['user'] as String? ?? userId;
    final roles = (json['roles'] as List<dynamic>?)?.cast<String>() ?? [];
    return (
      uid,
      roles,
      json['nickname'] as String?,
      json['avatar'] != null
          ? RevoltFile.fromJson(json['avatar'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Fetches a member with full role objects via `?roles=true`.
  /// Returns (userId, roles, nickname, avatar, rolesMap) where rolesMap
  /// is `Map<roleId, RevoltRole>` when the endpoint returns role data.
  Future<(String, List<String>, String?, RevoltFile?, Map<String, RevoltRole>)>
  fetchMemberWithRoles(String serverId, String userId) async {
    final response = await http.get(
      Uri.parse('$_apiBase/servers/$serverId/members/$userId?roles=true'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception(
        'fetchMemberWithRoles ${response.statusCode}: ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    // Response is either a bare Member or {member: Member, roles: {...}}
    Map<String, dynamic> memberJson;
    Map<String, RevoltRole> roleMap = {};
    if (json.containsKey('member') && json.containsKey('roles')) {
      memberJson = json['member'] as Map<String, dynamic>;
      final rolesJson = json['roles'] as Map<String, dynamic>?;
      if (rolesJson != null) {
        roleMap = rolesJson.map(
          (k, v) =>
              MapEntry(k, RevoltRole.fromJson(k, v as Map<String, dynamic>)),
        );
      }
    } else {
      memberJson = json;
    }
    final id = memberJson['_id'] as Map<String, dynamic>?;
    final uid = id?['user'] as String? ?? userId;
    final roles = (memberJson['roles'] as List<dynamic>?)?.cast<String>() ?? [];
    return (
      uid,
      roles,
      memberJson['nickname'] as String?,
      memberJson['avatar'] != null
          ? RevoltFile.fromJson(memberJson['avatar'] as Map<String, dynamic>)
          : null,
      roleMap,
    );
  }

  // -- WebSocket -------------------------------------------------------------

  void connectWebSocket() {
    // Cancel any existing WS stream subscription before reconnecting
    _wsStreamSub?.cancel();
    _wsStreamSub = null;
    _pingTimer?.cancel();
    // Recreate controller if it was previously closed
    if (_eventController.isClosed) {
      _eventController = StreamController<Map<String, dynamic>>.broadcast();
    }
    _ws = WebSocketChannel.connect(Uri.parse(_wsUrl));
    _ws!.sink.add(jsonEncode({'type': 'Authenticate', 'token': _token}));

    // Start the keep-alive Ping loop (20 seconds is a safe standard)
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      try {
        _ws?.sink.add(
          jsonEncode({
            'type': 'Ping',
            'data': DateTime.now().millisecondsSinceEpoch,
          }),
        );
      } catch (_) {
        // Catch in case the socket is temporarily in a bad state
      }
    });

    _wsStreamSub = _ws!.stream.listen(
      (data) {
        try {
          final event = jsonDecode(data as String) as Map<String, dynamic>;

          // Silently drop 'Pong' responses to avoid spamming your debug console
          if (event['type'] == 'Pong') return;

          debugPrint('[WS] << ${event['type']}');
          if (!_eventController.isClosed) {
            // Unwrap Bulk packets so all consumers see individual events.
            if (event['type'] == 'Bulk') {
              final batch = (event['v'] as List<dynamic>?) ?? [];
              for (final e in batch) {
                final sub = e as Map<String, dynamic>;
                debugPrint('[WS] << (bulk) ${sub['type']}');
                _eventController.add(sub);
              }
            } else {
              _eventController.add(event);
            }
          }
        } catch (_) {}
      },
      onDone: () {
        debugPrint('[WS] connection closed, notifying listeners');
        if (!_eventController.isClosed) {
          _pingTimer?.cancel();
          _eventController.add({'type': 'Disconnected'});
        }
      },
      onError: (Object err) {
        debugPrint('[WS] connection error: $err');
        if (!_eventController.isClosed) {
          _pingTimer?.cancel();
          _eventController.add({'type': 'Disconnected'});
        }
      },
    );
  }

  void disconnect() {
    _wsStreamSub?.cancel();
    _wsStreamSub = null;
    _pingTimer?.cancel();
    _ws?.sink.close();
    _ws = null;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}
