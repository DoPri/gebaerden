import 'dart:convert';

import 'package:drift/drift.dart';

import '../api/types.dart';

class VideoConverter extends TypeConverter<ApiVideo?, String?>
    with JsonTypeConverter<ApiVideo?, String?> {
  const VideoConverter();

  @override
  ApiVideo? fromSql(String? raw) => raw == null
      ? null
      : ApiVideo.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  @override
  String? toSql(ApiVideo? value) =>
      value == null ? null : jsonEncode(value.toJson());
}

class VideoListConverter extends TypeConverter<List<ApiVideo>?, String?>
    with JsonTypeConverter<List<ApiVideo>?, String?> {
  const VideoListConverter();

  @override
  List<ApiVideo>? fromSql(String? raw) => raw == null
      ? null
      : (jsonDecode(raw) as List)
            .map((v) => ApiVideo.fromJson(v as Map<String, dynamic>))
            .toList();

  @override
  String? toSql(List<ApiVideo>? value) =>
      value == null ? null : jsonEncode(value.map((v) => v.toJson()).toList());
}

/// Untyped, the column holds whatever a screen needs.
class JsonConverter extends TypeConverter<Object?, String> {
  const JsonConverter();

  @override
  Object? fromSql(String raw) => jsonDecode(raw);

  @override
  String toSql(Object? value) => jsonEncode(value);
}
