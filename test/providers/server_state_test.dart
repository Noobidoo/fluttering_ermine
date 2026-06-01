import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/providers/server_state.dart';

import '../helpers/messaging_test_helpers.dart';

RevoltChannel _channel(String id,
        {ChannelType type = ChannelType.textChannel,
        String? serverId,
        bool isVoice = false}) =>
    RevoltChannel(
      id: id,
      type: type,
      name: 'chan $id',
      serverId: serverId,
      isVoice: isVoice,
    );

Map<String, dynamic> _readyEvent({
  List<Map<String, dynamic>> servers = const [],
  List<Map<String, dynamic>> channels = const [],
}) =>
    {
      'type': 'Ready',
      'servers': servers,
      'channels': channels,
      'users': [],
    };

void main() {
  group('ServerState', () {
    late FakeRevoltService svc;
    late ServerState state;

    setUp(() {
      svc = FakeRevoltService();
      state = ServerState(svc);
      state.subscribeToEvents();
    });

    tearDown(() => svc.close());

    test('initial state', () {
      expect(state.servers, isEmpty);
      expect(state.selectedServer, isNull);
      expect(state.selectedChannel, isNull);
      expect(state.showDMs, false);
      expect(state.selectedServerChannels, isEmpty);
      expect(state.dmChannels, isEmpty);
    });

    test('Ready event populates servers and channels', () {
      svc.push(_readyEvent(
        servers: [
          {'_id': 's1', 'name': 'Alpha', 'channels': ['c1']},
          {'_id': 's2', 'name': 'Beta', 'channels': ['c2']},
        ],
        channels: [
          {
            '_id': 'c1',
            'channel_type': 'TextChannel',
            'name': 'general',
            'server': 's1',
          },
          {
            '_id': 'c2',
            'channel_type': 'TextChannel',
            'name': 'random',
            'server': 's2',
          },
          {
            '_id': 'dm1',
            'channel_type': 'DirectMessage',
            'recipients': ['u1', 'u2'],
          },
          {
            '_id': 'saved',
            'channel_type': 'SavedMessages',
          },
        ],
      ));

      expect(state.servers.length, 2);
      expect(state.servers[0].name, 'Alpha');
      expect(state.selectedServer?.id, 's1');
      expect(state.selectedServerChannels.length, 1);
      expect(state.selectedServerChannels[0].id, 'c1');
      expect(state.dmChannels.length, 2);
      expect(state.dmChannels[0].id, 'dm1');
      expect(state.dmChannels[1].id, 'saved');
    });

    test('selectServer changes server and fetches channels', () async {
      svc.push(_readyEvent(
        servers: [
          {'_id': 's1', 'name': 'Alpha', 'channels': ['c1', 'c2']},
          {'_id': 's2', 'name': 'Beta', 'channels': ['c3']},
        ],
        channels: [
          {
            '_id': 'c1',
            'channel_type': 'TextChannel',
            'name': 'general',
            'server': 's1',
          },
        ],
      ));

      svc.stubChannel(_channel('c2', serverId: 's1'));
      svc.stubChannel(_channel('c3', serverId: 's2'));

      final beta = state.servers[1];
      state.selectServer(beta);
      await Future<void>.delayed(Duration.zero);

      expect(state.selectedServer?.id, 's2');
      expect(state.selectedChannel, isNull);
      expect(state.showDMs, false);
      expect(state.selectedServerChannels.length, 1);
      expect(state.selectedServerChannels[0].id, 'c3');
    });

    test('selectDMs switches to DM view', () {
      svc.push(_readyEvent(
        servers: [
          {'_id': 's1', 'name': 'S', 'channels': []},
        ],
      ));

      state.selectDMs();
      expect(state.selectedServer, isNull);
      expect(state.selectedChannel, isNull);
      expect(state.showDMs, true);
    });

    test('selectChannel sets channel', () {
      final c = _channel('c1');
      state.selectChannel(c);
      expect(state.selectedChannel?.id, 'c1');
    });

    test('selectVoiceChannel sets channel', () {
      final c = _channel('vc1', isVoice: true);
      state.selectVoiceChannel(c);
      expect(state.selectedChannel?.id, 'vc1');
    });

    test('clear resets all state', () {
      svc.push(_readyEvent(
        servers: [
          {'_id': 's1', 'name': 'S', 'channels': []},
        ],
      ));

      state.selectChannel(_channel('c1'));
      expect(state.selectedChannel, isNotNull);

      state.clear();
      expect(state.servers, isEmpty);
      expect(state.selectedServer, isNull);
      expect(state.selectedChannel, isNull);
      expect(state.showDMs, false);
    });

    test('_fetchServerChannels error is caught and does not propagate', () async {
      svc.push(_readyEvent(
        servers: [
          {'_id': 's1', 'name': 'Alpha', 'channels': ['missing']},
        ],
      ));

      // Channels not stubbed → fetchChannels throws → catch block handles it
      state.selectServer(state.servers[0]);
      await Future<void>.delayed(Duration.zero);

      expect(state.selectedServer?.id, 's1');
      expect(state.selectedChannel, isNull);
      expect(state.showDMs, false);
    });

    test('dispose cancels subscription without throwing', () {
      expect(() => state.dispose(), returnsNormally);
    });

    test('dmChannels includes DM, group, and saved messages', () {
      final channels = [
        _channel('t', type: ChannelType.textChannel),
        _channel('d', type: ChannelType.directMessage),
        _channel('g', type: ChannelType.group),
        _channel('s', type: ChannelType.savedMessages),
        _channel('u', type: ChannelType.unknown),
      ];
      for (final c in channels) {
        svc.stubChannel(c);
      }

      // Manually set channels via _allChannels (normally done by Ready event)
      // We push a Ready to populate, then check dmChannels
      svc.push(_readyEvent(
        channels: [
          {'_id': 't', 'channel_type': 'TextChannel'},
          {'_id': 'd', 'channel_type': 'DirectMessage'},
          {'_id': 'g', 'channel_type': 'Group'},
          {'_id': 's', 'channel_type': 'SavedMessages'},
          {'_id': 'u', 'channel_type': 'FooBar'},
        ],
      ));

      expect(state.dmChannels.length, 3);
      expect(state.dmChannels.any((c) => c.id == 'd'), true);
      expect(state.dmChannels.any((c) => c.id == 'g'), true);
      expect(state.dmChannels.any((c) => c.id == 's'), true);
      expect(state.dmChannels.any((c) => c.id == 't'), false);
    });
  });
}
