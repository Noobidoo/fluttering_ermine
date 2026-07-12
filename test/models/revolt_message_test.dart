// Unit tests for RevoltMessage model - Phase 1 coverage.
//
// Pure Dart: no Flutter binding required.

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/revolt_message.dart';
import 'package:fluttering_ermine/models/revolt_file.dart';

// -- Helpers ------------------------------------------------------------------

Map<String, dynamic> _baseJson({
  String id = 'msg1',
  String channel = 'chan1',
  String author = 'u1',
  String content = 'Hello',
  String timestamp = '2024-01-01T00:00:00.000Z',
}) => {
  '_id': id,
  'channel': channel,
  'author': author,
  'content': content,
  'timestamp': timestamp,
};

// -- Tests ---------------------------------------------------------------------

void main() {
  // -- fromJson --------------------------------------------------------------

  group('RevoltMessage.fromJson', () {
    test('parses basic fields', () {
      final msg = RevoltMessage.fromJson(_baseJson());

      expect(msg.id, 'msg1');
      expect(msg.channelId, 'chan1');
      expect(msg.authorId, 'u1');
      expect(msg.content, 'Hello');
      expect(msg.timestamp, '2024-01-01T00:00:00.000Z');
      expect(msg.edited, isNull);
    });

    test('missing optional fields default to empty / null', () {
      final msg = RevoltMessage.fromJson(_baseJson());

      expect(msg.replies, isEmpty);
      expect(msg.reactions, isEmpty);
      expect(msg.attachments, isEmpty);
      expect(msg.edited, isNull);
    });

    test('null author field defaults to empty string', () {
      final json = _baseJson()..remove('author');
      final msg = RevoltMessage.fromJson(json);
      expect(msg.authorId, '');
    });

    test('null timestamp field defaults to empty string', () {
      final json = _baseJson()..remove('timestamp');
      final msg = RevoltMessage.fromJson(json);
      expect(msg.timestamp, '');
    });

    test('parses edited field', () {
      final json = _baseJson()..['edited'] = '2024-06-01T12:00:00.000Z';
      final msg = RevoltMessage.fromJson(json);
      expect(msg.edited, '2024-06-01T12:00:00.000Z');
    });

    test('parses replies list', () {
      final json = _baseJson()..['replies'] = ['replyA', 'replyB'];
      final msg = RevoltMessage.fromJson(json);
      expect(msg.replies, ['replyA', 'replyB']);
    });

    test('parses reactions map with multiple emoji', () {
      final json = _baseJson()
        ..['reactions'] = {
          '\u{1F44D}': ['u1', 'u2'],
          '\u2764': ['u3'],
        };
      final msg = RevoltMessage.fromJson(json);
      expect(msg.reactions['\u{1F44D}'], containsAll(['u1', 'u2']));
      expect(msg.reactions['\u2764'], contains('u3'));
    });

    test('parses empty reactions map', () {
      final json = _baseJson()..['reactions'] = <String, dynamic>{};
      final msg = RevoltMessage.fromJson(json);
      expect(msg.reactions, isEmpty);
    });

    test('parses attachments list', () {
      final json = _baseJson()
        ..['attachments'] = [
          {'_id': 'file1', 'tag': 'attachments', 'filename': 'photo.png'},
          {'_id': 'file2', 'tag': 'attachments', 'filename': 'doc.pdf'},
        ];
      final msg = RevoltMessage.fromJson(json);
      expect(msg.attachments.length, 2);
      expect(msg.attachments.first.id, 'file1');
      expect(msg.attachments.first.filename, 'photo.png');
      expect(msg.attachments.last.id, 'file2');
    });

    test('null content field is preserved as null', () {
      final json = _baseJson()..remove('content');
      final msg = RevoltMessage.fromJson(json);
      expect(msg.content, isNull);
    });
  });

  // -- copyWith --------------------------------------------------------------

  group('RevoltMessage.copyWith', () {
    late RevoltMessage original;

    setUp(() {
      original = RevoltMessage(
        id: 'msg1',
        channelId: 'chan1',
        authorId: 'u1',
        content: 'Original',
        timestamp: '2024-01-01T00:00:00.000Z',
        replies: ['replyId'],
        reactions: {
          '\u{1F44D}': ['u1'],
        },
      );
    });

    test('copyWith content updates content and sets edited', () {
      final updated = original.copyWith(content: 'Edited', edited: 'now');

      expect(updated.content, 'Edited');
      expect(updated.edited, 'now');
    });

    test('copyWith preserves immutable fields', () {
      final updated = original.copyWith(content: 'New');

      expect(updated.id, 'msg1');
      expect(updated.channelId, 'chan1');
      expect(updated.authorId, 'u1');
      expect(updated.timestamp, '2024-01-01T00:00:00.000Z');
      expect(updated.replies, ['replyId']);
    });

    test('copyWith reactions replaces reactions map', () {
      final newReactions = {
        '\u2764': ['u2', 'u3'],
      };
      final updated = original.copyWith(reactions: newReactions);

      expect(updated.reactions, newReactions);
      expect(updated.reactions.containsKey('\u{1F44D}'), isFalse);
    });

    test('copyWith without args returns equivalent message', () {
      final copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.content, original.content);
      expect(copy.reactions, original.reactions);
    });

    test('copyWith does not mutate the original', () {
      original.copyWith(content: 'Changed');
      expect(original.content, 'Original');
    });
  });

  // -- RevoltFile.urlFor -----------------------------------------------------

  group('RevoltFile', () {
    test('urlFor builds correct Autumn URL', () {
      final file = RevoltFile(
        id: 'abc123',
        tag: 'attachments',
        filename: 'image.png',
      );
      expect(
        file.urlFor('https://autumn.example.test'),
        'https://autumn.example.test/attachments/abc123',
      );
    });

    test('fromJson parses all fields', () {
      final file = RevoltFile.fromJson({
        '_id': 'xyz',
        'tag': 'avatars',
        'filename': 'avatar.jpg',
      });
      expect(file.id, 'xyz');
      expect(file.tag, 'avatars');
      expect(file.filename, 'avatar.jpg');
    });

    test('fromJson missing filename defaults to empty string', () {
      final file = RevoltFile.fromJson({'_id': 'id1', 'tag': 'attachments'});
      expect(file.filename, '');
    });
  });
}
