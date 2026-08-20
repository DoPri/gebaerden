import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database.dart';
import '../db/lists.dart';
import '../db/repo.dart';
import '../platform/files.dart';
import '../platform/local.dart';
import '../theme.dart';
import '../topics.dart';
import '../transfer/list_file.dart';
import 'tour.dart';
import 'widgets/entry_list.dart';
import 'widgets/pieces.dart';
import 'widgets/reminder_panel.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({required this.db, super.key});

  final AppDatabase db;

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  List<StoredList> _lists = [];
  Map<String, int> _counts = {};
  String? _pulling;
  var _adding = false;
  final _draft = TextEditingController();
  StreamSubscription<void>? _watch;

  @override
  void initState() {
    super.initState();
    _load();
    // Detail screen mutations affect list counts and names.
    _watch = widget.db
        .tableUpdates(
          TableUpdateQuery.onAllTables([widget.db.lists, widget.db.listItems]),
        )
        .listen((_) => _load());
  }

  @override
  void dispose() {
    _watch?.cancel();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lists = await allLists(widget.db);
    final counts = await listCounts(widget.db);
    if (mounted) {
      setState(() {
        _lists = lists;
        _counts = counts;
      });
    }
  }

  Future<void> _create() async {
    if (_draft.text.trim().isEmpty) return;
    await createList(widget.db, _draft.text);
    _draft.clear();
    setState(() => _adding = false);
    await _load();
  }

  Future<void> _pull(Topic topic) async {
    setState(() => _pulling = topic.name);
    try {
      await importTopic(widget.db, topic);
      await _load();
    } on Exception {
      if (mounted) {
        await _tell(
          context,
          'Das Thema konnte nicht geladen werden. Prüfe bitte deine Verbindung.',
        );
      }
    } finally {
      if (mounted) setState(() => _pulling = null);
    }
  }

  Future<void> _openFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Gebärden-Liste',
          extensions: [listExtension],
          uniformTypeIdentifiers: [listUti],
        ),
      ],
    );
    if (file == null) return;
    final text = await readText(file);
    if (!mounted) return;
    await receiveListFile(context, widget.db, text);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return ListView(
      children: [
        TourAnchor(
          spot: TourSpot.lists,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(child: SectionLabel('Deine Listen')),
                IconButton(
                  icon: const Icon(Icons.file_open_outlined, size: 19),
                  color: c.fgMuted,
                  tooltip: 'Geteilte Liste öffnen',
                  onPressed: _openFile,
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 21),
                  color: c.accent,
                  tooltip: 'Neue Liste',
                  onPressed: () => setState(() => _adding = !_adding),
                ),
              ],
            ),
          ),
        ),
        if (_adding)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _draft,
                    autofocus: true,
                    onSubmitted: (_) => _create(),
                    decoration: const InputDecoration(
                      hintText: 'Name der Liste',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(label: 'Anlegen', filled: true, onPressed: _create),
              ],
            ),
          ),
        for (final list in _lists) ...[
          const HairLine(),
          Tappable(
            onTap: () => context.push('/listen/${list.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(child: Text(list.name)),
                  Text(
                    '${_counts[list.id] ?? 0}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, size: 16, color: c.fgMuted),
                ],
              ),
            ),
          ),
        ],
        const HairLine(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Themen zum Einstieg'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final topic in topics)
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      child: Tappable(
                        onTap: _pulling == null ? () => _pull(topic) : null,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: minTap),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: c.border),
                          ),
                          child: Text(
                            _pulling == topic.name ? 'Lädt…' : topic.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Jedes Thema legt eine fertige Liste an.',
                style: TextStyle(fontSize: 12, height: 1.5, color: c.fgMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> receiveListFile(
  BuildContext context,
  AppDatabase db,
  String text,
) async {
  SharedList shared;
  try {
    shared = parseListFile(text);
  } on ListFileError catch (err) {
    if (context.mounted) await _tell(context, err.message);
    return;
  }

  if (!context.mounted) {
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.colors.surface,
      title: Text(shared.name),
      content: Text(
        '${shared.entries.length} ${shared.entries.length == 1 ? 'Wort' : 'Wörter'}. '
        'Als neue Liste übernehmen?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Übernehmen'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  await importSharedList(db, shared);
  if (context.mounted) {
    await _tell(context, 'Liste »${shared.name}« übernommen.');
  }
}

Future<void> _tell(BuildContext context, String message) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> openSharedPath(
  BuildContext context,
  AppDatabase db,
  String path,
) async {
  if (!localExists(path)) return;
  final text = await readText(XFile(path));
  if (!context.mounted) return;
  await receiveListFile(context, db, text);
}

Future<void> shareList(AppDatabase db, StoredList list) async {
  final text = await encodeList(db, list);
  final file = await textFile(listFileName(list.name), text);

  await SharePlus.instance.share(
    ShareParams(files: [file], subject: list.name),
  );
}

class ListScreen extends StatefulWidget {
  const ListScreen({required this.db, required this.id, super.key});

  final AppDatabase db;
  final String id;

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  StoredList? _list;
  List<CachedEntry> _entries = [];
  StreamSubscription<void>? _watch;

  @override
  void initState() {
    super.initState();
    _load();
    _watch = widget.db
        .tableUpdates(
          TableUpdateQuery.onAllTables([widget.db.lists, widget.db.listItems]),
        )
        .listen((_) => _load());
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final lists = await allLists(widget.db);
    final list = lists.where((l) => l.id == widget.id).firstOrNull;
    final entries = list == null
        ? <CachedEntry>[]
        : await getEntries(widget.db, await listEntryIds(widget.db, widget.id));
    if (mounted) {
      setState(() {
        _list = list;
        _entries = entries;
      });
    }
  }

  Future<void> _rename() async {
    final list = _list;
    if (list == null) return;
    final name = await _ask(context, 'Liste umbenennen', list.name);
    if (name == null) return;
    await renameList(widget.db, widget.id, name);
    await _load();
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      context,
      'Liste löschen',
      'Die Wörter selbst bleiben im Wörterbuch erhalten.',
    );
    if (ok != true) return;
    await deleteList(widget.db, widget.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _list;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          list?.name ?? '…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          if (list != null) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 19),
              color: c.fgMuted,
              tooltip: 'Liste teilen',
              onPressed: () => shareList(widget.db, list),
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              color: c.fgMuted,
              tooltip: 'Liste duplizieren',
              onPressed: () async {
                final copy = await duplicateList(
                  widget.db,
                  widget.id,
                  '${list.name} (Kopie)',
                );
                if (copy != null && context.mounted) {
                  context.pushReplacement('/listen/${copy.id}');
                }
              },
            ),
            if (!isSystem(list)) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: c.fgMuted,
                tooltip: 'Liste umbenennen',
                onPressed: _rename,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 19),
                color: c.danger,
                tooltip: 'Liste löschen',
                onPressed: _delete,
              ),
            ],
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: c.border),
        ),
      ),
      // Reminders are scoped to the list itself, independent of entry count.
      body: insetSides(
        Column(
          children: [
            if (_entries.any((e) => e.hasVideo)) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    label: 'Diese Liste lernen',
                    icon: Icons.school_outlined,
                    filled: true,
                    // Use go() to switch tab branch instead of pushing onto current stack.
                    onPressed: () => context.go('/lernen?liste=${widget.id}'),
                  ),
                ),
              ),
              const HairLine(),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Erinnerungen'),
                  const SizedBox(height: 8),
                  ReminderPanel(db: widget.db, listId: widget.id),
                ],
              ),
            ),
            const HairLine(),
            if (_entries.isEmpty)
              const Expanded(
                child: Note(
                  'Noch keine Wörter. Öffne eine Gebärde im Wörterbuch und '
                  'füge sie zu einer Liste hinzu.',
                ),
              )
            else
              Expanded(
                child: EntryListView(
                  db: widget.db,
                  entries: _entries,
                  onOpen: (entry) => context.push('/eintrag/${entry.id}'),
                  trailing: (entry) => IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: c.fgMuted,
                    tooltip: '${entry.word} aus der Liste entfernen',
                    onPressed: () async {
                      await removeFromList(widget.db, widget.id, [entry.id]);
                      await _load();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _ask(BuildContext context, String title, String initial) {
  return showDialog<String>(
    context: context,
    builder: (context) => _AskDialog(title: title, initial: initial),
  );
}

// State owns controller to outlive dialog dismiss animation.
class _AskDialog extends StatefulWidget {
  const _AskDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface,
      title: Text(widget.title),
      content: TextField(
        controller: _field,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _field.text),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

Future<bool?> _confirm(BuildContext context, String title, String body) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.colors.surface,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Löschen',
            style: TextStyle(color: context.colors.danger),
          ),
        ),
      ],
    ),
  );
}
