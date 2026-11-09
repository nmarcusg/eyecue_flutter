"""Build an isolated EyeCue Study APK with the retained local signing key.

Signing config stays outside the repository. Telemetry URL/publishable key come
from the environment. The verifier pins both the install ID and certificate.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from verify_study_apk import verify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-number', required=True, type=int)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--signing-config', type=Path, default=Path.home() /
                        '.config/eyecue/signing/study/signing.json')
    args = parser.parse_args()
    if not 1 <= args.build_number <= 999999999:
        raise SystemExit('Build number must be between 1 and 999999999')
    root = Path(__file__).resolve().parents[1]
    config = json.loads(args.signing_config.read_text())
    env = os.environ.copy()
    for key, variable in {
        'storeFile': 'EYECUE_KEYSTORE_PATH',
        'storePassword': 'EYECUE_KEYSTORE_PASSWORD',
        'keyAlias': 'EYECUE_KEY_ALIAS',
        'keyPassword': 'EYECUE_KEY_PASSWORD',
    }.items():
        if not config.get(key):
            raise SystemExit(f'Signing configuration missing {key}; no key will be generated')
        env[variable] = config[key]
    url = env.get('EYECUE_TELEMETRY_INGEST_URL', '')
    public_key = env.get('EYECUE_SUPABASE_PUBLISHABLE_KEY', '')
    if not url.startswith('https://') or not public_key.startswith('sb_publishable_'):
        raise SystemExit('Provide the HTTPS telemetry URL and publishable client key')
    # Only this build process is constrained; no project/user files are edited.
    env['GRADLE_OPTS'] = (
        '-Dorg.gradle.jvmargs="-Xmx2g -XX:MaxMetaspaceSize=768m '
        '-XX:ReservedCodeCacheSize=128m" -Dorg.gradle.workers.max=1 '
        '-Dorg.gradle.daemon=false -Dkotlin.compiler.execution.strategy=in-process'
    )
    subprocess.run([
        'flutter', 'build', 'apk', '--release', '--no-pub',
        '--flavor', 'study', '-t', 'lib/main_study.dart',
        '--build-name=1.0.0', f'--build-number={args.build_number}',
        f'--dart-define=EYECUE_APP_VERSION=1.0.0-study+{args.build_number}',
        f'--dart-define=EYECUE_TELEMETRY_INGEST_URL={url}',
        f'--dart-define=EYECUE_SUPABASE_PUBLISHABLE_KEY={public_key}',
    ], cwd=root, env=env, check=True)
    apk = root / 'build/app/outputs/flutter-apk/app-study-release.apk'
    info = verify(apk)
    info['commit'] = subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    info['telemetry'] = 'configured'
    args.output_dir.mkdir(parents=True, exist_ok=True)
    target = args.output_dir / f'eyecue-study-v{args.build_number}.apk'
    shutil.copy2(apk, target)
    (args.output_dir / 'BUILD.json').write_text(json.dumps(info, indent=2) + '\n')
    (args.output_dir / 'SHA256SUMS').write_text(
        f"{info['apkSha256']}  {target.name}\n")
    print(json.dumps(info, indent=2))
    print(f'Verified APK: {target}')


if __name__ == '__main__':
    main()
