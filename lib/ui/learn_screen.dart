import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fsrs/fsrs.dart' as f;
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/lists.dart';
import '../db/repo.dart';
import '../media/variants.dart';
import '../settings.dart';
import '../srs/scheduler.dart';
import '../theme.dart';
import 'cards.dart';
import 'tour.dart';
import 'widgets/pieces.dart';

const _modes = [
  (ReviewMode.self, 'Selbst'),
  (ReviewMode.choice, 'Auswahl'),
  (ReviewMode.typing, 'Tippen'),
];

const _directions = [
  (DirectionMode.recognition, 'Gebärde → Wort'),
  (DirectionMode.production, 'Wort → Gebärde'),
  (DirectionMode.both, 'Beides'),
];

const _directionHints = {
  DirectionMode.recognition: 'Du siehst die Gebärde und nennst das Wort.',
  DirectionMode.production:
      'Du liest das Wort und gebärdest es. Hier schätzt du dich immer selbst ein.',
  DirectionMode.both: 'Jedes Wort wird in beide Richtungen abgefragt.',
};

const _modeHints = {
  ReviewMode.self:
      'Du siehst die Auflösung und schätzt selbst ein, wie gut du sie wusstest.',
  ReviewMode.choice:
      'Multiple Choice mit vier Antworten. Bei Wort → Gebärde nutzt du weiter Selbsteinschätzung.',
  ReviewMode.typing: 'Tippe das Wort frei ein.',
};

class LearnScreen extends StatefulWidget {
  const LearnScreen({required this.db, this.listId, super.key});

  final AppDatabase db;
  final String? listId;

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  List<StoredCard> _queue = [];
  Map<int, CachedEntry> _entries = {};
  Map<int, ApiVideo> _videos = {};
  List<CachedEntry> _pool = [];
  List<StoredList> _lists = [];
  var _seen = 0;
  var _running = false;
  var _due = 0;
  var _fresh = 0;

  /// Shuts the answer buttons out while a card is being written away.
  var _writing = false;

  StoredCard? get _card => _queue.isEmpty ? null : _queue.first;

  var _loaded = false;

  StreamSubscription<int>? _writes;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    allLists(widget.db).then((lists) {
      if (mounted) setState(() => _lists = lists);
    });

