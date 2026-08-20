import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/queries.dart';
import '../db/database.dart';
import '../db/repo.dart';
import '../packages/manager.dart';
import '../settings.dart';
import '../theme.dart';
import 'widgets/pieces.dart';

enum TourSpot { tabs, search, browse, video, counts, review, lists, offline }

enum TourPlace { dictionary, entry, learn, lists, more }

// Spotlight uses latest-mounted context when multiple anchor instances exist.
class TourAnchor extends StatefulWidget {
  const TourAnchor({required this.spot, required this.child, super.key});

  final TourSpot spot;
  final Widget child;

  static final _live = <TourSpot, List<BuildContext>>{};

  static BuildContext? contextOf(TourSpot? spot) =>
      spot == null ? null : _live[spot]?.lastOrNull;

  static Rect? rectOf(TourSpot? spot) {
    final box = contextOf(spot)?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize || box.size.isEmpty) {
      return null;
    }
    return (box.localToGlobal(Offset.zero) & box.size).inflate(6);
  }

  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> {
  @override
  void initState() {
    super.initState();
    TourAnchor._live.putIfAbsent(widget.spot, () => []).add(context);
  }

  // Update live registry when reused element changes spot.
  @override
  void didUpdateWidget(TourAnchor old) {
    super.didUpdateWidget(old);
    if (old.spot == widget.spot) return;
    TourAnchor._live[old.spot]?.remove(context);
    TourAnchor._live.putIfAbsent(widget.spot, () => []).add(context);
  }

  @override
  void dispose() {
    TourAnchor._live[widget.spot]?.remove(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

@immutable
class TourStep {
  const TourStep({
    required this.place,
    required this.title,
    required this.body,
    this.spot,
  });

  final TourPlace place;
  final TourSpot? spot;
  final String title;
  final String body;
}

const tourSteps = <TourStep>[
  TourStep(
    place: TourPlace.dictionary,
    spot: TourSpot.tabs,
    title: 'Vier Bereiche',
    body:
        'Unten wechselst du zwischen Wörterbuch, Lernen, Listen und Mehr. '
        'Dieser Rundgang geht sie der Reihe nach durch.',
  ),
  TourStep(
    place: TourPlace.dictionary,
    spot: TourSpot.search,
    title: 'Suchen',
    body:
        'Tippe ein Wort ein. Die Treffer kommen von SignDict. Was du '
        'einmal geöffnet hast, findest du später auch ohne Verbindung wieder.',
  ),
  TourStep(
    place: TourPlace.dictionary,
    spot: TourSpot.browse,
    title: 'Stöbern',
    body:
        'Zufällig zeigt eine beliebige Gebärde und Neu die zuletzt '
        'hinzugekommenen. Weiter unten kannst du im Alphabet durch '
        'das Wörterbuch blättern.',
  ),
  TourStep(
    place: TourPlace.entry,
    spot: TourSpot.video,
    title: 'Videos',
    body:
        'So sieht eine Gebärde aus. Unter dem Video stellst du Tempo und '
        'Endlosschleife ein, gehst Bild für Bild vor und zurück, spiegelst '
        'die Aufnahme oder öffnest das Vollbild. Gibt es mehrere Aufnahmen zu '
        'einem Wort, stehen sie darunter zur Wahl.',
  ),
  TourStep(
    place: TourPlace.learn,
    spot: TourSpot.counts,
    title: 'Trainer',
    body:
        'Fällig sind Wörter, die erneut dran sind, neu die noch nie '
        'gezeigten. Wann ein Wort wiederkommt, richtet sich nach deinen '
        'Antworten.',
  ),
  TourStep(
    place: TourPlace.learn,
    spot: TourSpot.review,
    title: 'Abfrage',
    body:
        'Nutze Selbsteinschätzung, Multiple Choice oder tippe das Wort '
        'frei ein. Direkt darunter legst du fest, ob du die Gebärde erkennst '
        'oder sie selbst gebärdest.',
  ),
  TourStep(
    place: TourPlace.lists,
    spot: TourSpot.lists,
    title: 'Listen',
    body:
        'Sammle Wörter in eigenen Listen und lerne jede Liste für sich. '
        'Einstiegsthemen bieten dir fertige Listen, geteilte Listen öffnest du als '
        'Datei. Für jede Liste kannst du individuelle Erinnerungen einstellen.',
  ),
  if (downloadsAvailable)
    TourStep(
      place: TourPlace.more,
      spot: TourSpot.offline,
      title: 'Offline und Einstellungen',
      body:
          'Lade Gebärden herunter, damit du auch ohne Internetverbindung lernen kannst. '
          'Hier sicherst du außerdem deinen Fortschritt als Datei '
          'und stellst Farbschema, Akzentfarbe und Tageslimits ein.',
    )
  else
    TourStep(
      place: TourPlace.more,
      title: 'Einstellungen',
      body:
          'Hier sicherst du deinen Fortschritt als Datei und stellst '
          'Farbschema, Akzentfarbe und Tageslimits ein.',
    ),
];

// Placed above router so spotlight persists across navigation to entry screen.
class Tour extends StatefulWidget {
  const Tour({
    required this.db,
    required this.router,
    required this.child,
    super.key,
  });

  final AppDatabase db;
  final GoRouter router;
  final Widget child;

  @override
  State<Tour> createState() => _TourState();
}

class _TourState extends State<Tour> {
  int? _step;
  Rect? _hole;

  // Delay overlay until anchor is measured to prevent visual jump.
  var _placed = false;
  var _back = '/';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Single entry point checking tour completion state.
    if (_step != null || SettingsScope.of(context).tourDone) return;
    _go(0);
  }

  // ensureVisualUpdate guarantees post-frame callback fires without active animation.
  void _after(VoidCallback run) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) run();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _go(int index) {
    setState(() {
      _step = index;
      _hole = null;
      _placed = false;
    });
    // Postpone router navigation outside current build phase.
    _after(() => unawaited(_enter(index)));
  }

  Future<void> _enter(int index) async {
    if (_step != index) return;
    if (index == 0) _back = widget.router.state.uri.toString();

    switch (tourSteps[index].place) {
      case TourPlace.dictionary:
        widget.router.go('/');
      case TourPlace.learn:
        widget.router.go('/lernen');
      case TourPlace.lists:
        widget.router.go('/listen');
      case TourPlace.more:
        widget.router.go('/mehr');
      case TourPlace.entry:
        final id = await _example();
        // Use push() so subsequent router.go() automatically cleans up entry screen.
        if (id != null && mounted && _step == index) {
          widget.router.push('/eintrag/$id');
        }
    }
    if (!mounted || _step != index) return;
    _after(() => _place(index));
  }

  // Find any entry with a video to anchor spotlight.
  Future<int?> _example() async {
    final cached =
        await (widget.db.select(widget.db.entries)
              ..where((t) => t.currentVideo.isNotNull())
              ..limit(1))
            .getSingleOrNull();
    if (cached != null) return cached.id;

    try {
      final entry = await randomEntry();
      if (entry == null) return null;
      return (await cacheEntries(widget.db, [entry])).single.id;
    } on Exception {
      return null;
    }
  }

  void _place(int index) {
    if (_step != index) return;
    final target = TourAnchor.contextOf(tourSteps[index].spot);
    if (target != null) {
      Scrollable.ensureVisible(target, alignment: 0.5);
    }
    // Wait for layout pass following ensureVisible before measuring rect.
    _after(() => _follow(index));
  }

  // Poll anchor rect each frame to track async layout shifts.
  void _follow(int index) {
    if (_step != index) return;
    final rect = TourAnchor.rectOf(tourSteps[index].spot);
    if (!_placed || rect != _hole) {
      setState(() {
        _hole = rect;
        _placed = true;
      });
    }
    // Track existing frames only to avoid infinite render loop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _follow(index);
    });
  }

  Future<void> _finish() async {
    final settings = SettingsScope.of(context);
    widget.router.go(_back);
    setState(() {
      _step = null;
      _hole = null;
      _placed = false;
    });
    await settings.set('tourDone', true);
  }

  @override
  Widget build(BuildContext context) {
    final index = _step;
    final running = index != null && _placed;

    return Stack(
      children: [
        ExcludeSemantics(excluding: running, child: widget.child),
        if (running) _overlay(context, index, tourSteps[index]),
      ],
    );
  }

  Widget _overlay(BuildContext context, int index, TourStep step) {
    final hole = _hole;
    final above =
        hole != null &&
        hole.center.dy > MediaQuery.sizeOf(context).height * 0.55;

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          // Block taps from bubbling into underlying UI.
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Stack(
            children: [
              Positioned.fill(child: Spotlight(hole: hole)),
              SafeArea(
                minimum: const EdgeInsets.all(16),
                child: Align(
                  alignment: hole == null
                      ? Alignment.center
                      : above
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _card(context, index, step),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, int index, TourStep step) {
    final c = context.colors;
    final last = index == tourSteps.length - 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  step.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${index + 1} von ${tourSteps.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            step.body,
            style: TextStyle(fontSize: 14, height: 1.5, color: c.fgMuted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (!last) ...[
                Expanded(
                  child: AppButton(label: 'Überspringen', onPressed: _finish),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: AppButton(
                  label: last ? 'Fertig' : 'Weiter',
                  icon: last ? Icons.check : Icons.arrow_forward,
                  filled: true,
                  onPressed: last ? _finish : () => _go(index + 1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class Spotlight extends StatelessWidget {
  const Spotlight({required this.hole, super.key});

  final Rect? hole;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _Scrim(hole: hole, ring: context.colors.accent),
    );
  }
}

class _Scrim extends CustomPainter {
  const _Scrim({required this.hole, required this.ring});

  final Rect? hole;
  final Color ring;

  static const _radius = Radius.circular(6);

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final cut = hole;
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.55);

    if (cut == null) {
      canvas.drawPath(screen, scrim);
      return;
    }

    final rect = RRect.fromRectAndRadius(cut, _radius);
    canvas.drawPath(
      Path.combine(PathOperation.difference, screen, Path()..addRRect(rect)),
      scrim,
    );
    // Stroke boundary outline for contrast across varied backgrounds.
    canvas.drawRRect(
      rect,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_Scrim old) => old.hole != hole || old.ring != ring;
}
