import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/models.dart';

void main() {
  group('RevoltServer', () {
    test('fromJson parses basic fields', () {
      final json = {
        '_id': 'server1',
        'name': 'Test Server',
        'description': 'A test server',
        'channels': ['chan1', 'chan2'],
      };
      final server = RevoltServer.fromJson(json);
      expect(server.id, 'server1');
      expect(server.name, 'Test Server');
      expect(server.description, 'A test server');
      expect(server.channelIds, ['chan1', 'chan2']);
      expect(server.icon, isNull);
    });

    test('fromJson missing optional fields default to null/empty', () {
      final json = {'_id': 'server2', 'name': 'Minimal'};
      final server = RevoltServer.fromJson(json);
      expect(server.id, 'server2');
      expect(server.name, 'Minimal');
      expect(server.description, isNull);
      expect(server.channelIds, isEmpty);
      expect(server.icon, isNull);
    });

    test('iconUrlFor returns null when no icon', () {
      final json = {'_id': 's1', 'name': 'No Icon'};
      final server = RevoltServer.fromJson(json);
      expect(server.iconUrlFor('https://autumn.test'), isNull);
    });

    test('iconUrlFor returns url when icon present', () {
      final json = {
        '_id': 's1',
        'name': 'With Icon',
        'icon': {'_id': 'icon1', 'tag': 'icons', 'filename': 'server.png'},
      };
      final server = RevoltServer.fromJson(json);
      expect(
        server.iconUrlFor('https://autumn.test'),
        'https://autumn.test/icons/icon1',
      );
    });
  });
}
