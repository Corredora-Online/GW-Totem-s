import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/services/updates/release_updater.dart';

void main() {
  Map<String, dynamic> manifest() => {
    'schema': 1,
    'version': '1.2.3',
    'build': 1002003,
    'platforms': {
      'android': {
        'asset': 'gournet-kiosk-android.apk',
        'sha256': 'a' * 64,
        'size': 100,
      },
    },
  };
  test('new version builds a fixed repository URL without credentials', () {
    final release = ReleaseArtifact.parse(manifest(), 'android', 1)!;
    expect(
      release.uri.toString(),
      '${AppRelease.base}/download/v1.2.3/gournet-kiosk-android.apk',
    );
  });
  test('ignores equal and older builds', () {
    expect(ReleaseArtifact.parse(manifest(), 'android', 1002003), isNull);
    expect(ReleaseArtifact.parse(manifest(), 'android', 2000000), isNull);
  });
  test('rejects altered build, hash, path, and oversize payload', () {
    expect(
      () => ReleaseArtifact.parse({...manifest(), 'build': 7}, 'android', 1),
      throwsFormatException,
    );
    for (final value in [
      {'asset': '../evil.apk'},
      {'sha256': 'abc'},
      {'size': 999999999},
    ]) {
      final data = manifest();
      (data['platforms']['android'] as Map).addAll(value);
      expect(
        () => ReleaseArtifact.parse(data, 'android', 1),
        throwsFormatException,
      );
    }
  });
  test('rejects truncated or corrupted staged installers', () async {
    final dir = await Directory.systemTemp.createTemp('gournet-update-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/test.apk').writeAsBytes([1, 2, 3]);
    final artifact = ReleaseArtifact(
      '1.0.1',
      1000001,
      'gournet-kiosk-android.apk',
      sha256.convert([1, 2, 3]).toString(),
      3,
    );
    expect(await ReleaseUpdater().verified(file, artifact), true);
    await file.writeAsBytes([3, 2, 1]);
    expect(await ReleaseUpdater().verified(file, artifact), false);
    await file.writeAsBytes([1]);
    expect(await ReleaseUpdater().verified(file, artifact), false);
  });
}
