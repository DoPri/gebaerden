import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// Imports required by generated part file.
import '../api/types.dart';
import 'converters.dart';
import 'tables.dart';

export '../api/types.dart';
export 'tables.dart';

part 'database.g.dart';

// Web worker and wasm assets are pinned to pubspec.lock package versions.
final _web = DriftWebOptions(
  sqlite3Wasm: Uri.parse('sqlite3.wasm'),
  driftWorker: Uri.parse('drift_worker.js'),
);

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
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'gebaerden', web: _web));

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
        // Reminders are scoped to lists; legacy global settings are removed.
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

late AppDatabase db;
