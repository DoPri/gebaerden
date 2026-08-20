import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gebaerden/api/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  tearDown(() => useClient(http.Client()));

  test('passes data through', () async {
    useClient(
      MockClient(
        (_) async => _json({
          'data': {'ok': 1},
        }),
      ),
    );
    expect(await gql('query {}'), {'ok': 1});
  });

  test('retries on 500', () async {
    var calls = 0;
    useClient(
      MockClient((_) async {
        calls++;
        return calls < 3
            ? _json({'errors': <Object>[]}, 500)
            : _json({
                'data': {'ok': 1},
              });
      }),
    );
    expect(await gql('query {}'), {'ok': 1});
    expect(calls, 3);
  });

  test('does not retry on 404', () async {
    var calls = 0;
    useClient(
      MockClient((_) async {
        calls++;
        return _json({}, 404);
      }),
    );
    await expectLater(gql('query {}'), throwsA(isA<ApiError>()));
    expect(calls, 1);
  });

  test('does not retry GraphQL errors, they arrive with 200', () async {
    var calls = 0;
    useClient(
      MockClient((_) async {
        calls++;
        return _json({
          'errors': [
            {'message': 'Not found'},
          ],
        });
      }),
    );
    await expectLater(gql('query {}'), throwsA(isA<GraphqlError>()));
    expect(calls, 1, reason: 'deterministic, every retry is wasted');
  });

  test('a cancelled request never runs', () async {
    final cancel = CancelToken()..cancel();
    useClient(MockClient((_) async => throw StateError('must not be called')));
    await expectLater(
      gql('query {}', cancel: cancel),
      throwsA(isA<Cancelled>()),
    );
  });

  test('the concurrency cap survives a caller barging into a handover', () async {
    var active = 0;
    var peak = 0;
    final gates = <Completer<void>>[];

    useClient(
      MockClient((_) async {
        active++;
        peak = active > peak ? active : peak;
        // Hold request open to test queue behavior.
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        active--;
        return _json({'data': <String, Object?>{}});
      }),
    );

    final calls = [for (var i = 0; i < 8; i++) gql('query {}')];
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(peak, 4, reason: 'four at a time is the cap');

    // Test race condition where immediate follow-up might exceed concurrency cap.
    final barge = calls.first.then((_) => gql('query {}'));
    gates.first.complete();
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(peak, 4, reason: 'the freed slot went to the queue, not to both');

    // Unblock pending gates to allow clean shutdown.
    final pump = Timer.periodic(const Duration(milliseconds: 20), (_) {
      for (final gate in [...gates]) {
        if (!gate.isCompleted) gate.complete();
      }
    });
    await Future.wait([...calls, barge]);
    pump.cancel();
  });
}
