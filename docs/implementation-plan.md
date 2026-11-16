# EyeCue — Implementation Plan

Reviewed **2026-11-16** against local `main` at `aadf9e0`. The project can continue as a side project; the stages below are ordered work areas, not promised dates or completion percentages. See [project status](project-status.md), [progress history](implementation-progress.md), and [known issues](known-issues.md).

## Established implementation

The application has one native Ultralytics engine, the campus-trained 14-label detector, optional bundled depth, shared lifecycle coordination, audio guidance, gestures, TalkBack semantics, persisted settings, detector imports, and separate public/Study entry points. Study adds trial recording, charts, export, and optional manual upload. Build/signing and Play-internal automation exist; a workflow definition is not evidence that a release has been approved or distributed.

The original 15-task [app-only plan](app-only-implementation-plan.md) and [thesis-product audit](thesis-product-status-audit.md) remain dated records. Their Custom-isolate recovery, dual-engine comparison, old COCO model, package-placeholder, and historical release gates must not be treated as current implementation instructions.

## 1. Resume development reliably

- Recreate dependencies with a compatible Flutter SDK (CI: 3.44.2; Dart constraint: >=3.12.0 <4.0.0).
- Select a matching flavor and entry point: public + `lib/main.dart`, or Study + `lib/main_study.dart` with retained Study signing credentials.
- Keep settings, logs, credentials, and model data across development sessions unless a deliberate migration/reset is part of the task.
- Validate affected behavior with the [testing plan](testing-plan.md). For docs-only maintenance, source/link checks are sufficient; do not regenerate large builds solely to update prose.

Acceptance: a repeatable local development setup and recorded revision/toolchain for any new validation.

## 2. Validate the current native runtime

- Exercise camera permissions, first-payload readiness, retry, auto-start ON/OFF, explicit Stop/Start, pause/resume, background/foreground, and teardown on physical Android devices.
- Validate imported models through the real document picker, metadata checks, model identity transitions, and accelerator fallback.
- Confirm TalkBack controls and speech ownership on the exact build being evaluated; preserve the scope of earlier verified UI checks.
- Keep depth degradation explicit: stale/misaligned maps fall back to box-based distance, and bbox mode unloads/disables depth.

Acceptance: device/revision-specific results with logs and unresolved cases, not only a suite total.

## 3. Evaluate model and performance

- Use labelled data for the campus detector's 14 classes and report class distribution, protocol, and ground truth.
- Measure sustained performance with the [benchmark procedure](benchmark-procedure.md): detector/depth cadence targets, heatmap settings, accelerators, low power, thermal state, memory/battery conditions, and model fingerprint.
- Separate native inference, app-side alert intervals, and physical audible-warning latency. Configured Hz and confidence are not achieved FPS or accuracy.
- Calibrate distance if a research question requires measured metres; current MDE values are estimates.

Acceptance: reproducible results for the current model and build, with limitations. The retired Custom/Ultralytics comparison is optional historical research, not a dependency for current development.

## 4. Maintain Study data quality

- Validate Start/Pause/Resume/Finish/Discard and recovery of interrupted paused drafts.
- Record detector identities and model-change boundaries; never combine incompatible per-export model keys without resolving identities.
- Verify schema-4 export and the configured ingest validator together. Recheck deployment/authentication and researcher access separately from local implementation.
- Keep synthetic fixtures and real observations distinct in research records.

Acceptance: reproducible exports and a documented live-service check when upload is required.

## 5. Prepare an intentional distribution

Use the [release procedure](release-procedure.md), [privacy/data-safety notes](privacy-and-data-safety.md), and [Play checklist](play-store-checklist.md). Confirm version codes, public/Study identities, retained signing keys, compiled permissions, matching source, model provenance, and current Console requirements. Public test-signed artifacts are test artifacts; Study signing is mandatory. A manually dispatched signed public workflow may upload to internal testing when enabled.

Acceptance: explicit evidence for the chosen artifact/track; no inference of production availability from local code or old build records.

## Out of the active roadmap

The removed Dart inference isolate, `TransferableTypedData` frame transport, its resize implementation, and dual-engine fallback are no longer active application optimization tasks. Older milestone dates, completion percentages, and 40–70 hour estimates are retired. Reintroducing any such work requires a new scoped decision grounded in current evidence.
