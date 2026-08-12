import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

const endpoint = 'https://signdict.org/graphql-api';

/// signdict.org is volunteer-run.
const _maxConcurrent = 4;
const _minGap = Duration(milliseconds: 60);
const _maxAttempts = 3;

class ApiError implements Exception {
  ApiError(this.message, [this.status]);

  final String message;
  final int? status;

  @override
  String toString() => 'ApiError: $message';
}

/// Arrives with HTTP 200 and is deterministic, so never retried.
class GraphqlError implements Exception {
  GraphqlError(this.messages);

  final List<String> messages;

  bool get notFound =>
      messages.any((m) => m.toLowerCase().contains('not found'));

  @override
  String toString() => 'GraphqlError: ${messages.join('; ')}';
}

class Cancelled implements Exception {}

/// Drops a request the caller no longer wants, e.g. while typing.
class CancelToken {
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw Cancelled();
  }
}

var _active = 0;
var _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
final _waiting = <Completer<void>>[];
final _random = Random();

Future<void> _acquire() async {
  // The slot is taken before the wait and _release hands it straight on.
  // Counting up only after the wait would let a caller that arrives between
  // the handover and the resumed waiter slip past the check.
  if (_active >= _maxConcurrent) {
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  } else {
    _active++;
  }

  final now = DateTime.now();
  final wait = _nextSlot.difference(now);
  _nextSlot = (_nextSlot.isAfter(now) ? _nextSlot : now).add(_minGap);
  if (wait > Duration.zero) await Future<void>.delayed(wait);
}

void _release() {
  // The next in line inherits the slot, so the count stays put.
  if (_waiting.isNotEmpty) {
    _waiting.removeAt(0).complete();
    return;
  }
  _active--;
}

http.Client _client = http.Client();

/// Swappable for tests.
void useClient(http.Client client) => _client = client;

Future<Map<String, dynamic>> gql(
  String query, {
  Map<String, dynamic> variables = const {},
  CancelToken? cancel,
}) async {
  await _acquire();
  try {
    for (var attempt = 1; ; attempt++) {
      cancel?.throwIfCancelled();
      try {
        return await _once(query, variables);
      } on Exception catch (err) {
        if (cancel?.isCancelled == true) rethrow;
        if (attempt >= _maxAttempts || !_retriable(err)) rethrow;
        await Future<void>.delayed(
          Duration(
            milliseconds: (pow(2, attempt) as int) * 150 + _random.nextInt(150),
          ),
        );
      }
    }
  } finally {
    _release();
  }
}

Future<Map<String, dynamic>> _once(
  String query,
  Map<String, dynamic> variables,
) async {
  final res = await _client.post(
    Uri.parse(endpoint),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'query': query, 'variables': variables}),
  );

  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw ApiError('SignDict responded ${res.statusCode}', res.statusCode);
  }

  final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final errors = body['errors'] as List?;
  if (errors != null && errors.isNotEmpty) {
    throw GraphqlError([for (final e in errors) '${(e as Map)['message']}']);
  }

  final data = body['data'] as Map<String, dynamic>?;
  if (data == null) throw ApiError('SignDict returned no data');
  return data;
}

bool _retriable(Exception err) {
  if (err is Cancelled || err is GraphqlError) return false;
  if (err is ApiError) return err.status == null || err.status! >= 500;
  return true;
}
