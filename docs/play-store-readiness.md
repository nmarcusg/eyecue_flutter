# Play Store Readiness Ledger

Baseline evidence and implementation ledger for the EyeCue Play Store submission
programme. This document is the single source of truth for what is verified, what
is still pending, and what is blocked outside this repository.

## 1. Purpose & scope

This work consolidates the three histories that were developed separately — native
MDE depth integration, granular inference cadence, and Supabase research telemetry —
into one branch, `feat/play-store-readiness`, and then drives that consolidated line
to a state that is **Play Store ready**. "Play Store ready" here means *technically
and operationally prepared for submission*: signed, versioned, policy-compliant, and
verified on a release build. It does **not** mean submitted — no upload to Play
Console is performed by this work, and no production signing material is created
here.

## 2. Provenance / consolidation base

| Property | Value |
| --- | --- |
| Branch | `feat/play-store-readiness` |
| Base commit | `adfbc5d` (`docs(status): retire obsolete XNNPACK items and dead links`) |
| Worktree | `/home/nico/repos/eyecue_flutter-playstore` |
| Flutter | 3.44.2, stable channel |

Source histories incorporated into this base (each verified as an ancestor of `HEAD`
with `git merge-base --is-ancestor`):

| Source | Commit | Subject |
| --- | --- | --- |
| `codex/mde-integration` | `85b48ae` | `fix(mde): correct depth-artifact docs, bound heatmap cost, deflake estimator test` |
| `feat/supabase-research-telemetry` | `12f568b` | `feat(telemetry): add manual Supabase session upload` |
| `feat/waste-reduction` (via merge) | `c325b11` | `docs: reconcile waste-reduction state` |
| `dev` | `94f74d8` | `Merge pull request #7 from nmarcusg/feat/alert-latency-telemetry` |

The two feature histories are joined by merge commit `2722a7b`
(`merge: integrate MDE and research-telemetry histories for cadence work`, parents
`12f568b` and `85b48ae`), which is itself an ancestor of `adfbc5d`.

### WorkManager pin from `origin/main` is deliberately not merged

`origin/main` carries the WorkManager pin commit `fc30945`
(`fix(android): update WorkManager runtime`) on branch `fix/workmanager-release-startup`.
It is **not** merged into this history because an equivalent pin already exists here:
commit `74d4649` (`fix(android): update WorkManager runtime`) is an ancestor of `HEAD`
and already pins `androidx.work:work-runtime:2.11.2`
([`android/app/build.gradle.kts`](../android/app/build.gradle.kts:11)).

Verified equivalence: `git diff 74d4649 fc30945 -- android/app/build.gradle.kts android/build.gradle.kts`
produces **no output** — the Gradle files are byte-identical between the two commits.
The remaining difference is behavioural, not textual: whether the pinned runtime plus
its matching Room implementation and consumer R8 rules actually survive R8 shrinking
in a release build. That must be verified by a release-build run, not by diff
(`CONFIRMED-BY-INSPECTION` for the pin itself; behaviour still `INFERRED-UNVERIFIED`).

## 3. Evidence provenance legend

Every claim in this document carries one of these labels:

| Label | Meaning |
| --- | --- |
| `CONFIRMED-BY-INSPECTION` | Read directly in source at the cited file:line during the session that wrote the claim. |
| `CONFIRMED-BY-TEST` | Produced by an executed test command whose output was observed. |
| `CONFIRMED-BY-BUILD` | Produced by an executed build/packaging command whose output was observed. |
| `CONFIRMED-ON-DEVICE` | Observed on physical hardware with the reported build installed. |
| `INFERRED-UNVERIFIED` | Reasoned from adjacent evidence but not directly executed or measured. |
| `BLOCKED-EXTERNAL` | Cannot be resolved inside this repository; requires an owner action or an external account. |

A claim with no label is a documentation cross-reference only and must not be treated
as evidence.

## 4. Verified baseline

All numbers below were measured in `/home/nico/repos/eyecue_flutter-playstore` at
`adfbc5d`, after `flutter pub get` completed successfully (`Got dependencies!`).

### 4.1 Formatting

```
dart format --output=none --set-exit-if-changed .
Formatted 148 files (0 changed) in 2.97 seconds.   (exit 0)
```

