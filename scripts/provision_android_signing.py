"""Generate a new-device production identity locally. NEVER prints passwords.

Run once: python3 scripts/provision_android_signing.py
After authenticating gh yourself: python3 scripts/provision_android_signing.py --upload
The upload destination is intentionally fixed to the authorized repository.
"""
import base64
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / '.signing'
STORE = DIRECTORY / 'gournet-production.keystore'
PASSWORD = DIRECTORY / 'keystore-password.txt'
ALIAS = 'gournet-kiosk'
REPOSITORY = 'Corredora-Online/GW-Totem-s'

def main():
    os.umask(0o077)
    DIRECTORY.mkdir(mode=0o700, exist_ok=True)
    if '--upload' in sys.argv:
        if not STORE.is_file() or not PASSWORD.is_file():
            raise SystemExit('Generate the production key first.')
        if not shutil.which('gh'):
            raise SystemExit('Instala GitHub CLI y ejecuta gh auth login primero.')
        subprocess.run(['gh', 'auth', 'status'], check=True, stdout=subprocess.DEVNULL)
        values = {
            'ANDROID_KEYSTORE_BASE64': base64.b64encode(STORE.read_bytes()),
            'ANDROID_KEYSTORE_PASSWORD': PASSWORD.read_bytes().strip(),
            'ANDROID_KEY_ALIAS': ALIAS.encode(),
            'ANDROID_KEY_PASSWORD': PASSWORD.read_bytes().strip(),
        }
        for name, value in values.items():
            subprocess.run(['gh', 'secret', 'set', name, '--repo', REPOSITORY], input=value, check=True)
        print('Cuatro Secrets cifrados configurados sólo en ' + REPOSITORY)
        return
    if STORE.exists() or PASSWORD.exists():
        raise SystemExit('Signing identity already exists. Nothing was overwritten.')
    keytool = shutil.which('keytool')
    mac_keytool = Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool')
    if mac_keytool.exists():
        keytool = str(mac_keytool)
    if not keytool:
        raise SystemExit('Java keytool is required.')
    password = secrets.token_hex(32)
    env = dict(os.environ, GW_SIGNING_PASSWORD=password)
    subprocess.run([keytool, '-genkeypair', '-noprompt', '-keystore', str(STORE),
                    '-storetype', 'PKCS12', '-alias', ALIAS, '-keyalg', 'RSA',
                    '-keysize', '4096', '-validity', '10000',
                    '-dname', 'CN=Gour-net Kiosk, OU=Applications, O=Gour-net, C=CL',
                    '-storepass:env', 'GW_SIGNING_PASSWORD',
                    '-keypass:env', 'GW_SIGNING_PASSWORD'], env=env, check=True)
    PASSWORD.write_text(password + '\n')
    STORE.chmod(0o600)
    PASSWORD.chmod(0o600)
    print('Production identity created in .signing (ignored by Git). Back up this directory securely. No secrets printed.')

if __name__ == '__main__':
    main()
