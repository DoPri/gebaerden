import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../db/reminders.dart';
import '../../platform/notify.dart';
import '../../settings.dart';
import '../../theme.dart';
import 'pieces.dart';

/// The reminders of one list. A reminder belongs to exactly one list.
class ReminderPanel extends StatefulWidget {
  const ReminderPanel({required this.db, required this.listId, super.key});

  final AppDatabase db;
  final String listId;

  @override
  State<ReminderPanel> createState() => _ReminderPanelState();
}

class _ReminderPanelState extends State<ReminderPanel> {
  List<ScopedReminder> _reminders = [];
  String? _note;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final rows = await remindersFor(widget.db, widget.listId);
    if (mounted) setState(() => _reminders = rows);
  }

  /// Every alarm on the device is rewritten, not just this list's. They share
  /// one run of ids and scheduling only part of them would drop the rest.
  Future<void> _apply({bool ask = true}) async {
    await _load();
    if (!mounted) return;

    final due = await dueReminders(
      widget.db,
      SettingsScope.of(context).directions,
    );
    if (due.isEmpty) {
      await cancelReminders();
      if (mounted) setState(() => _note = null);
      return;
    }

    // Only a fresh reminder may prompt. Editing one must not re-ask.
    var ok = true;
    if (ask) {
      ok = await scheduleReminders(due);
    } else {
      await refreshReminders(due);
    }
    if (mounted) {
      setState(
        () => _note = ok
            ? null
            : 'Die Benachrichtigungen müssen für diese App erlaubt werden.',
      );
    }
  }

  Future<void> _add() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
    );
    if (picked == null) return;

    await addReminder(
      widget.db,
      widget.listId,
      Reminder(
        days: const {1, 2, 3, 4, 5, 6, 7},
        hour: picked.hour,
        minute: picked.minute,
      ),
    );
    await _apply();
  }

  Future<void> _time(ScopedReminder scoped) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: scoped.reminder.hour,
        minute: scoped.reminder.minute,
      ),
    );
    if (picked == null) return;

    await setReminder(
      widget.db,
      scoped.id,
      scoped.reminder.copyWith(hour: picked.hour, minute: picked.minute),
    );
    await _apply(ask: false);
  }

  Future<void> _toggle(ScopedReminder scoped, int day) async {
    final days = {...scoped.reminder.days};
    if (!days.remove(day)) days.add(day);
    // The last day cannot go, an alarm without a day never fires.
    if (days.isEmpty) return;

    await setReminder(
      widget.db,
      scoped.id,
      scoped.reminder.copyWith(days: days),
    );
    await _apply(ask: false);
  }

  Future<void> _remove(ScopedReminder scoped) async {
    await removeReminder(widget.db, scoped.id);
    await _apply(ask: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final scoped in _reminders)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (var day = 1; day <= 7; day++)
                      _Day(
                        label: weekdayNames[day - 1],
                        name: weekdayLongNames[day - 1],
                        on: scoped.reminder.days.contains(day),
                        onTap: () => _toggle(scoped, day),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    AppButton(
                      label: 'Um ${scoped.reminder.time} Uhr',
                      icon: Icons.schedule,
                      onPressed: () => _time(scoped),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 19),
                      color: c.fgMuted,
                      tooltip: 'Erinnerung entfernen',
                      onPressed: () => _remove(scoped),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: _reminders.isEmpty
                ? 'Erinnerung einrichten'
                : 'Erinnerung hinzufügen',
            icon: Icons.notifications_none,
            onPressed: _add,
          ),
        ),
        if (_note != null) ...[
          const SizedBox(height: 6),
          Text(_note!, style: TextStyle(fontSize: 12, color: c.fgMuted)),
        ],
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.label,
    required this.name,
    required this.on,
    required this.onTap,
  });

  final String label;
  final String name;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tappable(
      onTap: onTap,
      semanticLabel: name,
      child: Container(
        width: minTap,
        height: minTap,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: on ? c.accent : c.border),
          color: on ? c.accent : null,
        ),
        child: ExcludeSemantics(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: on ? c.accentFg : c.fgMuted),
          ),
        ),
      ),
    );
  }
}
