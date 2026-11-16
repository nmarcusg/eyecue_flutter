# EyeCue — Device Benchmark Procedure (MDE and detection)

> **Status at local `main` (`aadf9e0`, 2026-11-16):** this is a procedure, not a
> measurement report. The table below records no measurements for the current
> source baseline. Earlier device observations are retained in
> [`benchmark-results.md`](benchmark-results.md) with their historical model and
> device context; they do not validate the current campus detector.
>
> Two consequences worth stating plainly:
>
> - **No performance result for the current campus detector is recorded here.**
>   Older device figures refer to different YOLOv8 models and are not evidence for
>   this baseline.
> - The **1.5 FPS Redmi regression** refers to an earlier detector/run. This
>   matrix remains the way to measure the current model on that hardware; the
>   historical issue is not evidence of current performance.

Related: [`mde-integration.md`](mde-integration.md) (accelerator policy, stage
timings surface), [`known-issues.md`](known-issues.md) (unmeasured performance),
[`play-store-readiness.md`](play-store-readiness.md) (L4 gate).

## 1. What each run must be able to answer

1. Does detection hold its requested cadence (and what is it actually)?
2. Does depth run at its requested cadence, and what does each stage cost?
3. Which accelerator did native *actually* run — not which one was requested?
4. What does the heatmap cost when it is on?
5. Does the bbox fallback path cost less than MDE on?
6. What does low power mode do to both cadences?
7. Does the run drop frames, leak memory, throttle, crash or ANR?

## 2. Builds

Four builds cover the accelerator combinations. Build them **once** and keep the
APKs; do not rebuild between runs of the same configuration.

```sh
# Study debug entrypoint is needed for the Logs & Reports export steps below.
# Debug signing is sufficient for local installation; no upload token is needed
# for local JSON/CSV export.
flutter build apk --debug --flavor study -t lib/main_study.dart
cp build/app/outputs/flutter-apk/app-study-debug.apk ../apk-A-auto.apk

# B — depth pinned to CPU (no GPU context is created for the depth instance)
flutter build apk --debug --flavor study -t lib/main_study.dart \
  --dart-define=EYECUE_DEPTH_ACCELERATOR=cpu
cp build/app/outputs/flutter-apk/app-study-debug.apk ../apk-B-depthcpu.apk

# C — depth explicitly requests GPU
flutter build apk --debug --flavor study -t lib/main_study.dart \
  --dart-define=EYECUE_DEPTH_ACCELERATOR=gpu
cp build/app/outputs/flutter-apk/app-study-debug.apk ../apk-C-depthgpu.apk
```

The defines are **build-time only** (no settings, no persistence, no UI). The
public flavor uses `app.eyecue.mobile`; this Study debug build uses
`app.eyecue.mobile.study`, and Logs & Reports is provided by the Study entrypoint.
Verify each build carries what you think it does before measuring:

```sh
# The reported accelerator comes from native, never from the build define:
# logcat prints it once, on the first depth event that carries a value.
adb logcat -s flutter:V | grep '\[Depth\]'
```

A `--release` build is not part of this matrix: the matrix measures cadence and
per-stage cost, which the release build type does not change. Earlier release artifacts were inspected as recorded in
[`release-procedure.md`](release-procedure.md) §6. That historical bundle/DEX
evidence does not establish startup for an artifact built from current `main`;
§5.1 describes the device check.

## 3. Matrix

Run **every row** on the same device, same orientation (portrait), same scene
(a static room with one object ~1 m, one ~3 m and one ~6 m away), screen on,
airplane mode **off** (telemetry upload is manual and not triggered here).