`CONFIRMED-BY-TEST` — the tree is already format-clean; no file was rewritten
(`--output=none`). Re-measured at `d3a987a` after L1a vendored the plugin: the count is
**148**, not the 103 recorded at `adfbc5d`, because `dart format .` now also covers the
45 Dart files that live in-tree under `plugins/ultralytics_yolo/`.

### 4.2 Static analysis

```
flutter analyze  =>  4 issues found. (ran in 15.4s)
```

| Severity | Location | Rule |
| --- | --- | --- |
| warning | [`lib/services/alert_policy.dart`](../lib/services/alert_policy.dart:124) | `unused_field` — `_clock` is never used |
| warning | [`lib/services/tts_service.dart`](../lib/services/tts_service.dart:671) | `invalid_return_type_for_catch_error` — `int` returned from `onError`, must be `FutureOr<Null>` |
| info | [`test/services/assistive_detection_controller_test.dart`](../test/services/assistive_detection_controller_test.dart:9) | `unnecessary_import` — `package:flutter/foundation.dart` duplicated by `dart:ui` |
| info | [`test/services/tts_service_test.dart`](../test/services/tts_service_test.dart:11) | `unnecessary_import` — `package:flutter/foundation.dart` duplicated by `dart:ui` |

Zero errors. `CONFIRMED-BY-TEST`.

### 4.3 Test suite

```
flutter test  =>  +527 -1: Some tests failed.
```

| Result | Count |
| --- | --- |
| passed | 527 |
| failed | 1 |

Failing test, exact name and location:

```
test/services/tts_service_test.dart
  alert lifecycle telemetry a partial signal pair records a reconciliation timeout
```

`CONFIRMED-BY-TEST`. This failure is **PRE-EXISTING** and **NOT introduced by this
work**: the L0 commit adds a Markdown document only and changes no Dart source, test,
or asset. The planner independently measured the same single failure at the same base
commit.

### 4.4 Dashboard contract tests

```
cd /home/nico/Documents/ChatGPT/Eyecue/research-dashboard-cadence
node --test test/cadence.test.mjs
=> # tests 7   # pass 7   # fail 0
```

`CONFIRMED-BY-TEST`. Caveat, also measured: `node --test test/` reports
`# tests 1 # pass 0 # fail 1`. That is **not** a test failure — the runner receives a
directory where it expects files and treats it as one un-runnable entry. Use the explicit
file path above.

### 4.5 Baseline delta vs planner measurements

| Metric | Planner | Measured here | Delta |
| --- | --- | --- | --- |
| `flutter analyze` issues | 4 (0 errors, 2 warnings, 2 infos) | 4 (0 errors, 2 warnings, 2 infos) | identical |
| `flutter test` | 527 passed, 1 failed | 527 passed, 1 failed | identical |
| Failing test name | `tts_service_test.dart` → reconciliation timeout | same | identical |
| Dashboard `cadence.test.mjs` | 7/7 pass | 7/7 pass | identical |
| `dart format` | not measured by planner | 148 files, 0 changed (re-measured after L1a; includes the 45 vendored Dart files) | new measurement |

### 4.6 Native debug build (planner preflight)

```
flutter build apk --debug
=> build/app/outputs/flutter-apk/app-debug.apk        (625 s, exit 0)
```

`CONFIRMED-BY-BUILD`, measured by the planner preflight in this worktree. It establishes
three facts the native work depends on:

| Fact | Value |
| --- | --- |
| The vendored plugin compiles in-tree | yes — `plugins/ultralytics_yolo` Kotlin + CMake sources build through the app's Gradle project |
| Android Gradle Plugin | 9.0.1 |
| Gradle | 9.1.0 (cached on this host) |
| NDK | 28.2.13676358 (installed) |

Consequence for later items: an in-tree native edit has a real compile gate without a
toolchain bootstrap. The prebuilt `build/` tree (≈2.4 GB) is the incremental cache that
keeps that gate cheap, so `flutter clean` is not run during this programme. A release
AAB is deliberately out of scope here (disk headroom ≈4.4 GB, and L8/L9/L11 own the
release artefact).

## 5. Implementation ledger

