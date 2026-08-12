import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../transfer/backup.dart';
import 'pieces.dart';

const sectionNames = {
  BackupSection.lists: 'Listen und Wörter',
  BackupSection.progress: 'Lernstand und Verlauf',
  BackupSection.settings: 'Einstellungen',
  BackupSection.reminders: 'Erinnerungen',
};

/// What an export writes or what an import takes reads. On the way back the
/// picker only offers what the file actually holds, and the mode row comes
/// with it.
class SectionChoice {
  const SectionChoice(this.sections, this.mode);

  final Set<BackupSection> sections;
  final ImportMode mode;
}

const _modes = [
  (ImportMode.merge, 'Zusammenführen'),
  (ImportMode.replace, 'Ersetzen'),
];

Future<SectionChoice?> pickSections(
  BuildContext context, {
  required String title,
  required String action,
  Set<BackupSection> offered = const {...BackupSection.values},
  bool withMode = false,
}) => showDialog<SectionChoice>(
  context: context,
  builder: (context) => _SectionDialog(
    title: title,
    action: action,
    offered: offered,
    withMode: withMode,
  ),
);

class _SectionDialog extends StatefulWidget {
  const _SectionDialog({
    required this.title,
    required this.action,
    required this.offered,
    required this.withMode,
  });

  final String title;
  final String action;
  final Set<BackupSection> offered;
  final bool withMode;

  @override
  State<_SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends State<_SectionDialog> {
  late final Set<BackupSection> _picked = {...widget.offered};
  var _mode = ImportMode.merge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final section in BackupSection.values)
            if (widget.offered.contains(section))
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(sectionNames[section]!),
                value: _picked.contains(section),
                onChanged: (on) => setState(
                  () => on ?? false
                      ? _picked.add(section)
                      : _picked.remove(section),
                ),
              ),
          if (widget.withMode) ...[
            const SizedBox(height: 12),
            ChoiceRow(
              label: 'Beim Importieren',
              options: _modes,
              value: _mode,
              onChanged: (v) => setState(() => _mode = v),
            ),
            const SizedBox(height: 6),
            Text(
              'Zusammenführen behält bei jedem Wort den weiteren Stand. '
              'Ersetzen verwirft den Stand auf diesem Gerät.',
              style: TextStyle(fontSize: 12, height: 1.5, color: c.fgMuted),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(context, SectionChoice(_picked, _mode)),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