| # | MDE | Heatmap | Low power | Detector target | Depth target | Depth accelerator | Build |
|---|---|---|---|---|---|---|---|
| 1 | off (bbox) | — | off | Automatic | — | — | A |
| 2 | off (bbox) | — | off | 10 Hz | — | — | A |
| 3 | on | off | off | Automatic | 2 Hz | auto | A |
| 4 | on | off | off | 10 Hz | 2 Hz | auto | A |
| 5 | on | on | off | Automatic | 2 Hz | auto | A |
| 6 | on | on | off | 10 Hz | 2 Hz | auto | A |
| 7 | on | on | off | 10 Hz | 5 Hz | auto | A |
| 8 | on | on | off | 10 Hz | 2 Hz | GPU requested (detector default / depth GPU request) | C |
| 9 | on | on | off | 10 Hz | 2 Hz | CPU requested (detector default / depth CPU request) | B |
| 10 | on | on | off | 10 Hz | 5 Hz | CPU requested (detector default / depth CPU request) | B |
| 11 | on | on | **on** | Automatic | 2 Hz | auto | A |
| 12 | on | on | **on** | 10 Hz | 2 Hz | auto | A |

Notes:

- The detector's accelerator is not independently pinned by this matrix. The
  build-time define controls only depth; report the detector's native backend
  from its log rather than inferring it from the request.
- The detector default requests GPU with plugin fallback behavior. The actual
  backend must be read from the native `LiteRtModel` log line, not inferred from
  the depth define.
- At least two detector cadences (Automatic and 10 Hz) and two depth cadences
  (2 Hz and 5 Hz) appear in the matrix, per the L4 requirement.

## 4. Per-run protocol

For each row, in order:

1. `adb install -r ../apk-X.apk` (add `-t` only if the install rejects a debug APK).
2. `adb shell pm clear app.eyecue.mobile.study` — every run starts clean.
3. `adb logcat -c` — drop the old buffer.
4. Start the log filter (section 5) in one terminal.
5. Launch the app (section 5), start detection, set the settings for the row,
   hold the scene **still** for 120 s.
6. Stop detection, open **Logs & Reports**, export JSON (and CSV) for the run.
7. Pull the export (section 5) and name it `run-<row>-<date>.json`.
8. Record the run in a copy of the table in section 8, including the raw values
   below. Do **not** summarise "feels faster" anywhere.

Per-run record (all mandatory; write `NOT MEASURED` rather than leaving a blank):

| Field | Source |
|---|---|
| Build commit | `git rev-parse HEAD` at build time |
| Device + Android version | `adb shell getprop ro.product.model`, `ro.build.version.release`, `ro.product.cpu.abi` |
| Duration | wall clock of step 5 |
| Requested detector Hz | the settings value (Automatic or the number) |
| Effective detector Hz | resolved cadence (`effectiveDetectionHz` in the export) |
| Observed detector FPS | `inferenceFps` in the export |
| Detector stage timings | `detectorPreMs` / `detectorInferenceMs` / `detectorPostMs` (median of the run) |
| Depth requested Hz | the settings value |
| Depth effective Hz | resolved cadence (`effectiveDepthHz` in the export) |
| Depth observed Hz | `depthObservedHz` (EMA — not a steady-state throughput claim) |
| Depth latency | `depthLatencyMs` |
| Depth stage timings | `depthPreMs` / `depthInferenceMs` / `depthPostMs` in the export (median of the run; `heatmapBuildMs` is Dart-side presentation cost) |
| Accelerator actually reported | `depthAccelerator` in the export (`gpu`/`cpu`); `depthStatus` carries the same value plus `disabled`/`loading`/`degraded`. Both are the native value, never the requested policy |
| Heatmap state | on/off as set in the row |
| Thermals | `adb shell dumpsys thermalservice` before and after; treat as advisory |
| Memory | `adb shell dumpsys meminfo app.eyecue.mobile.study` before and after (`TOTAL PSS`) for the Study benchmark build |
| Dropped depth ticks | `depthDroppedTicks` — a **cumulative native counter**, not a per-sample drop count. Report the last sample minus the first sample of the run (see `mde-integration.md`) |
| Crashes / ANRs | `adb logcat -b crash -d` plus the run's own log |

## 5. Copy-pasteable commands