Status values: `PENDING`, `IN_PROGRESS`, `BLOCKED`, `DONE`.

An evidence label of `BLOCKED-EXTERNAL` means **(required)**: the label cannot be
produced from inside this repository, so the item it gates stays open until the owner
action in §7 is executed. It is never a waiver, and no later item may treat such an
item as `DONE`.

| Item | Scope (1 line) | Depends on | Status | Commit | Reviewer verdict | Evidence labels |
| --- | --- | --- | --- | --- | --- | --- |
| L0 baseline ledger | Record consolidation base, measured baseline, root-cause findings and gates in this document | — | DONE | `a8e0571` | PASS_WITH_NOTES | `CONFIRMED-BY-INSPECTION`, `CONFIRMED-BY-TEST` |
| L1a vendored plugin + reviewer notes | Replace the hosted `ultralytics_yolo` pin with the in-tree path dependency and apply the 7 L0 reviewer findings to this document | L0 | DONE | `d5390d4` | PASS_WITH_NOTES | `CONFIRMED-BY-INSPECTION`, `CONFIRMED-BY-TEST`, `CONFIRMED-BY-BUILD` |
| L1 native shared-frame MDE transport | Stop JPEG-encoding and re-decoding the analysis frame; run depth on the analysis frame inside the view and emit a compact block-mean grid (grid ≤ 36 864 bytes) | L0, L1a | DONE | `63131d5` (`3f81cc3` docs; remediation `15fcf39`, `2540470`, `79eb9c0`) | round 1 on `fcf4cd0`/`63131d5`/`3f81cc3` → CHANGES_REQUIRED (4 major/5 minor/2 nit); round 2 on `15fcf39`/`2540470` → CHANGES_REQUIRED (8 of 9 fixed, 4 open); round 3 remediation `79eb9c0`, re-review pending | `CONFIRMED-BY-INSPECTION` (grid arithmetic, `depthMaxDim` wiring, pause→failure→resume order), `CONFIRMED-BY-TEST` (payload key set/shape), `CONFIRMED-BY-BUILD` (vendored Kotlin compiles) |
| L2 compact depth payload + heatmap gating | Replace the dense Float32 depth return with a compact payload; build the heatmap only when it is displayed | L1 | PENDING | — | — | `CONFIRMED-BY-TEST`, `CONFIRMED-ON-DEVICE` (required) |
| L3 MDE enable/disable resource lifecycle | Release the depth model when MDE is turned off, not just the scheduler | L1 | PENDING | — | — | `CONFIRMED-BY-TEST` (required) |
| L4 accelerator policy + stage timings | Deterministic CPU/GPU selection with fallback, and per-stage inference timings | L2 | PENDING | — | — | `CONFIRMED-BY-TEST`, `CONFIRMED-ON-DEVICE` (required) |
| L5 telemetry perf fields + schema v4 | Carry cadence and stage-timing fields into the telemetry payload and bump the payload schema | L4 | PENDING | — | — | `CONFIRMED-BY-TEST` (required) |
| L6 Supabase idempotency + schema gating | Idempotent ingestion plus rejection of unknown payload schema versions server-side | L5 | PENDING | — | — | `BLOCKED-EXTERNAL` (required) |
| L7 dashboard contract compatibility | Keep the research dashboard able to read the amended payload contract | L5 | PENDING | — | — | `CONFIRMED-BY-TEST` (required) |
| L8 R8/WorkManager/Room release verification | Prove the pinned WorkManager + Room + consumer R8 rules survive a minified release build | L1–L4 | PENDING | — | — | `CONFIRMED-BY-BUILD` (required) |
| L9 Play Store configuration | Application ID, release signing config, versioning, permission surface | L8 | PENDING | — | — | `CONFIRMED-BY-BUILD` (required) |
| L10 licensing/privacy/store materials | Licence decision, AGPL-3.0 interaction with the bundled Ultralytics artefacts, Data Safety answers | L9 | PENDING | — | — | `BLOCKED-EXTERNAL` |
| L11 final readiness report | Release AAB build, artefact inspection, final readiness statement | all above | PENDING | — | — | `CONFIRMED-BY-BUILD`, `CONFIRMED-ON-DEVICE` (required) |

