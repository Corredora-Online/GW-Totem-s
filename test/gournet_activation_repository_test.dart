import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/data/remote/gournet_activation_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('envía el código por POST sin exponer una API Key', () async {
    late http.Request captured;
    final repository = GournetActivationRepository(
      endpoint: Uri.parse('https://example.test/iot/activacion/'),
      client: MockClient((request) async {
        captured = request;
        return http.Response('', 404);
      }),
    );
    addTearDown(repository.dispose);

    final apiKey = await repository.check('ABCD2345');

    expect(apiKey, isNull);
    expect(captured.method, 'POST');
    expect(captured.headers['content-type'], 'application/json');
    expect(captured.headers.containsKey('apiKey'), isFalse);
    expect(jsonDecode(captured.body), {'token': 'ABCD2345'});
  });

  test('extrae la API Key de una activación aprobada', () async {
    final repository = GournetActivationRepository(
      endpoint: Uri.parse('https://example.test/iot/activacion/'),
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'apiKey': 'activated-key'}), 200),
      ),
    );
    addTearDown(repository.dispose);

    expect(await repository.check('ABCD2345'), 'activated-key');
  });

  test('rechaza un 200 que no contiene una API Key', () async {
    final repository = GournetActivationRepository(
      endpoint: Uri.parse('https://example.test/iot/activacion/'),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(repository.dispose);

    expect(() => repository.check('ABCD2345'), throwsA(isA<FormatException>()));
  });
}
