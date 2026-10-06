import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config/gournet_api_config.dart';
import '../../domain/models/branch.dart';

class GournetBranchesRepository {
  GournetBranchesRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  void dispose() => _client.close();

  Future<List<Branch>> load({
    required String apiKey,
    required Uri endpoint,
  }) async {
    final response = await _client
        .get(
          endpoint,
          headers: {'accept': 'application/json', 'apiKey': apiKey},
        )
        .timeout(GournetApiConfig.requestTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Sucursales respondió HTTP ${response.statusCode}.',
        uri: endpoint,
      );
    }
    if (response.body.trim().isEmpty) {
      throw const FormatException('La API devolvió una respuesta vacía.');
    }
    final decoded = jsonDecode(response.body);
    final records = _records(decoded);
    final branches = records.map(_mapBranch).whereType<Branch>().toList();
    if (branches.isEmpty) {
      throw const FormatException('La API no devolvió sucursales válidas.');
    }
    branches.sort((a, b) => a.name.compareTo(b.name));
    return branches;
  }

  List<Map<String, dynamic>> _records(Object? decoded) {
    Object? value = decoded;
    if (decoded is Map<dynamic, dynamic>) {
      for (final key in const ['sucursales', 'data', 'results', 'items']) {
        if (decoded[key] is List<dynamic>) {
          value = decoded[key];
          break;
        }
      }
    }
    if (value is! List<dynamic>) {
      throw const FormatException('El listado de sucursales no es un array.');
    }
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => item.map((key, value) => MapEntry('$key', value)))
        .toList(growable: false);
  }

  Branch? _mapBranch(Map<String, dynamic> record) {
    final code = _first(record, const [
      'tus',
      'codigo_tus',
      'sucursal',
      'codigo_sucursal',
      'id_sucursal',
      'identificador',
      'codigo',
    ]);
    final internalId = _first(record, const ['_ID', 'id']);
    final id = internalId.isNotEmpty ? internalId : code;
    if (id.isEmpty) return null;
    final name = _first(record, const [
      'nombre',
      'name',
      'razon_social',
      'titulo',
    ]);
    return Branch(
      id: id,
      name: name.isEmpty ? 'Sucursal $id' : name,
      code: code,
      address: _first(record, const ['direccion', 'address', 'domicilio']),
      city: _first(record, const ['comuna', 'ciudad', 'city']),
    );
  }

  String _first(Map<String, dynamic> record, List<String> keys) {
    final normalized = {
      for (final entry in record.entries) entry.key.toLowerCase(): entry.value,
    };
    for (final key in keys) {
      final value = normalized[key.toLowerCase()]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}
