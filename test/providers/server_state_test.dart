import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fluttering_ermine/features/core/providers/service_providers.dart';
import 'package:fluttering_ermine/features/servers/providers/server_providers.dart';
import 'package:fluttering_ermine/models/models.dart';

import '../helpers/messaging_test_helpers.dart';

RevoltChannel _channel(
  String id, {
  ChannelType type = ChannelType.textChannel,
  String? serverId,
  bool isVoice = false,
}) => RevoltChannel(
  id: id,
  type: type,
  name: 'chan $id',
  serverId: serverId,
  isVoice: isVoice,
);

Map<String, dynamic> _readyEvent({
  List<Map<String, dynamic>> servers = const [],
  List<Map<String, dynamic>> channels = const [],
  List<Map<String, dynamic>> channelUnreads = const [],
}) => {
  'type': 'Ready',
  'servers': servers,
  'channels': channels,
  'users': [],
  'channel_unreads': channelUnreads,
};

void main() {
  group('ServerNotifier', () {
    late FakeRevoltService svc;
    late ProviderContainer container;

    setUp(() async {
      svc = FakeRevoltService();
      container = ProviderContainer(
        overrides: [revoltServiceProvider.overrideWithValue(svc)],
      );
      // Wait for async build to complete and WS subscription to start
      await container.read(serverStateProvider.future);
    });

    tearDown(() {
      svc.close();
      container.dispose();
    });

    // Helper functions to read live state (not a getter — invalid inside closures)
    ServerStateData state() => container.read(serverStateProvider).requireValue;
    ServerNotifier notifier() => container.read(serverStateProvider.notifier);

    test('initial state', () {
      expect(state().servers, isEmpty);
      expect(state().selectedServer, isNull);
      expect(state().selectedChannel, isNull);
      expect(state().showDMs, false);
      expect(state().selectedServerChannels, isEmpty);
      expect(state().dmChannels, isEmpty);
      expect(state().loadingMembers, false);
      expect(state().currentServerMemberIds, isNull);
    });

    test('Ready event populates servers and channels', () {
      svc.push(
        _readyEvent(
          servers: [
            {
              '_id': 's1',
              'name': 'Alpha',
              'channels': ['c1'],
            },
            {
              '_id': 's2',
              'name': 'Beta',
              'channels': ['c2'],
            },
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
            {'_id': 'saved', 'channel_type': 'SavedMessages'},
          ],
        ),
      );

      expect(state().servers.length, 2);
      expect(state().servers[0].name, 'Alpha');
      expect(state().selectedServer?.id, 's1');
      expect(state().selectedServerChannels.length, 1);
      expect(state().selectedServerChannels[0].id, 'c1');
      expect(state().dmChannels.length, 2);
      expect(state().dmChannels[0].id, 'dm1');
      expect(state().dmChannels[1].id, 'saved');
    });

    test('selectServer changes selected server', () async {
      svc.push(
        _readyEvent(
          servers: [
            {'_id': 's1', 'name': 'Alpha', 'channels': []},
            {'_id': 's2', 'name': 'Beta', 'channels': []},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      notifier().selectServer(state().servers[1]);

      expect(state().selectedServer?.id, 's2');
      expect(state().selectedChannel, isNull);
      expect(state().showDMs, false);
    });

    test('selectDMs switches to DM view', () async {
      svc.push(
        _readyEvent(
          servers: [
            {'_id': 's1', 'name': 'S', 'channels': []},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      notifier().selectDMs();
      expect(state().selectedServer, isNull);
      expect(state().selectedChannel, isNull);
      expect(state().showDMs, true);
    });

    test('selectChannel sets channel', () {
      final c = _channel('c1');
      notifier().selectChannel(c);
      expect(state().selectedChannel?.id, 'c1');
    });

    test('selectVoiceChannel sets channel', () {
      final c = _channel('vc1', isVoice: true);
      notifier().selectVoiceChannel(c);
      expect(state().selectedChannel?.id, 'vc1');
    });

    test('clear resets all state', () {
      svc.push(
        _readyEvent(
          servers: [
            {'_id': 's1', 'name': 'S', 'channels': []},
          ],
        ),
      );

      notifier().selectChannel(_channel('c1'));
      expect(state().selectedChannel, isNotNull);

      notifier().clear();
      expect(state().servers, isEmpty);
      expect(state().selectedServer, isNull);
      expect(state().selectedChannel, isNull);
      expect(state().showDMs, false);
    });

    test(
      '_fetchServerChannels error is caught and does not propagate',
      () async {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'Alpha',
                'channels': ['missing'],
              },
            ],
          ),
        );

        notifier().selectServer(state().servers[0]);
        await Future<void>.delayed(Duration.zero);

        expect(state().selectedServer?.id, 's1');
        expect(state().selectedChannel, isNull);
        expect(state().showDMs, false);
      },
    );

    test('dispose cancels subscription without throwing', () {
      expect(() => container.dispose(), returnsNormally);
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

      svc.push(
        _readyEvent(
          channels: [
            {'_id': 't', 'channel_type': 'TextChannel'},
            {'_id': 'd', 'channel_type': 'DirectMessage'},
            {'_id': 'g', 'channel_type': 'Group'},
            {'_id': 's', 'channel_type': 'SavedMessages'},
            {'_id': 'u', 'channel_type': 'FooBar'},
          ],
        ),
      );

      expect(state().dmChannels.length, 3);
      expect(state().dmChannels.any((c) => c.id == 'd'), true);
      expect(state().dmChannels.any((c) => c.id == 'g'), true);
      expect(state().dmChannels.any((c) => c.id == 's'), true);
      expect(state().dmChannels.any((c) => c.id == 't'), false);
    });

    // -- Unread tracking ------------------------------------------------------

    group('Unread tracking', () {
      test('Ready event with channel_unreads populates unread state', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1', 'c2'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'general',
                'server': 's1',
                'last_message_id': 'msg5',
              },
              {
                '_id': 'c2',
                'channel_type': 'TextChannel',
                'name': 'random',
                'server': 's1',
                'last_message_id': 'msg3',
              },
            ],
            channelUnreads: [
              {'_id': 'c1', 'last_id': 'msg5', 'mentions': []},
              {
                '_id': 'c2',
                'last_id': 'msg2',
                'mentions': ['u1'],
              },
            ],
          ),
        );

        expect(state().isChannelUnread('c1'), false);
        expect(state().isChannelUnread('c2'), true);
      });

      test('channel not in channel_unreads with messages is not unread', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'general',
                'server': 's1',
                'last_message_id': 'msg5',
              },
            ],
          ),
        );

        expect(state().isChannelUnread('c1'), false);
      });

      test('channel in channel_unreads with null last_id is not unread', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'general',
                'server': 's1',
                'last_message_id': 'msg5',
              },
            ],
            channelUnreads: [
              {'_id': 'c1', 'last_id': null, 'mentions': []},
            ],
          ),
        );

        expect(state().isChannelUnread('c1'), false);
      });

      test('channel with no messages is not unread', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'empty',
                'server': 's1',
              },
            ],
            channelUnreads: [
              {'_id': 'c1', 'last_id': 'msg1', 'mentions': []},
            ],
          ),
        );

        expect(state().isChannelUnread('c1'), false);
      });

      test('Message event makes channel unread beyond lastId', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'general',
                'server': 's1',
              },
            ],
            channelUnreads: [
              {'_id': 'c1', 'last_id': 'msg5', 'mentions': []},
            ],
          ),
        );

        expect(state().isChannelUnread('c1'), false);

        svc.push(msgEvent(id: 'msg6', channel: 'c1'));

        expect(state().isChannelUnread('c1'), true);
      });

      test('isChannelUnread false after markChannelRead matches latest', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'general',
                'server': 's1',
              },
            ],
            channelUnreads: [
              {'_id': 'c1', 'last_id': 'msg5', 'mentions': []},
            ],
          ),
        );

        svc.push(msgEvent(id: 'msg6', channel: 'c1'));
        expect(state().isChannelUnread('c1'), true);

        notifier().markChannelRead('c1', 'msg6');
        expect(state().isChannelUnread('c1'), false);
      });

      test('markChannelRead removes mentions', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'general',
                'server': 's1',
              },
            ],
            channelUnreads: [
              {
                '_id': 'c1',
                'last_id': 'msg5',
                'mentions': ['u1', 'u2'],
              },
            ],
          ),
        );

        expect(state().mentionCountFor('c1'), 2);

        notifier().markChannelRead('c1', 'msg5');
        expect(state().mentionCountFor('c1'), 0);
      });

      test('mentionCountFor returns correct count from channel_unreads', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'general',
                'server': 's1',
              },
            ],
            channelUnreads: [
              {
                '_id': 'c1',
                'last_id': 'msg5',
                'mentions': ['u1', 'u2', 'u3'],
              },
            ],
          ),
        );

        expect(state().mentionCountFor('c1'), 3);
      });

      test('mentionCountFor returns 0 for channel without mentions', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'general',
                'server': 's1',
              },
            ],
            channelUnreads: [
              {'_id': 'c1', 'last_id': 'msg5', 'mentions': []},
            ],
          ),
        );

        expect(state().mentionCountFor('c1'), 0);
      });

      test('mentionCountFor returns 0 for unknown channel', () {
        expect(state().mentionCountFor('nonexistent'), 0);
      });

      test('serverUnreadCount aggregates unread channels per server', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1', 'c2', 'c3'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'general',
                'server': 's1',
                'last_message_id': 'msg5',
              },
              {
                '_id': 'c2',
                'channel_type': 'TextChannel',
                'name': 'random',
                'server': 's1',
                'last_message_id': 'msg3',
              },
              {
                '_id': 'c3',
                'channel_type': 'TextChannel',
                'name': 'dev',
                'server': 's1',
                'last_message_id': 'msg1',
              },
            ],
            channelUnreads: [
              {'_id': 'c1', 'last_id': 'msg5', 'mentions': []},
              {'_id': 'c2', 'last_id': 'msg2', 'mentions': []},
            ],
          ),
        );

        expect(state().serverUnreadCount('s1'), 1);
      });

      test(
        'serverUnreadCount returns 0 for server with no unread channels',
        () {
          svc.push(
            _readyEvent(
              servers: [
                {
                  '_id': 's1',
                  'name': 'S1',
                  'channels': ['c1'],
                },
              ],
              channels: [
                {
                  '_id': 'c1',
                  'channel_type': 'TextChannel',
                  'name': 'general',
                  'server': 's1',
                  'last_message_id': 'msg5',
                },
              ],
              channelUnreads: [
                {'_id': 'c1', 'last_id': 'msg5', 'mentions': []},
              ],
            ),
          );

          expect(state().serverUnreadCount('s1'), 0);
        },
      );

      test('serverUnreadCount ignores channels from other servers', () {
        svc.push(
          _readyEvent(
            servers: [
              {
                '_id': 's1',
                'name': 'S1',
                'channels': ['c1'],
              },
              {
                '_id': 's2',
                'name': 'S2',
                'channels': ['c2'],
              },
            ],
            channels: [
              {
                '_id': 'c1',
                'channel_type': 'TextChannel',
                'name': 'general',
                'server': 's1',
                'last_message_id': 'msg5',
              },
              {
                '_id': 'c2',
                'channel_type': 'TextChannel',
                'name': 'random',
                'server': 's2',
                'last_message_id': 'msg3',
              },
            ],
            channelUnreads: [
              {'_id': 'c1', 'last_id': 'msg5', 'mentions': []},
            ],
          ),
        );

        expect(state().serverUnreadCount('s1'), 0);
        expect(state().serverUnreadCount('s2'), 0);
      });
    });

    // -- Members --------------------------------------------------------------

    group('Members', () {
      setUp(() {
        notifier().setUsersFetchedCallback((_) {});
        notifier().setServerProfileUpdatedCallback((_, _, _, _) {});
      });

      test('currentServerMemberIds returns null when no server selected', () {
        expect(state().currentServerMemberIds, isNull);
      });

      test('Ready event auto-fetches members for first server', () async {
        svc.stubMembers('s1', [
          (userId: 'u1', nickname: null, roles: <String>[], avatar: null),
          (userId: 'u2', nickname: null, roles: <String>[], avatar: null),
        ]);

        svc.push(
          _readyEvent(
            servers: [
              {'_id': 's1', 'name': 'S1', 'channels': []},
            ],
          ),
        );

        expect(state().loadingMembers, true);

        await Future<void>.delayed(Duration.zero);

        expect(state().loadingMembers, false);
        expect(state().currentServerMemberIds, hasLength(2));
      });

      test('fetchMembers does not re-fetch cached members', () async {
        svc.stubMembers('s1', [
          (userId: 'u1', nickname: null, roles: <String>[], avatar: null),
        ]);

        svc.push(
          _readyEvent(
            servers: [
              {'_id': 's1', 'name': 'S1', 'channels': []},
            ],
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(state().currentServerMemberIds, hasLength(1));

        await notifier().fetchMembers();
        expect(state().currentServerMemberIds, hasLength(1));
      });

      test('fetchMembers error does not propagate', () async {
        svc.fetchMembersThrows = true;

        svc.push(
          _readyEvent(
            servers: [
              {'_id': 's1', 'name': 'S1', 'channels': []},
            ],
          ),
        );

        await Future<void>.delayed(Duration.zero);
        expect(state().loadingMembers, false);
        expect(state().currentServerMemberIds, isNull);
      });

      test('isMember checks membership by server and userId', () async {
        svc.stubMembers('s1', [
          (userId: 'u1', nickname: 'Alice', roles: <String>[], avatar: null),
          (userId: 'u2', nickname: 'Bob', roles: <String>[], avatar: null),
        ]);

        svc.push(
          _readyEvent(
            servers: [
              {'_id': 's1', 'name': 'S1', 'channels': []},
            ],
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(state().isMember('s1', 'u2'), isTrue);
        expect(state().isMember('s1', 'unknown'), isFalse);
        expect(state().isMember('ghost', 'u1'), isFalse);
      });
    });

    // -- Invites --------------------------------------------------------------

    group('Invites', () {
      test('createInvite delegates to service', () async {
        svc.createInviteResult = 'abc123';

        final code = await notifier().createInvite('chan1');

        expect(code, 'abc123');
        expect(svc.createInviteCalls, contains('chan1'));
      });

      test('joinInvite delegates to service', () async {
        await notifier().joinInvite('join-me');

        expect(svc.joinInviteCalls, contains('join-me'));
      });
    });
  });
}
