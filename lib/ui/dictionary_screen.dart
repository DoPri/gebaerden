import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../api/queries.dart';
import '../db/database.dart';
import '../db/recent.dart';
import '../db/repo.dart';
import '../search/dictionary.dart';
import '../search/latest.dart';
import '../settings.dart';
import '../theme.dart';
import 'tour.dart';
import 'widgets/entry_list.dart';
import 'widgets/pieces.dart';

const _debounce = Duration(milliseconds: 220);

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({required this.db, super.key});

  final AppDatabase db;

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final _field = TextEditingController();
  Timer? _timer;
  CancelToken? _inflight;

  StreamSubscription<void>? _watch;
  List<CachedEntry> _hits = [];
  List<RecentItem> _recent = [];
  var _query = '';
  var _busy = false;
  var _failed = false;
  var _rolling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecent());
    // Opening a word happens on the detail screen, which pops back here.
    _watch = widget.db
        .tableUpdates(TableUpdateQuery.onTable(widget.db.recents))
        .listen((_) => unawaited(_loadRecent()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _inflight?.cancel();
    _watch?.cancel();
    _field.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final rows = [
      ...await recentItems(widget.db, RecentKind.entry),
      ...await recentItems(widget.db, RecentKind.search),
    ];
    if (mounted) setState(() => _recent = rows);
  }

  Future<void> _roll() async {
    setState(() => _rolling = true);
    try {
      final entry = await randomEntry();
      if (entry == null || !mounted) return;
      final row = (await cacheEntries(widget.db, [entry])).single;
      if (mounted) await context.push('/eintrag/${row.id}');
    } on Exception {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _rolling = false);
    }
  }

  void _repeat(RecentItem item) {
    if (item.kind == RecentKind.entry) {
      unawaited(context.push('/eintrag/${item.value}'));
      return;
    }
    _field.text = item.value;
    _onChanged(item.value);
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _inflight?.cancel();
    setState(() => _query = value.trim());

    if (_query.isEmpty) {
      setState(() {
        _hits = [];
        _busy = false;
        _failed = false;
      });
      return;
    }

    // Cache first, the network only refines.
    unawaited(_showCached(_query));
    _timer = Timer(_debounce, () => unawaited(_search(_query)));
  }

  Future<void> _showCached(String query) async {
    final rows = await cachedMatches(widget.db, query);
    if (mounted && _query == query && rows.isNotEmpty) {
      setState(() => _hits = rows);
    }
  }

  Future<void> _search(String query) async {
    final cancel = CancelToken();
    _inflight = cancel;
    setState(() {
      _busy = true;
      _failed = false;
    });

    try {
      final live = await liveSearch(widget.db, query, cancel: cancel);
      // The server matches substrings only. Cached hits carry the typo
      // tolerance, so they go after the live ones rather than being replaced.
      final cached = await cachedMatches(widget.db, query);
      if (!mounted || _query != query) return;

      final seen = live.map((e) => e.id).toSet();
      setState(
        () => _hits = [
          ...sortForDisplay(live, query),
          ...cached.where((e) => !seen.contains(e.id)),
        ],
      );
      if (live.isNotEmpty) {
        await remember(widget.db, RecentKind.search, query, query);
        await _loadRecent();
      }
    } on Cancelled {
      return;
    } on Exception {
      if (mounted && _query == query) setState(() => _failed = true);
    } finally {
      if (mounted && _query == query) setState(() => _busy = false);
    }
  }

  List<CachedEntry> get _visible {
    final settings = SettingsScope.of(context);
    if (settings.showWithoutVideo) return _hits;
    return _hits.where((e) => e.hasVideo).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _visible;

    return Column(
      children: [
        _SearchField(controller: _field, onChanged: _onChanged, busy: _busy),
        const HairLine(),
        Expanded(
          child: switch (true) {
            _ when _query.isEmpty => _Start(
              recent: _recent,
              rolling: _rolling,
              onRoll: _roll,
              onRepeat: _repeat,
              onClearRecent: () async {
                await clearRecent(widget.db);
                await _loadRecent();
              },
              onPick: (letter) => context.push('/buchstabe/$letter'),
            ),
            _ when _failed && rows.isEmpty => const Note(
              'Die Suche hat nicht funktioniert. Prüfe bitte deine Verbindung.',
              problem: true,
            ),
            _ when rows.isEmpty && !_busy => Note(
              _hits.isEmpty
                  ? 'Dazu haben wir nichts gefunden.'
                  : 'Zu diesen Treffern gibt es (noch) keine Videos.',
            ),
            _ => EntryListView(
              db: widget.db,
              entries: rows,
              onOpen: (entry) => context.push('/eintrag/${entry.id}'),
            ),
          },
        ),
        if (_busy && rows.isNotEmpty)
          LinearProgressIndicator(minHeight: 2, backgroundColor: c.surface2),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.busy,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TourAnchor(
        spot: TourSpot.search,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Nach einer Gebärde suchen',
            prefixIcon: Icon(Icons.search, size: 18, color: c.fgMuted),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close, size: 17, color: c.fgMuted),
                    tooltip: 'Eingabe löschen',
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _Start extends StatelessWidget {
  const _Start({
    required this.recent,
    required this.rolling,
    required this.onRoll,
    required this.onRepeat,
    required this.onClearRecent,
    required this.onPick,
  });

  final List<RecentItem> recent;
  final bool rolling;
  final VoidCallback onRoll;
  final ValueChanged<RecentItem> onRepeat;
  final VoidCallback onClearRecent;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        TourAnchor(
          spot: TourSpot.browse,
          child: Row(
            children: [
              Expanded(
                child: AppButton(
                  label: rolling ? 'Sucht…' : 'Zufällig',
                  icon: Icons.shuffle,
                  onPressed: rolling ? null : onRoll,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'Neu',
                  icon: Icons.auto_awesome_outlined,
                  onPressed: () => context.push('/neu'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (recent.isNotEmpty) ...[
          Row(
            children: [
              const Expanded(child: SectionLabel('Zuletzt')),
              Tappable(
                onTap: onClearRecent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 14,
                  ),
                  child: Text(
                    'Leeren',
                    style: TextStyle(fontSize: 12, color: c.fgMuted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in recent)
                WordChip(
                  item.label,
                  muted: item.kind == RecentKind.search,
                  onTap: () => onRepeat(item),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],

        const SectionLabel('Nach Buchstabe'),
        const SizedBox(height: 12),
        GridView.extent(
          maxCrossAxisExtent: 72,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.25,
          children: [
            for (final letter in letters)
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                child: Tappable(
                  onTap: () => onPick(letter),
                  semanticLabel: 'Buchstabe $letter',
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(letter, style: const TextStyle(fontSize: 15)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class NewestScreen extends StatefulWidget {
  const NewestScreen({required this.db, super.key});

  final AppDatabase db;

  @override
  State<NewestScreen> createState() => _NewestScreenState();
}

class _NewestScreenState extends State<NewestScreen> {
  final _cancel = CancelToken();
  List<CachedEntry> _entries = [];
  var _busy = true;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await newestEntries(widget.db, cancel: _cancel);
      if (mounted) setState(() => _entries = rows);
    } on Cancelled {
      return;
    } on Exception {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Neu im Wörterbuch',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: c.border),
        ),
      ),
      body: insetSides(switch (true) {
        _ when _entries.isNotEmpty => EntryListView(
          db: widget.db,
          entries: _entries,
          onOpen: (entry) => context.push('/eintrag/${entry.id}'),
        ),
        _ when _busy => const Note('Lädt…'),
        _ when _failed => const Note(
          'Das hat nicht funktioniert. Prüfe bitte deine Verbindung.',
          problem: true,
        ),
        _ => const Note('Nichts gefunden.'),
      }),
    );
  }
}