### 5.1 L1 fork mechanics (applied)

L1 stopped depending on the hosted package in `d5390d4`: `pubspec.yaml:29`–`:30` now
declare `ultralytics_yolo:` with `path: plugins/ultralytics_yolo`, replacing the former
`ultralytics_yolo: 0.6.13` hosted pin with a vendored copy of upstream 0.6.13 (see
[`plugins/ultralytics_yolo/VENDORED.md`](../plugins/ultralytics_yolo/VENDORED.md)).
Recorded reason: AGPL-preserving reproducibility — the AGPL-3.0 source we redistribute
must be the source we build — plus the native deviation already approved under D4
(`CONFIRMED-BY-INSPECTION` for the pin, `CONFIRMED-BY-BUILD` for the in-tree copy
compiling, see §4.6).

The vendored copy is now the only valid edit target: `~/.pub-cache` is a read-only
reference that is no longer part of the build, so every plugin citation below is made
against `plugins/ultralytics_yolo/`.

## 6. Verified MDE root cause

Findings only. **Nothing in this section is fixed by L0.** All five root causes and
both lifecycle gaps are `CONFIRMED-BY-INSPECTION` in the cited files this session.
Plugin citations use the vendored in-tree copy under `plugins/ultralytics_yolo/`, which
has been the build input since `d5390d4`. (Citations written before L1a pointed into
`~/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.6.13`; that copy is byte-identical but
is no longer consulted or built.)

### 6.1 Analysis frame is JPEG-encoded and transferred on every detection result

[`lib/screens/ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:398)
sets `includeOriginalImage: _mdeEnabled` when building the streaming config. The
streaming configuration key is built by `streamingConfigKey`
([`lib/screens/ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:140),
value assembly at `:143`), so enabling depth turns on per-result image transfer for the
whole stream.

On the native side,
`plugins/ultralytics_yolo/android/src/main/kotlin/com/ultralytics/yolo/YOLOView.kt:2470`
— guarded by `if (config.includeOriginalImage)` at `:2469` and reached from the per-result
stream path at `:1549`→`:1558` (the `convertResultToStreamData(...)` call is at `:1549`,
the `callback.invoke` at `:1558`, and the depth tick right after it at `:1564`)
— is the **only** JPEG encode on the per-detection hot path:
`bitmap.compress(Bitmap.CompressFormat.JPEG, 90, outputStream)`. The other `compress(`
sites (`:1358`, `:1394`, `:1415`, `:2541`) are capture/snapshot-only and outside the
argued hot path.

> Citation correction against the contract: the encode is at `YOLOView.kt:2319`,
> not `:2316`. Line `:2316` is the flag guard.

Consequence: at every detection result the plugin allocates a bitmap, JPEG-encodes it
at quality 90, copies it into a byte array, and ships it across the platform channel —
even though the depth path consumes only a small fraction of those frames.

### 6.2 Most of those encodes are already discarded by the estimator

[`lib/services/monocular_depth_estimator.dart`](../lib/services/monocular_depth_estimator.dart:156)
(`submitFrame`) keeps a **single latest-frame slot**: the `_pendingJpeg` declaration at
`:109` is overwritten wholesale at `:167`, and the queue depth is documented as "Never
exceeds one by design" (`debugPendingFrames`, `:119`). Frames arriving while a depth
inference is in flight are dropped.

Consequence: at the configured depth cadence (about 2 Hz) the overwhelming majority of
the JPEG encodes produced in 6.1 are encoded, copied and transferred only to be thrown
away before any inference runs. This is pure waste on the detection hot path.

### 6.3 The surviving JPEG is decoded again natively — Android → Dart → Android

The surviving bytes travel back into native code through the method channel:
[`lib/services/monocular_depth_estimator.dart`](../lib/services/monocular_depth_estimator.dart:256)
(`_run`) calls `yolo.predict(jpeg)`; the plugin's Dart side dispatches method
`predictSingleImage` at
`plugins/ultralytics_yolo/lib/core/yolo_inference.dart:56`–`:58`; and the
native handler decodes the bytes again with
`BitmapFactory.decodeByteArray(imageData, 0, imageData.size)` at
`plugins/ultralytics_yolo/android/src/main/kotlin/com/ultralytics/yolo/YOLOPlugin.kt:206`.

