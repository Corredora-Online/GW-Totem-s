import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class AppRelease {
  static const version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );
  static const build = int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 1);
  static const repository = 'Corredora-Online/GW-Totem-s';
  static const base = 'https://github.com/$repository/releases';
}

class ReleaseArtifact {
  const ReleaseArtifact(
    this.version,
    this.build,
    this.name,
    this.hash,
    this.size,
  );
  final String version;
  final int build;
  final String name;
  final String hash;
  final int size;
  Uri get uri => Uri.parse('${AppRelease.base}/download/v$version/$name');

  static ReleaseArtifact? parse(
    Map<String, dynamic> json,
    String platform,
    int currentBuild,
  ) {
    if (json['schema'] != 1) {
      throw const FormatException('Manifiesto no compatible');
    }
    final version = json['version'];
    final build = json['build'];
    if (version is! String ||
        !RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(version) ||
        build is! int) {
      throw const FormatException('Versión inválida');
    }
    final parts = version.split('.').map(int.parse).toList();
    if (build != parts[0] * 1000000 + parts[1] * 1000 + parts[2]) {
      throw const FormatException('Correlativo inválido');
    }
    if (build <= currentBuild) return null;
    final data = (json['platforms'] as Map?)?[platform];
    if (data is! Map) throw const FormatException('Plataforma no disponible');
    final name = platform == 'android'
        ? 'gournet-kiosk-android.apk'
        : 'gournet-kiosk-windows-x64-setup.exe';
    final hash = data['sha256'];
    final size = data['size'];
    if (data['asset'] != name ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        size is! int ||
        size < 1 ||
        size > 350 * 1024 * 1024) {
      throw const FormatException('Archivo de actualización inválido');
    }
    return ReleaseArtifact(version, build, name, hash, size);
  }
}

/// Public Releases only. Never sends Gour-net credentials or a GitHub token.
class ReleaseUpdater {
  Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
    for (var redirects = 0; redirects < 6; redirects++) {
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          !const {
            'github.com',
            'release-assets.githubusercontent.com',
            'objects.githubusercontent.com',
          }.contains(uri.host)) {
        throw const FormatException('Destino de descarga no permitido');
      }
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 25));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (!const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>().timeout(const Duration(seconds: 25));
      if (location == null) {
        throw const FormatException('Redirección sin destino');
      }
      uri = uri.resolve(location);
    }
    throw const FormatException('Demasiadas redirecciones');
  }

  Future<ReleaseArtifact?> check(String platform) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 25);
    try {
      final response = await _get(
        client,
        Uri.parse('${AppRelease.base}/latest/download/update-manifest.json'),
      );
      if (response.statusCode == 404) return null; // No complete release yet.
      if (response.statusCode != 200) {
        throw HttpException('Actualizaciones: HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 25))) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) {
          throw const FormatException('Manifiesto demasiado grande');
        }
      }
      return ReleaseArtifact.parse(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        platform,
        AppRelease.build,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> verified(File file, ReleaseArtifact artifact) async =>
      await file.exists() &&
      await file.length() == artifact.size &&
      (await sha256.bind(file.openRead()).first).toString() == artifact.hash;

  Future<File> download(ReleaseArtifact artifact) async {
    final support = await getApplicationSupportDirectory();
    final directory = await Directory('${support.path}/updates')
        .create(recursive: true);
    final file = File('${directory.path}/${artifact.build}-${artifact.name}');
    if (await verified(file, artifact)) return file;
    final partial = File('${file.path}.partial');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 25);
    IOSink? sink;
    try {
      final response = await _get(client, artifact.uri);
      if (response.statusCode != 200) {
        throw HttpException('Descarga: HTTP ${response.statusCode}');
      }
      sink = partial.openWrite();
      var count = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        count += chunk.length;
        if (count > artifact.size) {
          throw const FormatException('Tamaño de descarga inválido');
        }
        sink.add(chunk);
      }
      await sink.close();
      sink = null;
      if (!await verified(partial, artifact)) {
        throw const FormatException(
          'La descarga no pasó la verificación SHA-256',
        );
      }
      return await partial.rename(file.path);
    } finally {
      client.close(force: true);
      await sink?.close();
      if (await partial.exists()) await partial.delete();
    }
  }
}
