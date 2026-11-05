"""Verify the separate install identity and retained study certificate.

Uses Android SDK build tools; never reads or prints private signing material.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

STUDY_PACKAGE = 'app.eyecue.mobile.study'
STUDY_LABEL = 'EyeCue Study'
STUDY_CERT_SHA256 = 'f4e68ef0d166e3aafd1113f6b5ba0de7a0a12fb8a6b4d0a65c6bd67f1152da29'


def sdk_tool(name):
    sdk = Path(os.environ.get('ANDROID_HOME') or
               os.environ.get('ANDROID_SDK_ROOT') or
               Path.home() / 'Android' / 'Sdk')
    tools = list((sdk / 'build-tools').glob(f'*/{name}'))
    if not tools:
        raise RuntimeError(f'Android SDK tool missing: {name}')
    return max(tools, key=lambda p: tuple(int(n) for n in re.findall(r'\d+', p.parent.name)))


def verify(apk):
    certs = subprocess.check_output(
        [str(sdk_tool('apksigner')), 'verify', '--print-certs', str(apk)], text=True)
    certificates = re.findall(r'certificate SHA-256 digest: ([0-9a-f]+)', certs)
    if certificates != [STUDY_CERT_SHA256]:
        raise RuntimeError('Study signing certificate differs from the retained key')
    badging = subprocess.check_output(
        [str(sdk_tool('aapt')), 'dump', 'badging', str(apk)], text=True)
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
    if not package or package[1] != STUDY_PACKAGE:
        raise RuntimeError('APK would not install under the separate study identity')
    if f"application-label:'{STUDY_LABEL}'" not in badging:
        raise RuntimeError('Study launcher label is missing')
    return {
        'applicationId': package[1], 'versionCode': int(package[2]),
        'versionName': package[3], 'label': STUDY_LABEL,
        'certificateSha256': certificates[0],
        'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
        'apkBytes': apk.stat().st_size,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.apk), indent=2))
