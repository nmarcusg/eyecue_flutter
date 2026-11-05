# Separate EyeCue Study installation

EyeCue Study is an opt-in Android build for continuing research alongside an
existing EyeCue installation. It does not update, uninstall, migrate or read the
old app. Each package has its own permissions, models, settings and sessions.

| Build | Application ID | Launcher name |
| --- | --- | --- |
| Default / Play identity | `app.eyecue.mobile` | EyeCue |
| Study installation | `app.eyecue.mobile.study` | EyeCue Study |

The Kotlin namespace remains `app.eyecue.mobile`; it names source classes, not
the install identity. Framework provider authorities derive from applicationId.
The opt-in flag is `EYECUE_STUDY_BUILD=true` (or Gradle `-PeyecueStudyBuild=true`).
Study configuration refuses to build without signing material. Study release
versions carry `-study`; no study AAB/Play release is produced by CI.

## Retained signing identity

Study certificate SHA256:
`f4e68ef0d166e3aafd1113f6b5ba0de7a0a12fb8a6b4d0a65c6bd67f1152da29`

The private keystore and its credentials are outside Git, at
`~/.config/eyecue/signing/study/`, with a separate local backup under
`~/Documents/ChatGPT/Eyecue-private-signing/study/`. Both copies are on this
computer; keep an additional secure off-device backup before relying on them
for long-term distribution. Do not upload this signing folder with APKs.
Never regenerate or replace the study key for a routine update. Increase the
version code and retain the same package ID and signing certificate.

For a local build, set the existing telemetry URL and publishable client key
in the environment, then run:

```sh
python3 tool/build_study_apk.py --build-number 1 --output-dir /your/output/folder
```

The helper reads the protected signing config and verifies package, label,
signature and checksum before copying a deliverable. It never generates a key.
`tool/verify_study_apk.py APK` can check a later study artifact independently.

## Cloud builds

The existing Android workflow has an explicit `study_build` manual input. Set
four separate repository secrets using the retained study signing material:
`EYECUE_STUDY_KEYSTORE_BASE64`, `EYECUE_STUDY_KEYSTORE_PASSWORD`,
`EYECUE_STUDY_KEY_ALIAS`, and `EYECUE_STUDY_KEY_PASSWORD`.
The existing telemetry repository variables must also be configured. Secrets
must be supplied through GitHub's secret settings, never source or artifacts.
Missing keys fail the study build. A different key fails artifact verification.
The study flag and signed_release flag cannot both be enabled.

The new study installation starts empty. It does not recover the old app's
private logs. This packaging change also does not repair the existing 2MB
upload limit or private-only export flow; those require subsequent changes.
Keep the original EyeCue installed while its study records need preservation.
