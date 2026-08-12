class ApiVideo {
  const ApiVideo({
    required this.id,
    this.videoUrl,
    this.thumbnailUrl,
    this.license,
    this.copyright,
    this.originalHref,
    this.updatedAt,
    this.userName,
  });

  factory ApiVideo.fromJson(Map<String, dynamic> json) {
    return ApiVideo(
      id: json['id'] as int,
      videoUrl: json['videoUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      license: json['license'] as String?,
      copyright: json['copyright'] as String?,
      originalHref: json['originalHref'] as String?,
      updatedAt: json['updatedAt'] as String?,
      userName: (json['user'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }

  final int id;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? license;
  final String? copyright;
  final String? originalHref;
  final String? updatedAt;
  final String? userName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'videoUrl': videoUrl,
    'thumbnailUrl': thumbnailUrl,
    'license': license,
    'copyright': copyright,
    'originalHref': originalHref,
    'updatedAt': updatedAt,
    'user': userName == null ? null : {'name': userName},
  };

  /// Who to credit under the video.
  String get source => userName?.isNotEmpty == true
      ? userName!
      : (copyright?.isNotEmpty == true ? copyright! : 'Unbekannt');
}

/// Free-form upstream. Observed: word, phrase, example.
class ApiEntry {
  const ApiEntry({
    required this.id,
    required this.text,
    this.type,
    this.description,
    this.language,
    this.currentVideo,
    this.videos,
  });

  /// Plain parse. Normalising belongs to toCached, so hand-built entries go
  /// through the same rules.
  factory ApiEntry.fromJson(Map<String, dynamic> json) {
    final current = json['currentVideo'] as Map<String, dynamic>?;
    return ApiEntry(
      id: json['id'] as int,
      text: json['text'] as String,
      type: json['type'] as String?,
      description: json['description'] as String?,
      language:
          (json['language'] as Map<String, dynamic>?)?['shortName'] as String?,
      currentVideo: current == null ? null : ApiVideo.fromJson(current),
      videos: (json['videos'] as List?)
          ?.map((v) => ApiVideo.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }

  final int id;
  final String text;
  final String? type;
  final String? description;
  final String? language;
  final ApiVideo? currentVideo;
  final List<ApiVideo>? videos;
}
