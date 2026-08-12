import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database.dart';
import '../db/recent.dart';
import '../packages/manager.dart';
import '../platform/files.dart';
import '../platform/local.dart';
import '../search/dictionary.dart';
import '../settings.dart';
import '../srs/scheduler.dart';
import '../theme.dart';
import '../transfer/backup.dart';
import '../util/text.dart';
import 'offline_screen.dart';
import 'widgets/entry_list.dart';
import 'widgets/pieces.dart';
import 'widgets/section_dialog.dart';
import 'widgets/stats_panel.dart';

const _themes = [
  (ThemeMode.system, 'System'),
  (ThemeMode.light, 'Hell'),
  (ThemeMode.dark, 'Dunkel'),
];

class MoreScreen extends StatefulWidget {
  const MoreScreen({required this.db, super.key});

  final AppDatabase db;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  var _today = const TodayCount(total: 0, fresh: 0);

  @override
  void initState() {
    super.initState();
    reviewedToday(widget.db).then((count) {
      if (mounted) setState(() => _today = count);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = SettingsScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const SectionLabel('Heute'),
        const SizedBox(height: 6),
        Text(
          '${_today.total} ${_today.total == 1 ? 'Karte' : 'Karten'} beantwortet, '
          'davon ${_today.fresh} neu.',
          style: TextStyle(fontSize: 14, color: c.fgMuted),
        ),
        const SizedBox(height: 24),

        StatsPanel(db: widget.db),
        const SizedBox(height: 24),

        // Without a queue the section would lead nowhere.
        if (downloadsAvailable) ...[
          const SectionLabel('Offline'),
          const SizedBox(height: 8),
          _OfflineLink(db: widget.db),
          const SizedBox(height: 24),
        ],

        const SectionLabel('Darstellung'),
        const SizedBox(height: 8),
        ChoiceRow(
          label: 'Farbschema',
          options: _themes,
          value: settings.themeMode,
          onChanged: settings.setThemeMode,
        ),
        const SizedBox(height: 14),
        _AccentRow(value: settings.accent, onChanged: settings.setAccent),
        const SizedBox(height: 24),

        const SectionLabel('Tageslimits'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: NumberField(
                label: 'Neue Karten',
                value: settings.newPerDay,
                onChanged: (v) => settings.set('newPerDay', v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NumberField(
                label: 'Wiederholungen',
                value: settings.reviewPerDay,
                onChanged: (v) => settings.set('reviewPerDay', v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Wörter, die du achtmal vergessen hast, überspringt der Trainer.',
          style: TextStyle(fontSize: 12, height: 1.5, color: c.fgMuted),
        ),
        const SizedBox(height: 16),
        _Switch(
          label: 'Einträge ohne Video zeigen',
          hint: 'Nicht alle Einträge in SignDict haben bereits ein Video.',
          value: settings.showWithoutVideo,
          onChanged: (v) => settings.set('showWithoutVideo', v),
        ),
        const SizedBox(height: 24),

        const SectionLabel('Daten sichern'),
        const SizedBox(height: 8),
        _Backup(db: widget.db),
        const SizedBox(height: 24),

        const SectionLabel('Verlauf'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Suchverlauf löschen',
            icon: Icons.history,
            onPressed: () async {
              await clearRecent(widget.db);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Verlauf gelöscht.')),
                );
              }
            },
          ),
        ),
        const SizedBox(height: 24),

        const SectionLabel('Über die App'),
        const SizedBox(height: 6),
        Text(
          'Alle Gebärdenvideos stammen von SignDict und stehen unter '
          'Creative-Commons-Lizenzen. Rechteinhaber und Lizenz siehst du unter jedem '
          'Video. Diese App ist kein Angebot von SignDict.',
          style: TextStyle(fontSize: 13, height: 1.6, color: c.fgMuted),
        ),
        const SizedBox(height: 8),
        const LinkText(label: 'signdict.org', url: 'https://signdict.org'),
      ],
    );
  }
}

class _AccentRow extends StatelessWidget {
  const _AccentRow({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  Widget _swatch(BuildContext context, Color color, String label, bool active) {
    final c = context.colors;
    return Tappable(
      onTap: () => onChanged(color.toARGB32()),
      semanticLabel: label,
      child: Container(
        width: minTap,
        height: minTap,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? c.fg : c.border,
            width: active ? 2 : 1,
          ),
        ),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => _AccentDialog(value: value),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final known = suggestedAccents.map((a) => a.$1).toSet();

    return Semantics(
      label: 'Akzentfarbe',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (color, label) in suggestedAccents)
            _swatch(context, Color(color), label, color == value),
          Tappable(
            onTap: () => _pick(context),
            semanticLabel: 'Eigene Farbe',
            child: Container(
              width: minTap,
              height: minTap,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: known.contains(value) ? c.border : c.fg,
                  width: known.contains(value) ? 1 : 2,
                ),
              ),
              child: Icon(Icons.colorize_outlined, size: 18, color: c.fgMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentDialog extends StatefulWidget {
  const _AccentDialog({required this.value});

  final int value;

  @override
  State<_AccentDialog> createState() => _AccentDialogState();
}

class _AccentDialogState extends State<_AccentDialog> {
  late var _color = Color(widget.value);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AlertDialog(
      backgroundColor: c.surface,
      title: const Text('Akzentfarbe'),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: _color,
          onColorChanged: (color) => setState(() => _color = color),
          enableAlpha: false,
          labelTypes: const [ColorLabelType.hsl],
          pickerAreaBorderRadius: BorderRadius.circular(4),
          portraitOnly: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _color.toARGB32()),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              Text(
                hint,
                style: TextStyle(fontSize: 12, height: 1.5, color: c.fgMuted),
              ),
            ],
          ),
        ),
        Switch(value: value, activeThumbColor: c.accent, onChanged: onChanged),
      ],
    );
  }
}

