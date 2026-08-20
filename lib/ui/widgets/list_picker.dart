import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/lists.dart';
import '../../packages/manager.dart';
import '../../theme.dart';
import 'pieces.dart';

class ListPicker extends StatefulWidget {
  const ListPicker({required this.db, required this.entryId, super.key});

  final AppDatabase db;
  final int entryId;

  @override
  State<ListPicker> createState() => _ListPickerState();
}

class _ListPickerState extends State<ListPicker> {
  List<StoredList> _lists = [];
  Set<String> _member = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lists = await allLists(widget.db);
    final member = await listsContaining(widget.db, widget.entryId);
    if (mounted) {
      setState(() {
        _lists = lists;
        _member = member;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('In Listen'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final list in _lists)
                _Toggle(
                  label: list.name,
                  on: _member.contains(list.id),
                  onTap: () async {
                    await toggleInList(widget.db, list.id, widget.entryId);
                    await _load();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: on,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: Tappable(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: minTap),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? c.accent : c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (on) ...[
                  Icon(Icons.check, size: 14, color: c.accent),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(fontSize: 14, color: on ? c.accent : c.fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Stream asset rows because downloads finish asynchronously.
class OfflineToggle extends StatefulWidget {
  const OfflineToggle({required this.db, required this.entry, super.key});

  final AppDatabase db;
  final CachedEntry entry;

  @override
  State<OfflineToggle> createState() => _OfflineToggleState();
}

class _OfflineToggleState extends State<OfflineToggle> {
  var _busy = false;

  Future<void> _toggle({required bool saved}) async {
    setState(() => _busy = true);
    if (saved) {
      await downloads.removeDownloads([widget.entry.id]);
    } else {
      await downloads.startPackage(
        EntryPackage(widget.entry.id, widget.entry.word),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoredAsset>>(
      stream: (widget.db.select(
        widget.db.assets,
      )..where((t) => t.entryId.equals(widget.entry.id))).watch(),
      builder: (context, snapshot) {
        final saved = snapshot.data?.isNotEmpty ?? false;
        return AppButton(
          label: saved
              ? 'Offline gespeichert'
              : (_busy ? 'Wird geladen…' : 'Offline speichern'),
          icon: saved ? Icons.download_done : Icons.download_outlined,
          onPressed: _busy && !saved ? null : () => _toggle(saved: saved),
        );
      },
    );
  }
}
