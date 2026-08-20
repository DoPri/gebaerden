import 'package:flutter/material.dart';

import '../platform/network.dart';
import '../theme.dart';
import 'tour.dart';
import 'widgets/pieces.dart';

const tabs = [
  (path: '/', label: 'Wörterbuch', icon: Icons.menu_book_outlined),
  (path: '/lernen', label: 'Lernen', icon: Icons.school_outlined),
  (path: '/listen', label: 'Listen', icon: Icons.checklist_outlined),
  (path: '/mehr', label: 'Mehr', icon: Icons.tune_outlined),
];

class Shell extends StatelessWidget {
  const Shell({
    required this.child,
    required this.index,
    required this.onSelect,
    required this.title,
    super.key,
  });

  final Widget child;
  final int index;
  final ValueChanged<int> onSelect;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const HairLine(),
            if (!NetworkScope.online(context)) const _Offline(),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: TourAnchor(
        spot: TourSpot.tabs,
        child: _Tabs(index: index, onSelect: onSelect),
      ),
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      color: c.surface2,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        'Keine Internetverbindung. Du siehst nur, was vorher heruntergeladen wurde.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: c.fgMuted),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Semantics(
          label: 'Hauptnavigation',
          child: Row(
            children: [
              for (final (i, tab) in tabs.indexed)
                Expanded(
                  child: Semantics(
                    selected: i == index,
                    child: Tappable(
                      onTap: () => onSelect(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tab.icon,
                              size: 21,
                              color: i == index ? c.accent : c.fgMuted,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tab.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: i == index ? c.accent : c.fgMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
