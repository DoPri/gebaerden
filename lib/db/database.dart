import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// The generated part names both the converters and the types they produce.
import '../api/types.dart';
import 'converters.dart';
import 'tables.dart';

export '../api/types.dart';
export 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Entries,
    Assets,
    Cards,
    Reviews,
    Lists,
    ListItems,
    Reminders,
    Packages,
    Settings,
    Recents,
    Variants,
  ],
)
/// Both files sit in web/ and are pinned to the versions in pubspec.lock,
/// sqlite3.wasm to sqlite3 and drift_worker.js to drift.
final _web = DriftWebOptions(
  sqlite3Wasm: Uri.parse('sqlite3.wasm'),
  driftWorker: Uri.parse('drift_worker.js'),
);

class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'gebaerden', web: _web));

  /// A throwaway database on the device, so a test run leaves nothing behind.
  factory AppDatabase.forTesting() =>
      AppDatabase(driftDatabase(name: 'gebaerden_test', web: _web));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(lists, lists.newPerDay);
        await m.addColumn(lists, lists.reviewPerDay);
      }
      if (from < 3) {
        await m.createTable(reminders);
        // A reminder belongs to a list now. The old global one has no list to
        // belong to, so it goes and its alarms are cancelled on the next start.
        await (delete(
          settings,
        )..where((t) => t.key.isIn(const ['reminders', 'reminderAt']))).go();
      }
    },
    onCreate: (m) async {
      await m.createAll();
      await customStatement('CREATE INDEX idx_entries_text ON entries(word)');
      await customStatement(
        'CREATE INDEX idx_entries_video ON entries(has_video)',
      );
      await customStatement('CREATE INDEX idx_cards_due ON cards(due)');
      await customStatement('CREATE INDEX idx_cards_entry ON cards(entry_id)');
      await customStatement(
        'CREATE INDEX idx_reviews_at ON reviews(reviewed_at)',
      );
      await customStatement(
        'CREATE INDEX idx_reviews_card ON reviews(card_id)',
      );
      await customStatement(
        'CREATE INDEX idx_assets_entry ON assets(entry_id)',
      );
      await customStatement(
        'CREATE INDEX idx_items_entry ON list_items(entry_id)',
      );
      await customStatement('CREATE INDEX idx_recents_at ON recents(kind, at)');
    },
  );
}

/// Single instance for the running app. Tests build their own.
late AppDatabase db;
