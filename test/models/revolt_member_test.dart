import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/models.dart';

void main() {
  group('RevoltMember', () {
    test('fromJson parses all fields', () {
      final member = RevoltMember.fromJson({
        '_id': {'server': 'srv1', 'user': 'u1'},
        'nickname': 'Nick',
        'roles': ['role1', 'role2'],
        'avatar': {
          '_id': 'av1',
          'tag': 'avatars',
          'filename': 'server_pic.png',
        },
      });
      expect(member.serverId, 'srv1');
      expect(member.userId, 'u1');
      expect(member.nickname, 'Nick');
      expect(member.roles, ['role1', 'role2']);
      expect(member.avatar, isNotNull);
      expect(member.avatar!.id, 'av1');
      expect(member.avatar!.tag, 'avatars');
    });

    test('fromJson handles missing optional fields', () {
      final member = RevoltMember.fromJson({
        '_id': {'server': 'srv1', 'user': 'u1'},
      });
      expect(member.serverId, 'srv1');
      expect(member.userId, 'u1');
      expect(member.nickname, isNull);
      expect(member.roles, isEmpty);
      expect(member.avatar, isNull);
    });

    test('fromJson handles null roles', () {
      final member = RevoltMember.fromJson({
        '_id': {'server': 'srv1', 'user': 'u1'},
        'roles': null,
      });
      expect(member.roles, isEmpty);
    });

    test('fromJson handles null avatar', () {
      final member = RevoltMember.fromJson({
        '_id': {'server': 'srv1', 'user': 'u1'},
        'avatar': null,
      });
      expect(member.avatar, isNull);
    });
  });
}
