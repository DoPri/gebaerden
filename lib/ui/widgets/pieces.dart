import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme.dart';

// Android minimum touch target requirement.
const minTap = 48.0;

class Tappable extends StatelessWidget {
  const Tappable({
    required this.child,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        highlightColor: context.colors.surface2,
        splashFactory: NoSplash.splashFactory,
        child: child,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.filled = false,
    this.danger = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = danger ? c.danger : c.accent;
    final enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: filled ? tint : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: Tappable(
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: minTap),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: filled ? null : Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: filled ? c.accentFg : tint),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: filled ? c.accentFg : tint,
                    fontSize: 15,
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

class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    super.key,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: label,
      child: Row(
        children: [
          for (final (option, text) in options) ...[
            Expanded(
              child: Semantics(
                selected: option == value,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  child: Tappable(
                    onTap: () => onChanged(option),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: minTap),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: option == value ? c.accent : c.border,
                        ),
                      ),
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 14,
                          color: option == value ? c.accent : c.fgMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (option != options.last.$1) const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }
}

class Note extends StatelessWidget {
  const Note(this.text, {this.problem = false, super.key});

  final String text;
  final bool problem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: problem ? context.colors.danger : context.colors.fgMuted,
        ),
      ),
    );
  }
}

Widget insetSides(Widget child) =>
    SafeArea(top: false, bottom: false, child: child);

OutlineInputBorder outline(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(4),
  borderSide: BorderSide(color: color),
);

class HairLine extends StatelessWidget {
  const HairLine({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: context.colors.border);
}

class LinkText extends StatelessWidget {
  const LinkText({required this.label, required this.url, super.key});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: () => launchExternal(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: context.colors.fgMuted,
            decoration: TextDecoration.underline,
            decorationColor: context.colors.fgMuted,
          ),
        ),
      ),
    );
  }
}

Future<void> launchExternal(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class WordChip extends StatelessWidget {
  const WordChip(
    this.label, {
    required this.onTap,
    this.muted = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: Tappable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: minTap),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.border),
          ),
          // Prevents Center from expanding horizontally.
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: muted ? c.fgMuted : null),
            ),
          ),
        ),
      ),
    );
  }
}

class NumberField extends StatelessWidget {
  const NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: '$value',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(isDense: true),
          onChanged: (raw) {
            final parsed = int.tryParse(raw);
            if (parsed != null && parsed >= 0) onChanged(parsed);
          },
        ),
      ],
    );
  }
}
