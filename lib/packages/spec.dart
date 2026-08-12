// What a download job covers. Plain data, so the web build can carry the same
// rows without the queue behind them.

sealed class PackageSpec {
  const PackageSpec();

  factory PackageSpec.fromJson(Map<String, dynamic> json) =>
      switch (json['kind']) {
        'letter' => LetterPackage(json['letter'] as String),
        'list' => ListPackage(json['listId'] as String, json['name'] as String),
        'entry' => EntryPackage(json['entryId'] as int, json['text'] as String),
        _ => const AllPackage(),
      };

  String get id;
  String get label;
  Map<String, dynamic> toJson();
}

class AllPackage extends PackageSpec {
  const AllPackage();

  @override
  String get id => 'all';
  @override
  String get label => 'Alle Gebärden';
  @override
  Map<String, dynamic> toJson() => {'kind': 'all'};
}

class LetterPackage extends PackageSpec {
  const LetterPackage(this.letter);

  final String letter;

  @override
  String get id => 'letter:$letter';
  @override
  String get label => 'Buchstabe $letter';
  @override
  Map<String, dynamic> toJson() => {'kind': 'letter', 'letter': letter};
}

class ListPackage extends PackageSpec {
  const ListPackage(this.listId, this.name);

  final String listId;
  final String name;

  @override
  String get id => 'list:$listId';
  @override
  String get label => name;
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'list',
    'listId': listId,
    'name': name,
  };
}

class EntryPackage extends PackageSpec {
  const EntryPackage(this.entryId, this.text);

  final int entryId;
  final String text;

  @override
  String get id => 'entry:$entryId';
  @override
  String get label => text;
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'entry',
    'entryId': entryId,
    'text': text,
  };
}
