import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/models.dart';

void main() {
  group('RevoltUser', () {
    test('fromJson parses all fields including avatar', () {
      final json = {
        '_id': 'user1',
        'username': 'testuser',
        'discriminator': '1234',
        'display_name': 'Test User',
        'avatar': {
          '_id': 'avatar1',
          'tag': 'avatars',
          'filename': 'pic.png',
        },
      };
      final user = RevoltUser.fromJson(json);
      expect(user.id, 'user1');
      expect(user.username, 'testuser');
      expect(user.discriminator, '1234');
      expect(user.displayName, 'Test User');
      expect(user.avatar, isNotNull);
      expect(user.avatar!.id, 'avatar1');
      expect(user.avatar!.tag, 'avatars');
    });

    test('fromJson missing discriminator defaults to 0000', () {
      final json = {
        '_id': 'user2',
        'username': 'nodisc',
      };
      final user = RevoltUser.fromJson(json);
      expect(user.discriminator, '0000');
      expect(user.avatar, isNull);
    });

    test('displayUsername returns displayName when set', () {
      final user = RevoltUser(
        id: 'u1',
        username: 'raw',
        discriminator: '0000',
        displayName: 'Display',
      );
      expect(user.displayUsername, 'Display');
    });

    test('displayUsername falls back to username when no displayName', () {
      final user = RevoltUser(
        id: 'u1',
        username: 'raw',
        discriminator: '0000',
      );
      expect(user.displayUsername, 'raw');
    });

    test('avatarUrlFor uses avatar URL when avatar present', () {
      final user = RevoltUser(
        id: 'u1',
        username: 'test',
        discriminator: '0000',
        avatar: RevoltFile(id: 'av1', tag: 'avatars', filename: 'pic.png'),
      );
      expect(user.avatarUrlFor('https://autumn.test', 'https://api.test'),
          'https://autumn.test/avatars/av1');
    });

    test('avatarUrlFor falls back to default when no avatar', () {
      final user = RevoltUser(
        id: 'u1',
        username: 'test',
        discriminator: '0000',
      );
      expect(user.avatarUrlFor('https://autumn.test', 'https://api.test'),
          'https://api.test/users/u1/default_avatar');
    });
  });
}