```sh
# --- logcat: the lines that carry the numbers -------------------------------
adb logcat -c
adb logcat -v time \
  flutter:V YOLOView:V DepthEstimator:V LiteRtModel:V ObjectDetector:V \
  AndroidRuntime:E ActivityManager:W \
  | grep -E '\[Depth\]|LiteRT compiled on|GPU accelerator could not run|FATAL|ANR'

# In a second terminal, if you want the buffer kept for the record:
adb logcat -d -v time > run-<row>-logcat.txt

# --- launch -----------------------------------------------------------------
adb shell am start -n app.eyecue.mobile.study/.MainActivity
# (first start only) the app needs camera permission:
adb shell pm grant app.eyecue.mobile.study android.permission.CAMERA

# --- memory / thermals ------------------------------------------------------
adb shell dumpsys meminfo app.eyecue.mobile.study | grep -E 'TOTAL PSS|TOTAL RSS'
adb shell dumpsys thermalservice | grep -iE 'Thermal Status|temperature'

# --- export the telemetry session ------------------------------------------
# In the app: Logs & Reports -> Save JSON export (and Save CSV export).
# Choose Downloads in Android's document picker, then pull the chosen file.
adb pull /sdcard/Download/eyecue-export.json run-1.json

# --- crashes ----------------------------------------------------------------
adb logcat -b crash -d > run-<row>-crash.txt
```

Log lines that pin the accelerator claim (`CONFIRMED-BY-INSPECTION` until a
device run says otherwise):

- `LiteRT compiled on GPU` / `LiteRT compiled on CPU` — `LiteRtModel` init, per
  instance, including the detection instance.
- `GPU accelerator could not run model, falling back to CPU: …` — the fallback
  that must make `depthStatus == 'cpu'` while the build request was `gpu`.
- `[Depth] accelerator reported by native: <gpu|cpu> (requested useGpu=…)` —
  printed once per loaded instance, on the first depth event that carries an
  accelerator. This is the only log line that states what actually ran.
- `[Depth] first frame … in <latency> ms (useGpu=…)` — the *requested* value,
  useful only to prove the knob reached the factory. It is **not** an
  accelerator claim: a `useGpu=true` line can still be a CPU run.

### 5.1 Release-startup device gate (WorkManager / Room)

**Recorded evidence boundary:** the release-startup gate was documented as
unverified for the build host used during the prior review. Recheck the current
release artifact and device evidence before changing that status. DEX-presence
evidence in [`release-procedure.md`](release-procedure.md) §6.3 (the class
`androidx.work.impl.WorkDatabase_Impl` and its no-arg constructor survive R8) is
not proof that the app starts.

An AAB cannot be installed directly — use the release APK built for inspection:

```sh
cd /home/nico/repos/eyecue_flutter
adb devices
adb install -r build/app/outputs/flutter-apk/app-release.apk

# first run only: grant camera before launch, or answer the prompt
adb shell pm grant app.eyecue.mobile android.permission.CAMERA

adb logcat -c
adb logcat -v time | grep -E 'WorkDatabase|RoomDatabase|Failed to create an instance|FATAL|AndroidRuntime|ANR'

adb shell am start -n app.eyecue.mobile/.MainActivity
adb shell dumpsys activity activities | grep -i 'mResumedActivity'
adb logcat -b crash -d
```

The failure this gate exists to catch reads:

```
java.lang.RuntimeException: Cannot find implementation for androidx.work.impl.WorkDatabase.
  WorkDatabase_Impl does not exist
```

or `Failed to create an instance of class androidx.work.impl.WorkDatabase`. If the
app reaches the home screen with no such line and no crash dump, the row can be
recorded `CONFIRMED-ON-DEVICE` for startup only — still not for any performance
figure in §3.

`adb install` accepts a debug-signed APK — it is Play that refuses a debug-signed
upload, not the device. Inspect the artifact's actual package, version, signing
certificate, and build type before recording results; a test-signed artifact is
only a startup check, never a release-candidate check.

## 6. Reporting rules

- A value that was not read from an export, logcat or `dumpsys` is
  `NOT MEASURED`. Never infer a number from another run.
- Requested, effective and observed cadence are three different columns; do not
  collapse them.
- Report the accelerator native reported. A run built with
  `EYECUE_DEPTH_ACCELERATOR=gpu` that reports `cpu` is a **successful CPU run**,
  not a GPU one.
- Stage timings are nullable: `null` means "not reported", never `0 ms`.

## 7. Where the data comes from

Every per-run cell above is read from the export (schema 4); no `debugPrint` and
no debugger session is needed.

