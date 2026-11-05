# EyeCue Study v2 APK

This branch contains a verified installable research APK, separate from the
application source and main/dev history.

- Download: [eyecue-study-v2.apk](eyecue-study-v2.apk)
- Package: app.eyecue.mobile.study
- Launcher: EyeCue Study
- Version: 1.0.0-study, code 2
- Source: [aa4c7c26d634d2d0131ac67088802ab3134642a4](https://github.com/nmarcusg/eyecue_flutter/tree/aa4c7c26d634d2d0131ac67088802ab3134642a4)
- SHA256: 0fcf3449d60cbc87457bc951e3d4d99d7fed47c4b13531c1ad39f4be06347a5e
- Signing certificate SHA256: f4e68ef0d166e3aafd1113f6b5ba0de7a0a12fb8a6b4d0a65c6bd67f1152da29

Updates EyeCue Study v1 using the same retained signing key. It can coexist with
the original EyeCue. No uninstall or data clearing is needed. Original EyeCue
private sessions are not imported.

Includes previous alert/distance/model logging work and Android Save as exports
for complete saved trials in JSON/CSV. Internal trial storage remains independent.
The Supabase 2MB upload cap is unchanged. Samsung document-provider behavior has
not been physically verified. Automated checks and local optimized build passed.

Source license and corresponding third-party notices are in the linked source
commit. No private signing material or respondent logs are included here.