class LetterScreen extends StatefulWidget {
  const LetterScreen({required this.db, required this.letter, super.key});

  final AppDatabase db;
  final String letter;

  @override
  State<LetterScreen> createState() => _LetterScreenState();
}

class _LetterScreenState extends State<LetterScreen> {
  List<CachedEntry> _entries = [];
  var _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await cachedLetter(widget.db, widget.letter);
    if (mounted && cached.isNotEmpty) setState(() => _entries = cached);

    try {
      final live = await liveLetter(widget.db, widget.letter);
      if (mounted) setState(() => _entries = live);
    } on Exception {
      // The cache is already on screen.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = SettingsScope.of(context);
    final rows = settings.showWithoutVideo
        ? _entries
        : _entries.where((e) => e.hasVideo).toList();

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.letter,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: c.border),
        ),
      ),
      body: rows.isEmpty
          ? Note(_busy ? 'Lädt…' : 'Nichts gefunden.')
          : EntryListView(
              db: widget.db,
              entries: rows,
              onOpen: (entry) => context.push('/eintrag/${entry.id}'),
            ),
    );
  }
}

class _OfflineLink extends StatelessWidget {
  const _OfflineLink({required this.db});

  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return StreamBuilder<List<StoredAsset>>(
      stream: db.select(db.assets).watch(),
      builder: (context, snapshot) {
        final assets = snapshot.data ?? const <StoredAsset>[];
        final bytes = assets.fold(0, (sum, a) => sum + a.bytes);
        final entries = assets.map((a) => a.entryId).toSet().length;

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: Tappable(
            onTap: () => context.push('/offline'),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.download_outlined, size: 18, color: c.fgMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Gebärden herunterladen'),
                        Text(
                          bytes == 0
                              ? 'Nichts gespeichert'
                              : '$entries ${entries == 1 ? 'Gebärde' : 'Gebärden'}, '
                                    '${formatBytes(bytes)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: c.fgMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Backup extends StatefulWidget {
  const _Backup({required this.db});

  final AppDatabase db;

  @override
  State<_Backup> createState() => _BackupState();
}

class _BackupState extends State<_Backup> {
  var _busy = false;
  String? _note;

  Future<void> _export() async {
    final choice = await pickSections(
      context,
      title: 'Was soll exportiert werden?',
      action: 'Exportieren',
    );
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final text = await exportBackup(widget.db, sections: choice.sections);
      final file = await textFile(backupFileName(DateTime.now()), text);
      await SharePlus.instance.share(
        ShareParams(files: [file], subject: 'DGS Lernen Sicherung'),
      );
    } on Exception {
      if (mounted) {
        setState(() => _note = 'Die Sicherung hat nicht funktioniert.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Sicherung',
          extensions: [backupExtension],
          uniformTypeIdentifiers: [backupUti],
        ),
      ],
    );
    if (file == null) return;

    final text = await readText(file);
    final Set<BackupSection> offered;
    try {
      offered = sectionsIn(text);
    } on BackupError catch (e) {
      if (mounted) setState(() => _note = e.message);
      return;
    }
    if (!mounted) return;

    final choice = await pickSections(
      context,
      title: 'Was soll importiert werden?',
      action: 'Importieren',
      offered: offered,
      withMode: true,
    );
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final summary = await importBackup(
        widget.db,
        text,
        choice.mode,
        sections: choice.sections,
      );
      var note =
          '${count(summary.cards, 'Karte', 'Karten')}, '
          '${count(summary.reviews, 'Antwort', 'Antworten')} und '
          '${count(summary.lists, 'Liste', 'Listen')} importiert.';

      // Progress points at entry ids, so the words have to come back too.
      try {
        final fetched = await restoreEntries(widget.db);
        if (fetched > 0) {
          note += ' ${count(fetched, 'Wort', 'Wörter')} importiert.';
        }
      } on Exception {
        note +=
            ' Die Wörter werden geladen, sobald eine Internetverbindung besteht.';
      }
      if (mounted) setState(() => _note = note);
    } on BackupError catch (e) {
      if (mounted) setState(() => _note = e.message);
    } on Exception {
      if (mounted) {
        setState(() => _note = 'Die Sicherung konnte nicht gelesen werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppButton(
              label: 'Exportieren',
              icon: Icons.upload_outlined,
              onPressed: _busy ? null : _export,
            ),
            const SizedBox(width: 8),
            AppButton(
              label: 'Importieren',
              icon: Icons.download_outlined,
              onPressed: _busy ? null : _import,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Du kannst auswählen, was exportiert bzw. importiert werden soll.',
          style: TextStyle(fontSize: 12, height: 1.5, color: c.fgMuted),
        ),
        if (_note != null) ...[
          const SizedBox(height: 8),
          Text(_note!, style: TextStyle(fontSize: 12, color: c.fgMuted)),
        ],
      ],
    );
  }
}
