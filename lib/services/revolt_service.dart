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

  // ── Node config ───────────────────────────────────────────────────────────

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
  /// 1. Try `GET <base>/.well-known/revolt` — if it returns `{"api": "..."}`,
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
            final config = jsonDecode(configResponse.body) as Map<String, dynamic>;
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

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$_apiBase/auth/session/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data =
        jsonDecode(response.body) as Map<String, dynamic>;
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

  // ── Users ─────────────────────────────────────────────────────────────────

  Future<RevoltUser> fetchSelf() async {
    final response = await http.get(
      Uri.parse('$_apiBase/users/@me'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch current user');
    }
    return RevoltUser.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
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
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> updateProfile({String? displayName}) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    final response = await http.patch(
      Uri.parse('$_apiBase/users/@me'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('updateProfile: ${response.statusCode}');
    }
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<List<RevoltMessage>> fetchMessages(String channelId,
      {int limit = 50}) async {
    final response = await http.get(
      Uri.parse(
          '$_apiBase/channels/$channelId/messages?limit=$limit&sort=Latest'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception(
          'fetchMessages ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body);
    final List<dynamic> list =
        body is List ? body : (body as Map<String, dynamic>)['messages'] as List;
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
        {'id': replyToId, 'mention': true}
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
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> editMessage(
      String channelId, String messageId, String content) async {
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
      String channelId, String messageId, String emoji) async {
    await http.put(
      Uri.parse(
          '$_apiBase/channels/$channelId/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}'),
      headers: _headers,
    );
  }

  Future<void> removeReaction(
      String channelId, String messageId, String emoji) async {
    await http.delete(
      Uri.parse(
          '$_apiBase/channels/$channelId/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}'),
      headers: _headers,
    );
  }

  /// Uploads a file to Autumn and returns the file ID.
  Future<String> uploadAttachment(
      Uint8List bytes, String filename) async {
    final uri = Uri.parse('$_autumnBase/attachments');
    final request = http.MultipartRequest('POST', uri)
      ..headers['x-session-token'] = _token ?? ''
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      ));
    final streamed = await request.send();
    if (streamed.statusCode != 200) {
      throw Exception('Upload failed (${streamed.statusCode})');
    }
    final body = await streamed.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  // ── Channels ──────────────────────────────────────────────────────────────
  Future<RevoltChannel> fetchChannel(String channelId) async {
    final response = await http.get(
      Uri.parse('$_apiBase/channels/$channelId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch channel $channelId');
    }
    return RevoltChannel.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<RevoltChannel>> fetchChannels(List<String> channelIds) async {
    final responses = await Future.wait(channelIds.map((id) => http.get(
          Uri.parse('$_apiBase/channels/$id'),
          headers: _headers,
        )));
    return responses.map((response) {
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch channel: ${response.body}');
      }
      return RevoltChannel.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }).toList();
  }

  // ── Voice ─────────────────────────────────────────────────────────────────

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
          'joinVoiceChannel ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────

  void connectWebSocket() {
    // Cancel any existing WS stream subscription before reconnecting
    _wsStreamSub?.cancel();
    _wsStreamSub = null;
    // Recreate controller if it was previously closed
    if (_eventController.isClosed) {
      _eventController =
          StreamController<Map<String, dynamic>>.broadcast();
    }
    _ws = WebSocketChannel.connect(Uri.parse(_wsUrl));
    _ws!.sink
        .add(jsonEncode({'type': 'Authenticate', 'token': _token}));
    _wsStreamSub = _ws!.stream.listen(
      (data) {
        try {
          final event =
              jsonDecode(data as String) as Map<String, dynamic>;
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
      onDone: () {},
      onError: (_) {},
    );
  }

  void disconnect() {
    _wsStreamSub?.cancel();
    _wsStreamSub = null;
    _ws?.sink.close();
    _ws = null;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}
