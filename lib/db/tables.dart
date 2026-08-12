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

  /// Not `text`, that name is taken by drift's own column builder.
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

/// Video and thumbnail share a videoId.
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

/// reps, lapses and suspended are ours, dart-fsrs does not track them.
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

/// `before` is the card as it stood before the review. Undo replays it.
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

  /// Null falls back to the setting. A list carries its own budget so a day
  /// spent on one does not eat the next one's.
  IntColumn get newPerDay => integer().nullable()();
  IntColumn get reviewPerDay => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A reminder belongs to a list and nothing else. Days are ISO, 1 is Monday,
/// stored as the digits the encoding already used.
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

  /// Query text, or the entry id as a string.
  TextColumn get value => text()();
  TextColumn get label => text()();
  DateTimeColumn get at => dateTime()();
}

/// The video copy makes the row usable before the detail request.
@DataClassName('StoredVariant')
class Variants extends Table {
  IntColumn get entryId => integer()();
  IntColumn get videoId => integer()();
  TextColumn get video => text().map(const VideoConverter()).nullable()();
  DateTimeColumn get at => dateTime()();

  @override
  Set<Column> get primaryKey => {entryId};
}
