import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config/gournet_api_config.dart';

class GournetActivationRepository {
  GournetActivationRepository({
    Uri? endpoint,
    this.requestTimeout = GournetApiConfig.requestTimeout,
    http.Client? client,
  }) : endpoint = endpoint ?? GournetApiConfig.activationUri,
       _client = client ?? http.Client();

  final Uri endpoint;
  final Duration requestTimeout;
  final http.Client _client;

  void dispose() => _client.close();

  /// Devuelve null mientras el código todavía no ha sido activado por soporte.
  Future<String?> check(String token) async {
    final response = await _client
        .post(
          endpoint,
          headers: const {
            'accept': 'application/json',
            'content-type': 'application/json',
          },
          body: jsonEncode({'token': token}),
        )
        .timeout(requestTimeout);
    if (response.statusCode != HttpStatus.ok) return null;
    if (response.body.trim().isEmpty) {
      throw const FormatException('La activación respondió sin contenido.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<dynamic, dynamic>) {
      throw const FormatException('La activación respondió un JSON inválido.');
    }
    final apiKey = decoded['apiKey']?.toString().trim() ?? '';
    if (apiKey.isEmpty) {
      throw const FormatException('La activación no devolvió una API Key.');
    }
    return apiKey;
  }
}
