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

/// The widget a step points at.
enum TourSpot { tabs, search, browse, video, counts, review, lists, offline }

/// Where a step happens. The tour goes there before it shows.
enum TourPlace { dictionary, entry, learn, lists, more }

/// Marks the widget a step points at. A spot can exist more than once, two
/// entry screens stacked on each other carry the same controls, so the one
/// mounted last is the one the spotlight uses.
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

  /// Two anchors sit next to each other in the trainer, and a section that
  /// arrives late shifts them by one. The element is then reused for the
  /// other one, so the spot changes under a state that keeps living, and the
  /// registration from initState pointed at the wrong widget.
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

/// The walkthrough over the running app. Sits above the router rather than in
/// the tab shell, because the video step opens an entry screen and the
/// spotlight has to stay on top of it.
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

  /// The overlay stays out until the anchor has been measured, otherwise the
  /// card shows up centred and jumps into place a frame later.
  var _placed = false;

  /// Where the tour was started, so it hands the app back the way it found it.
  var _back = '/';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mehr clears the marker to run the tour again, so this is the only place
    // that decides whether it runs.
    if (_step != null || SettingsScope.of(context).tourDone) return;
    _go(0);
  }

  /// A post frame callback only fires if a frame is coming, and a step
  /// without an anchor asks for none.
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
    // Navigating goes through the router, which must not be told to rebuild
    // while this build is still running.
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
        // go replaces the stack, so the next step drops this screen again.
        if (id != null && mounted && _step == index) {
          widget.router.push('/eintrag/$id');
        }
    }
    if (!mounted || _step != index) return;
    _after(() => _place(index));
  }

  /// A word the video step can play. The cache holds the whole index after the
  /// first start, and a random one over the wire is the fallback. Without
  /// either the step keeps its text and shows no spotlight.
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
    // The scroll only lands in the next layout pass, and the box has to be
    // read after it.
    _after(() => _follow(index));
  }

  /// The screen under the spotlight keeps loading while the step is up. The
  /// scope chips of the trainer arrive late and push the counts down, so the
  /// ring sat a section too high. Nothing tells an ancestor that a row below
  /// it has moved, hence the rect is read again after every frame.
  void _follow(int index) {
    if (_step != index) return;
    final rect = TourAnchor.rectOf(tourSteps[index].spot);
    if (!_placed || rect != _hole) {
      setState(() {
        _hole = rect;
        _placed = true;
      });
    }
    // No ensureVisualUpdate here. This rides along with the frames that happen
    // anyway, asking for one of its own would never stop.
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
          // The tour walks the app itself. A tap through the hole would push a
          // screen under the overlay.
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

/// Dims everything except the anchored widget. Without a [hole] the whole
/// screen goes dark and the card sits in the middle of it.
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
    // The highlighted widget can sit on any surface, so it gets an outline of
    // its own rather than relying on the darkness around it.
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