    // On a fresh install, the dictionary only arrives once the app is up in
    // the background. This tab has counted by then and without listening it
    // would keep showing the zero.
    _writes = entryWrites.listen((_) {
      // The index comes in about fifty batches and rebuilding the deck for
      // each of them would read the whole cache that many times. Let the burst
      // settle first.
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 400), () {
        if (mounted && !_running) _preview();
      });
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    unawaited(_writes?.cancel());
    super.dispose();
  }

  @override
  void didUpdateWidget(LearnScreen old) {
    super.didUpdateWidget(old);
    // Switching the scope keeps this State and only swaps the widget, so
    // nothing else would recount and the old numbers would stay on screen.
    if (old.listId != widget.listId) unawaited(_preview());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The deck depends on the settings, which initState may not read yet.
    if (_loaded) return;
    _loaded = true;
    _preview();
  }

  Future<List<int>?> _scope() async =>
      widget.listId == null ? null : listEntryIds(widget.db, widget.listId!);

  /// The list being learned, once its row has arrived. Null means all words.
  StoredList? get _list =>
      _lists.where((l) => l.id == widget.listId).firstOrNull;

  /// A list carries its own budget, so a day spent on one leaves the next one
  /// untouched. Without its own it falls back to the global setting.
  int _newPerDay(AppSettings settings) =>
      _list?.newPerDay ?? settings.newPerDay;

  int _reviewPerDay(AppSettings settings) =>
      _list?.reviewPerDay ?? settings.reviewPerDay;

  Future<void> _setLimits({int? newPerDay, int? reviewPerDay}) async {
    final id = widget.listId;
    if (id == null) return;
    await setListLimits(
      widget.db,
      id,
      newPerDay: newPerDay,
      reviewPerDay: reviewPerDay,
    );
    final lists = await allLists(widget.db);
    if (mounted) setState(() => _lists = lists);
  }

  Future<void> _clearLimits() async {
    final id = widget.listId;
    if (id == null) return;
    await clearListLimits(widget.db, id);
    final lists = await allLists(widget.db);
    if (mounted) setState(() => _lists = lists);
  }

  Future<void> _preview() async {
    final settings = SettingsScope.of(context);
    final deck = await buildDeck(
      widget.db,
      DeckOptions(
        entryIds: await _scope(),
        directions: settings.directions,
        newLimit: 0,
        reviewLimit: 0,
      ),
    );
    if (mounted) {
      setState(() {
        _due = deck.dueCount;
        _fresh = deck.newCount;
      });
    }
  }

  Future<void> _start() async {
    final settings = SettingsScope.of(context);
    final scope = await _scope();
    final today = await reviewedToday(widget.db, entryIds: scope);

    final deck = await buildDeck(
      widget.db,
      DeckOptions(
        entryIds: scope,
        directions: settings.directions,
        newLimit: (_newPerDay(settings) - today.fresh).clamp(0, 9999),
        reviewLimit: (_reviewPerDay(settings) - (today.total - today.fresh))
            .clamp(0, 9999),
      ),
    );

    final rows = await getEntries(
      widget.db,
      deck.cards.map((c) => c.entryId).toSet().toList(),
    );
    final videos = await preferredVideos(widget.db, rows);

    // A short deck cannot supply its own distractors.
    final pool = rows.length >= 12
        ? rows
        : await (widget.db.select(widget.db.entries)
                ..where((t) => t.hasVideo.equals(true))
                ..limit(60))
              .get();

    if (!mounted) return;
    setState(() {
      _entries = {for (final row in rows) row.id: row};
      _videos = videos;
      _pool = pool;
      _queue = deck.cards;
      _seen = 0;
      _running = true;
    });
  }

  Future<void> _answer(f.Rating rating) async {
    final card = _card;
    // One answer at a time. A second tap while the write is still running would
    // grade the same card twice and drop the next one unseen.
    if (card == null || _writing) return;
    _writing = true;

    // A forgotten word gets the heavier bump.
    unawaited(
      rating == f.Rating.again
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.lightImpact(),
    );
    final StoredCard graded;
    try {
      graded = await gradeCard(widget.db, card, rating);
    } finally {
      _writing = false;
    }
    final rest = _queue.skip(1).toList();
    if (!mounted) return;

    setState(() {
      _seen++;
      // Again puts the card back into this session.
      _queue = rating == f.Rating.again ? [...rest, graded] : rest;
      if (_queue.isEmpty) _running = false;
    });
    if (_queue.isEmpty) await _preview();
  }

  Future<void> _undo() async {
    final restored = await undoLast(widget.db);
    if (restored == null || !mounted) return;
    setState(() {
      _queue = [restored, ..._queue.where((c) => c.id != restored.id)];
      _seen = (_seen - 1).clamp(0, 9999);
      _running = true;
    });
  }

  Future<void> _markKnown() async {
    final card = _card;
    if (card == null || _writing) return;
    _writing = true;
    try {
      await addToList(widget.db, knownList, [card.entryId]);
    } finally {
      _writing = false;
    }
    if (!mounted) return;

    setState(() {
      _queue = _queue.where((c) => c.entryId != card.entryId).toList();
      if (_queue.isEmpty) _running = false;
    });
    if (_queue.isEmpty) await _preview();
  }

  @override
  Widget build(BuildContext context) {
    return _running ? _session(context) : _lobby(context);
  }

  Widget _lobby(BuildContext context) {
    final c = context.colors;
    final settings = SettingsScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_seen > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$_seen ${_seen == 1 ? 'Karte' : 'Karten'} gelernt.',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.undo, size: 18),
                  color: c.fgMuted,
                  tooltip: 'Letzte Antwort zurücknehmen',
                  onPressed: _undo,
                ),
              ],
            ),
          ),
        if (_lists.isNotEmpty) ...[
          const SectionLabel('Umfang'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Link(
                label: 'Alle Wörter',
                to: '/lernen',
                small: true,
                replace: true,
                selected: widget.listId == null,
              ),
              for (final list in _lists)
                _Link(
                  label: list.name,
                  to: '/lernen?liste=${list.id}',
                  small: true,
                  replace: true,
                  selected: list.id == widget.listId,
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        TourAnchor(
          spot: TourSpot.counts,
          child: Row(
            children: [
              _Count(label: 'Fällig', value: _due),
              const SizedBox(width: 28),
              _Count(label: 'Neu', value: _fresh),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionLabel('Abfrage'),
        const SizedBox(height: 8),
        TourAnchor(
          spot: TourSpot.review,
          child: ChoiceRow(
            label: 'Abfrageart',
            options: _modes,
            value: settings.mode,
            onChanged: (mode) => settings.set('mode', mode.name),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _modeHints[settings.mode]!,
          style: TextStyle(fontSize: 12, height: 1.5, color: c.fgMuted),
        ),
        const SizedBox(height: 20),
        const SectionLabel('Richtung'),
        const SizedBox(height: 8),
        ChoiceRow(
          label: 'Abfragerichtung',
          options: _directions,
          value: settings.direction,
          onChanged: (direction) async {
            await settings.set('direction', direction.name);
            await _preview();
          },
        ),
        const SizedBox(height: 6),
        Text(
          _directionHints[settings.direction]!,
          style: TextStyle(fontSize: 12, height: 1.5, color: c.fgMuted),
        ),
        const SizedBox(height: 22),
        if (_due + _fresh > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Loslegen',
              icon: Icons.school_outlined,
              filled: true,
              onPressed: _start,
            ),
          )
        else
          Text(
            'Hier ist gerade nichts fällig. Hinweis: Der Trainer nimmt nur Wörter, zu denen es auch ein Video gibt.',
            style: TextStyle(fontSize: 14, height: 1.5, color: c.fgMuted),
          ),
        if (_list != null) ...[
          const SizedBox(height: 28),
          const SectionLabel('Tageslimits dieser Liste'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: NumberField(
                  key: ValueKey('neu-${_list!.id}-${_list!.newPerDay}'),
                  label: 'Neue Karten',
                  value: _newPerDay(settings),
                  onChanged: (v) => _setLimits(newPerDay: v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NumberField(
                  key: ValueKey('wdh-${_list!.id}-${_list!.reviewPerDay}'),
                  label: 'Wiederholungen',
                  value: _reviewPerDay(settings),
                  onChanged: (v) => _setLimits(reviewPerDay: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Gilt nur für diese Liste.',
            style: TextStyle(fontSize: 12, height: 1.5, color: c.fgMuted),
          ),
          if (_list!.newPerDay != null || _list!.reviewPerDay != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Vorgabe verwenden',
                icon: Icons.settings_backup_restore,
                onPressed: _clearLimits,
              ),
            ),
          ],
        ],
        const SizedBox(height: 28),
        const SectionLabel('Weitere Übungen'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Link(label: 'Fingeralphabet', to: '/fingeralphabet'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Link(label: 'Zahlen', to: '/zahlen'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _session(BuildContext context) {
    final c = context.colors;
    final settings = SettingsScope.of(context);
    final card = _card;
    final entry = card == null ? null : _entries[card.entryId];
    if (card == null || entry == null) return const SizedBox.shrink();

    final props = CardProps(
      db: widget.db,
      entry: entry,
      card: card,
      video: _videos[entry.id],
      pool: _pool,
      onAnswer: _answer,
    );

    // Choice and typing need a written answer, which only recognition has.
    // The seen counter is part of the key. So, a card answered wrong comes back
    // as the same id and without a fresh state it would stay locked in its
    // answered shape.
    final body =
        card.direction == Direction.production ||
            settings.mode == ReviewMode.self
        ? SelfRatedCard(props, key: ValueKey('${card.id}:$_seen'))
        : settings.mode == ReviewMode.choice
        ? ChoiceCard(props, key: ValueKey('${card.id}:$_seen'))
        : TypingCard(props, key: ValueKey('${card.id}:$_seen'));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_queue.length} übrig',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.undo, size: 18),
                color: c.fgMuted,
                tooltip: 'Letzte Antwort zurücknehmen',
                onPressed: _seen == 0 ? null : _undo,
              ),
              IconButton(
                icon: const Icon(Icons.done_all, size: 18),
                color: c.fgMuted,
                tooltip: 'Kenne ich schon',
                onPressed: _markKnown,
              ),
              TextButton(
                onPressed: () async {
                  setState(() => _running = false);
                  await _preview();
                },
                child: Text('Beenden', style: TextStyle(color: c.fgMuted)),
              ),
            ],
          ),
        ),
        const HairLine(),
        Expanded(child: body),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        Text('$value', style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({
    required this.label,
    required this.to,
    this.small = false,
    this.selected = false,
    this.replace = false,
  });

  final String label;
  final String to;
  final bool small;
  final bool selected;

  /// Scope chips swap the branch instead of stacking another lobby on it.
  final bool replace;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(small ? 999 : 4),
      child: Tappable(
        onTap: () => replace ? context.go(to) : context.push(to),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: small ? 12 : 16,
            vertical: small ? 7 : 13,
          ),
          // A chip in the Wrap has to shrink to its word. With an alignment a
          // Container fills the width it is offered instead.
          alignment: small ? null : Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(small ? 999 : 4),
            border: Border.all(color: selected ? c.accent : c.border),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: selected ? c.accent : null),
          ),
        ),
      ),
    );
  }
}