> Citation correction against the contract: this decode is at `YOLOPlugin.kt:206`,
> not `:192`.

The cost is a full Android→Dart→Android round trip per depth frame: encode on the
producer side, channel copy, decode on the consumer side, then a depth inference whose
input is resized from the model's stored input dimensions, defaulting to 640×640 when
the model does not report them (`DepthEstimator.kt:30`–`:31`; `:32` is the `inputSize`
assignment).

### 6.4 The dense Float32 depth map is returned on every depth frame

`Predictor.includeRawMaskData` defaults to `true`
(`plugins/ultralytics_yolo/android/src/main/kotlin/com/ultralytics/yolo/Predictor.kt:136`),
and
`DepthEstimator.kt:111` therefore fills a dense `FloatArray(width * height)` on every
frame: `val values = if (includeRawMaskData) FloatArray(width * height) else null`.

Consequence: a full-resolution float depth grid crosses the platform channel each
depth frame, which dwarfs the compact per-object data the UI and telemetry actually
consume.

### 6.5 The heatmap is built unconditionally, even when hidden

[`lib/screens/ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:336)
constructs `MonocularDepthEstimator()` with no `heatmapBuilder` argument. The estimator
accepts an injected builder (`this.heatmapBuilder`, `:63`) but falls back to building
the heatmap itself: `await (heatmapBuilder ?? _buildHeatmap)(depthMap)` at
[`lib/services/monocular_depth_estimator.dart`](../lib/services/monocular_depth_estimator.dart:202),
with `_buildHeatmap` at `:390`.

Consequence: colourisation, alpha baking and `ui.Image` allocation happen for every
depth frame regardless of whether the heatmap is visible, so the cheapest configuration
(heatmap off) still pays the full heatmap cost.

### 6.6 Lifecycle gap: turning MDE off does not release the model

When the distance mode changes while MDE is disabled,
[`lib/screens/ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:572)
runs the MDE-off block at `:572`–`:574` — `_depth.stop()`, `_depth.clearFrame()`, and
`_depthSmoother.reset()` (`:574`).

> Citation correction against the contract: the block is `:572`–`:574`, not
> `:570`–`:573` (line `:570` is the enclosing `if`).

`stop()` halts the scheduler and `clearFrame()` drops the pending slot, but neither
releases the loaded depth model/interpreter: `stop()` is itself documented "The model
stays loaded" ([`lib/services/monocular_depth_estimator.dart`](../lib/services/monocular_depth_estimator.dart:303)).
The release hook `_disposeModel()` (`:329`) is reachable only from `dispose()` (call
site `:428`), never from the toggle path. Memory held by the model survives repeated
enable/disable cycles.

### 6.7 Lifecycle gap: release identity is still a template

[`android/app/build.gradle.kts`](../android/app/build.gradle.kts:25) sets
`applicationId = "com.example.eyecue_flutter"`, and the release build type inherits
`signingConfig = signingConfigs.getByName("debug")`
([`android/app/build.gradle.kts`](../android/app/build.gradle.kts:34)). A release
artefact produced from this tree cannot be published; both lines are L9 work.

### 6.8 Two facts L1 depends on

**The frame is already in hand where the stream result is built.** At
`YOLOView.kt:1486` the analysis callback stores the sensor-orientation analysis `Bitmap`
it decoded from the `ImageProxy` (`latestAnalysisBitmap = bitmap`), and `:1531`
(`result.copy(originalImage = bitmap)`) reuses that same bitmap for the stream *before*
the encode at `:2470`. The shared bitmap is therefore the analysis frame in sensor
orientation, not a rotated rendering of it — which is exactly the frame the depth model
consumes. That is what makes a shared-frame transport cheap: the bitmap L1b needs is the
one the analysis path already has, so no new capture and no copy is required.

**Depth entry point (as extended by L1b).** L1b does **not** go through the `YOLOPlugin`
`predictSingleImage` handler
(`plugins/ultralytics_yolo/android/src/main/kotlin/com/ultralytics/yolo/YOLOPlugin.kt:192`,
decode at `:206`) any more: the analysis frame never becomes bytes, so the Dart dispatch
side (`plugins/ultralytics_yolo/lib/core/yolo_inference.dart:56`–`:58`) is off the depth
path. The tick calls `instanceManager.predict(...)` directly from the view.

