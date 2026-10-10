import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/config/gournet_api_config.dart';
import '../../domain/models/category.dart';
import '../../domain/models/product.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../mock/mock_catalog_repository.dart';

typedef CatalogDirectoryResolver = Future<Directory> Function();

class GournetCatalogRepository implements CatalogRepository {
  GournetCatalogRepository({
    this.apiKey = GournetApiConfig.apiKey,
    this.tus = GournetApiConfig.branchCode,
    Uri? endpoint,
    this.requestTimeout = GournetApiConfig.requestTimeout,
    http.Client? client,
    CatalogDirectoryResolver? storageDirectory,
    CatalogRepository? fallback,
  }) : endpoint = endpoint ?? GournetApiConfig.catalogUri,
       _client = client ?? http.Client(),
       _storageDirectory = storageDirectory ?? getApplicationSupportDirectory,
       _fallback = fallback ?? MockCatalogRepository();

  static const _cacheVersion = 2;
  static const _cacheFilename = 'gournet-catalog-cache.json';
  static const _imageDirectoryName = 'gournet-catalog-images';

  final String apiKey;
  final String tus;
  final Uri endpoint;
  final Duration requestTimeout;
  final http.Client _client;
  final CatalogDirectoryResolver _storageDirectory;
  final CatalogRepository _fallback;

  void dispose() => _client.close();