| Value | Produced by | Recorded in telemetry? |
|---|---|---|
| Detector `preMs`/`inferenceMs`/`postMs`/`fps` | `DetectorStageTimings.fromMetrics` in the screen's metrics handler | Yes — `detectorPreMs`, `detectorInferenceMs`, `detectorPostMs`; the native rate is `inferenceFps` (the detector observed FPS, `0` = not reported) |
| Depth `preMs`/`inferenceMs`/`postMs` | `YOLODepthEvent` → `MonocularDepthEstimator.stageTimings` | Yes — `depthPreMs`, `depthInferenceMs`, `depthPostMs` |
| Depth `accelerator` | native `YOLOView.emitDepthEvent` → `DepthStageTimings.accelerator` | Yes — `depthAccelerator` (and `depthStatus`) |
| Depth grid size | `DepthFrame.grid` | Yes — `depthGridWidth`, `depthGridHeight` |
| Heatmap build cost | `MonocularDepthEstimator` around its heatmap builder | Yes — `heatmapBuildMs` |
| Depth `droppedTicks` (cumulative) | native `YOLOView` counter → `DepthStageTimings.droppedTicks` | Yes — `depthDroppedTicks` |
| Cadence + `depthLatencyMs` + `depthObservedHz` + `depthStatus` | existing telemetry cadence sample | Yes |

There is no `depthQueueWaitMs` column: the depth tick is native and
latest-frame-wins, so there is no Dart-side queue to wait in and nothing honest to
report. Session wall-clock is `session.durationMs` on the export header, not per
sample.

The detector/depth stage timings, `depthAccelerator`, the grid size,
`heatmapBuildMs` and `depthDroppedTicks` are **thinned to every fifth sample**
(sample 0, 5, 10, …) to keep the upload under the ingest bound; the cadence,
`inferenceFps` and `latencyMs` fields stay on every sample. Take each run's
median from the samples that carry the keys, and read `depthDroppedTicks` as a
cumulative counter over those same samples.

## 8. Results table

Cells marked `NOT MEASURED — device gate` mean this procedure contains no
recorded run for that configuration. Do not replace a cell with a number unless
the run was performed and its record filled.

| # | Device / Android | Detector req / eff / obs Hz | Detector stages (pre / inf / post) | Depth req / eff / obs Hz | Depth latency | Depth stages (pre / inf / post) | Accelerator reported | Heatmap | Dropped depth ticks (cumulative → run delta) | Memory (PSS) | Thermals | Crashes / ANRs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | n/a | n/a | n/a | n/a | n/a | n/a | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 2 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | n/a | n/a | n/a | n/a | n/a | n/a | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 3 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | off | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 4 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | off | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 5 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | on | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 6 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | on | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 7 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | on | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 8 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | on | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 9 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | on | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 10 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | on | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 11 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | on | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 12 | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | on | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate | NOT MEASURED — device gate |
| 13 (independent detector/depth pinning) | NOT MEASURABLE — detector accelerator has no independent build define | NOT MEASURABLE — detector accelerator has no independent build define | NOT MEASURABLE — detector accelerator has no independent build define | NOT MEASURABLE — detector accelerator has no independent build define | NOT MEASURABLE — detector accelerator has no independent build define | NOT MEASURABLE — detector accelerator has no independent build define | NOT MEASURABLE — detector accelerator has no independent build define | — | NOT MEASURABLE — detector accelerator has no independent build define | NOT MEASURABLE — detector accelerator has no independent build define | NOT MEASURABLE — detector accelerator has no independent build define | NOT MEASURABLE — detector accelerator has no independent build define |

## 9. Exit criteria

The performance question closes only when:

1. Rows 1–12 are filled from real runs on the Redmi device (and, if available, a
   second device with a different GPU), each with its export and logcat retained.
2. The 1.5 FPS regression is either reproduced (and fixed) or shown not to
   recur, with the numbers in row 1 vs row 3/5.
3. Row 8 vs row 9 states which accelerator native reported for each, proving the
   fallback path is reported truthfully.
4. Until then, this document is the deliverable, and no on-device claim is made.
