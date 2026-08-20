import 'dart:math';

import 'package:flutter/material.dart';
import 'package:fsrs/fsrs.dart' as f;

import '../db/database.dart';
import '../srs/scheduler.dart';
import '../theme.dart';
import '../util/text.dart';
import 'widgets/pieces.dart';
import 'widgets/sign_video.dart';

const _labels = {
  f.Rating.again: 'Nochmal',
  f.Rating.hard: 'Schwer',
  f.Rating.good: 'Gut',
  f.Rating.easy: 'Leicht',
};

final _random = Random();

List<T> shuffled<T>(Iterable<T> items) {
  final list = [...items];
  for (var i = list.length - 1; i > 0; i--) {
    final j = _random.nextInt(i + 1);
    final swap = list[i];
    list[i] = list[j];
    list[j] = swap;
  }
  return list;
}

class CardProps {
  const CardProps({
    required this.db,
    required this.entry,
    required this.card,
    required this.video,
    required this.pool,
    required this.onAnswer,
  });

  final AppDatabase db;
  final CachedEntry entry;
  final StoredCard card;
  final ApiVideo? video;
  final List<CachedEntry> pool;
  final void Function(f.Rating) onAnswer;
}

class SelfRatedCard extends StatefulWidget {
  const SelfRatedCard(this.props, {super.key});

  final CardProps props;

  @override
  State<SelfRatedCard> createState() => _SelfRatedCardState();
}

class _SelfRatedCardState extends State<SelfRatedCard> {
  var _revealed = false;

  @override
  void didUpdateWidget(SelfRatedCard old) {
    super.didUpdateWidget(old);
    if (old.props.card.id != widget.props.card.id) _revealed = false;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.props;
    final recognition = p.card.direction == Direction.recognition;
    final intervals = previewIntervals(p.card);

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              if (recognition) ...[
                if (p.video != null)
                  SignVideo(
                    db: p.db,
                    video: p.video!,
                    label: 'gesuchte Gebärde',
                    compact: true,
                    controls: false,
                  ),
                const _Prompt('Welches Wort ist das?'),
                _Answer(_revealed ? p.entry.word : '—'),
              ] else ...[
                const SizedBox(height: 32),
                const _Prompt('Wie wird das gebärdet?'),
                _Answer(p.entry.word),
                if (_revealed && p.video != null)
                  SignVideo(
                    db: p.db,
                    video: p.video!,
                    label: p.entry.word,
                    compact: true,
                    controls: false,
                  ),
              ],
            ],
          ),
        ),
        const HairLine(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: _revealed
              ? Row(
                  children: [
                    for (final grade in grades) ...[
                      Expanded(
                        child: _GradeButton(
                          label: _labels[grade]!,
                          hint: intervals[grade]!,
                          danger: grade == f.Rating.again,
                          onTap: () => p.onAnswer(grade),
                        ),
                      ),
                      if (grade != grades.last) const SizedBox(width: 6),
                    ],
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: 'Auflösen',
                    icon: Icons.visibility_outlined,
                    filled: true,
                    onPressed: () => setState(() => _revealed = true),
                  ),
                ),
        ),
      ],
    );
  }
}

class ChoiceCard extends StatefulWidget {
  const ChoiceCard(this.props, {super.key});

  final CardProps props;

  @override
  State<ChoiceCard> createState() => _ChoiceCardState();
}

class _ChoiceCardState extends State<ChoiceCard> {
  late List<CachedEntry> _options;

  int? _picked;

  @override
  void initState() {
    super.initState();
    _draw();
  }

  @override
  void didUpdateWidget(ChoiceCard old) {
    super.didUpdateWidget(old);
    if (old.props.card.id != widget.props.card.id) {
      _picked = null;
      _draw();
    }
  }

  void _draw() {
    final p = widget.props;
    final others = shuffled(p.pool.where((e) => e.id != p.entry.id)).take(3);
    _options = shuffled([p.entry, ...others]);
  }

  void _answer(CachedEntry option) {
    if (_picked != null) return;
    setState(() => _picked = option.id);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        widget.props.onAnswer(
          option.id == widget.props.entry.id ? f.Rating.good : f.Rating.again,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.props;

    return ListView(
      children: [
        if (p.video != null)
          SignVideo(
            db: p.db,
            video: p.video!,
            label: 'gesuchte Gebärde',
            compact: true,
            controls: false,
          ),
        const _Prompt('Welches Wort ist das?'),
        const SizedBox(height: 8),
        for (final option in _options)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Builder(
              builder: (context) {
                final right = _picked != null && option.id == p.entry.id;
                final wrong = _picked == option.id && option.id != p.entry.id;
                final tint = right ? c.success : (wrong ? c.danger : null);

                return Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  child: Tappable(
                    onTap: _picked == null ? () => _answer(option) : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: tint ?? c.border),
                      ),
                      child: Text(
                        option.word,
                        style: TextStyle(color: tint ?? c.fg),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class TypingCard extends StatefulWidget {
  const TypingCard(this.props, {super.key});

  final CardProps props;

  @override
  State<TypingCard> createState() => _TypingCardState();
}

class _TypingCardState extends State<TypingCard> {
  final _field = TextEditingController();
  bool? _right;

  @override
  void didUpdateWidget(TypingCard old) {
    super.didUpdateWidget(old);
    if (old.props.card.id != widget.props.card.id) {
      _field.clear();
      _right = null;
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    if (_right != null) return;
    final ok = answersMatch(_field.text, widget.props.entry.word);
    setState(() => _right = ok);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) widget.props.onAnswer(ok ? f.Rating.good : f.Rating.again);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.props;
    final tint = _right == null ? c.border : (_right! ? c.success : c.danger);

    return ListView(
      children: [
        if (p.video != null)
          SignVideo(
            db: p.db,
            video: p.video!,
            label: 'gesuchte Gebärde',
            compact: true,
            controls: false,
          ),
        const _Prompt('Welches Wort ist das?'),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _field,
            autofocus: true,
            enabled: _right == null,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Wort eintippen',
              enabledBorder: _right == null ? null : outline(tint),
              focusedBorder: _right == null ? null : outline(tint),
              disabledBorder: _right == null ? null : outline(tint),
            ),
          ),
        ),
        if (_right == false)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Richtig ist: ${p.entry.word}',
              style: TextStyle(color: c.danger),
            ),
          ),
        if (_right == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'Prüfen',
                filled: true,
                onPressed: _submit,
              ),
            ),
          ),
      ],
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

class _Answer extends StatelessWidget {
  const _Answer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall,
    ),
  );
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.hint,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final String hint;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: Tappable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: danger ? c.danger : c.border),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 14, color: danger ? c.danger : c.fg),
              ),
              Text(hint, style: TextStyle(fontSize: 11, color: c.fgMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
