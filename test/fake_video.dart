import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Test double for [VideoPlayerPlatform].
class FakeVideoPlayer extends VideoPlayerPlatform {
  final opened = <DataSource>[];
  final calls = <String>[];

  var broken = false;

  /// Prevents players from emitting initialized events until [release].
  var hold = false;
  final _held = <void Function()>[];

  void release() {
    hold = false;
    for (final report in _held.toList()) {
      report();
    }
    _held.clear();
  }

  var duration = const Duration(seconds: 2);
  var _next = 0;
  final _events = <int, StreamController<VideoEvent>>{};
  final _positions = <int, Duration>{};

  void install() {
    VideoPlayerPlatform.instance = this;
  }

  void finish(int playerId) {
    _positions[playerId] = duration;
    _events[playerId]?.add(VideoEvent(eventType: VideoEventType.completed));
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    calls.add('create');
    opened.add(dataSource);

    final id = _next++;
    // Subscribes after create to prevent event race conditions.
    void report() {
      if (_events[id]?.isClosed ?? true) return;
      _events[id]?.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: duration,
          // Dimensions chosen to fit test viewport.
          size: const Size(640, 240),
        ),
      );
    }

    _events[id] = StreamController<VideoEvent>.broadcast()
      ..onListen = () => scheduleMicrotask(() {
        if (hold) {
          _held.add(report);
          return;
        }
        report();
      });
    _positions[id] = Duration.zero;
    return id;
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      create(options.dataSource);

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      broken ? _failing() : (_events[playerId]?.stream ?? const Stream.empty());

  /// Simulates platform error event for invalid media sources.
  Stream<VideoEvent> _failing() async* {
    yield* Stream<VideoEvent>.error(
      PlatformException(code: 'VideoError', message: 'gone'),
    );
  }

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async => calls.add('play');

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      calls.add('setLooping:$looping');

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      calls.add('setVolume:$volume');

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      calls.add('setPlaybackSpeed:$speed');

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seekTo:${position.inMilliseconds}');
    _positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      buildView(options.playerId);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setWebOptions(
    int playerId,
    VideoPlayerWebOptions options,
  ) async {}
}
