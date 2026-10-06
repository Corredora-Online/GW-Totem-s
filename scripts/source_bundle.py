"""One-time reviewed source export, excluding secrets and generated output."""
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ROOTS = ['lib', 'test', 'android', 'windows', 'assets', 'scripts', 'docs', 'packaging', 'README.md', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.metadata', '.gitignore']
SKIP_PARTS = {'build', '.gradle', 'ephemeral', '.git', '.dart_tool', '__pycache__', '.cxx'}
SKIP_NAMES = {'local.properties', 'key.properties', '.DS_Store', 'GeneratedPluginRegistrant.java'}
SKIP_SUFFIXES = {'.keystore', '.jks', '.apk', '.aab', '.iml', '.log', '.zip', '.pyc'}
SECRET = re.compile(rb'gw_live_[A-Za-z0-9_.-]{20,}|ghp_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{25,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----')

def bundle():
    files = []
    for root in ROOTS:
        path = ROOT / root
        for file in ([path] if path.is_file() else sorted(path.rglob('*'))):
            relative = file.relative_to(ROOT)
            if not file.is_file() or file.is_symlink() or SKIP_PARTS.intersection(relative.parts) or file.name in SKIP_NAMES or file.suffix in SKIP_SUFFIXES:
                continue
            if SECRET.search(file.read_bytes()):
                raise SystemExit(f'Credential-like content: {relative}; export stopped')
            files.append(file)
    output = ROOT / 'project-source.zip'
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in files:
            archive.write(file, file.relative_to(ROOT))
    print(f'{len(files)} source files; {output.stat().st_size} bytes; {output}')

if __name__ == '__main__':
    bundle()
