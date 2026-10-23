# EyeCue — Development Workflow

> **Read this first before every development session.**

This document describes the recommended workflow for contributing to EyeCue. It is designed for both human developers and AI agents.

## Session Start Checklist

Before writing any code, complete these steps in order:

1. **Read [`project-status.md`](project-status.md)** — Understand overall progress, current milestone, current blocker, and next objective.
2. **Read [`implementation-plan.md`](implementation-plan.md)** — Review the roadmap, milestones, and feature dependencies.
3. **Review [`implementation-progress.md`](implementation-progress.md)** — See exactly what is completed, in progress, and remaining.
4. **Review [`implementation-decisions.md`](implementation-decisions.md)** — Understand why key architectural decisions were made. Do not reverse decisions without explicit discussion.
5. **Check [`known-issues.md`](known-issues.md)** — Be aware of current blockers, technical debt, and platform-specific limitations.
6. **Check [`session-log.md`](session-log.md)** — Review the last session's objectives, completed work, and next steps.

## During Development

### Scope Discipline

- **Implement only the current task.** Do not expand scope to adjacent features.
- **Do not modify unrelated files.** If a change requires touching files outside the task scope, pause and reassess.
- **Do not refactor working code** unless the refactor is explicitly part of the current task.
- **Do not optimize performance** unless the optimization is explicitly part of the current task.

### Code Quality

- Follow existing patterns in the codebase (e.g., the pure service pattern in [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart), or [`inference_cadence.dart`](../lib/services/inference_cadence.dart) for a side-effect-free policy).
- Add error handling for all new code paths.
- Prefer explicit types over `dynamic` or `var` where the type is not obvious.
- Keep methods focused and small. Extract helpers when a method exceeds ~30 lines.

### Testing

- Write unit tests for new logic (see [`testing-plan.md`](testing-plan.md) for priorities).
- Run `flutter test` after each change to verify nothing is broken.
- Run `flutter analyze` to catch static analysis issues.

### Commit Practices

- Commit each logical change separately.
- Write descriptive commit messages referencing the milestone and task.

## After Development

### Documentation Updates

After completing a task, update the relevant documentation:

1. **Append to [`session-log.md`](session-log.md):**
   - Add a new entry at the top with today's date
   - Record: objective, completed work, issues encountered, decisions made, next session's focus

2. **Update [`changelog.md`](changelog.md):**
   - If the session completed a version milestone, add an entry
   - List Added, Changed, Removed, Fixed under the version heading

3. **Update [`implementation-progress.md`](implementation-progress.md):**
   - Mark completed tasks as ✅
   - Update "Current Work" section
   - Update "Last Updated" timestamp

4. **Update [`project-status.md`](project-status.md):**
   - Update "Recent Accomplishments" if the task was significant
   - Update "Current Blocker" if resolved
   - Update "Last Updated" timestamp

5. **Update [`known-issues.md`](known-issues.md):**
   - Remove resolved blockers
   - Add new technical debt items discovered
   - Update planned fix status

6. **Log implementation decisions** in [`implementation-decisions.md`](implementation-decisions.md) if a significant new decision was made.

7. **Update [`benchmark-results.md`](benchmark-results.md)** if any performance measurements were taken.

8. **Update [`research-notes.md`](research-notes.md)** if new papers, benchmarks, or ideas were explored.

### Verification

- Verify the app builds: `flutter build apk --debug`
- Verify the app runs on the test device
- Verify no regressions in existing functionality
- Verify all documentation links are still valid

## Common Tasks Reference

### Adding a New Dependency

1. Add to `pubspec.yaml`
2. Run `flutter pub get`
3. Document in [`architecture.md`](architecture.md) (External Dependencies table)
4. Explain rationale in commit message

### Adding a New Source File

1. Place in the appropriate directory:
   - `lib/models/` — data classes
   - `lib/screens/` — full-screen widgets
   - `lib/services/` — business logic, isolates, API wrappers
   - `lib/widgets/` — reusable UI components (create if needed)
2. Follow existing naming conventions (`snake_case.dart`)
3. Update [`architecture.md`](architecture.md) folder structure if significant

### Running Benchmarks

1. Use the official TFLite benchmark tool: `android_aarch64_benchmark_model`
2. Record results in [`benchmark-results.md`](benchmark-results.md)
3. Update [`project-status.md`](project-status.md) if results change priorities

## File Ownership

| File/Directory | Purpose | When to Modify |
|----------------|---------|----------------|
| `lib/` | Application source code | During feature implementation |
| `test/` | Automated tests | When adding/updating tests |
| `assets/` | Model files, labels, images | When updating ML models or labels |
| `docs/` | Project documentation | After every development session |
| `pubspec.yaml` | Dependencies | When adding/removing packages |
| `chat_spec.md` | Historical specification | **Never** — preserve as historical record |
| `auditor.md` | Project audit | When a full re-audit is needed |

## AI Agent Notes

If you are an AI agent working on this project:

- This `docs/` directory is your primary source of truth.
- [`chat_spec.md`](../chat_spec.md) is the canonical historical specification. Reference it, do not modify it.
- [`auditor.md`](../auditor.md) is a point-in-time audit. It may become stale as the project evolves.
- Always read the session-start documents before proposing changes.
- Prefer updating documentation over asking the user to do so.
- When uncertain about a design decision, consult [`implementation-decisions.md`](implementation-decisions.md) first.
