#!/usr/bin/env bash
set -euo pipefail

# Gradle's official endpoint redirects to GitHub releases, which can return
# 504 on hosted runners. The fallback is accepted only with Gradle's published
# SHA-256; neither a failed transfer nor a checksum mismatch is used.
version=9.1.0
sha256=b84e04fa845fecba48551f425957641074fcc00a88a84d2aae5808743b35fc85
properties=android/gradle/wrapper/gradle-wrapper.properties
if ! grep -Fqx "distributionSha256Sum=$sha256" "$properties" ||
   ! grep -Fqx "distributionUrl=https\\://services.gradle.org/distributions/gradle-${version}-all.zip" "$properties"; then
  echo 'Gradle download helper and wrapper configuration disagree.' >&2
  exit 1
fi
archive="${RUNNER_TEMP:?RUNNER_TEMP must be set}/gradle-${version}-all.zip"
part="${archive}.part"
primary="${EYECUE_GRADLE_PRIMARY_URL:-https://services.gradle.org/distributions/gradle-${version}-all.zip}"
fallback="${EYECUE_GRADLE_FALLBACK_URL:-https://mirror.math.princeton.edu/pub/macports/distfiles/gradle/gradle-${version}-all.zip}"
trap 'rm -f "$part"' EXIT

download() {
  curl --fail --location --silent --show-error --retry 1 --retry-delay 2 \
    --connect-timeout 15 --max-time "$2" --output "$part" "$1"
}

if ! download "$primary" 90; then
  echo 'Official Gradle download failed; trying the checksum-verified fallback.'
  rm -f "$part"
  download "$fallback" 360
fi
printf '%s  %s\n' "$sha256" "$part" | sha256sum --check --status
mv "$part" "$archive"

# The wrapper still verifies distributionSha256Sum when installing this file.
# This temporary modification only affects the CI checkout.
python3 - "$archive" "$properties" <<'PY'
from pathlib import Path
import sys

archive = Path(sys.argv[1]).resolve()
properties = Path(sys.argv[2])
lines = properties.read_text().splitlines()
assert sum(line.startswith('distributionUrl=') for line in lines) == 1
properties.write_text('\n'.join(
    f'distributionUrl={archive.as_uri()}' if line.startswith('distributionUrl=') else line
    for line in lines
) + '\n')
PY
