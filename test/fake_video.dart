import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Stands in for the real player. Install it once per test and drive it with
/// [finish].
class FakeVideoPlayer extends VideoPlayerPlatform {
  /// Which players were opened, in order.
  final opened = <DataSource>[];
  final calls = <String>[];

  /// Set before pumping to make the platform report a broken file.
  var broken = false;

  /// Keeps every player from reporting itself as initialized until [release],
  /// so a test can act while a clip is still opening.
  var hold = false;
  final _held = <void Function()>[];

  /// Lets the held players report in.
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

  /// Reports the video as played out, the way the platform does at the end.
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
    // The controller subscribes after create, so the first event waits for the
    // listener instead of racing it. A generator here would deadlock, its
    // cancel only returns once the inner stream ends. dispose is what closes
    // the controller, which close_sinks cannot follow, so it never goes
    // through a local of its own.
    void report() {
      if (_events[id]?.isClosed ?? true) return;
      _events[id]?.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: duration,
          // Wide and short, so the controls fit the test viewport.
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

  /// The real plugin reports a bad source as an error on this stream.
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
