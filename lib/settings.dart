import 'package:flutter/material.dart';

import 'db/database.dart';
import 'theme.dart';

enum ReviewMode { self, choice, typing }

/// Which way round cards are asked.
enum DirectionMode { recognition, production, both }

/// Named once, so the stored default and the fallback below cannot drift apart.
const _fallbackMode = ReviewMode.self;
const _fallbackDirection = DirectionMode.recognition;

final _defaults = Map<String, Object?>.unmodifiable({
  'themeMode': 'system',
  'accent': defaultAccent,
  'speed': 1.0,
  'loop': true,
  'mirror': false,
  'mode': _fallbackMode.name,
  'direction': _fallbackDirection.name,
  'newPerDay': 20,
  'reviewPerDay': 200,
  'showWithoutVideo': false,
  'tourDone': false,
});

/// One table, so a new key needs no migration.
class AppSettings extends ChangeNotifier {
  AppSettings(this._db);

  final AppDatabase _db;
  final Map<String, Object?> _values = Map.of(_defaults);

  Future<void> load() async {
    for (final row in await _db.select(_db.settings).get()) {
      final fallback = _defaults[row.key];
      final value = row.value;
      if (fallback == null) continue;

      final fits = fallback is num
          ? value is num
          : value.runtimeType == fallback.runtimeType;
      if (fits) _values[row.key] = value;
    }
  }

  Future<void> set(String key, Object? value) async {
    _values[key] = value;
    notifyListeners();
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(StoredSetting(key: key, value: value));
  }

  T _read<T>(String key) => _values[key] as T;

  /// Numbers go through num. What arrives depends on the platform and on what
  /// an imported file carried, 7 and 7.0 mean the same thing.
  int _whole(String key) => (_values[key]! as num).toInt();

  double _decimal(String key) => (_values[key]! as num).toDouble();

  ThemeMode get themeMode => switch (_read<String>('themeMode')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeMode(ThemeMode mode) => set('themeMode', mode.name);

  int get accent => _whole('accent');

  Future<void> setAccent(int value) => set('accent', value);

  double get speed => _decimal('speed');
  bool get loop => _read<bool>('loop');
  bool get mirror => _read<bool>('mirror');
  int get newPerDay => _whole('newPerDay');
  int get reviewPerDay => _whole('reviewPerDay');
  bool get showWithoutVideo => _read<bool>('showWithoutVideo');
  bool get tourDone => _read<bool>('tourDone');

  /// An imported file passes the type check with any string, so fall back
  /// rather than throw on a name no enum carries.
  ReviewMode get mode => ReviewMode.values.firstWhere(
    (m) => m.name == _read<String>('mode'),
    orElse: () => _fallbackMode,
  );

  DirectionMode get direction => DirectionMode.values.firstWhere(
    (d) => d.name == _read<String>('direction'),
    orElse: () => _fallbackDirection,
  );

  List<Direction> get directions => switch (direction) {
    DirectionMode.recognition => const [Direction.recognition],
    DirectionMode.production => const [Direction.production],
    DirectionMode.both => const [Direction.recognition, Direction.production],
  };
}

class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({
    required AppSettings super.notifier,
    required super.child,
    super.key,
  });

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
