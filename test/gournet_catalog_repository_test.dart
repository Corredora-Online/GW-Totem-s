import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/data/remote/gournet_catalog_repository.dart';
import 'package:gournet_kiosk/domain/models/category.dart';
import 'package:gournet_kiosk/domain/models/product.dart';
import 'package:gournet_kiosk/domain/repositories/catalog_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const fallbackCatalog = CatalogData(
  categories: [Category(id: 'cafeteria', name: 'Cafetería', sortOrder: 1)],
  products: [
    Product(
      id: 'local',
      sku: 'CAF-001',
      name: 'Producto local',
      description: 'Respaldo',
      price: 1,
      categoryId: 'cafeteria',
      image: 'assets/images/products/espresso.png',
      available: true,
      tags: ['Local'],
      modifierGroups: [],
    ),
  ],
);

final apiPayload = [
  {
    '_ID': '32',
    'sku': 'CAF-001',
    'nombre': 'Espresso remoto',
    'categoria': 'Cafetería',
    'descripcion': 'Descripción desde la API',
    'precio_base': '2500',
    'disponibilidad': 'disponible',
    'control_stock': 'true',
    'stock': '10',
    'imagen_principal': 'https://images.example/espresso.png',
    'atributos_alimentarios': {'vegano': 'true', 'sin_gluten': 'true'},
    'nivel_picante': 'ninguno',
    'orden': '10',
    // La API ya filtró este registro usando el TUS de la query. Este campo
    // puede contener el _ID interno y no debe volver a filtrarse en la app.
    'sucursales': '24',
    'ultimo_cambio': '2026-08-31 09:27:43',
  },
  {
    '_ID': '31',
    'sku': 'TEST-001',
    'nombre': 'Producto sin precio',
    'categoria': 'Pruebas',
    'descripcion': '',
    'precio_base': '0',
    'disponibilidad': 'disponible',
    'control_stock': 'false',
    'stock': '0',
    'imagen_principal': null,
    'orden': '20',
  },
];

class _FallbackRepository implements CatalogRepository {
  const _FallbackRepository();

  @override
  Future<CatalogData> loadCatalog() async => fallbackCatalog;
}

void main() {
  test('descarga, mapea y guarda el catálogo Gour-net localmente', () async {
    final directory = await Directory.systemTemp.createTemp('gournet-catalog-');
    addTearDown(() => directory.delete(recursive: true));
    late http.Request catalogRequest;
    final client = MockClient((request) async {
      if (request.url.host == 'images.example') {
        return http.Response.bytes([1, 2, 3, 4], 200);
      }
      catalogRequest = request;
      return http.Response(
        jsonEncode(apiPayload),
        200,
        headers: {'etag': 'catalog-v1'},
      );
    });
    final repository = GournetCatalogRepository(
      apiKey: 'test-api-key',
      tus: '5QQTw5u1K8ed',
      client: client,
      storageDirectory: () async => directory,
      fallback: const _FallbackRepository(),
    );
    addTearDown(repository.dispose);

    final catalog = await repository.loadCatalog();

    expect(catalogRequest.headers['apiKey'], 'test-api-key');
    expect(catalogRequest.url.queryParameters['tus'], '5QQTw5u1K8ed');
    expect(catalog.products, hasLength(1));
    expect(catalog.products.single.id, '32');
    expect(catalog.products.single.name, 'Espresso remoto');
    expect(catalog.products.single.price, 2500);
    expect(catalog.products.single.tags, containsAll(['Vegano', 'Sin gluten']));
    expect(catalog.products.single.image, startsWith(directory.path));
    expect(catalog.categories.single.id, 'cafeteria');
    expect(
      File('${directory.path}/gournet-catalog-cache.json').existsSync(),
      isTrue,
    );
    final cache = jsonDecode(
      await File('${directory.path}/gournet-catalog-cache.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(cache['tus'], '5QQTw5u1K8ed');
    expect(cache['products'], isNotEmpty);
  });

  test('usa ETag y conserva la copia local ante un 304', () async {
    final directory = await Directory.systemTemp.createTemp('gournet-etag-');
    addTearDown(() => directory.delete(recursive: true));
    final first = GournetCatalogRepository(
      apiKey: 'test-api-key',
      tus: '5QQTw5u1K8ed',
      client: MockClient((request) async {
        if (request.url.host == 'images.example') {
          return http.Response.bytes([1], 200);
        }
        return http.Response(
          jsonEncode(apiPayload),
          200,
          headers: {'etag': 'catalog-v1'},
        );
      }),
      storageDirectory: () async => directory,
      fallback: const _FallbackRepository(),
    );
    await first.loadCatalog();
    first.dispose();

    final second = GournetCatalogRepository(
      apiKey: 'test-api-key',
      tus: '5QQTw5u1K8ed',
      client: MockClient((request) async {
        expect(request.headers['if-none-match'], 'catalog-v1');
        expect(request.url.queryParameters['tus'], '5QQTw5u1K8ed');
        return http.Response('', 304);
      }),
      storageDirectory: () async => directory,
      fallback: const _FallbackRepository(),
    );
    addTearDown(second.dispose);

    final catalog = await second.loadCatalog();

    expect(catalog.products.single.name, 'Espresso remoto');
  });
}