### 6.9 L1b outcome (closes 6.1–6.4 for the depth path)

`CONFIRMED-BY-INSPECTION` in the vendored plugin, `CONFIRMED-BY-TEST` for the payload
contract (key set, rejection of `values`/`originalImage`, failure marker shape),
`CONFIRMED-BY-BUILD` for the Kotlin. The grid arithmetic and the `depthMaxDim` wiring are
**not** test-covered and stay `CONFIRMED-BY-INSPECTION` — see the payload fact below.

| Finding | Status after L1b |
| --- | --- |
| 6.1 JPEG encode per detection result | closed for the depth path — `includeOriginalImage` is no longer set from `lib/` (`grep -rn "includeOriginalImage" lib` is empty); upstream keeps supporting the flag for other consumers |
| 6.2 encodes discarded by the estimator | closed — there is no Dart-side frame slot any more |
| 6.3 Android → Dart → Android round trip | closed — the depth instance runs on the analysis bitmap inside the view |
| 6.4 dense `Float32` depth map per frame | closed for the stream — the event carries a block-mean grid (`depthGrid`), `values` is not allocated on the tick path (`includeRawData = false`) and is never serialized |
| 6.5 heatmap built unconditionally | **open** — L2 |
| 6.6 MDE off does not release the model | **open** — L3 |

Transport facts (`CONFIRMED-BY-INSPECTION`): the interval and the in-flight guard are
native, the tick runs after the detector result and the stream callback, and the event
rides the existing view event channel as `type: 'depth'`. The tick calls
`YOLOInstanceManager.predict(..., includeRawData = false, drawOverlays = false)`, so it
builds neither the dense `values` copy nor the annotated full-frame bitmap that
`drawAnnotations` would allocate.

Failure fact (`CONFIRMED-BY-INSPECTION`): a depth inference that throws or returns no grid
emits `{type: 'depth', error: 'inference_failed', timestamp}` exactly once and sets a
native latch (`depthDisabled`) that stops the tick until the next streaming config — or a
`pauseCamera()` re-arm — arrives. Dart maps the `error` marker to degraded **before** its
pause/stopped early return, so a failure landing inside the pause window still withdraws
the instance id; `retry()` re-pushes the id, clearing the latch. Pause → failure → resume
therefore ends in a visible `degraded` state, never a silently dead depth path.

Payload fact (`CONFIRMED-BY-INSPECTION` for the arithmetic, `CONFIRMED-BY-TEST` only for the
shape the Dart side parses): `depthMaxDim` is now actually applied — the tick resolves the
instance predictor via `YOLOInstanceManager.predictorInstance(id): Predictor?`, casts it to
`DepthEstimator` and assigns `gridMaxDim` before each inference, logging once if the cast
fails. The cap holds the longest side at `depthMaxDim`, so the grid is
≤ 96 × 96 × 4 = **36 864 bytes**, and the production 4:3 analysis stream emits
96 × 72 × 4 = 27 648 bytes — versus the JPEG plus its native re-decode it replaces.
Neither figure is produced by an executed native test: there is no Kotlin test source set
for `plugins/**`, so the grid maths is `CONFIRMED-BY-INSPECTION` until a real-device or
JVM/Robolectric measurement exists.

