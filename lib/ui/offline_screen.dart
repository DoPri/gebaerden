// drift also exports Column and Table, which mean widgets here.
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';

import '../api/queries.dart';
import '../db/database.dart';
import '../db/lists.dart';
import '../packages/manager.dart';
import '../theme.dart';
import 'widgets/pieces.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}

class OfflineScreen extends StatefulWidget {
  const OfflineScreen({required this.db, super.key});

  final AppDatabase db;

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  List<StoredList> _lists = [];

  @override
  void initState() {
    super.initState();
    allLists(widget.db).then((lists) {
      if (mounted) setState(() => _lists = lists);
    });
  }

  Future<void> _clear() async {
    final entryIds = (await widget.db.select(widget.db.assets).get())
        .map((a) => a.entryId)
        .toSet()
        .toList();
    await downloads.removeDownloads(entryIds);
    await widget.db.delete(widget.db.packages).go();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Offline', style: Theme.of(context).textTheme.titleMedium),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: c.border),
        ),
      ),
      body: insetSides(_body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;

    return StreamBuilder<List<StoredAsset>>(
      stream: widget.db.select(widget.db.assets).watch(),
      builder: (context, snapshot) {
        final assets = snapshot.data ?? const <StoredAsset>[];
        final bytes = assets.fold(0, (sum, a) => sum + a.bytes);
        final entries = assets.map((a) => a.entryId).toSet().length;

        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatBytes(bytes),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          '$entries ${entries == 1 ? 'Gebärde' : 'Gebärden'} offline verfügbar',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (bytes > 0)
                    AppButton(
                      label: 'Leeren',
                      icon: Icons.delete_outline,
                      danger: true,
                      onPressed: _clear,
                    ),
                ],
              ),
            ),
            const HairLine(),
            _Jobs(db: widget.db),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Pakete'),
                  const SizedBox(height: 6),
                  Text(
                    'Der Download läuft weiter, auch wenn du die App schließt.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: c.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
            _Package(
              label: 'Alle Gebärden',
              hint: 'Circa 4.000 Stück, etwa 450 MB.',
              onTap: () => downloads.startPackage(const AllPackage()),
            ),
            for (final list in _lists)
              _Package(
                label: list.name,
                onTap: () =>
                    downloads.startPackage(ListPackage(list.id, list.name)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: const SectionLabel('Nach Buchstabe'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final letter in letters)
                    SizedBox(
                      width: 52,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        child: Tappable(
                          onTap: () =>
                              downloads.startPackage(LetterPackage(letter)),
                          semanticLabel: 'Buchstabe $letter herunterladen',
                          child: Container(
                            constraints: const BoxConstraints(
                              minHeight: minTap,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: c.border),
                            ),
                            child: Text(letter),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Jobs extends StatelessWidget {
  const _Jobs({required this.db});

  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return StreamBuilder<List<StoredPackage>>(
      // error belongs here too. Without it, a package that lost a file dropped
      // out of the list and looked as if the download had simply stopped,
      // with no way left to send it off again.
      stream:
          (db.select(db.packages)..where(
                (t) =>
                    t.status.equalsValue(PackageStatus.running) |
                    t.status.equalsValue(PackageStatus.paused) |
                    t.status.equalsValue(PackageStatus.queued) |
                    t.status.equalsValue(PackageStatus.error),
              ))
              .watch(),
      builder: (context, snapshot) {
        final jobs = snapshot.data ?? const <StoredPackage>[];
        if (jobs.isEmpty) return const SizedBox.shrink();

        return Column(
          children: [
            for (final job in jobs) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            job.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          job.total > 0 ? '${job.done} / ${job.total}' : '…',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (job.status == PackageStatus.running)
                          IconButton(
                            icon: const Icon(Icons.pause, size: 18),
                            color: c.fgMuted,
                            tooltip: 'Pausieren',
                            onPressed: () => downloads.pausePackage(job.id),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.play_arrow, size: 18),
                            color: c.accent,
                            tooltip: 'Fortsetzen',
                            onPressed: () => downloads.resumePackage(job),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: c.fgMuted,
                          tooltip: 'Abbrechen',
                          onPressed: () => downloads.cancelPackage(job.id),
                        ),
                      ],
                    ),
                    if (job.error case final reason?)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          reason,
                          style: TextStyle(fontSize: 12, color: c.fgMuted),
                        ),
                      ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: job.total > 0 ? job.done / job.total : null,
                        minHeight: 4,
                        backgroundColor: c.surface2,
                      ),
                    ),
                  ],
                ),
              ),
              const HairLine(),
            ],
          ],
        );
      },
    );
  }
}

class _Package extends StatelessWidget {
  const _Package({required this.label, required this.onTap, this.hint});

  final String label;
  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: Tappable(
          onTap: onTap,
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
                      Text(label),
                      if (hint != null)
                        Text(
                          hint!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
