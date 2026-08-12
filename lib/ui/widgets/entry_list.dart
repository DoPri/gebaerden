import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../media/media.dart';
import '../../theme.dart';
import 'pieces.dart';

class EntryRow extends StatelessWidget {
  const EntryRow({
    required this.entry,
    this.thumb,
    this.onTap,
    this.trailing,
    super.key,
  });

  final CachedEntry entry;
  final MediaSource? thumb;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Tappable(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  _Thumb(thumb),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.word,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15),
                        ),
                        if (!entry.hasVideo)
                          Text(
                            'Kein Video',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (trailing == null)
                    Icon(Icons.chevron_right, size: 16, color: c.fgMuted),
                ],
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.source);

  final MediaSource? source;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placeholder = Icon(
      Icons.videocam_off_outlined,
      size: 16,
      color: c.fgMuted,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 64,
        height: 48,
        color: c.surface2,
        alignment: Alignment.center,
        child: switch (source) {
          // Some thumbnails 404 upstream.
          MediaSource(isFile: true, :final file) => Image.file(
            file,
            fit: BoxFit.cover,
            width: 64,
            height: 48,
            errorBuilder: (_, _, _) => placeholder,
          ),
          MediaSource(:final url?) => Image.network(
            url,
            fit: BoxFit.cover,
            width: 64,
            height: 48,
            errorBuilder: (_, _, _) => placeholder,
          ),
          _ => placeholder,
        },
      ),
    );
  }
}

class EntryListView extends StatefulWidget {
  const EntryListView({
    required this.db,
    required this.entries,
    required this.onOpen,
    this.trailing,
    this.header,
    super.key,
  });

  final AppDatabase db;
  final List<CachedEntry> entries;
  final void Function(CachedEntry) onOpen;
  final Widget Function(CachedEntry)? trailing;
  final Widget? header;

  @override
  State<EntryListView> createState() => _EntryListViewState();
}

class _EntryListViewState extends State<EntryListView> {
  Map<int, MediaSource> _thumbs = {};
  StreamSubscription<void>? _watch;

  @override
  void initState() {
    super.initState();
    _load();
    // Picking a variant or finishing a download changes what a row should show.
    _watch = widget.db
        .tableUpdates(
          TableUpdateQuery.onAllTables([widget.db.variants, widget.db.assets]),
        )
        .listen((_) => _load());
  }

  @override
  void didUpdateWidget(EntryListView old) {
    super.didUpdateWidget(old);
    if (old.entries != widget.entries) _load();
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final found = await thumbnailsFor(widget.db, widget.entries);
    if (mounted) setState(() => _thumbs = found);
  }

  @override
  Widget build(BuildContext context) {
    final head = widget.header;
    return ListView.separated(
      itemCount: widget.entries.length + (head == null ? 0 : 1),
      separatorBuilder: (_, _) => const HairLine(),
      itemBuilder: (context, index) {
        if (head != null && index == 0) return head;
        final entry = widget.entries[index - (head == null ? 0 : 1)];
        return EntryRow(
          entry: entry,
          thumb: _thumbs[entry.id],
          onTap: () => widget.onOpen(entry),
          trailing: widget.trailing?.call(entry),
        );
      },
    );
  }
}
