import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../api/queries.dart';
import '../db/database.dart';
import '../db/recent.dart';
import '../db/repo.dart';
import '../media/variants.dart';
import '../packages/manager.dart';
import '../search/dictionary.dart';
import '../theme.dart';
import 'widgets/list_picker.dart';
import 'widgets/pieces.dart';
import 'widgets/sign_video.dart';
import 'widgets/variant_list.dart';

String signdictUrl(int id, [int? videoId]) => videoId == null
    ? 'https://signdict.org/entry/$id'
    : 'https://signdict.org/entry/$id/video/$videoId';

class EntryScreen extends StatefulWidget {
  const EntryScreen({required this.db, required this.id, super.key});

  final AppDatabase db;
  final int id;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  CachedEntry? _entry;
  List<CachedEntry> _related = [];
  var _chosen = 0;
  var _failed = false;

  List<ApiVideo> get _videos {
    final entry = _entry;
    if (entry == null) return const [];
    if (entry.videos?.isNotEmpty == true) return entry.videos!;
    return entry.currentVideo == null ? const [] : [entry.currentVideo!];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await getEntry(widget.db, widget.id);
    if (cached != null && mounted) {
      setState(() => _entry = cached);
      await remember(widget.db, RecentKind.entry, '${cached.id}', cached.word);
      await _restorePick();
    }

    try {
      final fresh = await fetchEntry(widget.id);
      if (!mounted) return;
      // Upstream returns null for missing or deleted IDs without error.
      if (fresh == null) {
        if (_entry == null) setState(() => _failed = true);
        return;
      }
      final row = (await cacheEntries(widget.db, [fresh])).single;
      if (!mounted) return;
      setState(() => _entry = row);
      await remember(widget.db, RecentKind.entry, '${row.id}', row.word);
      await _restorePick();

      final near = await relatedTo(widget.db, row);
      if (mounted) setState(() => _related = near);
    } on Exception {
      if (mounted && _entry == null) setState(() => _failed = true);
    }
  }

  Future<void> _restorePick() async {
    final entry = _entry;
    if (entry == null) return;
    final video = await preferredVideo(widget.db, entry);
    final index = _videos.indexWhere((v) => v.id == video?.id);
    if (mounted && index >= 0) setState(() => _chosen = index);
  }

  Future<void> _pick(int index) async {
    final entry = _entry;
    if (entry == null) return;
    setState(() => _chosen = index);
    await setPreferred(widget.db, entry.id, _videos[index]);
    // Keep offline download synced with chosen variant.
    await refreshDownloadFor(widget.db, entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entry = _entry;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          entry?.word ?? '…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          if (entry != null)
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 19),
              color: c.fgMuted,
              tooltip: 'Gebärde teilen',
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                  text: signdictUrl(
                    entry.id,
                    _videos.elementAtOrNull(_chosen)?.id,
                  ),
                  subject: entry.word,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: c.border),
        ),
      ),
      body: insetSides(switch (entry) {
        null when _failed => const Note(
          'Die Gebärde konnte nicht geladen werden.',
          problem: true,
        ),
        null => const SizedBox.shrink(),
        _ => ListView(
          children: [
            if (_videos.isEmpty)
              const Note('Zu dieser Gebärde gibt es noch kein Video.')
            else
              SignVideo(
                db: widget.db,
                video: _videos[_chosen.clamp(0, _videos.length - 1)],
                label: entry.word,
              ),
            if (_videos.length > 1)
              VariantList(
                db: widget.db,
                videos: _videos,
                selected: _chosen,
                word: entry.word,
                onSelect: _pick,
              ),
            if (entry.description != null) ...[
              const HairLine(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  entry.description!,
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ],
            if (entry.hasVideo && downloadsAvailable) ...[
              const HairLine(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OfflineToggle(db: widget.db, entry: entry),
              ),
            ],
            if (_related.isNotEmpty) ...[
              const HairLine(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Verwandte Wörter'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final item in _related)
                          WordChip(
                            item.word,
                            onTap: () => context.push('/eintrag/${item.id}'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const HairLine(),
            ListPicker(db: widget.db, entryId: entry.id),
            const HairLine(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: LinkText(
                label: 'Bei SignDict ansehen',
                url: signdictUrl(
                  entry.id,
                  _videos.elementAtOrNull(_chosen)?.id,
                ),
              ),
            ),
          ],
        ),
      }),
    );
  }
}
