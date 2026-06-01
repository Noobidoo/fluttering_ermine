import 'dart:async';

import 'package:mocktail/mocktail.dart';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/services/revolt_service.dart';
import 'package:fluttering_ermine/services/voice_event_service.dart';

class MockRevoltService extends Mock implements RevoltService {
  final _eventCtrl =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);

  @override
  Stream<Map<String, dynamic>> get events => _eventCtrl.stream;

  void pushEvent(Map<String, dynamic> event) => _eventCtrl.add(event);

  @override
  String get apiBase => 'https://api.example.test';

  @override
  String get autumnBase => 'https://autumn.example.test';

  void close() => _eventCtrl.close();
}

class MockVoiceEventService extends Mock implements VoiceEventService {
  final _membershipCtrl = StreamController<dynamic>.broadcast(sync: true);
  final _publishingCtrl =
      StreamController<VoicePublishingStateChangeEvent>.broadcast(sync: true);

  @override
  Stream<dynamic> get membershipEvents => _membershipCtrl.stream;

  @override
  Stream<VoicePublishingStateChangeEvent> get publishingEvents =>
      _publishingCtrl.stream;

  @override
  void subscribeToWebSocketEvents() {}

  void close() {
    _membershipCtrl.close();
    _publishingCtrl.close();
  }
}
