import 'package:flutter/material.dart';

import '../db/database.dart';
import '../srs/charset.dart';
import '../theme.dart';
import '../util/text.dart';
import 'cards.dart';
import 'widgets/pieces.dart';
import 'widgets/sign_video.dart';

enum _Mode { read, spell }

class CharsetScreen extends StatefulWidget {
  const CharsetScreen({required this.db, required this.charset, super.key});

  final AppDatabase db;
  final Charset charset;

  @override
  State<CharsetScreen> createState() => _CharsetScreenState();
}

class _CharsetScreenState extends State<CharsetScreen> {
  Map<String, CachedEntry> _set = {};
  List<String> _words = [];
  var _mode = _Mode.read;
  String? _error;
  var _busy = true;

  String? _asked;
  List<String> _options = [];
  String? _picked;

  String? _word;
  List<String> _letters = [];
  var _step = 0;
  final _field = TextEditingController();
  bool? _right;

  bool get _isAlphabet => widget.charset == Charset.alphabet;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final set = await loadCharset(widget.db, widget.charset);
      final words = _isAlphabet
          ? await spellableWords(widget.db, set)
          : <String>[];
      if (!mounted) return;
      setState(() {
        _set = set;
        _words = words;
        _busy = false;
      });
      _next();
    } on Exception {
      if (mounted) {
        setState(() {
          _error =
              'Die Gebärden für das Fingeralphabet konnten nicht geladen werden.';
          _busy = false;
        });
      }
    }
  }

  void _next() {
    if (_set.isEmpty) return;
    final chars = _set.keys.toList();

    setState(() {
      _picked = null;
      _right = null;
      _field.clear();

      if (_mode == _Mode.read) {
        _asked = pick(chars);
        final others = shuffled(chars.where((c) => c != _asked)).take(3);
        _options = shuffled([_asked!, ...others]);
      } else if (_words.isNotEmpty) {
        _word = pick(_words);
        _letters = toChars(_word!, _set) ?? [];
        _step = 0;
      }
    });
  }

  void _answer(String option) {
    if (_picked != null) return;
    setState(() => _picked = option);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _next();
    });
  }

  void _check() {
    if (_right != null) return;
    setState(() => _right = answersMatch(_field.text, _word ?? ''));
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) _next();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = _isAlphabet ? 'Fingeralphabet' : 'Zahlen';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: c.border),
        ),
      ),
      body: insetSides(switch (true) {
        _ when _busy => const Note('Lädt…'),
        _ when _error != null => Note(_error!, problem: true),
        _ when _set.isEmpty => const Note(
          'Es wurden keine Gebärden für das Fingeralphabet gefunden.',
        ),
        _ => Column(
          children: [
            if (_isAlphabet && _words.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: ChoiceRow(
                  label: 'Übungsart',
                  options: const [
                    (_Mode.read, 'Lesen'),
                    (_Mode.spell, 'Buchstabieren'),
                  ],
                  value: _mode,
                  onChanged: (mode) {
                    setState(() => _mode = mode);
                    _next();
                  },
                ),
              ),
            Expanded(
              child: _mode == _Mode.read
                  ? _reading(context)
                  : _spelling(context),
            ),
          ],
        ),
      }),
    );
  }

  Widget _reading(BuildContext context) {
    final c = context.colors;
    final entry = _asked == null ? null : _set[_asked];
    if (entry?.currentVideo == null) return const SizedBox.shrink();

    return ListView(
      children: [
        SignVideo(
          db: widget.db,
          video: entry!.currentVideo!,
          label: 'Gebärde',
          compact: true,
          controls: false,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Text(
            _isAlphabet ? 'Welcher Buchstabe ist das?' : 'Welche Zahl ist das?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final option in _options)
                Builder(
                  builder: (context) {
                    final right = _picked != null && option == _asked;
                    final wrong = _picked == option && option != _asked;
                    final tint = right ? c.success : (wrong ? c.danger : null);

                    return SizedBox(
                      width: 74,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        child: Tappable(
                          onTap: _picked == null ? () => _answer(option) : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: tint ?? c.border),
                            ),
                            child: Text(
                              option.toUpperCase(),
                              style: TextStyle(
                                fontSize: 17,
                                color: tint ?? c.fg,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _spelling(BuildContext context) {
    final c = context.colors;
    if (_letters.isEmpty) {
      return const Note(
        'Noch keine passenden Wörter gefunden. Sieh dir erst ein paar '
        'Gebärden im Wörterbuch an.',
      );
    }

    final entry = _set[_letters[_step.clamp(0, _letters.length - 1)]];
    if (entry?.currentVideo == null) return const SizedBox.shrink();

    return ListView(
      children: [
        SignVideo(
          db: widget.db,
          key: ValueKey('$_word-$_step'),
          video: entry!.currentVideo!,
          label: 'Gebärde',
          compact: true,
          controls: false,
          loop: false,
          onEnded: () {
            if (_step < _letters.length - 1) setState(() => _step++);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            'Buchstabe ${_step + 1} von ${_letters.length}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _field,
            enabled: _right == null,
            onSubmitted: (_) => _check(),
            decoration: const InputDecoration(
              hintText: 'Welches Wort war das?',
            ),
          ),
        ),
        if (_right != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _right! ? 'Richtig.' : 'Richtig war: $_word',
              textAlign: TextAlign.center,
              style: TextStyle(color: _right! ? c.success : c.danger),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Prüfen',
                    filled: true,
                    onPressed: _check,
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Nochmal zeigen',
                  onPressed: () => setState(() => _step = 0),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
