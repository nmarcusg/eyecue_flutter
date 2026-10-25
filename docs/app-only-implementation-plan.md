# EyeCue — App-Only Implementation Plan

> **Superseded for speech scheduling (2026-10-17):** any statements in this plan describing TTS as "cooldown + label de-duplication + urgent bypass", or implying that speech history is written when an announcement is requested, no longer describe the implementation. The current behaviour is a lifecycle-aware arbiter described in [`architecture.md`](architecture.md#speech-scheduling-workstream-1). The rest of this plan is a dated implementation record and is retained as historical evidence.

> **Created:** 2026-09-01
> **Status:** App-only implementation substantially complete and validated through 2026-09-05; Android release engineering remains gated on owner decisions, credentials, and device availability.
> **Scope:** Fifteen repository-owned application tasks that can be built without
> retraining the model, collecting a labelled dataset, recruiting respondents,
> or running the formal thesis study.

See also: [`implementation-plan.md`](implementation-plan.md) for the full thesis
roadmap, [`project-status.md`](project-status.md) for current status,
[`known-issues.md`](known-issues.md) for blockers, and
[`testing-plan.md`](testing-plan.md) for the broader validation strategy.

## 1. Scope boundary

This plan covers application implementation and its automated verification. It
does **not** claim completion of work that inherently requires external evidence:

- model accuracy, precision, recall, F1, or mAP evaluation;
- model training, fine-tuning, or replacement;
- the controlled multi-device performance matrix;
- the visually impaired participant study, SUS, or statistical analysis;
- purchase/approval of an Ultralytics commercial licence; or
- Google Play account submission and review.

Local unit/widget/integration tests and a final smoke test remain part of normal
engineering quality. “App-only” means no new research dataset, respondents, or
model development is required—not that the code should ship without testing.

## 2. Implementation principles

1. **Ultralytics is the preferred engine; Custom is a bounded fallback.** Do not
   remove Custom until Ultralytics has passed the separate device matrix.
2. **Preference and runtime state are different.** A temporary fallback must not
   overwrite the user's preferred engine.
3. **Share assistive behavior.** Both engines should emit normalized `Detection`
   objects and metrics into one shared layer for spatial analysis, tracking,
   summaries, TTS, correction records, and telemetry.
4. **Do not merge the camera pipelines.** Ultralytics retains its native path;
   Custom retains its isolate/YUV path. Only their status and outputs are unified.
5. **Bound every retry.** No automatic recovery or fallback loop may run forever.
6. **Avoid duplicate speech.** TalkBack live regions and EyeCue TTS must not both
   announce every detection.
7. **Version persisted data.** Settings, corrections, and telemetry exports need
   schema versions and backward-compatible defaults.
8. **Never commit signing secrets.** Keystores, passwords, and local signing
   property files stay outside Git and must have a documented backup owner.

## 3. Shared foundation

Before implementing the individual tasks, introduce the smallest shared contracts
needed to avoid duplicating them across the two detection screens.

### Proposed contracts

- `DetectionRuntimeState`: `idle`, `requestingPermission`, `startingCamera`,
  `loadingModel`, `ready`, `paused`, `recovering`, `fallback`, `failed`, and
  `disposed`.
- `DetectionFailure`: typed category, safe user message, technical detail,
  recoverability, engine, retry count, and timestamp.
- `EngineRuntimeSelection`: preferred engine, currently active engine, fallback
  reason, and whether an explicit retry is available.
- `AssistiveDetectionController`: accepts normalized detections and metrics from
  either engine and owns spatial analysis, tracking, scene summaries, TTS,
  corrections, and telemetry dispatch.

### Constraints

- Do not create a third inference abstraction that copies camera frames or tensor
  buffers.
- Keep `InferenceService` and `YOLOViewController` engine-specific.
- The common layer begins only after detections are normalized into EyeCue's
  existing `Detection` model.
- Extract common UI only where it eliminates actual duplication: status/error
  panels, object cards, controls, and assistive announcements.

### Foundation acceptance criteria

- Both engines still load the same configured model, labels, and thresholds.
- Existing detection cards, TTS, gestures, and telemetry remain behaviorally
  unchanged before the new features are enabled.
- No engine-specific camera object crosses into the shared controller.
- The historical 77-test and 127-test totals are **revision-specific results** (77 for the earlier release baseline, 127 for the 2026-09-05 revision). Neither verifies the relocated Workstream 1 commits; this plan is retained as dated evidence.

## 4. Delivery order

| Phase | Tasks | Reason |
|---|---|---|
| A — Runtime foundation | Error/loading UI, isolate recovery, engine fallback | Establish one reliable state and failure protocol before changing defaults |
| B — Product policy | Ultralytics default, Custom Advanced/Legacy | Safe only after fallback and recovery paths are visible |
| C — Accessibility and control | TalkBack, sensitivity, Ultralytics labels | Direct user-facing improvements with limited data-model risk |
| D — Research data inside the app | Telemetry export, correction interface | Version schemas before movement records add new fields |
| E — Assistive intelligence | Movement tracking, scene summaries | Build tracking first so summaries can describe motion without later redesign |
| F — Android release engineering | Package identity, Android config, signing, AAB | Package identity must be final before signing and release artifacts |

## 5. Dependency and size summary

Sizes are relative implementation effort, not calendar estimates.

| Task | Priority | Size | Depends on |
|---|---:|---:|---|
| Error/loading UI | P0 | M | Shared runtime state |
| Isolate restart recovery | P0 | L | Shared runtime state |
| Engine fallback | P0 | L | Error state + bounded Custom recovery |
| Default-engine policy | P0 | S | Engine fallback; distribution licence remains a release gate |
| TalkBack/Semantics | P0 | L | Shared status/output semantics |
| Ultralytics labels | P1 | M | Shared labels; metadata packaging validation |
| Detection sensitivity | P1 | M | Versioned settings + controlled engine reload |
| Telemetry export | P1 | M | Versioned telemetry DTOs |
| Correction interface | P1 | L | Versioned telemetry/export schema |
| Movement tracking | P1 | L | Shared normalized detection stream |
| Scene summaries | P1 | M | Shared assistive controller; movement state optional but preferred |
| Package identity | P0 release | M | Final application ID decision |
| Android configuration | P0 release | M | Package identity |
| Release signing | P0 release | M | Package identity + Android release config |
| Release AAB | P0 release | S | Signing + release config |

---

## 6. Task plans

### 6.1 Isolate restart recovery

**Goal:** Recover the Custom engine from a worker-isolate exit or fatal Dart-level
inference failure without requiring the user to restart the application.

**Implemented:** `InferenceService` delegates worker lifecycle to an injectable
coordinator. Worker generations, stale-message rejection, bounded retries,
healthy-operation reset, terminal failure, explicit retry, and disposal-safe
backoff are implemented. The screen releases its busy gate on recovery events.

**Design:**

- Separate “stop current worker” from “dispose the whole service.” Result/error
  controllers stay open during a restart and close only during final disposal.
- Spawn the worker with dedicated `onError` and `onExit` ports.
- Add a monotonically increasing worker generation ID. Ignore messages from a
  worker whose generation is no longer current.
- On a recoverable fatal event: clear `_isInferring`, invalidate the old
  `SendPort`, kill/close the worker resources, and respawn the model worker.
- Use bounded backoff, for example immediate first retry, then a short delay, with
  no more than two automatic restarts in one detection session.
- Reset the retry budget after a sustained healthy interval, not immediately after
  the model-loaded handshake.
- After the budget is exhausted, publish a typed terminal failure for the engine
  fallback coordinator or Retry UI.
- Record restart attempt, success, failure category, and active engine in telemetry.

**Likely files:**

- `lib/services/inference_isolate.dart`
- `lib/screens/detection_screen.dart`
- new `lib/models/detection_runtime_state.dart`
- new `lib/services/inference_worker_lifecycle.dart`
- new `test/services/inference_lifecycle_test.dart`

**Automated tests:**

- Simulated isolate exit triggers exactly one respawn.
- Late messages from the previous generation are ignored.
- Busy-frame state is released before retry.
- Two failed restarts terminate without an infinite loop.
- `dispose()` during backoff prevents the scheduled restart.
- Successful recovery returns runtime state to `ready`.

**Verification:** Seven deterministic lifecycle tests pass, including explicit
worker-exit respawn, stale-generation rejection, busy-gate release, delayed
retry, terminal failure, disposal during backoff, and healthy recovery.

**Acceptance criteria:**

- A forced worker exit produces a visible/announced “recovering” state.
- Custom inference resumes automatically when restart succeeds.
- Terminal failure exposes Retry and fallback actions.
- No closed-stream, duplicate-worker, or camera-ownership errors occur.

### 6.2 Engine fallback

**Goal:** Keep detection available when the preferred Ultralytics engine cannot
initialize or suffers a terminal runtime failure.

**Implemented:** `EngineCoordinator` separates persisted preference from active
engine, performs one-shot typed fallback to Custom, preserves the preference,
and prevents fallback oscillation. Permission denial remains a user decision and
does not trigger engine fallback.

**Design:**

- Add an `EngineCoordinator` above `EngineDetectionScreen` with separate
  `preferredEngine` and `activeEngine` values.
- Treat permission denial as a shared user decision—not an engine failure—and do
  not fallback merely because permission is missing.
- Trigger fallback only for typed model-load, native initialization, camera-bind,
  or terminal inference failures after the preferred engine's own retry budget is
  exhausted.
- Automatically attempt Custom once. Preserve Ultralytics as the persisted
  preference and mark Custom as a temporary fallback.
- Display an accessible banner explaining the active fallback and provide
  **Retry Ultralytics** and **Use Custom for now** actions.
- Never bounce automatically from Custom back to Ultralytics during the same
  session. Return only through an explicit retry or a fresh app start.
- If Custom also fails, stop and present a terminal error; never create an
  Ultralytics↔Custom loop.
- Record preferred/active engine and fallback reason in telemetry.

**Likely files:**

- `lib/screens/engine_detection_screen.dart`
- `lib/screens/ultralytics_detection_screen.dart`
- `lib/screens/detection_screen.dart`
- new `lib/services/engine_coordinator.dart`
- `lib/services/telemetry_service.dart`
- new `test/services/engine_coordinator_test.dart`

**Automated tests:**

- Ultralytics terminal failure activates Custom exactly once.
- Permission denial does not trigger fallback.
- Temporary fallback does not overwrite the persisted preference.
- Retry returns to Ultralytics after successful load.
- Dual failure reaches a stable terminal state.
- Widget test verifies banner wording and both actions.

**Acceptance criteria:**

- A user is never left on an indefinitely loading Ultralytics screen.
- Fallback state is visible and announced once.
- Camera ownership is released before mounting the alternate engine.
- Fallback cannot oscillate or produce duplicate TTS.

### 6.3 Default-engine policy

**Goal:** Present Ultralytics as the recommended/default engine and retain Custom
as an Advanced/Legacy fallback.

**Implemented:** Fresh settings default to Ultralytics, explicit persisted Custom
choices are preserved, the settings UI marks Ultralytics as Recommended, and
Custom is presented as the Advanced/compatibility option.

**Design:**

- Change the default for a settings file with no engine value to Ultralytics.
- Add a settings schema version so absence, legacy files, and corrupt values are
  distinguishable.
- Do not silently overwrite an explicit existing Custom choice.
- Label Ultralytics **Recommended** and show it in the normal settings section.
- Move Custom into an **Advanced / compatibility fallback** section with a concise
  explanation that it is slower and retained for recovery/testing.
- Home/Detect status should report the active runtime, including temporary
  fallback, rather than only the persisted preference.
- Keep the distribution-licence decision as a release gate. The code can support
  this policy before publication, but an Ultralytics-default artifact must not be
  distributed without the selected compliant licence path.

**Likely files:**

- `lib/models/app_settings.dart`
- `lib/services/settings_service.dart`
- `lib/screens/settings_screen.dart`
- `lib/screens/home_screen.dart`
- `test/services/settings_service_test.dart`
- `test/widget_test.dart`

**Automated tests:**

- Fresh settings default to Ultralytics.
- An explicit persisted Custom value remains Custom after migration.
- Unknown/corrupt values use the documented safe default.
- Settings display Recommended and Advanced/Legacy semantics.

**Acceptance criteria:**

- New installs start with Ultralytics.
- Existing explicit user choices are respected.
- Active fallback is never misrepresented as active Ultralytics.

### 6.4 TalkBack and Semantics

**Goal:** Make the complete application navigable and understandable through
Android TalkBack without relying on sight.

**Implemented:** Primary controls, runtime states, warnings, detection cards,
charts, correction flows, and deliberate live regions have a systematic
semantics pass. Decorative camera/drawing descendants are excluded, detection
frames are not per-frame TalkBack live regions, and 200% text-scale layouts are
covered by widget tests. Device TalkBack validation remains manual.

**Design:**

- Create a screen-by-screen semantics inventory for Home, Detect, Settings, Help,
  and Logs & Reports.
- Give each interactive control a label, role, state, value, hint, and enabled
  status where applicable.
- Merge each detection card into one concise semantic node: object, confidence,
  relative position, approximate proximity, and priority.
- Mark status/fallback/warning changes as deliberate live regions, but do not make
  per-frame detections a TalkBack live region because EyeCue TTS already announces
  them.
- Exclude decorative icons, camera texture, and duplicate visual labels from the
  accessibility tree.
- Give charts text alternatives containing latest value, average, minimum,
  maximum, sample count, and engine.
- Establish predictable traversal order: status → warning → detections → controls.
- Respect large font scaling and keep minimum touch targets.
- Centralize one-shot system accessibility announcements so they cannot race with
  EyeCue TTS.

**Likely files:**

- `lib/widgets/accessible_button.dart`
- `lib/widgets/detection_card.dart`
- `lib/widgets/warning_banner.dart`
- `lib/widgets/status_pill.dart`
- `lib/widgets/charts.dart`
- all files under `lib/screens/`
- new `test/accessibility/semantics_test.dart`

**Automated tests:**

- `SemanticsTester` verifies labels, roles, selected/toggled state, and hints.
- No duplicate semantic label for icon plus text.
- Detection card exposes one coherent node.
- Charts expose a meaningful text summary.
- 200% text-scale widget tests show no overflow on primary screens.

**Acceptance criteria:**

- Every primary action is reachable and identifiable with TalkBack.
- Engine, detection, pause, error, and fallback states are announced once.
- TalkBack does not continuously repeat camera-frame changes.
- No critical information exists only through color or position.

### 6.5 Correction interface

**Goal:** Let a user mark a detection as correct, incorrect, or uncertain and
optionally choose the intended COCO label.

**Implemented:** Detection cards and the last announcement expose correction
actions; correct/incorrect/unsure records and optional shared-label corrections
are versioned, image-free, linked to the originating engine/session/detection,
and included in JSON/CSV exports.

**Design:**

- Add an accessible **Report detection** action to each detection card and a
  **Correct last announcement** action near Repeat.
- Open a bottom sheet with three first-level choices: Correct, Incorrect, Unsure.
- For Incorrect, optionally present a searchable list sourced from `labels.txt`.
- Store a versioned `DetectionCorrection` record: record ID, timestamp, session,
  active engine, predicted class/label/confidence/box, feedback type, optional
  corrected label, and current threshold.
- Do not capture or export a camera image by default. Image capture would require a
  separate privacy decision and is outside this task.
- Corrections are research annotations only; they must not update the live model
  or change future detections automatically.
- Include correction records in JSON/CSV export.

**Likely files:**

- new `lib/models/detection_correction.dart`
- new `lib/services/correction_service.dart`
- new `lib/widgets/detection_correction_sheet.dart`
- `lib/widgets/detection_card.dart`
- `lib/screens/logs_reports_screen.dart`
- telemetry/export service and tests

**Automated tests:**

- Correct/incorrect/unsure records serialize and round-trip.
- Corrected label must exist in the shared label list.
- Cancelling the sheet writes no record.
- Correction remains linked to the original engine/session/detection.
- Semantics expose the action and result confirmation.

**Acceptance criteria:**

- A correction can be completed without seeing the screen.
- No image or personally identifying data is stored implicitly.
- Correction exports remain parseable and schema-versioned.

### 6.6 Detection sensitivity

**Goal:** Make the confidence threshold configurable without changing the model.

**Implemented:** Versioned settings expose shared More detections, Balanced, and
Fewer false alerts presets plus a bounded advanced value. The selected threshold
is applied to both engines and persisted with clamping/migration safeguards.

**Design:**

- Add a persisted `detectionConfidence` value with a default of `0.25`.
- Prefer accessible presets over an unexplained raw number:
  **More detections** (`0.15`), **Balanced** (`0.25`), and
  **Fewer false alerts** (`0.40`). An Advanced slider may expose the bounded
  range `0.10–0.75` in `0.05` steps.
- Keep IoU at `0.45`; it is not a user-facing sensitivity control.
- Pass the selected confidence in the Custom worker initialization payload rather
  than reading mutable UI state inside the isolate.
- Rebuild/reload the Ultralytics view with the selected threshold through one
  controlled engine restart. Do not reload on every slider drag; apply on release
  or through an Apply action.
- Record the active threshold with telemetry and corrections.
- Clamp invalid persisted values and migrate missing legacy values to `0.25`.

**Likely files:**

- `lib/models/app_settings.dart`
- `lib/models/model_config.dart`
- `lib/services/settings_service.dart`
- `lib/services/inference_isolate.dart`
- `lib/screens/settings_screen.dart`
- `lib/screens/ultralytics_detection_screen.dart`
- settings/parser/widget tests

**Automated tests:**

- Persistence, migration, and clamping.
- Custom parser receives the configured value.
- Ultralytics view is reloaded once per applied change.
- Presets display plain-language descriptions and semantic values.

**Acceptance criteria:**

- Both engines use the same selected threshold.
- Changing sensitivity never starts two camera pipelines.
- The default behavior remains identical at `0.25`.

### 6.7 Telemetry export

**Goal:** Export current research telemetry and corrections as machine-readable
JSON and CSV without a server.

**Implemented:** Versioned immutable JSON/CSV export DTOs, stable named CSV
columns, RFC-compatible escaping, recovery/correction rows, and image-free
privacy boundaries are covered by tests and exposed from Logs & Reports. A
maintained external share/save package remains an explicit dependency decision;
local export generation works offline.

**Design:**

- Define immutable export DTOs instead of serializing mutable service internals.
- Use a top-level schema version, app version, export time, session metadata,
  settings snapshot, per-engine samples, detection records, failures/fallbacks,
  and corrections.
- JSON preserves nested structure. CSV uses separate files or a `record_type`
  column with a documented stable header.
- Implement RFC-compatible quoting for commas, quotes, newlines, and non-ASCII
  labels.
- Write to the app documents/cache area, then invoke Android's system share/save
  flow. Prefer one maintained sharing package rather than custom platform-channel
  code, subject to dependency review.
- Generate files only on explicit user action and delete temporary share files on
  the next safe cleanup.
- Do not export forensic camera PNGs, absolute internal paths, or device identifiers
  by default.
- Add a data dictionary to the documentation.

**Likely files:**

- new `lib/models/telemetry_export.dart`
- new `lib/services/telemetry_export_service.dart`
- `lib/services/telemetry_service.dart`
- `lib/screens/logs_reports_screen.dart`
- `pubspec.yaml` only if a share/save dependency is selected
- new `test/services/telemetry_export_service_test.dart`

**Automated tests:**

- Deterministic JSON snapshot and round-trip validation.
- CSV escaping for punctuation, quotes, newlines, and Unicode.
- Empty, Custom-only, Ultralytics-only, and mixed sessions.
- Failures/corrections retain engine and threshold fields.
- Export errors show a recoverable UI message.

**Acceptance criteria:**

- JSON and CSV open in standard analysis tools.
- The export states its schema and units.
- No camera image or hidden device identifier is included.
- Export works entirely offline.

### 6.8 Ultralytics labels

**Goal:** Replace native labels such as `class 41` with the same COCO names used by
EyeCue cards and TTS, without retraining the model.

**Implemented:** `labels.txt` remains authoritative, the deterministic metadata
packaging tool produces the metadata-enriched artifact without changing graph or
tensor structure, and FlatBuffer/model checks prove structural preservation.
EyeCue's normalized adapter/cards/TTS resolve all valid COCO indices. Native
overlay label behavior still requires device-level revalidation before it can be
treated as a release guarantee.

**Design:**

- Keep `labels.txt` as the authoritative label order.
- Add a deterministic repository tool that appends the Ultralytics metadata ZIP
  payload (`task: detect`, indexed names) to the same TFLite graph. This changes
  packaging metadata, not weights, tensors, or inference behavior.
- Use the metadata-enriched artifact for **both** engines so the controlled-input
  policy remains intact.
- Record the base graph checksum and generated artifact checksum.
- Extend the flatbuffer/model validator to prove input/output tensors and internal
  tensor counts are unchanged.
- Verify the Custom interpreter accepts the standards-compatible trailing metadata
  and returns equivalent output for a fixed input.
- If metadata packaging proves incompatible with Custom, use a separately documented
  fallback: hide the native overlay and render EyeCue-labelled boxes from normalized
  `YOLOResult` coordinates. Do not maintain a fork of the whole plugin merely for
  labels.

**Likely files:**

- new `tool/package_ultralytics_metadata.dart`
- `assets/yolov8n_int8_new.tflite` or a generated/committed metadata-enriched copy
- `lib/models/model_config.dart`
- `tool/validate_flatbuffer.dart`
- `docs/model-assets.md` or the existing model documentation

**Automated tests:**

- Metadata names exactly match all 80 lines of `labels.txt`.
- Graph/tensor metadata matches the base model.
- Class index 41 resolves identically in native and EyeCue paths.
- Packaging is deterministic from identical inputs.

**Acceptance criteria:**

- No numeric fallback labels appear for valid COCO class indices.
- Custom and Ultralytics still run the same learned graph and label order.
- No model retraining or new dataset is required.

### 6.9 Package identity

**Goal:** Replace the placeholder Android identity with the final EyeCue identity
before any Play release is created.

**Resolved (owner decision):** the namespace and application ID are the
owner-approved final `app.eyecue.mobile` (`2d0d0cd`; gate D1 decided). The thesis
placeholder `com.eyecue` was not used.

**Design:**

- Use the thesis-specified `com.eyecue` only after confirming it is the final,
  organization-controlled ID. Once published, the application ID cannot be changed
  without creating a different Play application.
- Update Gradle namespace/application ID, Kotlin package declaration and directory,
  manifest references, test configuration, deep links if added, and app label
  `EyeCue`.
- Consider a debug-only application ID suffix so development builds can coexist
  with the release app.
- Treat the new ID as a fresh installation; document that preferences and logs from
  the placeholder package do not migrate automatically.
- Search the entire repository and generated configuration for the old identifier.

**Likely files:**

- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- Kotlin `MainActivity.kt` path/package
- Android test manifests/configuration
- release documentation

**Automated checks:**

- Repository search contains no unintended placeholder ID.
- Debug and release manifests resolve to the documented IDs.
- Launcher label is `EyeCue`.
- App starts after a clean install under the new ID.

**Acceptance criteria:**

- Release application ID is final and consistent.
- Debug/release coexistence policy is documented.
- The package rename occurs before production signing and Play artifact creation.

### 6.10 Android configuration

**Goal:** Make supported Android versions and release behavior explicit and
reproducible.

**Pending release engineering:** `minSdk`/`targetSdk` policy, release
optimization, manifest inspection, and dual-LiteRT ABI validation still need an
explicit release configuration after the final package identity is confirmed.

**Design:**

- Set thesis-aligned minimum Android version explicitly (currently documented as
  API 29) after confirming that dropping API 24–28 is intentional.
- Pin/record compile and target SDK behavior for the release toolchain rather than
  relying silently on moving defaults. Recheck the current Play requirement at the
  actual submission date.
- Preserve Android 13+ permission behavior and declare only permissions the app
  uses.
- Configure ABI behavior for the App Bundle and verify both LiteRT runtime families
  remain packaged correctly.
- Add release-only resource shrinking/minification only after keep rules are proven
  for Flutter, LiteRT, Ultralytics, camera, and TTS.
- Configure deterministic version code/name ownership and document the increment
  process.
- Add a release manifest inspection step.

**Likely files:**

- `android/app/build.gradle.kts`
- `android/gradle.properties`
- `android/app/proguard-rules.pro` if shrinking is enabled
- `android/app/src/main/AndroidManifest.xml`
- release checklist documentation

**Automated checks:**

- Gradle release configuration resolves without debug signing.
- Manifest merger output contains only expected permissions/components.
- Release build includes both required native runtimes and model assets.
- Version code/name are present and reproducible.

**Acceptance criteria:**

- Supported minimum API is explicit.
- Release configuration does not depend on a developer's local Flutter defaults.
- Any shrinking configuration has a tested keep-rule set and rollback switch.

### 6.11 Release signing

**Goal:** Sign release artifacts with an EyeCue-owned production key instead of the
debug keystore.

**Pending production credentials:** The release build still requires a
project-owned production key, ignored local/CI secret injection, and a deliberate
fail-closed signing configuration. No credentials or key identity will be
guessed.

**Design:**

- Create one production upload key using the organization/project owner's identity.
- Store the keystore outside the repository. Store aliases/passwords in local
  ignored properties or CI secrets, never in source control.
- Make release configuration fail with a clear message when required signing values
  are absent; never silently fall back to debug signing.
- Document secure backup, recovery ownership, expiry, and rotation procedure.
- Prefer Play App Signing for final distribution while retaining the upload key
  backup.
- Add certificate fingerprint verification to the release checklist.

**Likely files:**

- `android/app/build.gradle.kts`
- `.gitignore`
- ignored local signing properties template with no secrets
- new `docs/release-checklist.md` or existing release documentation

**Verification:**

- Build a signed release artifact with local secret injection.
- Verify certificate and signatures with Android signing tools.
- Scan tracked files/history for keystore material and passwords.
- Confirm the release build fails when signing configuration is intentionally
  removed.

**Acceptance criteria:**

- No release artifact is signed by the debug key.
- No signing secret is tracked by Git.
- At least two authorized locations hold recoverable key backups.

### 6.12 Release AAB

**Goal:** Produce a reproducible, signed Android App Bundle suitable for later Play
Console upload.

**Pending release artifact:** Only the multi-ABI debug APK has been built and
inspected. A signed AAB, APK-set install, release manifest, ABI, asset, and
certificate validation require the final identity and production signing inputs.

**Design:**

- Build from a clean checkout using the documented Flutter version and locked
  dependencies.
- Use release signing and the final package identity.
- Generate a symbol/mapping archive if obfuscation or shrinking is enabled and keep
  it with the matching version code.
- Validate the AAB structure, application ID, SDK values, permissions, assets,
  native ABIs, and signing certificate.
- Generate an installable APK set from the AAB and perform a clean-install smoke
  test before treating the bundle as releasable.
- Record total AAB size and estimated ABI-specific delivery size separately; do not
  compare the 204 MB debug APK directly with Play delivery.
- Produce a checksums manifest and release notes.

**Likely files/artifacts:**

- `build/app/outputs/bundle/release/*.aab` (generated, not committed)
- symbol/mapping archive outside source control
- `docs/release-checklist.md`
- release notes/checksum record

**Verification:**

- `flutter build appbundle --release` succeeds.
- Bundle validation and APK-set generation succeed.
- Generated APK set installs and both engines reach their expected startup state.
- AAB contains the model, labels, and required native libraries.

**Acceptance criteria:**

- Signed AAB is reproducible from documented inputs.
- Artifact identity, version, certificate, and checksum are recorded.
- Technical readiness does not get mislabeled as licence or Play-review approval.

### 6.13 Error and loading UI

**Goal:** Give users a stable, accessible, actionable state for every camera/model/
engine transition and failure.

**Implemented:** Both detection engines use the shared typed runtime/failure
vocabulary and [`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart)
for actionable loading, permission, camera, model, recovery, fallback, and
terminal states. Runtime transitions are covered by semantics and lifecycle
tests; native/device-specific failure behavior remains subject to device testing.

**Design:**

- Drive UI from `DetectionRuntimeState`, not scattered booleans.
- Provide distinct messages for permission, camera initialization, model loading,
  native engine initialization, worker restart, temporary fallback, and terminal
  failure.
- Use one reusable `DetectionStatePanel` with Retry, Open Settings, Use fallback,
  and Stop actions selected by failure capabilities.
- Add bounded initialization timeouts that become recoverable failures rather than
  infinite spinners.
- Preserve technical details in logs/telemetry while showing safe plain language to
  users.
- Announce state transitions once through the shared accessibility/TTS policy.
- Disable incompatible controls while starting/recovering and preserve Stop.

**Likely files:**

- new `lib/models/detection_runtime_state.dart`
- new `lib/widgets/detection_state_panel.dart`
- both detection screens or a shared detection experience widget
- engine/inference services and widget tests

**Automated tests:**

- Every state renders the correct message/actions.
- Timeout transitions once and can be retried.
- A disposed screen cannot update state after an async result.
- Technical exception text is not exposed as the main user message.
- Semantics announce changes without repeating on each rebuild.

**Acceptance criteria:**

- No indefinite loading state after a known failure.
- Every recoverable failure has a usable next action.
- Both engines use the same terminology and accessibility behavior.

### 6.14 Scene summaries

**Goal:** Produce concise, deterministic environmental summaries from existing
detections without adding a generative model or cloud dependency.

**Implemented:** `SceneSummaryService` provides one pure, deterministic summary
policy for both normalized engine outputs, with bounded alert/scan phrasing,
spatial grouping, priority ordering, cautious approximate language, and shared
TTS/semantics use.

**Design:**

- Extract a pure `SceneSummaryService`/`UtteranceBuilder` shared by both engines.
- Group duplicate labels by relative position and retain the most relevant instance.
- Order content by immediate high-priority/approaching objects, center-path objects,
  proximity, then confidence.
- Separate two modes:
  - **Alert:** one urgent actionable object; short enough for real-time use.
  - **Quick scan:** up to four useful scene items grouped left/center/right.
- Use cautious language: “appears near” and “appears to be approaching”; never
  claim measured distance or that a path is safe.
- Apply a phrase budget and deterministic templates to avoid long speech queues.
- Keep formatting independent from TTS so it can also populate Semantics and logs.

**Likely files:**

- new `lib/services/scene_summary_service.dart`
- `lib/services/tts_service.dart`
- shared assistive controller
- both detection screens remove duplicated quick-scan construction
- new `test/services/scene_summary_service_test.dart`

**Automated tests:**

- Empty, single, duplicate, multi-position, and high-priority scenes.
- Stable ordering independent of input list order.
- Phrase length/item limit.
- No unsupported “safe,” exact-distance, or certainty language.
- Movement phrases appear only after a confirmed track state.

**Acceptance criteria:**

- Both engines speak identical summaries for equivalent detections.
- Alerts remain short; scans remain bounded and spatially organized.
- Summary construction is pure and fully unit-tested.

### 6.15 Movement tracking

**Goal:** Estimate whether a detected object appears to approach, move away, or stay
stable by comparing normalized boxes over time—without changing the detector.

**Implemented:** `ObjectTracker` associates normalized detections across
timestamped frames and exposes conservative stable/approaching/moving-away
estimates with bounded tracks, hysteresis, expiry, and telemetry integration.

**Design:**

- Add a pure, engine-independent `ObjectTracker` after result normalization.
- Associate detections with existing tracks by class plus IoU/center-distance cost.
- Store track ID, first/last timestamp, smoothed center, smoothed area/height,
  confidence, hit count, and missed-update count.
- Use timestamps rather than frame counts so behavior remains comparable across
  different inference FPS.
- Require a minimum track age/hit count before exposing motion.
- Estimate approach from sustained relative growth in box area/height with
  hysteresis. Treat sideways center motion separately and expire stale tracks.
- Expose conservative states: `unknown`, `stable`, `approaching`, `movingAway`.
- Phrase the result as an estimate. It is not calibrated speed or distance.
- Rate-limit movement alerts and prioritize only high-priority or center-path
  approaching objects.
- Record track/motion state in telemetry without changing raw detections.

**Likely files:**

- new `lib/models/tracked_detection.dart`
- new `lib/services/object_tracker.dart`
- `lib/services/spatial_analysis_service.dart` or shared assistive controller
- `lib/services/telemetry_service.dart`
- `lib/services/scene_summary_service.dart`
- new `test/services/object_tracker_test.dart`

**Automated tests:**

- Stable boxes remain stable under small jitter.
- Sustained area growth becomes approaching only after minimum evidence.
- Area shrink becomes moving away.
- Crossing same-class objects do not immediately swap tracks under the documented
  matching policy.
- Missed frames expire tracks.
- Equivalent timestamped sequences behave consistently at different FPS.
- Alert hysteresis/cooldown prevents repeated speech.

**Acceptance criteria:**

- Tracking adds no inference dependency and runs for both engines.
- Raw detection output remains available for debugging/evaluation.
- Motion claims are conservative, timestamp-based, and explicitly approximate.
- Processing overhead stays bounded by the small post-NMS detection count.

## 7. Cross-feature test gates

Each phase must pass these gates before the next phase becomes the default branch
behavior:

1. `flutter analyze` reports zero issues — ✅ current validation.
2. Existing tests plus new feature tests pass — ✅ 127 tests passed **at the 2026-09-05 revision** (historical; not a result for the current Workstream 1 branch).
3. Settings migration preserves valid existing preferences.
4. Custom and Ultralytics can each start/stop without duplicate camera ownership.
5. Switching engines leaves no late callback, stream, TTS, or telemetry writer.
6. TalkBack tree contains no duplicate per-frame announcements.
7. Export schema fixtures remain backward-readable after later fields are added — ✅ covered by export tests.
8. A release build never silently uses debug signing — ⏳ release configuration remains pending production-key decisions.

## 8. Recommended implementation slices

Keep commits small and independently reversible:

1. Runtime-state/failure models and tests.
2. Shared error/loading panel.
3. Custom isolate bounded restart.
4. Engine coordinator and bounded fallback.
5. Ultralytics-default settings migration and Advanced/Legacy UI.
6. Semantics audit by screen, one screen per commit where practical.
7. Threshold settings and engine application.
8. Ultralytics label metadata packaging.
9. Versioned telemetry DTOs and JSON export.
10. CSV export and Android share/save UI.
11. Correction records and correction sheet.
12. Pure object tracker.
13. Shared scene-summary service and removal of duplicated scan phrasing.
14. Final Android package/config migration.
15. Release signing configuration and AAB checklist.

## 9. Definition of done for this plan

The repository-owned application/runtime portion is implemented and validated.
The Android release-engineering bullets below remain intentionally open because
they require a final package decision, production credentials, and release
artifact/device checks that cannot be inferred from source code.

The app-only implementation phase is complete when:

- Ultralytics is the recommended new-install default and Custom is a visible,
  bounded fallback;
- Custom can restart its worker or fail cleanly into the coordinator;
- every runtime transition has accessible, actionable UI;
- TalkBack covers all primary screens and controls without duplicating TTS;
- sensitivity, corrections, JSON/CSV export, labelled Ultralytics overlays,
  movement estimates, and shared scene summaries are implemented and tested;
- the Android package/configuration is final;
- release builds require production signing; and
- a signed, validated AAB can be generated reproducibly.

Completion of this plan still does **not** establish model accuracy, broad device
compatibility, participant-study success, Ultralytics licence compliance, or Play
Store approval. Those remain separate evidence and external-release tracks.
