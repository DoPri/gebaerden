import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Converted from the OKLCH values the web version used.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.fg,
    required this.fgMuted,
    required this.accent,
    required this.accentHover,
    required this.accentFg,
    required this.danger,
    required this.success,
  });

  static const light = AppColors(
    bg: Color(0xFFFBFAF7),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF2F0EC),
    border: Color(0xFFDEDCD8),
    fg: Color(0xFF1D1A17),
    fgMuted: Color(0xFF68645E),
    accent: Color(0xFF955E11),
    accentHover: Color(0xFF7F4A00),
    accentFg: Color(0xFFFDFCF8),
    danger: Color(0xFFBA3630),
    success: Color(0xFF2B7440),
  );

  static const dark = AppColors(
    bg: Color(0xFF12100E),
    surface: Color(0xFF1B1916),
    surface2: Color(0xFF272420),
    border: Color(0xFF34312D),
    fg: Color(0xFFEEEDEA),
    fgMuted: Color(0xFF9D9994),
    accent: Color(0xFFE3AC58),
    accentHover: Color(0xFFF5C578),
    accentFg: Color(0xFF16130F),
    danger: Color(0xFFEA6B60),
    success: Color(0xFF69BA7C),
  );

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color fg;
  final Color fgMuted;
  final Color accent;
  final Color accentHover;
  final Color accentFg;
  final Color danger;
  final Color success;

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? border,
    Color? fg,
    Color? fgMuted,
    Color? accent,
    Color? accentHover,
    Color? accentFg,
    Color? danger,
    Color? success,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      border: border ?? this.border,
      fg: fg ?? this.fg,
      fgMuted: fgMuted ?? this.fgMuted,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentFg: accentFg ?? this.accentFg,
      danger: danger ?? this.danger,
      success: success ?? this.success,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      border: Color.lerp(border, other.border, t)!,
      fg: Color.lerp(fg, other.fg, t)!,
      fgMuted: Color.lerp(fgMuted, other.fgMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentFg: Color.lerp(accentFg, other.accentFg, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

extension AppColorsOf on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// Material's defaults run large here.
const _sizes = {
  'headline': 24.0,
  'title': 18.0,
  'body': 15.0,
  'small': 13.0,
  'label': 11.0,
};

/// A handful of ready-made accents. The picker takes any color.
const suggestedAccents = [
  (0xFF955E11, 'Ocker'),
  (0xFF9C4A2F, 'Ziegel'),
  (0xFF5F6B23, 'Oliv'),
  (0xFF3C6B57, 'Salbei'),
  (0xFF3A6280, 'Stahl'),
  (0xFF75456D, 'Pflaume'),
];

const defaultAccent = 0xFF955E11;

double _contrast(Color a, Color b) {
  final x = a.computeLuminance() + 0.05;
  final y = b.computeLuminance() + 0.05;
  return x > y ? x / y : y / x;
}

/// Walks the lightness until the color carries text on [on]. Any color has
/// to stay readable, and the picker hands over whatever the user likes.
Color _readable(Color base, Color on) {
  final up = on.computeLuminance() < 0.5;
  var hsl = HSLColor.fromColor(base);

  for (var i = 0; i < 100; i++) {
    if (_contrast(hsl.toColor(), on) >= 4.5) return hsl.toColor();
    final next = hsl.lightness + (up ? 0.01 : -0.01);
    if (next <= 0 || next >= 1) break;
    hsl = hsl.withLightness(next);
  }
  return up ? Colors.white : Colors.black;
}

Color _shift(Color base, double by) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withLightness((hsl.lightness + by).clamp(0.0, 1.0)).toColor();
}

AppColors accented(AppColors base, int accent) {
  final wanted = Color(accent);
  final resolved = _readable(wanted, base.bg);
  final dark = base.bg.computeLuminance() < 0.5;

  return base.copyWith(
    accent: resolved,
    accentHover: _shift(resolved, dark ? 0.08 : -0.08),
    accentFg: _contrast(resolved, base.bg) > _contrast(resolved, base.fg)
        ? base.bg
        : base.fg,
  );
}

OutlineInputBorder _field(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(4),
  borderSide: BorderSide(color: color),
);

/// From Android 15 the app draws under the system bars and nothing else paints
/// them, so the icons have to be told which way to go. Transparent throughout,
/// the surface underneath is what shows.
SystemUiOverlayStyle systemOverlay(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    // iOS reads this the other way round.
    statusBarBrightness: brightness,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

ThemeData appTheme(Brightness brightness, [int accent = defaultAccent]) {
  final dark = brightness == Brightness.dark;
  final c = accented(dark ? AppColors.dark : AppColors.light, accent);

  // No webfont, so the system face on both platforms.
  final typography = Typography.material2021(platform: defaultTargetPlatform);
  final base = brightness == Brightness.dark
      ? typography.white
      : typography.black;

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: c.bg,
    typography: typography,
    // An AppBar sets its own overlay style, otherwise derived from its
    // background, which would fight the one the app declares.
    appBarTheme: AppBarTheme(systemOverlayStyle: systemOverlay(brightness)),
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: c.accent,
          brightness: brightness,
        ).copyWith(
          surface: c.surface,
          onSurface: c.fg,
          primary: c.accent,
          onPrimary: c.accentFg,
          error: c.danger,
          onError: c.accentFg,
          outline: c.border,
        ),
    textTheme: base
        .apply(bodyColor: c.fg, displayColor: c.fg)
        .copyWith(
          headlineSmall: base.headlineSmall?.copyWith(
            color: c.fg,
            fontSize: _sizes['headline'],
            fontWeight: FontWeight.w400,
          ),
          titleMedium: base.titleMedium?.copyWith(
            color: c.fg,
            fontSize: _sizes['title'],
            fontWeight: FontWeight.w400,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            color: c.fg,
            fontSize: _sizes['body'],
          ),
          bodySmall: base.bodySmall?.copyWith(
            color: c.fgMuted,
            fontSize: _sizes['small'],
          ),
          labelSmall: base.labelSmall?.copyWith(
            color: c.fgMuted,
            fontSize: _sizes['label'],
            letterSpacing: 0.6,
          ),
        ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: TextStyle(color: c.fgMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: _field(c.border),
      enabledBorder: _field(c.border),
      focusedBorder: _field(c.accent),
      disabledBorder: _field(c.border),
      errorBorder: _field(c.danger),
      focusedErrorBorder: _field(c.danger),
    ),
    extensions: [c],
    // Ripples would read as stock Material.
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.surface2,
  );
}
