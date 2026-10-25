# EyeCue — Device Benchmark Procedure (MDE and detection)

> **Status:** procedure only. **Nothing in this file has been measured.** No
> Android device is attached to the workspace that produced it, so every cell in
> [the results table](#8-results-table) reads `NOT MEASURED — device gate`.
>
> Two consequences worth stating plainly:
>
> - **No `CONFIRMED-ON-DEVICE` claim exists for any performance figure** on this
>   branch — not for detection FPS, not for depth latency or cadence, not for the
>   stage timings, not for memory or thermals.
> - **The 1.5 FPS Redmi regression is not considered resolved.** It is closed
>   only by running the matrix below on that hardware and recording the numbers.

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
cd /home/nico/repos/eyecue_flutter-playstore

# A — auto (this is what ships): asks for GPU, native falls back to CPU if it cannot run it
flutter build apk --debug
cp build/app/outputs/flutter-apk/app-debug.apk ../apk-A-auto.apk

# B — depth pinned to CPU (no GPU context is created for the depth instance)
flutter build apk --debug --dart-define=EYECUE_DEPTH_ACCELERATOR=cpu
cp build/app/outputs/flutter-apk/app-debug.apk ../apk-B-depthcpu.apk

# C — depth explicitly GPU
flutter build apk --debug --dart-define=EYECUE_DEPTH_ACCELERATOR=gpu
cp build/app/outputs/flutter-apk/app-debug.apk ../apk-C-depthgpu.apk
```

The defines are **build-time only** (no settings, no persistence, no UI). Verify
each build carries what you think it does before measuring:

```sh
# The reported accelerator comes from native, never from the build define:
# logcat prints it once, on the first depth event that carries a value.
adb logcat -s flutter:V | grep '\[Depth\]'
```

A `--release` build is a separate, later gate (L8/L11) and is not part of this
matrix; the workspace has no disk budget for a release AAB.

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
| 8 | on | on | off | 10 Hz | 2 Hz | GPU (detect GPU / depth GPU) | C |
| 9 | on | on | off | 10 Hz | 2 Hz | CPU (detect GPU / depth CPU) | B |
| 10 | on | on | off | 10 Hz | 5 Hz | CPU (detect GPU / depth CPU) | B |
| 11 | on | on | **on** | Automatic | 2 Hz | auto | A |
| 12 | on | on | **on** | 10 Hz | 2 Hz | auto | A |

Notes:

- **Detect CPU / depth GPU** (the third accelerator combination) cannot be
  expressed: the knob only covers the depth instance, and detection has no
  equivalent define. Record the row as `NOT MEASURABLE — no detection knob`
  rather than guessing.
- Detector CPU-only is likewise not selectable; a GPU→CPU fallback on detection
  is only observable through the native `LiteRtModel` log line (below), not
  forced by this build.
- At least two detector cadences (Automatic and 10 Hz) and two depth cadences
  (2 Hz and 5 Hz) appear in the matrix, per the L4 requirement.

## 4. Per-run protocol

For each row, in order:

1. `adb install -r ../apk-X.apk` (add `-t` only if the install rejects a debug APK).
2. `adb shell pm clear com.example.eyecue_flutter` — every run starts clean.
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
| Detector stage timings | `detectorPreMs` / `detectorInferenceMs` / `detectorPostMs` (median of the run; `detectorObservedFps` is the native rate) |
| Depth requested Hz | the settings value |
| Depth effective Hz | resolved cadence (`effectiveDepthHz` in the export) |
| Depth observed Hz | `depthObservedHz` (EMA — not a steady-state throughput claim) |
| Depth latency | `depthLatencyMs` |
| Depth stage timings | `depthPreMs` / `depthInferenceMs` / `depthPostMs` in the export (median of the run; `heatmapBuildMs` is Dart-side presentation cost) |
| Accelerator actually reported | `depthAccelerator` in the export (`gpu`/`cpu`); `depthStatus` carries the same value plus `disabled`/`loading`/`degraded`. Both are the native value, never the requested policy |
| Heatmap state | on/off as set in the row |
| Thermals | `adb shell dumpsys thermalservice` before and after; treat as advisory |
| Memory | `adb shell dumpsys meminfo com.example.eyecue_flutter` before and after (`TOTAL PSS`) |
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
adb shell am start -n com.example.eyecue_flutter/.MainActivity
# (first start only) the app needs camera permission:
adb shell pm grant com.example.eyecue_flutter android.permission.CAMERA

# --- memory / thermals ------------------------------------------------------
adb shell dumpsys meminfo com.example.eyecue_flutter | grep -E 'TOTAL PSS|TOTAL RSS'
adb shell dumpsys thermalservice | grep -iE 'Thermal Status|temperature'

# --- export the telemetry session ------------------------------------------
# In the app: Logs & Reports -> Export JSON (and Export CSV). The files land in
# the app's documents dir, readable from a debug build with run-as.
adb shell run-as com.example.eyecue_flutter ls -l app_flutter
adb exec-out run-as com.example.eyecue_flutter cat app_flutter/<export-name>.json > run-<row>.json

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
| Detector `preMs`/`inferenceMs`/`postMs`/`fps` | `DetectorStageTimings.fromMetrics` in the screen's metrics handler | Yes — `detectorPreMs`, `detectorInferenceMs`, `detectorPostMs`, `detectorObservedFps` |
| Depth `preMs`/`inferenceMs`/`postMs` | `YOLODepthEvent` → `MonocularDepthEstimator.stageTimings` | Yes — `depthPreMs`, `depthInferenceMs`, `depthPostMs` |
| Depth `accelerator` | native `YOLOView.emitDepthEvent` → `DepthStageTimings.accelerator` | Yes — `depthAccelerator` (and `depthStatus`) |
| Depth grid size | `DepthFrame.grid` | Yes — `depthGridWidth`, `depthGridHeight` |
| Heatmap build cost | `MonocularDepthEstimator` around its heatmap builder | Yes — `heatmapBuildMs` |
| Depth `droppedTicks` (cumulative) | native `YOLOView` counter → `DepthStageTimings.droppedTicks` | Yes — `depthDroppedTicks` |
| Cadence + `depthLatencyMs` + `depthObservedHz` + `depthStatus` | existing telemetry cadence sample | Yes |

`depthQueueWaitMs` is exported as `null` on every sample: the depth tick is
native and latest-frame-wins, so there is no Dart-side queue to wait in and no
honest value to report. Session wall-clock is `session.durationMs` on the export
header, not per sample.

## 8. Results table

Every cell is `NOT MEASURED — device gate` because no device is attached. Do not
replace a cell with a number unless the run was performed and its record filled.

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
| 13 (detect CPU / depth GPU) | NOT MEASURABLE — no detection accelerator knob | NOT MEASURABLE — no detection accelerator knob | NOT MEASURABLE — no detection accelerator knob | NOT MEASURABLE — no detection accelerator knob | NOT MEASURABLE — no detection accelerator knob | NOT MEASURABLE — no detection accelerator knob | NOT MEASURABLE — no detection accelerator knob | — | NOT MEASURABLE — no detection accelerator knob | NOT MEASURABLE — no detection accelerator knob | NOT MEASURABLE — no detection accelerator knob | NOT MEASURABLE — no detection accelerator knob |

## 9. Exit criteria

The performance question closes only when:

1. Rows 1–12 are filled from real runs on the Redmi device (and, if available, a
   second device with a different GPU), each with its export and logcat retained.
2. The 1.5 FPS regression is either reproduced (and fixed) or shown not to
   recur, with the numbers in row 1 vs row 3/5.
3. Row 8 vs row 9 states which accelerator native reported for each, proving the
   fallback path is reported truthfully.
4. Until then, this document is the deliverable, and no on-device claim is made.