  @override
  Future<CatalogData> loadCatalog() async {
    final fallbackCatalog = await _fallback.loadCatalog();
    final directory = await _resolveStorageDirectory();
    final cached = directory == null ? null : await _readCache(directory);

    try {
      final headers = {'accept': 'application/json', 'apiKey': apiKey};
      final cachedEtag = cached?.etag;
      if (cachedEtag != null) headers['if-none-match'] = cachedEtag;
      final requestUri = endpoint.replace(
        queryParameters: {...endpoint.queryParameters, 'tus': tus.trim()},
      );
      final response = await _client
          .get(requestUri, headers: headers)
          .timeout(requestTimeout);

      if (response.statusCode == HttpStatus.notModified && cached != null) {
        return await _mapCatalog(cached.products, fallbackCatalog, directory);
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Catálogo Gour-net respondió HTTP ${response.statusCode}.',
          uri: requestUri,
        );
      }

      final products = _decodeProducts(response.body);
      final etag = response.headers['etag'];
      if (directory != null &&
          (cached == null ||
              cached.etag != etag ||
              !_samePayload(cached.products, products))) {
        await _writeCache(directory, products, etag);
      }
      return await _mapCatalog(products, fallbackCatalog, directory);
    } catch (_) {
      if (cached != null) {
        return await _mapCatalog(cached.products, fallbackCatalog, directory);
      }
      return fallbackCatalog;
    }
  }

  Future<Directory?> _resolveStorageDirectory() async {
    try {
      final directory = await _storageDirectory();
      if (!await directory.exists()) await directory.create(recursive: true);
      return directory;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _decodeProducts(String body) {
    if (body.trim().isEmpty) {
      throw const FormatException('La API devolvió un cuerpo vacío.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! List<dynamic>) {
      throw const FormatException('El catálogo no es un array JSON.');
    }
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }

  Future<_CachedCatalog?> _readCache(Directory directory) async {
    try {
      final file = File('${directory.path}/$_cacheFilename');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != _cacheVersion ||
          decoded['tus'] != tus.trim() ||
          decoded['products'] is! List<dynamic>) {
        return null;
      }
      final products = (decoded['products'] as List<dynamic>)
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList(growable: false);
      return _CachedCatalog(
        products: products,
        etag: decoded['etag'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(
    Directory directory,
    List<Map<String, dynamic>> products,
    String? etag,
  ) async {
    final target = File('${directory.path}/$_cacheFilename');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': _cacheVersion,
        'tus': tus.trim(),
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'etag': etag,
        'products': products,
      }),
      flush: true,
    );
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  bool _samePayload(
    List<Map<String, dynamic>> cached,
    List<Map<String, dynamic>> remote,
  ) => jsonEncode(cached) == jsonEncode(remote);

  Future<CatalogData> _mapCatalog(
    List<Map<String, dynamic>> records,
    CatalogData fallbackCatalog,
    Directory? directory,
  ) async {
    final fallbackBySku = {
      for (final product in fallbackCatalog.products) product.sku: product,
    };
    final cachedImages = directory == null
        ? const <String, String>{}
        : await _cacheImages(records, directory);
    final mapped = <_OrderedProduct>[];

    for (final record in records) {
      final sku = _string(record['sku']);
      final fallback = fallbackBySku[sku];
      final name = _string(record['nombre']);
      if (!_boolean(record['publicar_comercio_virtual']) || name.isEmpty) {
        continue;
      }
      final price = _integer(record['precio_comercio_virtual']);

      final id = _string(record['_ID']).isNotEmpty
          ? _string(record['_ID'])
          : sku;
      final categoryName = _string(record['categoria']).isEmpty
          ? 'Sin categoría'
          : _string(record['categoria']);
      final categoryId = _slug(categoryName);
      final remoteImage = _string(record['imagen_principal']);
      final tags = _dietaryTags(record['atributos_alimentarios']);
      final spicy = _string(record['nivel_picante']);
      if (spicy.isNotEmpty && spicy.toLowerCase() != 'ninguno') {
        tags.add('Picante ${_humanize(spicy).toLowerCase()}');
      }
      final available =
          _string(record['disponibilidad']).toLowerCase() == 'disponible';

      mapped.add(
        _OrderedProduct(
          order: _integer(record['orden']),
          categoryName: categoryName,
          product: Product(
            id: id,
            sku: sku,
            name: name,
            description: _string(record['descripcion']),
            price: price,
            categoryId: categoryId,
            image:
                cachedImages[id] ??
                (remoteImage.isNotEmpty
                    ? remoteImage
                    : fallback?.image ??
                          'assets/images/products/cheeseburger.png'),
            available: available,
            tags: tags.isNotEmpty ? tags : fallback?.tags ?? const [],
            modifierGroups: fallback?.modifierGroups ?? const [],
          ),
        ),
      );
    }

    mapped.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.product.name.compareTo(b.product.name);
    });

    final categoryOrder = <String, int>{};
    final categoryNames = <String, String>{};
    for (final item in mapped) {
      final id = item.product.categoryId;
      categoryNames[id] = item.categoryName;
      final current = categoryOrder[id];
      if (current == null || item.order < current) {
        categoryOrder[id] = item.order;
      }
    }
    final categories =
        categoryNames.entries
            .map(
              (entry) => Category(
                id: entry.key,
                name: entry.value,
                sortOrder: categoryOrder[entry.key] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return CatalogData(
      categories: categories,
      products: mapped.map((item) => item.product).toList(growable: false),
    );
  }

  Future<Map<String, String>> _cacheImages(
    List<Map<String, dynamic>> records,
    Directory directory,
  ) async {
    final imageDirectory = Directory('${directory.path}/$_imageDirectoryName');
    try {
      if (!await imageDirectory.exists()) {
        await imageDirectory.create(recursive: true);
      }
      final entries = await Future.wait(
        records.map((record) => _cacheImage(record, imageDirectory)),
      );
      return {
        for (final entry in entries)
          if (entry != null) entry.$1: entry.$2,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<(String, String)?> _cacheImage(
    Map<String, dynamic> record,
    Directory directory,
  ) async {
    final id = _string(record['_ID']);
    final imageUrl = _string(record['imagen_principal']);
    if (id.isEmpty || imageUrl.isEmpty) return null;
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || !uri.hasScheme) return null;

    final extension = _safeExtension(uri.pathSegments.lastOrNull);
    final version = _slug(_string(record['ultimo_cambio']));
    final file = File(
      '${directory.path}/${_slug(id)}_${version.isEmpty ? 'current' : version}.$extension',
    );
    if (await file.exists() && await file.length() > 0) return (id, file.path);

    try {
      final response = await _client.get(uri).timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok || response.bodyBytes.isEmpty) {
        return null;
      }
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      await temporary.rename(file.path);
      return (id, file.path);
    } catch (_) {
      return null;
    }
  }

  List<String> _dietaryTags(Object? value) {
    final raw = <String>[];
    if (value is List<dynamic>) {
      raw.addAll(value.where((item) => item != null).map((item) => '$item'));
    } else if (value is Map<dynamic, dynamic>) {
      for (final entry in value.entries) {
        if (_boolean(entry.value)) raw.add(entry.key.toString());
      }
    } else if (value is String && value.trim().isNotEmpty) {
      raw.addAll(value.split(','));
    }
    return raw
        .map((item) => _humanize(item))
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: true);
  }

  String _humanize(String value) {
    final text = value.trim().replaceAll('_', ' ').toLowerCase();
    if (text.isEmpty) return '';
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }

  String _string(Object? value) => value?.toString().trim() ?? '';

  int _integer(Object? value) =>
      int.tryParse(_string(value).replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;

  bool _boolean(Object? value) =>
      value == true ||
      const {
        'true',
        '1',
        'yes',
        'si',
        'sí',
      }.contains(_string(value).toLowerCase());

  String _slug(String value) {
    var result = value.toLowerCase();
    const replacements = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String _safeExtension(String? filename) {
    final extension = filename?.split('.').last.toLowerCase() ?? '';
    return const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)
        ? extension
        : 'jpg';
  }
}

class _CachedCatalog {
  const _CachedCatalog({required this.products, required this.etag});

  final List<Map<String, dynamic>> products;
  final String? etag;
}

class _OrderedProduct {
  const _OrderedProduct({
    required this.order,
    required this.categoryName,
    required this.product,
  });

  final int order;
  final String categoryName;
  final Product product;
}

extension on List<String> {
  String? get lastOrNull => isEmpty ? null : last;
}
