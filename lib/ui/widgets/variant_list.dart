import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../media/license.dart';
import '../../media/media.dart';
import '../../platform/local.dart';
import '../../theme.dart';
import '../../util/time.dart';
import 'pieces.dart';

/// Mirrors what signdict.org shows: still, contributor, age and license.
class VariantList extends StatefulWidget {
  const VariantList({
    required this.db,
    required this.videos,
    required this.selected,
    required this.word,
    required this.onSelect,
    super.key,
  });

  final AppDatabase db;
  final List<ApiVideo> videos;
  final int selected;
  final String word;
  final ValueChanged<int> onSelect;

  @override
  State<VariantList> createState() => _VariantListState();
}

class _VariantListState extends State<VariantList> {
  Map<int, MediaSource> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final found = <int, MediaSource>{};
    for (final video in widget.videos) {
      final source = await resolveMedia(widget.db, video, AssetKind.thumbnail);
      if (source != null) found[video.id] = source;
    }
    if (mounted) setState(() => _thumbs = found);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: SectionLabel(
            '${widget.videos.length} Varianten für »${widget.word}«',
          ),
        ),
        for (final (index, video) in widget.videos.indexed) ...[
          const HairLine(),
          _Variant(
            video: video,
            thumb: _thumbs[video.id],
            active: index == widget.selected,
            onTap: () => widget.onSelect(index),
          ),
        ],
        const HairLine(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Deine Auswahl wird dauerhaft gespeichert.',
            style: TextStyle(fontSize: 12, height: 1.5, color: c.fgMuted),
          ),
        ),
      ],
    );
  }
}

class _Variant extends StatelessWidget {
  const _Variant({
    required this.video,
    required this.thumb,
    required this.active,
    required this.onTap,
  });

  final ApiVideo video;
  final MediaSource? thumb;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final license = parseLicense(video.license);
    final age = relativeTime(video.updatedAt);

    return Semantics(
      selected: active,
      child: Tappable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: active ? Border.all(color: c.accent, width: 2) : null,
                  color: c.surface2,
                ),
                clipBehavior: Clip.antiAlias,
                child: switch (thumb) {
                  MediaSource(isFile: true, :final path?) => Image(
                    image: localImage(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  MediaSource(:final url?) => Image.network(
                    url,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: active ? c.accent : c.fg,
                      ),
                    ),
                    Text(
                      [?age, ?license?.label].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (active) Icon(Icons.check, size: 17, color: c.accent),
            ],
          ),
        ),
      ),
    );
  }
}