Build fact (`CONFIRMED-BY-BUILD`): `flutter build apk --debug` on the L1b tree →
`build/app/outputs/flutter-apk/app-debug.apk`, 116 s incremental (the planner
preflight's from-cache figure in §4.6 was 625 s), exit 0. Re-verified on the remediation
commit `15fcf39`: Gradle `assembleDebug` 39.8 s (45.5 s wall), exit 0, with the vendored
Kotlin recompiled (`build/ultralytics_yolo/.../YOLOView*.class` rewritten), which is the
only compile gate that covers `plugins/**`. Re-verified again on the round-3 remediation:
Gradle `assembleDebug` 45.0 s (52.06 s wall), exit 0, `flutter analyze` 4 issues / 0
errors, `flutter test` 534 passing + 1 known pre-existing TTS failure; both
`YOLOView.class` and `YOLOInstanceManager.class` were rewritten by that build, and
`javap -p` on the latter reports
`public final com.ultralytics.yolo.Predictor predictorInstance(java.lang.String)`, which is
why the `DepthEstimator` cast is now reachable. That is a **compile-time** proof of the
signature, not a runtime measurement: no device is attached, so the end-to-end
`depthMaxDim` → grid effect is `CONFIRMED-BY-INSPECTION`.
The key set, the failure marker and the payload *shape* are pinned by
[`test/services/depth_payload_parity_test.dart`](../test/services/depth_payload_parity_test.dart:133);
its primary grid fixture is the production 4:3 stream (640×480 → 96×72), with 16:9
(640×360 → 96×54) kept as a secondary case. That test feeds the parser a hand-built event:
it cannot catch a regression in `DepthEstimator.blockMeanGrid`, so the aspect guarantee
itself is `CONFIRMED-BY-INSPECTION` (see the payload fact above).

## 7. External gates register

Gates that cannot be closed inside this repository. Each row names a single
continuation action the owner can execute.

| Gate | Why blocked | Exact continuation command | Owner action required |
| --- | --- | --- | --- |
| Physical-device performance matrix | No Android device attached to the build host, so no measurement of frame timing, thermal behaviour or accelerator selection exists | `flutter devices` then `flutter run --release -d <device-id>`; capture per-stage timings from the L4 instrumentation | Attach a target-class Android device (or emulator with a documented caveat) and host it for a measurement session |
| Production signing material | No keystore or Play App Signing enrolment exists in this repository; release builds are still debug-signed | `keytool -genkeypair -v -keystore upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`, then wire `android/key.properties` and a release `signingConfig` | Create the upload keystore, store it outside the repo, provide the alias/passwords out of band, enrol in Play App Signing |
| Local Supabase stack | Supabase CLI is not installed and the volume has 6.7 GB free (93 % used); installing the CLI plus Docker images is not affordable here | Deferred by design. When capacity exists: `supabase start && supabase db reset && supabase functions serve ingest-telemetry` | Provision disk capacity and approve installing the Supabase CLI; until then L6 stays external |
| Play Console submission | No Play Console account, listing or track is configured in this workspace | Not automatable from the repository; use the Play Console web UI after L9–L11 artefacts exist | Create/confirm the Play Console account, pay the registration fee, complete listing metadata |
| Production application ID confirmation | `applicationId` is still `com.example.eyecue_flutter`; publishing under a placeholder or an unowned domain is not acceptable | Provisional ID `app.eyecue.mobile` is proposed in §8. After approval: edit `applicationId` in `android/app/build.gradle.kts`, then `flutter build appbundle --release` | Confirm the reverse-domain ID and verify ownership of the corresponding domain namespace |
| Final licence selection | The project licence is undecided, and AGPL-3.0 obligations interact with redistribution of the bundled Ultralytics model/plugin | After decision: add the chosen `LICENSE` file and reconcile `docs/` and store listing text | Choose the project licence and confirm the AGPL-3.0 analysis for the vendored plugin and model weights |

## 8. Owner decision register

| # | Decision | Current status | Constraint |
| --- | --- | --- | --- |
| D1 | Production `applicationId` | Provisional `app.eyecue.mobile` | Must not be published without explicit owner confirmation; changing it after the first Play release is not possible for the same listing |
| D2 | Final project licence | Undecided | Must be compatible with AGPL-3.0 obligations arising from the bundled Ultralytics model and plugin; decide before publishing source and before L10 |
| D3 | Privacy / Data Safety answers | Undecided | Must state whether device model and Android version are collected as part of research telemetry; the answers must match what `supabase/migrations/202610200001_create_research_telemetry.sql` actually stores |
| D4 | Vendored plugin fork | **Approved** | Approval for the vendored Ultralytics plugin fork has already been given by the owner; this is recorded here so later items do not re-litigate it |

## 9. Reviewer verdict log

Rule: **no implementer may approve their own commit.** Every row requires a reviewer
other than the author of the commit being reviewed.

| Commit | Item | Verdict | Findings | Reviewed by role |
| --- | --- | --- | --- | --- |
| `a8e0571` | L0 baseline ledger | PASS_WITH_NOTES | 7 findings (5 minor/nit citation precision, 1 unlabelled claim, 1 cell-shape inconsistency); all applied in `e03bc36` | reviewer |
| `fcf4cd0`, `63131d5`, `3f81cc3` | L1 native shared-frame MDE transport | CHANGES_REQUIRED | 4 major: (1) grid aspect broken — per-axis scaling forced every crop to 96×96; (2) a failing depth inference was invisible and never stopped; (3) `stop()` blocked the platform thread and interrupted in-flight inference; (4) per-tick full-frame annotation copy. 5 minor: non-volatile `depthExecutor`; out-of-order `_publish`; misleading `imageWidth`/`imageHeight`/`rotationDegrees` keys; grid built on the dense path too; tautological grid test. 2 nits: two drifted doc statements | reviewer |
| `15fcf39` | L1 remediation of the findings above | CHANGES_REQUIRED (round 2: 8 of 9 fixed, 4 open) | Finding → fix map: MAJOR-1 single scale from the longest side in `DepthEstimator.kt:135` (640×360 → 96×54); MAJOR-2 one-shot `{type: depth, error: inference_failed}` event + `depthDisabled` latch (`YOLOView.kt:1659`) mapped to `_degrade()` in `monocular_depth_estimator.dart:144`; MAJOR-3 `shutdown()` only, never `shutdownNow()`/`awaitTermination` (`YOLOView.kt:2567`); MAJOR-4 `drawOverlays = false` on the depth tick (`YOLO.kt:75`, `YOLOView.kt:1622`); MINOR-5 `@Volatile depthExecutor` + create/teardown lock (`YOLOView.kt:173`, `:1598`); MINOR-6 single-in-flight publish guard (`monocular_depth_estimator.dart:100`, `:163`); MINOR-7 `rotationDegrees` removed, `imageWidth`/`imageHeight` = analysed bitmap dims (`YOLOView.kt:1672`, `yolo_result.dart:399`); MINOR-8 grid only when `!includeRawMaskData` (`DepthEstimator.kt:130`); MINOR-9 portrait + landscape payload-shape tests (`depth_payload_parity_test.dart:204`, `:213`) | reviewer |
| `79eb9c0` | L1 remediation round 2 — the four findings left open by the round-2 review | pending re-review | NEW-1 `YOLOInstanceManager.predictorInstance(instanceId): Predictor?` (was `Unit`) and `gridMaxDim = config.depthMaxDim` applied to the resolved `DepthEstimator` on the tick path, with a one-shot `Log.w` instead of a swallowing `runCatching`; compiled artefact checked with `javap` (`public final com.ultralytics.yolo.Predictor predictorInstance(java.lang.String)`). NEW-2 `depthDisabled = false` in `pauseCamera()` and the Dart depth handler now maps an `error` event before its `_paused`/`!_detectionActive` early return, so pause → failure → resume ends in a visible `degraded` state. NEW-3/MINOR-9 primary fixture is the production 4:3 stream (640×480 → 96×72), the impossible 360×640 case is gone, and the aspect guarantee is relabelled `CONFIRMED-BY-INSPECTION`. NIT `private val depthLock = Any()` replaces both `synchronized(this)` blocks. | reviewer |

## 10. Rollback instructions

This branch is **additive on `adfbc5d`**: it introduces work on top of the verified
consolidation base and rewrites no history. Rolling back the entire programme therefore
means discarding the branch, not reverting commits on a protected branch.

To abandon the work:

```sh
git worktree remove /home/nico/repos/eyecue_flutter-playstore
git branch -D feat/play-store-readiness
```

If the worktree is retained for inspection, only the branch needs removing:
`git branch -D feat/play-store-readiness` (run from any checkout that does not have it
checked out).

Statement of blast radius (`CONFIRMED-BY-INSPECTION`): no protected branch (`dev`,
`main`) was modified, no commit was rewritten, no stash was created or dropped, no other
worktree was touched, and no external system (Supabase project, Play Console, signing
infrastructure) was modified by this work. Checking out `dev` in the primary checkout is
explicitly out of scope for this rollback.
