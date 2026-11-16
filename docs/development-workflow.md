# EyeCue — Development Workflow

Reviewed **2026-11-16**. This guide applies to the current single-engine public/Study project. Use the code and selected revision as implementation truth; dated docs provide evidence and context.

## Start a session

1. Read [project status](project-status.md), [known issues](known-issues.md), and the most recent [session log](session-log.md) entries.
2. Inspect `git status --short`, the current branch/HEAD, and remote divergence. Preserve existing edits; do not automatically merge or reset a dirty checkout.
3. Read the relevant architecture, model, data, UI, or release contract from the [documentation index](index.md).
4. Choose the smallest task and record what would demonstrate success.

The active checkout is `/home/nico/repos/eyecue_flutter`. Old worktrees were removed after verified archival under `/home/nico/repos/eyecue-archive/2026-11-16`. Their branches and local-file snapshots can be recovered; there is no need to keep one checkout per experiment. Recreate a worktree only when concurrent development needs it.

## Restore the development environment

CI uses Flutter 3.44.2. `pubspec.yaml` requires **Dart** >=3.12.0 <4.0.0; this is not a Flutter 3.12 requirement. Native Java compilation targets Java 17. Android SDK versions come from the selected Flutter toolchain.

```bash
cd /home/nico/repos/eyecue_flutter
flutter pub get
flutter run --flavor public -t lib/main.dart
```

The Study entry point adds research sessions and reporting:

```bash
flutter run --flavor study -t lib/main_study.dart
```

Study tasks require the retained signing configuration even in debug mode. Follow [Study installation](study-installation.md) and [release signing](release-procedure.md); do not regenerate a replacement identity/key casually. Build/cache directories were deliberately removed to save space and will regenerate when needed.

## Implement and verify

Follow the existing constructor-injected services and pure-policy patterns. Keep the public/Study boundary, model identity, persisted schema compatibility, and TalkBack/EyeCue speech ownership explicit. Engine selection currently has only Ultralytics; Custom-isolate instructions in old records are historical.

Select checks that cover the change:

```bash
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
node --test supabase/functions/ingest-telemetry/validate.test.mjs
```

Run dependency resolution first when caches are absent. Use targeted tests during implementation and the required wider gates before distributing. Native plugin changes also need native compilation and device evidence; a Dart suite alone does not cover them. Match flavor/entry point for builds:

```bash
flutter build apk --debug --flavor public -t lib/main.dart
```

Documentation-only edits need factual/source review, local link checks, and `git diff --check`; an APK build or a fresh performance claim is unnecessary. Record commands actually run and their revision, rather than copying a previous test total. See [testing plan](testing-plan.md) and [benchmark procedure](benchmark-procedure.md).

## Finish a session

- Update affected current contracts and [project status](project-status.md) when behavior or priorities change.
- Prepend a dated [session entry](session-log.md) with scope, revision, evidence, limits, decisions, and next work. Preserve previous entries.
- Update the [changelog](changelog.md) for meaningful behavior/tooling changes and the [progress log](implementation-progress.md) when a task is completed.
- Keep historical plans, audits, and test/device outcomes tied to their dates. Link to the current contract instead of rewriting an old result.
- Review the diff and keep secrets, datasets, caches, and local signing material outside tracked changes. Commit only the intended work when committing is requested.

## Documentation ownership

Current guidance lives in root `docs/` and the root README. `docs/frontend-workflow/` preserves design/implementation records; dated audits and `chat_spec.md` preserve historical evidence. Plugin upstream docs describe the generic package; [`VENDORED.md`](../plugins/ultralytics_yolo/VENDORED.md) records EyeCue-specific differences. Do not replace license text or upstream changelog history with app documentation. The [file-by-file audit](documentation-audit.md) records review coverage and exceptions.
