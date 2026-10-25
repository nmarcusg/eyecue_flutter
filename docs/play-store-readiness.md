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

The dashboard lives in a **separate repository**
(`/home/nico/Documents/ChatGPT/Eyecue/research-dashboard-cadence`, branch
`feat/dashboard-cadence`), so its contract tests run there, not here:

```
cd /home/nico/Documents/ChatGPT/Eyecue/research-dashboard-cadence
node --test test/cadence.test.mjs test/perf-fields.test.mjs
=> # tests 21   # pass 21   # fail 0
```

`CONFIRMED-BY-TEST`. The 7 `cadence.test.mjs` cases are unchanged from the baseline;
the 14 `perf-fields.test.mjs` cases cover the schema-4 render, the schema-3 fallback,
the striding note and the dropped-tick delta with its single-sample and counter-reset
refusals. Caveat, also measured: `node --test test/` reports
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
| L1 native shared-frame MDE transport | Stop JPEG-encoding and re-decoding the analysis frame; run depth on the analysis frame inside the view and emit a compact block-mean grid (grid ≤ 36 864 bytes) | L0, L1a | DONE | `63131d5` (`3f81cc3` docs; remediation `15fcf39`, `2540470`, `79eb9c0`) | round 1 on `fcf4cd0`/`63131d5`/`3f81cc3` → CHANGES_REQUIRED (4 major/5 minor/2 nit); round 2 on `15fcf39`/`2540470` → CHANGES_REQUIRED (8 of 9 fixed, 4 open); round 3 remediation `79eb9c0` -> PASS_WITH_NOTES (docs `2540470`, `614a6ca`); 2 minors carried to L2 | `CONFIRMED-BY-INSPECTION` (grid arithmetic, `depthMaxDim` wiring, pause→failure→resume order), `CONFIRMED-BY-TEST` (payload key set/shape), `CONFIRMED-BY-BUILD` (vendored Kotlin compiles) |
| L2 compact depth payload + heatmap gating | Replace the dense Float32 depth return with a compact payload; build the heatmap only when it is displayed | L1 | DONE | `ca35e75` | `CONFIRMED-BY-TEST` (heatmap builder not invoked while hidden, re-enable rebuilds, disable disposes through `Image.debugDisposed`, degraded interleaving, boxes/heatmap independence, `streamingConfigKey` heatmap-agnostic), `CONFIRMED-BY-BUILD` (debug APK, vendored Kotlin recompiled), `CONFIRMED-BY-INSPECTION` (native colourisation/bitmap skip, `DepthMap.image` consumer list, screen wiring). `CONFIRMED-ON-DEVICE` is still required for the frame-time effect |
| L3 MDE enable/disable resource lifecycle | Release the depth model when MDE is turned off, not just the scheduler | L1 | DONE | `8b8e1be` (L2 housekeeping) + the L3 lifecycle commit and its remediation commit | PASS_WITH_NOTES (accepted at `f0b659b`) | `CONFIRMED-BY-TEST` (release disposes the instance, clears frame/heatmap, parks `idle`, keeps `observedHz`/`lastLatencyMs`, is idempotent; disable → re-enable loads exactly once back to `ready`, including a disable that lands while a load is in flight — `a disable during the load does not strand the re-enable` asserts two loads, the stale handle released and the second adopted; `a load that finishes after a release is disposed, not adopted` asserts the release count on the fake handle; `a publish in flight at a release is dropped`; `depthNeedsReload` both branches), `CONFIRMED-BY-INSPECTION` (screen wiring: release only on a mode change that turns depth off; `_retryDepth` re-arms through `depthNeedsReload()`), `CONFIRMED-BY-BUILD` (debug APK). `CONFIRMED-ON-DEVICE` is still required for the resident-memory effect |
| L4 accelerator policy + stage timings + dispose-during-load fix | Deterministic CPU/GPU selection with fallback, per-stage inference timings and the pre-existing dispose-during-load leak | L2 | DONE | `99a40d9` (dispose fix) + the commit carrying this row (accelerator + timings + docs) | pending review | `CONFIRMED-BY-TEST` (pure `resolveDepthAccelerator` incl. junk/empty → `auto`; `DetectorStageTimings` mapping with `0` → `null`; `YOLODepthEvent` stage parsing with absent keys → `null` and the key set now including `droppedTicks`; reported accelerator taken from the event, so a requested GPU that fell back reports `cpu`; a `cpu` policy passing `useGpu: false`; stage timings and `droppedTicks` surviving `stop()`/`releaseModel()`; the dispose-during-load release), `CONFIRMED-BY-INSPECTION` (lifecycle fix: `dispose()` bumps the release epoch and drops the in-flight slot, adoption routed through the epoch branch, the `loading` write and the `_load` catch guarded; native `depthDroppedTicks` increments at both skip sites and resets in `stop()`), `CONFIRMED-BY-BUILD` (debug APK plus a `--dart-define=EYECUE_DEPTH_ACCELERATOR=cpu` build). **Every performance figure is device-gated: no `CONFIRMED-ON-DEVICE` claim exists** — see [`benchmark-procedure.md`](benchmark-procedure.md) |
| L5 telemetry perf fields + schema v4 | Carry the detector/depth stage timings, the reported depth accelerator, the depth grid size, the heatmap cost and the cumulative `depthDroppedTicks` into each telemetry sample and bump the payload schema 3 → 4 | L4 | DONE | `8f2ab0a` (L4 follow-ups) + the commit carrying this row (telemetry) | PASS_WITH_NOTES (accepted at `f179e24`; the notes are closed in `9868c48`) | `CONFIRMED-BY-TEST` (every new sample key present and nullable, unknown omitted rather than `0`, no `depthQueueWaitMs` key, schema-3 rows read as unknown and re-serialise unchanged, worst-case export 1 322 400 bytes compact < 1 500 000 before the perf thinning, forbidden-token scan, worst-case upload envelope 1 850 400 bytes with device-shaped numbers < 1 900 000 after round 2), `CONFIRMED-BY-INSPECTION` (device model / Android version deliberately not collected — owner gate in L10) |
| L6 Supabase idempotency + schema gating | Idempotent ingestion plus rejection of unknown payload schema versions server-side | L5 | DONE | `9868c48` (L5 follow-ups) + the commit carrying this row | pending review | `CONFIRMED-BY-TEST` (the validator contract, `node --test supabase/functions/ingest-telemetry/validate.test.mjs`: 41 cases covering every forbidden key at three depths, the `frameNumber` allowance, case-variant and padded spellings that pass by design, each mistyped envelope field, schema 3 and 4 accepted, 2/5/3.5 rejected with `supported: [3, 4]`, the 2 000 000 / 2 000 001-byte boundary, the storage bound at least 20 % above the wire cap, and four coupling guards that read the migration SQL and `index.ts` (the fourth is the unguarded `telemetry_sessions_check` drop); plus the client error mapping per status, including the duplicate-versus-success split, each asserting the local session survives), `CONFIRMED-BY-INSPECTION` (the new migration: unique index on `(participant_code, client_session_id)`, `check (telemetry_schema_version in (3, 4))`, RLS and every existing row untouched; the function's probe → `upsert(..., onConflict, ignoreDuplicates)` path and its 201/200 split; the TypeScript was not compiled or deployed — inspection only), `BLOCKED-EXTERNAL` (**not** the `(required)` variant this row used to carry: the executable part of the contract is now covered by `node --test`, so the previous required label is superseded). **Neither the migration nor the function has ever been executed**: no PostgreSQL server, no Supabase CLI, no cached images, 4.3 GB free. The stack run is carried in §7 and is still open — this row claims no SQL or Deno execution |
| L7 dashboard contract compatibility | Keep the research dashboard able to read the amended payload contract | L5 | DONE | `ebfcc6e` (Flutter side: schema-4 contract evidence and this document) + `21a3263` (dashboard, in the **separate repository** `/home/nico/Documents/ChatGPT/Eyecue/research-dashboard-cadence`, branch `feat/dashboard-cadence`) + `efb3fb5` (Flutter remediation) + `e646279` (dashboard docs) | PASS_WITH_NOTES (remediation verified at `1581498` + `efb3fb5`; round 1 on `21a3263`/`ebfcc6e` → CHANGES_REQUIRED (4 medium, 1 low-medium, 5 low; the round-1 headline said "3 medium" because the two documentation findings were counted as one), remediation `1581498` (dashboard) + `efb3fb5` (Flutter remediation) | `CONFIRMED-BY-TEST` (the dashboard suite, **run in that separate repository**: `node --test test/cadence.test.mjs test/perf-fields.test.mjs` → 21/21 — the 7 cadence cases byte-identical to the baseline, the 14 perf cases covering the schema-4 render, the schema-3 fallback that renders no zeros, the striding note, and the rendered dropped-tick labels: one carrier → `unknown (single sample — no delta)` and never "0 ticks", two carriers → "4 ticks over 2 points", a decreasing counter → `unknown (counter reset)`, singular "1 point"/"1 sample", and a precision note with no backticks (all of these assert the `cadence.js` label helpers, not the panel template); plus the Flutter suite `flutter test` 589 passing + the 1 known pre-existing `tts_service_test` failure, of which the three new cases exercise the 4 KiB response clamp through the sender seam — single-chunk truncation at 4096 B, a codepoint split by the cut that decodes without throwing, and a `duplicated` prefix that still answers `already uploaded earlier`), `CONFIRMED-BY-INSPECTION` (the SQL side of the contract: the dashboard reads `payload` / `telemetry_schema_version` exactly as written by `supabase/migrations/202610200001_create_research_telemetry.sql` and amended by `202610250001` — neither the migration nor the function has been executed, and nothing on the dashboard path touches the database directly; and the panel rendering two of those labels, [`dist/app.js:35`], which **no test executes** — `heatmapBuildMs` is emitted under the "last sampled" label and the delta as "N ticks over M points", so those two panel-level claims are inspection-only rather than test evidence), **NO DEPLOYMENT WAS PERFORMED**: the dashboard is a static bundle in a separate repository, never built for, uploaded to, or served from any host, and publishing it is an owner-gated action (see §7) |
| L8 R8/WorkManager/Room release verification | Prove the pinned WorkManager + Room + consumer R8 rules survive a minified release build | L1–L4 | DONE | `2d0d0cd` (shrinking config) + the commit carrying this row (release build + inspection) | CHANGES_REQUIRED (see §9) | `CONFIRMED-BY-BUILD` (a minified `flutter build appbundle --release` and `flutter build apk --release` both completed: AAB 78 607 421 B, APK 91 191 297 B, digests in [`release-procedure.md`](release-procedure.md) §6), `CONFIRMED-BY-INSPECTION` (the release `classes.dex` **defines** `androidx.work.impl.WorkDatabase_Impl` with a public no-arg `<init>()` and 33 methods, and 727 `androidx.room.*` rows survive — so the historical `Failed to create an instance of class androidx.work.impl.WorkDatabase` reflective lookup has its target). **Installed startup is `NOT VERIFIED` — device gate**, see the note in that row |
| L9 Play Store configuration | Application ID, release signing config, versioning, permission surface | L8 | DONE | `2d0d0cd` + the commit carrying this row (manifest read back from the release APK) | CHANGES_REQUIRED (see §9) | `CONFIRMED-BY-BUILD` (real `aapt2`/`apkanalyzer` output on `app-release.apk`: `package: name='app.eyecue.mobile' versionCode='1' versionName='1.0.0-testsigned'`, no `android:debuggable` attribute hence false, `minSdkVersion:'24'` / `targetSdkVersion:'36'` / `compileSdkVersion='36'`, the 11-entry permission list, `launchable-activity: name='app.eyecue.mobile.MainActivity'`; model assets in the AAB are exactly `yolo26n-depth_w8a32.tflite` + `yolov8n_int8_new_metadata.tflite` with the three tooling-only models absent; three ABIs `arm64-v8a`/`armeabi-v7a`/`x86_64`; secret scan 0 hits; no `design-reference`/`docs`/`tool`/`test` entries bundled — all in [`release-procedure.md`](release-procedure.md) §6), `BLOCKED-EXTERNAL` (upload keystore, Play App Signing, owner confirmation of the provisional `applicationId`) |
| L10 permission surface + licensing/privacy/store materials | Remove the three unused camerax-injected permissions, add the licence notice, third-party notices, privacy/Data-Safety answers and the Play checklist | L9 | DONE (owner decisions remain open) | `8766586` (permissions + rebuild) + `842d38b` (licence, notices, privacy, checklist) | pending review | `CONFIRMED-BY-BUILD` (AAB 78 607 313 B sha256 `6d566ed4…`, APK 91 191 189 B sha256 `3c932ed4…`, both `-testsigned`), `CONFIRMED-BY-INSPECTION` (`aapt2` lists 8 permissions; `RECORD_AUDIO`, `WRITE_EXTERNAL_STORAGE` and `READ_EXTERNAL_STORAGE` absent), `BLOCKED-EXTERNAL` (licence D2, Data Safety D3, legal review R1–R7) |
| L11 final readiness report | Release AAB build, artefact inspection, final readiness statement and one classification | all above | DONE | the commit carrying this row ([`release-readiness-report.md`](release-readiness-report.md)) | pending review | `CONFIRMED-BY-BUILD`, `CONFIRMED-BY-INSPECTION`; `CONFIRMED-ON-DEVICE` is **still required and still absent** — classification `CODE_READY_WITH_EXTERNAL_GATES` |

The L8/L9 digests recorded in the two rows above (`feaab199…`, `99ac0da9…`) describe
the artefacts built at `870c24e`. The L10 manifest change forced a rebuild; the
current files are AAB `6d566ed4…` / APK `3c932ed4…`, recorded in
[`release-procedure.md`](release-procedure.md) §6 and
[`release-readiness-report.md`](release-readiness-report.md) §4.

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

Closed by L3: the estimator gained `releaseModel()` and the MDE-off block calls it, so the
interpreter is disposed on the disable path and reloaded once on re-enable — including when
the disable lands while a load is still in flight, which invalidates that load and lets the
re-enable start and adopt its own (`stop()` is still the pause path and still keeps the
model). The line citations above are the baseline ones and have moved since.

### 6.7 Lifecycle gap: release identity is still a template

[`android/app/build.gradle.kts`](../android/app/build.gradle.kts:25) sets
`applicationId = "com.example.eyecue_flutter"`, and the release build type inherits
`signingConfig = signingConfigs.getByName("debug")`
([`android/app/build.gradle.kts`](../android/app/build.gradle.kts:34)). A release
artefact produced from this tree cannot be published; both lines are L9 work.

Closed by L9 in `2d0d0cd`: `applicationId`/`namespace` are now
`app.eyecue.mobile` (provisional, gate D1) and the release build type no longer
inherits the debug signing config — it uses an owner-supplied `release`
`signingConfig` when keystore material is present and otherwise falls back
explicitly, with `versionNameSuffix = "-testsigned"` and a Gradle warning, so an
unsigned-environment build cannot pass as a Play release
([`android/app/build.gradle.kts`](../android/app/build.gradle.kts:80)). The
fallback was exercised by this item's build: the artefact reports
`versionName='1.0.0-testsigned'` and verifies as `CN=Android Debug`. Publication
is still `BLOCKED-EXTERNAL` (no keystore).

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
| 6.5 heatmap built unconditionally | closed by L2 (`ca35e75`) — the estimator builds an RGBA buffer and a `ui.Image` only while the overlay asks for one, and the native streaming path no longer colourises the crop or allocates the ARGB bitmap at all |
| 6.6 MDE off does not release the model | closed by L3 — `_handleSettingsChanged` calls `releaseModel()` on the mode change that turns depth off, which disposes the interpreter and parks the estimator at `idle`; the model is reloaded once on re-enable (also when a disable interrupts an in-flight load) and pause/stop/backgrounding still keep it |

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

### 6.10 L2 outcome (`ca35e75`)

**Native (`DepthEstimator.postProcessDepth`).** When `includeRawMaskData` is false — exactly the
native stream, which already skips the dense `values` copy — the crop is no longer colourised:
`colorizeDepth` (the LUT pass that also wrote the persistent `colorPixels` `IntArray`) is not
called, `Bitmap.createBitmap(...ARGB_8888)` (≈0.8 MB at 518×389 per inference) is not allocated,
and `DepthMap.image` stays `null`. `minDepth`/`maxDepth` come from a single scan
(`depthRange`) that applies the same predicate as the colouriser (`isfinite && > 0`), and a crop
with no valid sample still fails with the same `error("Depth output contains no valid values")`.
The still-image/overlay path (`includeRawMaskData = true`) is unchanged: same `colorizeDepth`
call, same bitmap, same `values`.

Every `DepthMap.image` consumer checked before making it null on this path
(`grep -rn "depthMap\\?\\.image\\|depthMap?.image" plugins/ultralytics_yolo`): `YOLO.kt:405`
(`drawAnnotations` DENSE MAPS arm — not reached on the tick, which passes
`drawOverlays = false`), `YOLOView.kt:1935` (the view's own overlay for its detection task, not
the depth instance), and no Dart consumer: `YOLODepthMap.fromMap` in
`plugins/ultralytics_yolo/lib/models/yolo_result.dart:345` (`:297` is its call site)
reads only the numeric fields.
`YOLOPlugin.kt:295` and `YOLOView.kt:2414` serialise `requireNotNull(depthMap.values)`, not the
image, and both sit on the dense (`includeRawMaskData = true`) paths, which keep `values`.

**Dart (`MonocularDepthEstimator`).** A settable `heatmapEnabled` gates construction: while it is
false `_publish` never calls the builder (`heatmapBuilder ?? _buildHeatmap`), the frame carries
`heatmap: null`, and the grid plus all distance sampling is unchanged. Disabling drops the held
image (a heatmap-less copy replaces the frame, then `ui.Image.dispose()`), so the GPU texture is
released and no stale overlay can be shown. Re-enabling makes the very next frame carry a
heatmap; a builder that completes after the toggle is disowned. The screen sets the flag from
`heatmapRequested(mdeEnabled, showDepthHeatmap)` in `initState` and
`_handleSettingsChanged`, so the toggle is presentation-only: the streaming-config key does not
contain it, the camera is not restarted and the depth tick keeps running.

Freshness is deliberately **not** part of the gate. `DepthOverlayState.resolve` already hides a
stale heatmap for display; gating construction on it would need the frame the gate governs, so a
hidden heatmap could never be rebuilt.

**Degraded guard.** `_publish` only publishes `ready` when the state is not `degraded`, so a good
frame in flight when an `error` event lands can no longer re-arm the instance id and clear the
native latch. `loading`/`idle` transitions are untouched, and a successful frame after `retry()`
still publishes `ready`.

**Evidence.** `CONFIRMED-BY-TEST`: four new cases in
[`test/services/monocular_depth_estimator_test.dart`](../test/services/monocular_depth_estimator_test.dart:270)
(builder count 0 while hidden with a valid grid; re-enable rebuilds; disable disposes and keeps
the grid; the frame-in-flight/degrade interleaving) and three in
[`test/screens/depth_overlay_state_test.dart`](../test/screens/depth_overlay_state_test.dart:81)
(the gate truth table, the key staying heatmap-agnostic, boxes/heatmap independence over all four
combinations). Verification on `ca35e75`: `dart format` clean, `flutter analyze` 4 issues / 0
errors (all pre-existing), `flutter test` 541 passing + the 1 known pre-existing TTS failure,
targeted suite 46/46, `flutter build apk --debug` exit 0 — Gradle `assembleDebug` 26.5 s
(31.0 s wall), which recompiled the vendored Kotlin. `CONFIRMED-BY-INSPECTION` covers the native
skip (no Kotlin test source set) and the per-frame cost that is skipped; the wall-clock saving on
a device is still `CONFIRMED-ON-DEVICE`-only and unmeasured.

## 7. External gates register

Gates that cannot be closed inside this repository. Each row names a single
continuation action the owner can execute.

| Gate | Why blocked | Exact continuation command | Owner action required |
| --- | --- | --- | --- |
| Physical-device performance matrix | No Android device attached to the build host, so no measurement of frame timing, thermal behaviour or accelerator selection exists | `flutter devices` then `flutter run --release -d <device-id>`; capture per-stage timings from the L4 instrumentation | Attach a target-class Android device (or emulator with a documented caveat) and host it for a measurement session |
| Production signing material | No keystore or Play App Signing enrolment exists in this repository; release builds are still debug-signed | `keytool -genkeypair -v -keystore upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`, then wire `android/key.properties` and a release `signingConfig` | Create the upload keystore, store it outside the repo, provide the alias/passwords out of band, enrol in Play App Signing |
| Local Supabase stack | `BLOCKED-EXTERNAL — disk capacity`: no PostgreSQL server, no Supabase CLI and no cached Supabase images on this host, and the volume holds 4.3 GB free of 91 GB (96 % used). Nothing was installed and no image was pulled | `npx supabase@latest start` (needs ≈10 GB for images), then `npx supabase@latest db reset` (applies `202610200001`, then `202610250001`), `npx supabase@latest db lint`, `npx supabase@latest functions serve ingest-telemetry`, replay one envelope twice (`201` then `200 {"duplicated":true}`) and confirm `select count(*) from public.telemetry_sessions` stays 1, then `npx supabase@latest stop` | Provision disk capacity and approve installing the Supabase CLI; until then migration and function execution stay unverified |
| Play Console submission | No Play Console account, listing or track is configured in this workspace | Not automatable from the repository; use the Play Console web UI after L9–L11 artefacts exist | Create/confirm the Play Console account, pay the registration fee, complete listing metadata |
| Production application ID confirmation | `applicationId` is `app.eyecue.mobile` (`2d0d0cd`) but still **provisional**, pending D1; publishing under an unowned domain is not acceptable, and the value cannot change after the first Play upload for that listing | If D1 changes the ID, edit `applicationId` and `namespace` in `android/app/build.gradle.kts` and the Kotlin package path, then rebuild: `flutter build appbundle --release` | Confirm the reverse-domain ID and verify ownership of the corresponding domain namespace |
| Final licence selection | The project licence is undecided, and AGPL-3.0 obligations interact with redistribution of the bundled Ultralytics model/plugin | After decision: add the chosen `LICENSE` file and reconcile `docs/` and store listing text | Choose the project licence and confirm the AGPL-3.0 analysis for the vendored plugin and model weights |
| Dashboard deployment | The research dashboard is a static bundle in a **separate repository** (`/home/nico/Documents/ChatGPT/Eyecue/research-dashboard-cadence`, branch `feat/dashboard-cadence`). L7 verified it with `node --test` only: **no deployment was performed** — no bundle was built for a host, nothing was uploaded and no site was published, and neither repository can deploy it | Not automatable from this repository: `cd /home/nico/Documents/ChatGPT/Eyecue/research-dashboard-cadence && node --test test/cadence.test.mjs test/perf-fields.test.mjs` reproduces the verified contract, then publish `dist/` to the study's chosen host | Choose and authorise the host for the dashboard bundle, then publish it; until then researchers have the contract and its tests, not a served site |

## 8. Owner decision register

| # | Decision | Current status | Constraint |
| --- | --- | --- | --- |
| D1 | Production `applicationId` | Provisional `app.eyecue.mobile` | Must not be published without explicit owner confirmation; changing it after the first Play release is not possible for the same listing |
| D2 | Final project licence | Undecided | Must be compatible with AGPL-3.0 obligations arising from the bundled Ultralytics model and plugin; decide before publishing source and before L10 |
| D3 | Privacy / Data Safety answers | Undecided | Must state whether device model and Android version are collected as part of research telemetry; the answers must match what `supabase/migrations/202610200001_create_research_telemetry.sql` actually stores |
| D4 | Vendored plugin fork | **Approved** | Approval for the vendored Ultralytics plugin fork has already been given by the owner; this is recorded here so later items do not re-litigate it |

The research dashboard is **not** part of this repository and is **not deployed** by
anything here: it is a static bundle under
`/home/nico/Documents/ChatGPT/Eyecue/research-dashboard-cadence` (branch
`feat/dashboard-cadence`). L7 verified it with `node --test` only — no build was
produced for a host, nothing was uploaded and no site was published. Making it
reachable to researchers is an owner-gated action, recorded in §7.

## 9. Reviewer verdict log

Rule: **no implementer may approve their own commit.** Every row requires a reviewer
other than the author of the commit being reviewed.

| Commit | Item | Verdict | Findings | Reviewed by role |
| --- | --- | --- | --- | --- |
| `a8e0571` | L0 baseline ledger | PASS_WITH_NOTES | 7 findings (5 minor/nit citation precision, 1 unlabelled claim, 1 cell-shape inconsistency); all applied in `e03bc36` | reviewer |
| `fcf4cd0`, `63131d5`, `3f81cc3` | L1 native shared-frame MDE transport | CHANGES_REQUIRED | 4 major: (1) grid aspect broken — per-axis scaling forced every crop to 96×96; (2) a failing depth inference was invisible and never stopped; (3) `stop()` blocked the platform thread and interrupted in-flight inference; (4) per-tick full-frame annotation copy. 5 minor: non-volatile `depthExecutor`; out-of-order `_publish`; misleading `imageWidth`/`imageHeight`/`rotationDegrees` keys; grid built on the dense path too; tautological grid test. 2 nits: two drifted doc statements | reviewer |
| `15fcf39` | L1 remediation of the findings above | CHANGES_REQUIRED (round 2: 8 of 9 fixed, 4 open) | Finding → fix map: MAJOR-1 single scale from the longest side in `DepthEstimator.kt:135` (640×360 → 96×54); MAJOR-2 one-shot `{type: depth, error: inference_failed}` event + `depthDisabled` latch (`YOLOView.kt:1659`) mapped to `_degrade()` in `monocular_depth_estimator.dart:144`; MAJOR-3 `shutdown()` only, never `shutdownNow()`/`awaitTermination` (`YOLOView.kt:2567`); MAJOR-4 `drawOverlays = false` on the depth tick (`YOLO.kt:75`, `YOLOView.kt:1622`); MINOR-5 `@Volatile depthExecutor` + create/teardown lock (`YOLOView.kt:173`, `:1598`); MINOR-6 single-in-flight publish guard (`monocular_depth_estimator.dart:100`, `:163`); MINOR-7 `rotationDegrees` removed, `imageWidth`/`imageHeight` = analysed bitmap dims (`YOLOView.kt:1672`, `yolo_result.dart:399`); MINOR-8 grid only when `!includeRawMaskData` (`DepthEstimator.kt:130`); MINOR-9 portrait + landscape payload-shape tests (`depth_payload_parity_test.dart:204`, `:213`) | reviewer |
| `79eb9c0` | L1 remediation round 2 — the four findings left open by the round-2 review | PASS_WITH_NOTES | NEW-1 `YOLOInstanceManager.predictorInstance(instanceId): Predictor?` (was `Unit`) and `gridMaxDim = config.depthMaxDim` applied to the resolved `DepthEstimator` on the tick path, with a one-shot `Log.w` instead of a swallowing `runCatching`; compiled artefact checked with `javap` (`public final com.ultralytics.yolo.Predictor predictorInstance(java.lang.String)`). NEW-2 `depthDisabled = false` in `pauseCamera()` and the Dart depth handler now maps an `error` event before its `_paused`/`!_detectionActive` early return, so pause → failure → resume ends in a visible `degraded` state. NEW-3/MINOR-9 primary fixture is the production 4:3 stream (640×480 → 96×72), the impossible 360×640 case is gone, and the aspect guarantee is relabelled `CONFIRMED-BY-INSPECTION`. NIT `private val depthLock = Any()` replaces both `synchronized(this)` blocks. | reviewer |

| `79eb9c0`, `2540470`, `614a6ca` | L1b final verdict — the accepted stack (3 review rounds) | PASS_WITH_NOTES | L1b accepted: round 3 cleared NEW-1/NEW-2/NEW-3 and the `depthLock` nit (see the `79eb9c0` row above); `2540470` and `614a6ca` carry the remediation sha and the round-2 review log. Two minors were carried forward and are **resolved in L2 (`ca35e75`)**: (1) the streaming path still colourised the full crop and allocated an ARGB bitmap nothing read; (2) `_publish` published `ready` unconditionally, so a good frame in flight could flip `degraded` back to `ready` and clear the native latch. Also noted and **not** fixed here: `_retryDepth` never calls `_armDepth()` (pre-existing since `1e4b54e`) — **handed to L3** | reviewer |
| `ca35e75` | L2 heatmap gating + unused depth work | PASS_WITH_NOTES | Scope: native `postProcessDepth` skips colourisation + bitmap on the `!includeRawMaskData` path, Dart `heatmapEnabled` gate with image disposal, `_publish` degraded guard, 7 new tests, docs. Evidence: `flutter test` 541 + 1 known TTS failure, targeted 46/46, `flutter analyze` 4 / 0 errors, `flutter build apk --debug` exit 0 (Gradle 26.5 s). Two housekeeping items carried to L3 and **fixed in `8b8e1be`**: (1) no test covered the disowned-builder branch — the in-flight case's builder returned `null`, so a publish losing `heatmapEnabled` while holding a real `ui.Image` was unasserted; (2) §6.10 cited `yolo_result.dart:297` for `YODepthMap.fromMap` when `:297` is the call site (`:345` is the factory) | reviewer |
| `8b8e1be` | L3 housekeeping — L2 follow-ups | pending review | The disowned-builder test now blocks a real `ui.Image`, flips the gate off, and asserts `Image.debugDisposed` plus a grid-only frame; the §6.10 citation is corrected to `:345`. Verified standalone against the `b523f5e` `lib/` (16/16 targeted). No `lib/` change | reviewer (pending) |
| L3 lifecycle commit (the commit carrying this row) | L3 MDE enable/disable resource lifecycle + `_retryDepth` repair | CHANGES_REQUIRED (round 1, below) | Implementation only; no self-approval (rule above). `MonocularDepthEstimator.releaseModel()` disposes the instance, clears frame + heatmap, clears the load-failure flag and parks `idle`, keeping the notifiers and the observed-Hz/latency history; the screen calls it only on the mode change that turns depth off, so pause/stop/backgrounding keep the model. `_retryDepth` re-arms (`_armDepth()`) when `instanceId == null` and otherwise re-pushes the id — this closes the dead end present since `1e4b54e`, where a model-load failure left depth dead with no affordance. A release epoch disposes a load that lands after the disable instead of adopting it. Test seam: a `DepthModelFactory`/`DepthModelHandle` pair defaulting to the real `YOLO` path, injected by tests only. Evidence: `flutter test` 547 + 1 known TTS failure, targeted 21/21, `flutter analyze` 4 / 0 errors, `flutter build apk --debug` exit 0 (Gradle 25.7 s) | reviewer |
| `8b8e1be`, `82dd272` | L3 round 1 review — MDE enable/disable resource lifecycle | CHANGES_REQUIRED | 1 medium + 4 low + 1 flake + 1 nit. MEDIUM: a disable→enable inside the load window ended silently `idle` — `releaseModel()` bumped the release epoch but left `_preparing` pointing at the load it had just invalidated, so the re-enable joined the doomed load, which landed on the epoch mismatch, was disposed and re-armed nothing (`idle`, `_yolo == null`, no heatmap, no depth distance, no `degraded`, therefore no retry affordance). LOW: `_publish` guarded `_disposed` but not the release, so a frame in flight at release time republished and flipped `ready` with no model; `a load that finishes after a release is disposed, not adopted` never observed the dispose; the screen half of the retry fix had no test; `re-enabling makes the next frame carry a heatmap again` was flaky (1 in 17 full-file runs) because `decodeImageFromPixels` completion is not bounded by `pumpEventQueue()`. NIT: `_handleSettingsChanged` repeated the `stop()`/`clearFrame()` that `releaseModel()` already performs, and `testImage()` only delegated to `_testImage()`. DOCS: `known-issues.md` and this ledger claimed "reloaded exactly once on re-enable" unconditionally, and `mde-integration.md` described the lifecycle order as dispose-then-clear when the code clears-then-disposes | reviewer |
| L3 remediation (the commit carrying this row) | The findings above | pending review | `releaseModel()` now clears the in-flight slot and `prepare()` clears only its own, so a re-enable starts and adopts a fresh load (`a disable during the load does not strand the re-enable`: two loads, the stale handle released, `depth-2` adopted, `ready`; the test fails on the unfixed code with only one load). The epoch-mismatch branch re-parks `idle` only when no newer load owns the state and never over `degraded`. `_publish` carries the release epoch and drops a frame that outlived its release (`a publish in flight at a release is dropped`). The release test now asserts `releases == 1` on the stale fake handle. `depthNeedsReload()` is pure, `_retryDepth()` calls it, and both branches are unit-tested. The three real-image tests pre-decode their `ui.Image`, so the platform decoder is out of the publish path; 10 consecutive full-file runs green. Docs corrected as listed | reviewer (pending) |
| `f0b659b` | L3 final verdict — MDE enable/disable resource lifecycle (accepted) | PASS_WITH_NOTES | The round-1 findings (`8b8e1be`, `82dd272` review) are verified fixed at `f0b659b`; the rows above stay as history. Two review findings were carried into L4 and closed there (`99a40d9`): (1) **pre-existing dispose-during-load leak** — `dispose()` never bumped the release epoch and the load-adoption path had no `_disposed` check, so a load in flight at teardown was adopted: in release the 5.3 MB interpreter landed on a dead estimator and leaked, in debug the `ready` write asserted on the disposed notifier; (2) two test nits — the release/telemetry test decoded a `ui.Image` inside the heatmap builder instead of pre-decoding it, and `expect(models.single.instanceId, 'depth-1', reason: 'the handle was never adopted')` asserted nothing about adoption. Evidence at acceptance: `flutter test` 550 + 1 known TTS failure, `flutter analyze` 4 / 0 errors. No performance claim | reviewer |
| `99a40d9` + the commit carrying this row | L4 accelerator policy + stage timings + dispose-during-load fix | pending review | Implementation only; no self-approval (rule above). **Accelerator:** pure `resolveDepthAccelerator` (unknown/empty → `auto`) resolved from `--dart-define=EYECUE_DEPTH_ACCELERATOR`, `DepthAccelerator.useGpu` fed to `DepthModelFactory(useGpu:)`; build-time only, nothing persisted, no UI. The reported accelerator now comes from the native depth event, so a GPU request that fell back reports `cpu` and `depthStatusFor` passes it through. **Timings:** `DetectorStageTimings` derived from the streaming metrics, `DepthStageTimings` on the estimator with nullable stages and a native cumulative `droppedTicks`; nothing is added to the telemetry payload (that is L5). **Lifecycle:** `dispose()` invalidates loads exactly like `releaseModel()`, and the late handle is disposed through the epoch branch. **Device gate:** no `CONFIRMED-ON-DEVICE` claim for any figure; the matrix lives in [`benchmark-procedure.md`](benchmark-procedure.md) and the 1.5 FPS Redmi regression stays open until it runs. Evidence: `dart format` clean, `flutter analyze` 4 / 0 errors, `flutter test` 563 + 1 known TTS failure, the depth file 5 consecutive green runs, `flutter build apk --debug` both without and with the cpu define | reviewer (pending) |

| `8f2ab0a` + the commit carrying this row | L5 telemetry perf fields + schema 3 → 4 | pending review | Implementation only; no self-approval (rule above). **Scope:** each sample now carries `detectorPreMs/InferenceMs/PostMs/ObservedFps`, `depthPreMs/InferenceMs/PostMs/Accelerator/GridWidth/GridHeight`, `heatmapBuildMs` and the cumulative `depthDroppedTicks`; `depthQueueWaitMs` is exported as `null` because the depth tick, its cadence gate and the latest-frame-wins guard are native, so no Dart queue exists. Session wall-clock stays on the header (`session.durationMs`). **Null policy:** a measurement is written only when measured — an unknown is absent (or, for `depthQueueWaitMs`, explicitly `null`), never `0`; `depthAccelerator` (raw native value) and `depthStatus` (derived, includes `disabled`/`loading`/`degraded`) stay distinct. **Backward compatibility:** schema-3 sample rows are passed through untouched, so every new key reads as unknown and re-serialises unchanged. **Payload guard:** the worst case (500 samples with every field, 2000 detections, 500 alert records) measures **1 322 400 bytes** compact, below the 1 500 000 target; the upload envelope with the **pre-schema-4 sample shape** measures 1 910 180 bytes against the 2 000 000 cap. Writing `null` for every unmeasured key added 149 000 bytes and broke that cap, so unmeasured keys are now omitted instead. **Superseded in part by the L5 remediation** (row below): `depthQueueWaitMs` and `detectorObservedFps` are removed, the eleven tertiary perf keys are thinned to every fifth sample and the sample cap is 400. **Device info:** `deviceModel`/`androidVersion` remain `null` by decision — no device-info dependency is added, recorded as an owner gate in L10. Evidence: `dart format` clean, `flutter analyze` 4 pre-existing / 0 errors, `flutter test` per the run log, the three telemetry suites green, `flutter build apk --debug` |

| `8f2ab0a`, `3d4d516` | L5 round 1 review — telemetry perf fields + schema 4 | CHANGES_REQUIRED | 1 high + 2 medium + 2 low + 2 note. **HIGH:** the upload-envelope worst-case test used samples carrying none of the schema-4 fields, so it reported 1 910 180 bytes and hid the real case; with the new per-sample fields the body is ≈ 2.04 MB, above the ingest's 2 000 000-byte limit, so the whole session upload would 413 and be lost with no user-visible diagnosis. **MEDIUM:** `heatmapBuildMs` was only ever assigned, so hiding the overlay mid-session froze the last value and kept exporting it while depth stayed on, contradicting the data dictionary. **LOW/NOTE:** ledger export figure stated as 1 320 400 (actually 1 322 400), the 1 910 180 envelope figure was not labelled as the pre-schema-4 sample shape, and the `detectorObservedFps` / `heatmap_build_ms = 0` / re-exported v3 header semantics were undocumented. | reviewer |
| `3d4d516` (L5 remediation round 1) | The high/medium/doc findings above | pending review | **Honest measurement first:** the worst-case envelope test now populates every schema-4 sample key at its maximum and failed at **2 027 180 bytes** before the fix (≈ 2 040 680 including the removed `detectorObservedFps` duplicate). **Reclamation:** `depthQueueWaitMs` removed (≈ 12 KB), `detectorObservedFps` removed as a duplicate of `inferenceFps` (≈ 13 KB), the eleven tertiary perf keys thinned to every fifth sample (≈ 94 KB), and `_maxSamples` 500 → 400 (≈ 43 KB, so a longer session keeps a **rolling window** of its 400 most recent samples and drops the oldest — that cap is the one lossy boundary; no individual record is ever truncated). **Post-fix worst case at that point:** 1 878 480 bytes — **121 520 bytes under 2 000 000** and **21 520 bytes under the 1 900 000 target** (the two margins, quoted separately; the earlier row conflated them). **Superseded by round 2** (row below): that 1 878 480-byte fixture still used tidy 2-decimal literals. **Client guard:** `TelemetryUploadService` refuses a body above `maxUploadBodyBytes` (2 000 000) with an explicit failure telling the user to save a local export; the session is untouched, so JSON/CSV export still recovers it (tested). **Heatmap staleness:** `lastHeatmapBuildMs` is cleared by the disable branch, `_dropHeatmap`, `clearFrame` (hence `releaseModel`/`dispose`) and only written when the builder returned an image (tested — but see the round-2 HIGH: the two post-await discard branches of `_publish` did not clear it). Docs: data dictionary, benchmark procedure, MDE integration and the envelope ledger corrected. Evidence: `dart format`, `flutter analyze`, `flutter test` (three telemetry suites + the depth estimator), `flutter build apk --debug`. | reviewer |

| `1f3d279` | L5 round 2 review — telemetry schema v4 remediation | CHANGES_REQUIRED | 1 high (reopened) + 1 medium + 3 doc findings. **HIGH (reopened):** the envelope fixture still lied about number width. Detections were built with `Rect.fromLTWH(0.11, 0.22, 0.33, 0.44)` and `confidence: 0.87`, but on device a box is a Float32 plugin value divided in double arithmetic (`box.xywh.left / imageWidth`, then `right - left`), so each coordinate serialises as a 17–19-character decimal: ≈ +74 B on every detection-bearing record, ≈ +296 KB across 4 000 records, i.e. the honest envelope was above the 2 000 000-byte ingest bound that the test claimed to protect. **MEDIUM:** `_buildTimedHeatmap` wrote `_lastHeatmapBuildMs` before the two discard branches of `_publish` (`heatmapEnabled` false, release epoch changed) and neither cleared it, so a build completing after a disable or `releaseModel()` re-set a non-null cost on a discarded image and it kept being exported. **DOCS:** "none truncates a record" was false (`_maxSamples` is 400, so a longer session drops its oldest samples), the stale "500" survived in the dictionary and two source comments, the two margins were quoted as one, the precision contract was undocumented and the ledger had no round-2 rows | reviewer |
| L5-remediation-2 (the commit carrying this row) | The round-2 findings above | pending review | **Device-shaped fixtures:** every worst-case detection and correction now uses Float32-derived values (`0.11363636363636363`, `0.8700000047683716`, …). **Honest pre-fix measurement: 2 018 480 bytes** — the test failed, and with the default guard the upload was refused locally. **Precision contract (serialisation only):** box coordinates 4 dp, confidence/probability-like scores 3 dp, latency/Hz/percentiles 1 dp, sub-ms stage timings 2 dp (1 dp would turn a 4.75 ms stage into 4.8). Rounding lives in `TelemetryExportService`; the stored samples are never mutated, so banding, in-app comparisons and speech text keep full precision (tested). **Post-fix worst case: 1 850 400 bytes — 149 600 bytes under 2 000 000 and 49 600 bytes under 1 900 000.** Caps unchanged: rounding plus the existing N=5 thinning and the 400-sample cap were enough, so no further reduction of `_maxRecords`/the correction cap (2 000 each) was needed. **Heatmap race:** both discard branches of `_publish` now clear `_lastHeatmapBuildMs`, and the two in-flight tests that complete the builder after a disable / after `releaseModel()` assert it is `null` (both fail on the unfixed code). **Guard:** `maxBodyBytes` is `@visibleForTesting`, which documents that only tests should set it — it does **not** by itself stop application code from passing a wider value, because the named constructor parameter is the widening path and analyses with zero diagnostics (L5 review follow-up, corrected in the commit carrying this row); behaviour unchanged. **Docs:** the rolling sample window (400 samples ≈ 13 min at 0.5 Hz, slides, drops oldest, `sample 0` is the oldest *retained* sample, strided perf keys can differ between exports of the same growing session) is documented in the dictionary and in `supabase-research-telemetry.md`; stale "500" references fixed; the two margins quoted separately; the precision contract added to the dictionary. Evidence: `dart format --set-exit-if-changed` clean, `flutter analyze` 4 pre-existing / 0 errors, `flutter test` green, the four targeted suites green, `flutter build apk --debug` | reviewer (pending) |

| `f179e24` | L5 final verdict — telemetry perf fields + schema v4 (accepted) | PASS_WITH_NOTES | Accepted: the round-1/round-2 findings (`3d4d516`, `1f3d279`) are verified fixed at `f179e24`, and the rows above stay as history. Three notes, closed in `9868c48`: (1) the ledger and the commit message claimed `maxBodyBytes` being `@visibleForTesting` means application code "cannot widen the bound" — the named constructor parameter is the widening path and analyses with zero diagnostics, so the claim was reworded rather than enforced (an `assert` would be stripped in release builds); (2) the data dictionary's "no record is ever partially written, re-ordered, or shortened" omitted the one exception it always had, the numeric rounding; (3) the JSON/CSV exports share the upload's rounding, which L10 study materials depend on. No `lib/` behaviour change in the follow-up commit | reviewer |
| L6 ingestion hardening (the commit carrying this row) | Supabase idempotency, schema gating, client error mapping | pending review | Implementation only; no self-approval (rule above). **Migration** (introduced in `b0c09c4`, amended in `ff567d8`; `202610200001` untouched): plain `create unique index telemetry_sessions_participant_session_uidx on (participant_code, client_session_id)` — a duplicate that already existed would fail loudly instead of being deleted, documented in the header — plus `check (telemetry_schema_version in (3, 4))` and a table comment naming the Edge Function as the only writer; RLS policies and existing rows are untouched. The original unnamed `check (octet_length(payload::text) <= 2000000)` — PostgreSQL named it `telemetry_sessions_check` — is dropped in the new migration and re-added as `telemetry_sessions_payload_size` at 2 400 000 B, because `jsonb` re-spaces the JSON on text output so the stored form is larger than the compact body; the 2 000 000-byte wire cap in the function stays the authoritative limit and the wider table bound only prevents unbounded storage. **Idempotency:** a `.select('id')` probe decides `201 {accepted:true}` (first write) from `200 {accepted:true, duplicated:true}` (replay), then `upsert(..., {onConflict: 'participant_code,client_session_id', ignoreDuplicates: true})` writes with `on conflict do nothing`, so a replay can neither add a row nor overwrite the stored payload; the probe/write race window is documented. **Schema gating:** membership in `SUPPORTED_SCHEMA_VERSIONS = [3, 4]`, answering `400 {error:'unsupported_schema_version', supported:[3,4]}`; the row shape is never inferred from the header, so a v3 payload re-stamped 4 is accepted. **Validator:** the rules moved to `validate.js` (plain ESM + JSDoc) so `node --test` runs them with no Deno, Docker or database — 41 cases, all green (four added at L6: case-variant key spellings that pass by design, two coupling guards that read the migration SQL and `index.ts` from disk, and the storage bound against the wire cap; one added by the L6 review: the unguarded `drop constraint telemetry_sessions_check` guard, with the headroom guard tightened from `>` to `>= MAX_BODY_BYTES * 1.2`). Forbidden keys grew to 19 as an exact-match set with a one-name `frameNumber` allowlist. **Client:** `TelemetryUploadResponse` now carries the body, and 401/403, 400 schema, 400 validation, 413 and 5xx map to distinct actionable messages; the local 2 000 000-byte guard is the same bound as the wire cap in the function — not stricter — and a `200 {duplicated:true}` replay now returns `TelemetryUploadResult.alreadyUploaded()` with its own "already uploaded earlier" message instead of the success text, because `client_session_id` is minted once per app run, so upload → detect → upload again is discarded by the idempotency pair. **Not executed:** the SQL and the TypeScript — see the `BLOCKED-EXTERNAL` label and §7. Evidence: `node --test` 41/41, `dart format --set-exit-if-changed` clean, `flutter analyze` 4 pre-existing / 0 errors, `flutter test` 585 passing + the 1 known pre-existing `tts_service_test` failure, targeted upload + logs-screen suites 58/58, `flutter build apk --debug` (Gradle `assembleDebug` 29.8 s) | reviewer (pending) |
| `b0c09c4` | L6 round 1 review — Supabase idempotency, schema gating, client error mapping | CHANGES_REQUIRED | 2 high + 2 medium + 5 low. *Provenance: the round-1 findings were delivered in chat only, so this list was reconstructed from what `ff567d8` then fixed; the severity split is the round-1 review's own (2 H / 2 M / 5 L).* **HIGH-1** a `200 {"accepted":true,"duplicated":true}` replay was answered with the plain success text. `client_session_id` is minted once per app run and the upload button re-arms after every attempt, so "upload, keep detecting, upload again" claimed success for a snapshot the idempotency pair had just discarded. **HIGH-2** the table bound stayed at `octet_length(payload::text) <= 2000000` while the function's authoritative limit is 2 000 000 B on the *compact* body it receives. `jsonb` re-spaces the JSON on text output, so a body the function accepted could still be refused at insert as a `500 database_write_failed`, with nothing the app could act on. **MEDIUM-1** the response body was buffered whole just to read a machine-readable error code, so a hostile or accidentally huge answer was read into memory without a cap. **MEDIUM-2** `_requestUploadMetadata` created the two `TextEditingController`s and disposed them after `showDialog` returned, so the closing route rebuilt disposed controllers for the length of its exit animation (`A TextEditingController was used after being disposed`); it surfaced while the new screen tests were being added. **LOW-1** the docs called the client guard "stricter" than the wire cap; it is *identical*, and ordering is its only advantage. **LOW-2** forbidden-key matching is exact on case and whitespace, but nothing said so, so it read as an unconditional boundary. **LOW-3** a syntactically valid non-object body (`[]`, `"text"`, `42`) answers `invalid_telemetry_payload`; the status table implied only shape/consent failures did. **LOW-4** nothing tied the migration SQL to the code that depends on it, so a renamed constraint, column or `onConflict` target could drift silently, and the blocked reproduction had no maxed-payload / stored-size proof. **LOW-5** the `400` validation message told the user to "try again later", advice that cannot succeed for a rejected shape, and the branches that lose data did not all say "save a local export" | reviewer |
| `ff567d8` (L6 remediation round 1) | The nine findings above | pending review | **HIGH-1** `TelemetryUploadResult.alreadyUploaded()` carries a distinct, non-error message for a replay and the screen renders it through the existing SnackBar/Semantics pattern (tests: `a duplicate upload says so instead of reporting success`, `a stored upload keeps the plain success text`). **HIGH-2** the original unnamed check is dropped and re-added as `telemetry_sessions_payload_size` at 2 400 000 B, with the 2 000 000-byte wire cap left authoritative in the function and the gap documented. **MEDIUM-1** response reads stop at 4 KiB (`_maxResponseBytes`). **MEDIUM-2** `_UploadMetadataDialog` owns its controllers and disposes them in `dispose()`. **LOW-1** docs corrected: identical, not stricter. **LOW-2** documented as a deliberate exact-match tripwire, plus a test that case-variant and padded spellings pass by design. **LOW-3** the status table lists the valid-non-object case. **LOW-4** two coupling guards read the migration SQL and `index.ts` from disk (schema list, unique-index columns against the `onConflict` target) and the reproduction gained the maxed-payload / stored-size step. **LOW-5** every data-losing branch says "local export" and the validation message no longer suggests retrying. Evidence at the time: `node --test` 41/41, `dart format --set-exit-if-changed` clean, `flutter analyze` 4 pre-existing / 0 errors, `flutter test` 585 + the 1 known pre-existing `tts_service_test` failure, upload + logs-screen suites 58/58 | reviewer (pending) |
| `21a3263`, `ebfcc6e` | L7 round 1 review — dashboard contract compatibility (schema-4 perf rendering, contract evidence, response-clamp coverage) | CHANGES_REQUIRED | 4 medium + 1 low-medium + 5 low (the round-1 headline said "3 medium" because the two documentation findings were counted as one). *Provenance: the round-1 findings were delivered in chat only, so this list was reconstructed from the remediation diff; the severities are the round-1 review's own.* **MEDIUM-1** the dashboard computed `droppedTicks` as last − first whenever **any** carrier existed, so a session with exactly one carrier rendered "0 ticks" — a fabricated zero out of a cumulative counter sampled once, which the module's own invariant and the contract README forbid ("a missing field is never rendered as `0`"). **MEDIUM-2** `droppedTicksPoints` was computed and asserted but read by no label, so the disambiguator that makes the delta meaningful was invisible in the UI. **MEDIUM-3** the L6 evidence line said `node --test` 40/40 while the same row's body said 41 cases. **MEDIUM-4** the L7 ledger row was still `PENDING` with no implementation row, so the item's commits and evidence existed nowhere in this document. **LOW-MEDIUM-1** the 4 KiB response clamp had no test on the path that decides duplicate-versus-success — the one branch where a truncated body can misreport a replay as a write. **LOW-1** no guard for a non-monotonic counter: `depthDroppedTicks` resets in the native `stop()`, so a mid-session reset made last − first under-report or render "-3 ticks". **LOW-2** `PERF_PRECISION_NOTE` carried markdown backticks into `innerHTML`, so researchers read a literal `` `left`/`right` ``. **LOW-3** "1 points" / "1 samples" rendered verbatim. **LOW-4** `heatmapBuildMs` is a last value but sat in a block whose legend described medians. **LOW-5** the dialog pre-warning test used a screen-wide `find.textContaining`, so it never proved the sentence was inside the confirm dialog | reviewer |
| `1581498` (dashboard) + `efb3fb5` (Flutter) | L7 remediation of the eleven findings above | pending review | **MEDIUM-1** a delta now needs **two** carriers: `summarizePerf()` in the dashboard's `dist/cadence.js` leaves `droppedTicks` null on a single carrier and `droppedTicksLabel()` renders `unknown (single sample — no delta)` — never "0 ticks" (test: *a single carrier of the counter renders no delta at all*). **MEDIUM-2** the label states the delta and its span together ("4 ticks over 2 points"), so `droppedTicksPoints` is surfaced instead of dangling. **MEDIUM-3** both L6 evidence lines now say `node --test` 41/41, which is what the validator actually reports. **MEDIUM-4** the L7 ledger row above now carries `ebfcc6e`, `21a3263`, `1581498`, the evidence labels, the separate-repository and no-deployment facts, and a §7 row making publication an owner-gated action. **LOW-MEDIUM-1** the clamp moved into `TelemetryUploadService.readClampedBody()` so it is exercised directly, and `_reportsDuplicate()` reads the flag out of the prefix when the 4 KiB cap cuts the body mid-JSON, so a replay is no longer reported as a write; three tests cover a single 10 KB chunk truncated at 4096 B, a codepoint split by the cut that decodes without throwing, and a `duplicated` prefix that still answers *already uploaded earlier*. **LOW-1** any decreasing consecutive carrier sets `droppedTicksState = 'counter-reset'` and renders `unknown (counter reset)`, asserted next to the monotonic case. **LOW-2** the backticks are gone from `PERF_PRECISION_NOTE`, with a test asserting the string contains none. **LOW-3** a `plural()` helper singularises "1 point" / "1 sample" in the stage rows and the striding note, asserted for 1 and 6. **LOW-4** the detail stat reads "Heatmap build (last sampled)", so a last value no longer sits under a median legend. **LOW-5** the pre-warning assertion is scoped with `find.descendant(of: find.byType(AlertDialog), …)`. Evidence: dashboard `node --test test/cadence.test.mjs test/perf-fields.test.mjs` 21/21 (the 7 cadence cases byte-identical), `node --test supabase/functions/ingest-telemetry/validate.test.mjs` 41/41, `flutter test` 589 passing + the 1 known pre-existing `tts_service_test` failure, targeted upload + logs-screen suites 62/62, `dart format --set-exit-if-changed` clean, `flutter analyze` 4 pre-existing / 0 errors. No deployment performed | reviewer (pending) |
| `efb3fb5`, `1581498` | L7 final verdict — dashboard contract compatibility (accepted) | PASS_WITH_NOTES | The eleven round-1 findings are verified fixed (see the remediation row directly above; the severity split in the round-1 row is that review's own, reconstructed from the remediation diff because those findings were delivered in chat only). Re-measured on the Flutter side at this commit: `flutter analyze` 4 issues / 0 errors, `flutter test` 589 passing + the 1 known pre-existing `tts_service_test` failure — the same counts L7 recorded, so the clamp/contract work did not move the suite. Three notes, none blocking: (1) the dashboard's 21/21 is a **separate repository's** suite, reproducible only by running it there, and nothing in this repository can deploy that bundle (§7 gate); (2) the L7 row and this log still describe the dashboard contract from the Flutter side, so a future payload change must update both repositories in the same step; (3) `droppedTicks` remains a cumulative counter whose single-carrier case renders `unknown (single sample — no delta)`, which is correct but means a one-heartbeat session reports no tick figure at all | reviewer |
| `2d0d0cd` + the commit carrying this row | L8 R8/WorkManager/Room release verification + L9 Play Store configuration — release bundle build and bundle/APK inspection | pending review | Implementation only; no self-approval (rule above). **Build (`CONFIRMED-BY-BUILD`):** `flutter build appbundle --release` (Gradle `bundleRelease` 242.0 s, 4:05 wall) → `build/app/outputs/bundle/release/app-release.aab` 78 607 421 B, sha256 `feaab199c74dda67985cd596e1e873313159a49c12d916c9b33219ea43cb821b`, and `flutter build apk --release` (33.3 s, 0:37 wall) → `build/app/outputs/flutter-apk/app-release.apk` 91 191 297 B, sha256 `99ac0da9a49697d3e027a4b8920d1ae3e9fd220061ea7db47056295351439a83`. **Honest artefact status:** no `android/key.properties` and no `EYECUE_*` variable existed on the host, so the L9 fallback applied — `versionName='1.0.0-testsigned'`, `apksigner` reports `CN=Android Debug`, and both files are test artefacts that Play would refuse. The fallback is exactly what `2d0d0cd` claims it does, which is itself the evidence that the guard works. **Bundle inspection (`CONFIRMED-BY-INSPECTION`):** `base` module + 23 `BUNDLE-METADATA` debug-symbol entries; model assets are exactly `yolo26n-depth_w8a32.tflite` (5 474 749 B) and `yolov8n_int8_new_metadata.tflite` (3 483 114 B) with `yolov8n.tflite`, `yolov8n_int8.tflite` and `yolov8n_int8_new.tflite` **absent**; three ABIs (`arm64-v8a`, `armeabi-v7a`, `x86_64`, no `x86`) and `libLiteRtClGlAccelerator.so` only on the 64-bit ABIs; permissions `CAMERA`, `INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED`, `RECORD_AUDIO`, `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion='28'`), `READ_EXTERNAL_STORAGE`, `app.eyecue.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`; no `android:debuggable`; secret scan over the **decompressed** AAB and APK 0 hits for `service_role`, `SUPABASE_SECRET`, `BEGIN PRIVATE KEY`, `eyJhbGciOi`; no `design-reference`/`docs`/`tool`/`test` entries. **R8 (the release-blocking question):** the single `classes.dex` defines `androidx.work.impl.WorkDatabase_Impl` with a public no-arg `<init>()` and 33 methods, 727 `androidx.room.*` rows survive, and the `WorkDatabase`/`WorkDatabase_Impl`/`RoomDatabase` string counts are 2 / 1 / 1 — so **not a blocker**, the reflective lookup the historical crash failed on now has its target. **Device gate:** installed startup is `NOT VERIFIED` — no device, no AVD, and creating one is not permitted (5.0 GB free). The DEX-presence result is a proxy, not proof; the exact `adb install`/`am start`/logcat commands are recorded in [`benchmark-procedure.md`](benchmark-procedure.md) §5.1. **Residual doc drift owned by nobody yet:** `auditor.md`, `chat_spec.md` and four dated audit documents still quote `com.example.eyecue_flutter`; they are historical snapshots and were deliberately not rewritten | reviewer (pending) |

| `2d0d0cd`, `870c24e` | L8/L9 round 1 review — release verification + Play Store configuration | CHANGES_REQUIRED | 2 medium + 5 low. **MEDIUM-1** the permission attribution table was wrong, and it is the input the Data Safety answer depends on: `RECORD_AUDIO`/`WRITE_EXTERNAL_STORAGE` were credited to `flutter_tts` (whose manifest declares zero permissions) instead of `camera_android_camerax`, and `READ_EXTERNAL_STORAGE` was listed as a plugin declaration when the merger *implies* it from `WRITE_EXTERNAL_STORAGE`. **MEDIUM-2** a debug-signed artefact was indistinguishable from a production one by filename. **LOW-1** the `<queries>` `IMAGE_CAPTURE` removal in `2d0d0cd` was undisclosed. **LOW-2** `2d0d0cd` also touched `lib/` (four comment lines) although `lib/` was out of that commit's scope. **LOW-3** the device-gate wording implied microphone/storage prompts. **LOW-4** the ledger recorded truncated digests (`feaab199c7…`). **LOW-5** the `870c24e` message was reported to say "33 members" where the figure is 33 methods + 8 fields. All fixed or disclosed in the L10 commits below | reviewer |
| L10 attribution + naming commit | Rebuild of the permission table from the merger blame/report, per-permission recommendation table, `-testsigned` artefact naming, `<queries>` disclosure, device-gate wording, full digests | pending review | Implementation only; no self-approval. Table rebuilt from `manifest-merger-blame-release-report.txt` (element line + `-->[<dependency>]` line) and `manifest-merger-release-report.txt`; the `READ_EXTERNAL_STORAGE` row quotes the merger's own `IMPLIED from … reason: io.flutter.plugins.camerax requested WRITE_EXTERNAL_STORAGE` line. Naming: `bundleRelease`/`assembleRelease` `doLast` rename, active only when `hasUploadSigning` is false (AGP 9 removed the variant output-file-name property, so the rename cannot be expressed through the variant API); both fallback artefacts are now `app-release-testsigned.{aab,apk}` and no plain-named artefact remains, while a keystore keeps the normal names | implementer |
| `2d0d0cd` (disclosure) | Out-of-scope `lib/` change | disclosed, not reverted | `2d0d0cd` added four comment lines to [`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart:250) — a `shortcut:` note on the truncated-body duplicate heuristic. It is a comment-only change with no behaviour, it is correct, and history is not rewritten; it is disclosed here because `lib/` was outside that commit's scope | implementer |
| `870c24e` (disclosure) | "33 members" vs 33 methods + 8 fields | verified — premise not reproducible | The review reported the message saying "33 members". `git log -1 --format=%B 870c24e | grep -n "33"` matches **nothing**: the message states no member count at all. The figure lives only in §6.3 and this ledger ("33 methods"), which matches the method column of `apkanalyzer dex packages --defined-only` for this APK (`C d 33 33 2268 androidx.work.impl.WorkDatabase_Impl`). The review's "8 fields" is not reproducible from that row (its field column also reads 33), so neither number is restated as reviewed; the doc keeps "33 methods" because that column is unambiguous. No message rewrite | implementer |

| `8766586` | L10 permission removal + artefact rebuild | pending review | Implementation only; no self-approval. Three `tools:node="remove"` rules: `RECORD_AUDIO` and `WRITE_EXTERNAL_STORAGE` (both injected by `camera_android_camerax`) plus the merger-implied `READ_EXTERNAL_STORAGE`, which needs its own rule — measured by re-running `:app:processReleaseMainManifest` with only the first two rules, which still declared it. `aapt2` on the rebuilt APK lists 8 permissions (was 11). The test-signed APK is now marked by the `markTestSignedApk` task because renaming inside `assembleRelease` is a no-op (Flutter copies the APK after that task). Residual risk: camerax video-with-audio and shared-storage capture would fail; neither path is used, and the removal is unverified without a device | implementer |
| `842d38b` | L10 licence, notices, privacy, Play checklist | pending review | `LICENSE` grants nothing (D2 still open); `THIRD_PARTY_NOTICES.md` enumerates the vendored plugin (AGPL-3.0, upstream `LICENSE` verbatim, eight numbered deviations), both bundled models with provenance and digests, the 99 pinned pub packages and the native/AAR inventory, lists R1–R7 for qualified legal review and defines the AGPL source-distribution procedure; `docs/privacy-and-data-safety.md` answers from code with citations or marks OWNER DECISION and carries the Data Safety answer sheet; `docs/play-store-checklist.md` answers no owner-facing field and flags every policy value with "verify current Google Play policy at submission time". **No legal opinion given** | implementer |
| the commit carrying the L11 row | L11 final readiness report | pending review | Verification recorded per command (`dart format` 104/0, `flutter analyze` 4 issues/0 errors, `flutter test` 589 passed + 1 known pre-existing TTS failure, validator 41/41, `git diff --check` clean, conflict-marker scan 0 hits, secret scan 0 hits); artefacts re-hashed and re-inspected; classification `CODE_READY_WITH_EXTERNAL_GATES`, with `READY_FOR_PLAY_STORE_SUBMISSION` stated as unavailable | implementer |

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
