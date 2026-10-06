"""Validate a release tag and create the LAST asset published to a release."""
import hashlib
import json
import pathlib
import re
import sys


def version_info(tag):
    if not re.fullmatch(r"v(?:0|[1-9][0-9]{0,2})\.(?:0|[1-9][0-9]{0,2})\.(?:0|[1-9][0-9]{0,2})", tag):
        raise ValueError("Usa un tag como v1.0.1 (componentes 0..999)")
    parts = list(map(int, tag[1:].split('.')))
    return tag[1:], parts[0] * 1000000 + parts[1] * 1000 + parts[2]


def create_manifest(tag, directory):
    version, build = version_info(tag)
    result = dict(schema=1, version=version, build=build, platforms={})
    for platform, name in [('android', 'gournet-kiosk-android.apk'), ('windows', 'gournet-kiosk-windows-x64-setup.exe')]:
        artifact = directory / name
        size = artifact.stat().st_size
        if not 0 < size <= 350 * 1024 * 1024:
            raise ValueError('Tamaño de artefacto inválido')
        with artifact.open('rb') as stream:
            digest = hashlib.sha256()
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        result['platforms'][platform] = dict(asset=name, size=size, sha256=digest.hexdigest())
    return result


if __name__ == '__main__':
    tag = sys.argv[1]
    if len(sys.argv) == 2:
        version, build = version_info(tag)
        print(f'version={version}\nbuild={build}')
    else:
        directory = pathlib.Path(sys.argv[2])
        (directory / 'update-manifest.json').write_text(json.dumps(create_manifest(tag, directory), indent=2) + '\n')
