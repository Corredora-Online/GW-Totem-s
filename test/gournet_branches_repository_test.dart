import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/data/remote/gournet_branches_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('obtiene sucursales con la API Key y normaliza sus campos', () async {
    late http.Request captured;
    final repository = GournetBranchesRepository(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode([
            {
              '_ID': '24',
              'TUS': '5QQTw5u1K8ed',
              'nombre': 'Providencia',
              'direccion': 'Av. Providencia 1234',
              'comuna': 'Providencia',
            },
          ]),
          200,
        );
      }),
    );
    addTearDown(repository.dispose);

    final branches = await repository.load(
      apiKey: 'test-key',
      endpoint: Uri.parse('https://example.test/sucursales'),
    );

    expect(captured.method, 'GET');
    expect(captured.headers['apiKey'], 'test-key');
    expect(branches.single.id, '24');
    expect(branches.single.code, '5QQTw5u1K8ed');
    expect(branches.single.name, 'Providencia');
  });

  test('separa el TUS alfanumérico del _ID interno de la sucursal', () async {
    final repository = GournetBranchesRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {'_ID': '24', 'TUS': '5QQTw5u1K8ed', 'nombre': 'LOCAL'},
          ]),
          200,
        ),
      ),
    );
    addTearDown(repository.dispose);

    final branches = await repository.load(
      apiKey: 'test-key',
      endpoint: Uri.parse('https://example.test/sucursales'),
    );

    expect(branches.single.id, '24');
    expect(branches.single.code, '5QQTw5u1K8ed');
  });

  test('conserva el TUS aunque el _ID interno sea distinto', () async {
    final repository = GournetBranchesRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {'_ID': 'internal-branch-id', 'TUS': 'local-24', 'nombre': 'LOCAL'},
          ]),
          200,
        ),
      ),
    );
    addTearDown(repository.dispose);

    final branches = await repository.load(
      apiKey: 'test-key',
      endpoint: Uri.parse('https://example.test/sucursales'),
    );

    expect(branches.single.id, 'internal-branch-id');
    expect(branches.single.code, 'local-24');
  });
}
