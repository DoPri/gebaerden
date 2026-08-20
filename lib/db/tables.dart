// coverage:ignore-file

import 'package:drift/drift.dart';

import 'converters.dart';

enum Direction { recognition, production }

enum ListKind { known, favourites, learning, custom }

enum AssetKind { video, thumbnail }

enum PackageStatus { queued, running, paused, done, error }

enum RecentKind { search, entry }

@DataClassName('CachedEntry')
class Entries extends Table {
  IntColumn get id => integer()();

  /// Named `word` because `text` conflicts with drift's column builder.
  TextColumn get word => text()();
  TextColumn get type => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get language => text().nullable()();
  BoolColumn get hasVideo => boolean()();
  TextColumn get currentVideo =>
      text().map(const VideoConverter()).nullable()();
  TextColumn get videos => text().map(const VideoListConverter()).nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StoredAsset')
class Assets extends Table {
  IntColumn get videoId => integer()();
  TextColumn get kind => textEnum<AssetKind>()();
  IntColumn get entryId => integer()();
  TextColumn get localPath => text()();
  IntColumn get bytes => integer()();
  DateTimeColumn get downloadedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {videoId, kind};
}

/// Tracks reps, lapses, and suspension not handled by dart-fsrs.
@DataClassName('StoredCard')
class Cards extends Table {
  TextColumn get id => text()();
  IntColumn get entryId => integer()();
  TextColumn get direction => textEnum<Direction>()();
  IntColumn get state => integer()();
  IntColumn get step => integer().nullable()();
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();
  DateTimeColumn get due => dateTime()();
  DateTimeColumn get lastReview => dateTime().nullable()();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  BoolColumn get suspended => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Stores serialized prior card state for review undo.
@DataClassName('StoredReview')
class Reviews extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cardId => text()();
  IntColumn get entryId => integer()();
  IntColumn get rating => integer()();
  DateTimeColumn get reviewedAt => dateTime()();
  TextColumn get before => text()();
}

@DataClassName('StoredList')
class Lists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<ListKind>()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Independent daily budget per list; null falls back to global setting.
  IntColumn get newPerDay => integer().nullable()();
  IntColumn get reviewPerDay => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Reminders are scoped to lists. Days stored as ISO weekday digits (1 = Monday).
@DataClassName('StoredReminder')
class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get listId => text()();
  TextColumn get days => text()();
  IntColumn get hour => integer()();
  IntColumn get minute => integer()();
}

@DataClassName('StoredListItem')
class ListItems extends Table {
  TextColumn get listId => text()();
  IntColumn get entryId => integer()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {listId, entryId};
}

@DataClassName('StoredPackage')
class Packages extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();
  TextColumn get spec => text()();
  TextColumn get status => textEnum<PackageStatus>()();
  IntColumn get done => integer().withDefault(const Constant(0))();
  IntColumn get total => integer().withDefault(const Constant(0))();
  IntColumn get bytes => integer().withDefault(const Constant(0))();
  TextColumn get error => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StoredSetting')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().map(const JsonConverter())();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('RecentItem')
class Recents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => textEnum<RecentKind>()();
  TextColumn get value => text()();
  TextColumn get label => text()();
  DateTimeColumn get at => dateTime()();
}

/// Caches video metadata for immediate display before detail request completes.
@DataClassName('StoredVariant')
class Variants extends Table {
  IntColumn get entryId => integer()();
  IntColumn get videoId => integer()();
  TextColumn get video => text().map(const VideoConverter()).nullable()();
  DateTimeColumn get at => dateTime()();

  @override
  Set<Column> get primaryKey => {entryId};
}
