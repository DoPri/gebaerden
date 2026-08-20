import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../srs/stats.dart';
import '../../theme.dart';
import 'pieces.dart';

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

class StatsPanel extends StatefulWidget {
  const StatsPanel({required this.db, super.key});

  final AppDatabase db;

  @override
  State<StatsPanel> createState() => _StatsPanelState();
}

class _StatsPanelState extends State<StatsPanel> {
  Stats? _stats;

  @override
  void initState() {
    super.initState();
    collectStats(widget.db).then((stats) {
      if (mounted) setState(() => _stats = stats);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (stats == null || stats.cards == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Figure(
              label: 'Aktueller Streak',
              value: '${stats.streak}',
              unit: '',
            ),
            const SizedBox(width: 32),
            _Figure(
              label: 'Gelernt',
              value: '${stats.retained}',
              unit: '/ ${stats.cards}',
            ),
          ],
        ),
        const SizedBox(height: 22),
        const SectionLabel('Letzte 14 Tage'),
        const SizedBox(height: 8),
        _Bars(days: stats.history, filled: true),
        const SizedBox(height: 22),
        const SectionLabel('Kommende 7 Tage'),
        const SizedBox(height: 8),
        _Bars(days: stats.forecast, filled: false, labelled: true),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(width: 4),
            Text(unit, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({
    required this.days,
    required this.filled,
    this.labelled = false,
  });

  final List<DayCount> days;
  final bool filled;
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    var peak = 1;
    for (final day in days) {
      if (day.count > peak) peak = day.count;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final day in days) ...[
          Expanded(
            child: Semantics(
              label: '${day.day.day}.${day.day.month}.: ${day.count}',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 56,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          // A blank day still needs a visible baseline.
                          height: 2 + 54 * day.count / peak,
                          decoration: BoxDecoration(
                            color: filled ? c.accent : c.surface2,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (labelled) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${day.count}',
                      style: TextStyle(fontSize: 11, color: c.fgMuted),
                    ),
                    Text(
                      _weekdays[day.day.weekday - 1],
                      style: TextStyle(fontSize: 11, color: c.fgMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (day != days.last) const SizedBox(width: 3),
        ],
      ],
    );
  }
}
