import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../db/database.dart';
import '../../media/license.dart';
import '../../media/media.dart';
import '../../platform/local.dart';
import '../../settings.dart';
import '../../theme.dart';
import 'pieces.dart';

const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5];

/// One frame at 25 fps.
const _step = Duration(milliseconds: 40);

class SignVideo extends StatefulWidget {
  const SignVideo({
    required this.db,
    required this.video,
    required this.label,
    this.controls = true,
    this.loop,
    this.compact = false,
    this.onEnded,
    super.key,
  });

  final AppDatabase db;
  final ApiVideo video;
  final String label;
  final bool controls;

  /// Overrides the stored preference while playing a sequence.
  final bool? loop;

  /// Caps the height so question and answers share one screen.
  final bool compact;
  final VoidCallback? onEnded;

  @override
  State<SignVideo> createState() => _SignVideoState();
}

class _SignVideoState extends State<SignVideo> {
  VideoPlayerController? _player;
  MediaSource? _poster;
  var _ended = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(SignVideo old) {
    super.didUpdateWidget(old);
    if (old.video.id != widget.video.id) _open();
  }

  @override
  void dispose() {
    _player?.removeListener(_onTick);
    _player?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final wanted = widget.video.id;
    final old = _player;
    old?.removeListener(_onTick);

    final source = await resolveMedia(widget.db, widget.video, AssetKind.video);
    final poster = await resolveMedia(
      widget.db,
      widget.video,
      AssetKind.thumbnail,
    );
    if (!mounted || widget.video.id != wanted) return;
    if (source == null) return _giveUp(wanted, old, poster);

    final next = source.isFile
        ? localVideo(source.path!)
        : VideoPlayerController.networkUrl(Uri.parse(source.url!));

    try {
      await next.initialize();
    } on Object {
      // A truncated file or an unreachable url must not take the screen down.
      await next.dispose();
      return _giveUp(wanted, old, poster);
    }

    if (!mounted || widget.video.id != wanted) {
      await next.dispose();
      return;
    }

    final settings = SettingsScope.of(context);
    await next.setLooping(widget.loop ?? settings.loop);
    await next.setPlaybackSpeed(settings.speed);
    await next.setVolume(0);
    await next.play();
    next.addListener(_onTick);

    setState(() {
      _player = next;
      _poster = poster;
      _ended = false;
    });
    await old?.dispose();
  }

  /// Nothing playable. The old clip has to go, it belongs to another word by
  /// now and the still takes its place.
  Future<void> _giveUp(
    int wanted,
    VideoPlayerController? old,
    MediaSource? poster,
  ) async {
    if (!mounted || widget.video.id != wanted) return;
    setState(() {
      _player = null;
      _poster = poster;
    });
    await old?.dispose();
  }

  void _onTick() {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;

    final done =
        !player.value.isLooping &&
        player.value.position >= player.value.duration &&
        player.value.duration > Duration.zero;
    if (done && !_ended) {
      _ended = true;
      widget.onEnded?.call();
    }
  }

  Future<void> _seekBy(Duration delta) async {
    final player = _player;
    if (player == null) return;
    await player.pause();
    final target = player.value.position + delta;
    await player.seekTo(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final player = _player;
    final license = parseLicense(widget.video.license);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: widget.compact
                ? MediaQuery.sizeOf(context).height * 0.38
                : double.infinity,
          ),
          child: Semantics(
            label: 'Gebärde für ${widget.label}',
            child: AspectRatio(
              aspectRatio: player?.value.aspectRatio ?? 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: player == null || !player.value.isInitialized
                    ? _Poster(_poster)
                    : Transform.flip(
                        flipX: settings.mirror,
                        child: VideoPlayer(player),
                      ),
              ),
            ),
          ),
        ),
        if (widget.controls)
          if (player == null)
            const _Controls(player: null, onStep: null)
          else
            ValueListenableBuilder(
              valueListenable: player,
              builder: (context, _, _) =>
                  _Controls(player: player, onStep: _seekBy),
            ),
        _Credits(video: widget.video, license: license),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster(this.source);

  final MediaSource? source;

  @override
  Widget build(BuildContext context) {
    return switch (source) {
      MediaSource(isFile: true, :final path?) => Image(
        image: localImage(path),
        fit: BoxFit.contain,
      ),
      MediaSource(:final url?) => Image.network(
        url,
        fit: BoxFit.contain,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player, required this.onStep});

  final VideoPlayerController? player;
  final Future<void> Function(Duration)? onStep;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = SettingsScope.of(context);
    final playing = player?.value.isPlaying ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          _Round(
            icon: Icons.skip_previous_outlined,
            label: 'Ein Bild zurück',
            onTap: player == null ? null : () => onStep!(-_step),
          ),
          _Round(
            icon: playing ? Icons.pause : Icons.play_arrow,
            label: playing ? 'Pause' : 'Abspielen',
            onTap: player == null
                ? null
                : () => playing ? player!.pause() : player!.play(),
          ),
          _Round(
            icon: Icons.skip_next_outlined,
            label: 'Ein Bild vor',
            onTap: player == null ? null : () => onStep!(_step),
          ),
          _Round(
            icon: Icons.fullscreen,
            label: 'Vollbild',
            onTap: player == null
                ? null
                : () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FullscreenVideo(
                        player: player!,
                        mirror: settings.mirror,
                      ),
                    ),
                  ),
          ),
          const Spacer(),
          _Round(
            icon: Icons.flip,
            label: 'Spiegeln',
            active: settings.mirror,
            onTap: () => settings.set('mirror', !settings.mirror),
          ),
          _Round(
            icon: Icons.repeat,
            label: 'Endlosschleife',
            active: settings.loop,
            onTap: () async {
              await settings.set('loop', !settings.loop);
              await player?.setLooping(settings.loop);
            },
          ),
          _Speed(player: player),
        ],
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      icon: Icon(icon, size: 19),
      color: active ? c.accent : c.fgMuted,
      tooltip: label,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}

class _Speed extends StatelessWidget {
  const _Speed({required this.player});

  final VideoPlayerController? player;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = SettingsScope.of(context);

    return PopupMenuButton<double>(
      tooltip: 'Tempo',
      initialValue: settings.speed,
      color: c.surface,
      onSelected: (speed) async {
        await settings.set('speed', speed);
        await player?.setPlaybackSpeed(speed);
      },
      itemBuilder: (context) => [
        for (final speed in _speeds)
          PopupMenuItem(value: speed, child: Text(_label(speed))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          _label(settings.speed),
          style: TextStyle(
            fontSize: 13,
            color: settings.speed == 1.0 ? c.fgMuted : c.accent,
          ),
        ),
      ),
    );
  }

  static String _label(double speed) =>
      '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 2).replaceAll('.', ',')}x';
}

class _Credits extends StatelessWidget {
  const _Credits({required this.video, required this.license});

  final ApiVideo video;
  final License? license;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(video.source, style: small),
          if (license != null)
            LinkText(label: 'Lizenz: ${license!.label}', url: license!.url),
          if (video.originalHref != null)
            LinkText(label: 'Originalquelle', url: video.originalHref!),
        ],
      ),
    );
  }
}

/// Shares the controller with the small player, so it keeps its position.
class FullscreenVideo extends StatelessWidget {
  const FullscreenVideo({
    required this.player,
    required this.mirror,
    super.key,
  });

  final VideoPlayerController player;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: player.value.aspectRatio,
              child: Transform.flip(flipX: mirror, child: VideoPlayer(player)),
            ),
          ),
          SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Vollbild verlassen',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
