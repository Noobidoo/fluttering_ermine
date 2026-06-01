import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/models.dart';

void main() {
  group('RevoltChannel', () {
    test('fromJson parses TextChannel', () {
      final json = {
        '_id': 'chan1',
        'channel_type': 'TextChannel',
        'name': 'general',
        'server': 'server1',
        'description': 'Chat',
      };
      final c = RevoltChannel.fromJson(json);
      expect(c.id, 'chan1');
      expect(c.type, ChannelType.textChannel);
      expect(c.name, 'general');
      expect(c.serverId, 'server1');
      expect(c.description, 'Chat');
      expect(c.isVoice, false);
      expect(c.recipientIds, isNull);
      expect(c.lastMessageId, isNull);
    });

    test('fromJson parses DirectMessage', () {
      final json = {
        '_id': 'dm1',
        'channel_type': 'DirectMessage',
        'recipients': ['user1', 'user2'],
        'last_message_id': 'msg99',
      };
      final c = RevoltChannel.fromJson(json);
      expect(c.type, ChannelType.directMessage);
      expect(c.recipientIds, ['user1', 'user2']);
      expect(c.lastMessageId, 'msg99');
    });

    test('fromJson parses Group', () {
      final json = {
        '_id': 'group1',
        'channel_type': 'Group',
        'name': 'My Group',
      };
      final c = RevoltChannel.fromJson(json);
      expect(c.type, ChannelType.group);
      expect(c.name, 'My Group');
    });

    test('fromJson parses SavedMessages', () {
      final json = {
        '_id': 'saved1',
        'channel_type': 'SavedMessages',
      };
      final c = RevoltChannel.fromJson(json);
      expect(c.type, ChannelType.savedMessages);
    });

    test('fromJson unknown channel_type defaults to unknown', () {
      final json = {
        '_id': 'unknown1',
        'channel_type': 'FooBar',
      };
      final c = RevoltChannel.fromJson(json);
      expect(c.type, ChannelType.unknown);
    });

    test('fromJson missing channel_type defaults to unknown', () {
      final json = {
        '_id': 'no-type',
      };
      final c = RevoltChannel.fromJson(json);
      expect(c.type, ChannelType.unknown);
    });

    test('isVoice true when voice field present', () {
      final json = {
        '_id': 'vc1',
        'channel_type': 'TextChannel',
        'voice': {'sub': 'abc'},
      };
      final c = RevoltChannel.fromJson(json);
      expect(c.isVoice, true);
    });

    test('isTextBased returns true for text, DM, group, saved messages', () {
      expect(
          RevoltChannel(id: 't', type: ChannelType.textChannel).isTextBased,
          true);
      expect(
          RevoltChannel(id: 'd', type: ChannelType.directMessage).isTextBased,
          true);
      expect(RevoltChannel(id: 'g', type: ChannelType.group).isTextBased,
          true);
      expect(
          RevoltChannel(id: 's', type: ChannelType.savedMessages).isTextBased,
          true);
      expect(RevoltChannel(id: 'u', type: ChannelType.unknown).isTextBased,
          false);
    });
  });
}
