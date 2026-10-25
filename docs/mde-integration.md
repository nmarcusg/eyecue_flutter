# EyeCue — Monocular Depth Estimation (MDE) Integration

> **Status:** Implemented and carried on `feat/granular-inference-cadence` above
> the integrated MDE line. Verified on this branch with `flutter analyze --no-pub`
> (4 pre-existing issues) and `flutter test --no-pub` (527 passing, 1 pre-existing
> failure). No release build, device run or measurement has been performed on
> this branch, so depth accuracy, on-device latency, thermal behaviour and the
> manual matrix below are **unverified on hardware**. Metres are estimates, not
> measurements.

## What changed

EyeCue now has **one detection engine** (`ultralytics_yolo`, `YOLOView`) and an
**optional second model instance** that estimates metric depth from the same
camera session. The Custom EyeCue Dart/TFLite engine, `tflite_flutter` and the
Gradle classic-LiteRT workaround were removed in the same branch; see
[`architecture.md`](architecture.md).

Two independent user preferences control presentation, plus one mode control:

- **Distance estimation mode** — `monocularDepth` (default) or
  `boundingBoxApproximation`.
- **Show bounding boxes** (default on).
- **Show depth heatmap** (default on; the switch is disabled and its value kept
  while the mode is `boundingBoxApproximation`).

Settings schema version is `5`: the distance/overlay work added the `3 → 4`
fields and the inference-cadence work added `4 → 5` (`detectionTargetHz`,
`depthTargetHz`). The parser is field-tolerant, so older JSON loads with the
defaults and unknown modes fall back to `monocularDepth`.

## Architecture and data flow

```
                    one camera session (CameraX, YOLOView)
                                   │
                ┌──────────────────┴───────────────────┐
                │  YOLOView (YOLOTask.detect)          │
                │  onStreamingData(payload)            │
                │   • detections (normalized, upright) │
                │   • metrics, frameNumber, timestamp  │
                │   • imageWidth/imageHeight (upright) │
                │  (no image ever crosses the channel) │
                │                                      │
                │  depth tick (own thread, ≤depth Hz)  │
                │   • reuses the analysis Bitmap       │
                │   • instanceManager.predict(depth)   │
                │   • emits type:'depth' event         │
                └──────────────┬───────────────────────┘
                               │
        ┌──────────────────────┼───────────────────────────┐
        ▼                      ▼                           ▼
 Detection parse        Depth sampler                Depth estimator
 YOLODetectionResults   inset 12% → sensor box       parses the depth event
 → Detection[]          → median over grid values    → DepthFrame + heatmap
        │               → EMA α=0.4 per trackId       (ui.Image per frame)
        ▼                      ▼                           │
 SpatialAnalysisService  estimatedMeters                 ▼
 (band, priority, pos)        │                    DepthFrame.grid
        │                      ▼
        ▼               AssistiveDetectionController / AlertPolicy / TtsService
 Detection screen stack:
 YOLOView → DepthHeatmapView → BoundingBoxPainter → DetectionInformationOverlay
          → GestureSurface
```

### Why a second `YOLO` instance

The plugin exposes depth through the same single-image `YOLO` API. A second
instance with `useMultiInstance: true` gets its own channel and interpreter, so
depth work never shares state with the camera-bound `YOLOView` instance.

### Why a native shared-frame path

`YOLOView` is camera-bound and cannot be fed a frame from Dart. The previous
transport shipped the analysis frame as a JPEG on every delivered stream result
(`includeOriginalImage: true`) and pushed it back through
`predictSingleImage`, which re-decoded it natively: a full
Android → Dart → Android round trip per depth frame, with the encode and the
decode both on the delivery path, and every frame the estimator dropped still
paid for it.

L1b replaced that with a native tick inside the view. The streaming config now
carries `depthInstanceId`, `depthIntervalMs` and `depthMaxDim` instead of an
image flag (the vendored plugin's deviation list records the fork). The view:

1. keeps the analysis `Bitmap` it already decoded for detection (nothing on that
   path recycles or draws into it, so no copy is taken);
2. after the detector result **and** the stream callback have been delivered,
   checks the native cadence and the in-flight guard, then runs the depth
   instance on its own single-thread executor;
3. emits `type: 'depth'` on the existing view event channel as a compact
   block-mean grid — `Float32List` through `StandardMessageCodec`, the same trick
   `semanticMask.classMap` uses.

`depthMaxDim` is applied, not decorative:
`YOLOInstanceManager.predictorInstance(instanceId)` returns the instance's
predictor (or `null` when no model is loaded), the tick casts it to
`DepthEstimator` and sets `gridMaxDim = config.depthMaxDim` immediately before the
inference, so a non-default value genuinely changes the emitted grid. A failed
cast is logged once (`Log.w`) instead of being swallowed by `runCatching`, so a
wiring break cannot sit silent behind the default cap.

Grid aspect is aspect-correct: one scale for both axes, taken from the crop's
longest side, so the grid's longest side is ≤ `depthMaxDim` and its short side
follows the crop ratio. The production analysis stream is 4:3 (nothing sets
`analysisResolution`; CameraX yields 640×480 and `ImageUtils.toBitmap` never
rotates), so at the default 96 cap the app emits a **96×72** grid, not a 96×96
square.

Payload keys (exactly): `depthGrid`, `width`, `height`, `minDepth`, `maxDepth`,
`imageWidth`, `imageHeight`, `latencyMs`, `preMs`, `inferenceMs`, `postMs`,
`accelerator`, `droppedTicks`, `timestamp` (plus `type` for routing). Grid
values are metres; a
block with no valid sample (finite, 0.1–80 m) is `NaN`. The bound at the 96-cap
is ≤96 × 96 × 4 = **36 864 bytes** per event; the 4:3 stream emits
96 × 72 × 4 = 27 648 bytes, versus hundreds of KB for the dense map and ~
hundreds of KB for the JPEG.

The stream also allocates **no colour buffer and no bitmap**:
`DepthEstimator.postProcessDepth` builds `DepthMap.image` only when
`includeRawMaskData` is true (the still-image/overlay path). On the native-stream
path it skips `colorizeDepth` and the `Bitmap.createBitmap(..., ARGB_8888)`
entirely (≈0.8 MB per inference at a 518×389 crop, plus the persistent
`colorPixels` `IntArray` it reuses) and takes `minDepth`/`maxDepth` from one scan
of the same crop, because the event reads only `grid`/`minDepth`/`maxDepth`.
`DepthMap.image` is therefore `null` on that path only; the still-image and
overlay paths keep both the bitmap and the dense `values`.

Cadence ownership moved with the transport: the interval is native, so there is
no Dart timer, no pending frame slot and no queue. Latest frame wins (a tick in
flight makes the next one a no-op), and depth work is scheduled only after
detection output, so detection latency cannot be affected.

## Depth model

| Item | Value |
|---|---|
| Official id | `yolo26n-depth` |
| Artifact | [`assets/yolo26n-depth_w8a32.tflite`](../assets/yolo26n-depth_w8a32.tflite), bundled |
| Format | `FlatBuffer (TFL3)` + appended **deflated** zip entry `metadata.json` (563 bytes): `task: depth`, `imgsz` 640×640, `w8a32`, `names {"0":"depth"}`, AGPL-3.0, version `8.4.104` |
| Source | official Ultralytics export from the pinned plugin release `v0.6.6` |
| Load | lazy, once per depth-enabled session; its instance id then reaches the streaming config and the native tick |
| Accelerator | GPU first, with an automatic CPU fallback inside the native model open; a depth inference that still fails raises the native failure event once and the estimator degrades to bounding-box distance until the user retries |

The metadata entry is deflated, so a raw byte grep misses it; `inspectModel` and
`YOLOFileUtils.loadModelLabels` decompress it normally. The estimator still
passes `YOLOTask.depth` explicitly instead of relying on it.

### Why the model is bundled

Distribution is **offline-first**: the artifact ships in the APK as a Flutter
asset, exactly like the detection model, and is loaded through the same
`YOLOModelResolver` → `_copyFlutterAssetToDocuments` → `inspectModel` → native
`loadModel` path that detection already proves on device.

The previous design passed the official model id and let the plugin download
`yolo26n-depth_w8a32.tflite` on first use into
`<documents>/mobile-standard-v1/`. That could never work in a release build: at
the time the release manifest declared only `CAMERA` (`INTERNET` existed solely
in the debug and profile manifests), so the download failed, the model load
threw, the estimator degraded, and depth never ran — while detection kept
working because its model was bundled. Bundling removes the network dependency
entirely instead of widening permissions, so the assistive path also works with
no connectivity. The main manifest now declares `INTERNET` as well, but only for
the optional manual research-telemetry upload; detection and depth still make no
network requests.

`shortcut:` the plugin copies an asset once into the documents dir keyed by
filename, and `_copyFlutterAssetToDocuments` returns early when that file
already exists. A future model swap must therefore ship a **new filename**, or
devices keep loading the stale cached copy.

A model that still fails to load now logs `[Depth] loading model: <path>
(useGpu=<bool>)` and `[Depth] model load failed: <error>` before degrading, and
the first successful frame logs its map size, depth range, elapsed milliseconds
and accelerator choice — so an on-device failure is never silent.

## Coordinates

- Detections are normalized to the **upright** frame (`imageWidth`/`imageHeight`
  from the stream payload).
- The streamed JPEG is in **sensor** orientation; `ImageUtils.toBitmap` does not
  rotate it.
- `BoxTransform.invertRect(box, rotation)` maps an upright box into sensor
  space. `rotation` comes from `BoxTransform.displayRotationDegrees(
  sensorOrientation, deviceDegrees, isFront)` using `availableCameras()`
  (`camera` package) plus the current orientation.
- Rear camera only: this build never sets `lensFacing`, so mirror handling is
  intentionally absent.
- **Limitation:** the plugin exposes no rotation angle to Dart and Flutter
  reports only portrait/landscape, so the device angle is approximated as
  `0`/`90`. A 180° turn (and landscape-left vs landscape-right) is not
  observable; if the rotation cannot be resolved at all, the app forces the
  degraded path (bbox distance, no heatmap).
- The preview is `FILL_CENTER`. `BoundingBoxPainter` already maps normalized
  boxes with a `BoxFit` parameter, so the Flutter box layer uses
  `BoxFit.cover` and no new geometry code exists.

## Sampling and smoothing

1. Inset each detection box by **12%** on every side (`insetBox`).
2. Map upright → sensor (`sensorSpaceBox`).
3. Sample every depth pixel in that region; reject non-finite, `<= 0`,
   `< 0.1 m` and `> 80 m`.
4. Require **≥ 8** valid samples, otherwise no metric value for that object.
5. Take the **median** (never a mean, never a single pixel).
6. Smooth with an EMA `α = 0.4` keyed by the tracker identity matched from the
   previous frame (`DepthSmoother`). The raw map is never overwritten; only the
   reported estimate is smoothed.

The heatmap is a **display-only downsample**: the RGBA buffer is built on a grid
whose longest side is ≤ 320 px (stride 1/2/4/8, nearest-neighbour), so a
640×480 map costs ~77k pixels per update instead of ~307k. Distance sampling
above still reads the full-resolution map.

`shortcut:` the inset-median heuristic is uncalibrated — lens calibration and
per-device intrinsics are out of scope.

## Cadence settings

| Setting | Type | Default | Range |
|---|---|---|---|
| Detection target | `int?` (`null` = Automatic) | Automatic (uncapped native behaviour) | 1–30 Hz |
| Depth target | `int` | 2 Hz | 2–10 Hz |

`InferenceCadence.resolve` is pure and returns effective values without
rewriting the stored requests:

- Automatic keeps the detector uncapped; a numeric target is passed to
  `inferenceFrequency`.
- Low power mode caps detection at **4 Hz** and depth at **2 Hz**, and reports
  `lowPowerClamped` so the UI and telemetry can explain the clamp.
- A numeric detector target also caps depth (`sourceLimited`): depth cannot run
  faster than the frames that feed it.
- `boundingBoxApproximation` disables depth work (`effectiveDepthHz = 0`).

**Requested is not observed.** The two targets are requests. `depth_observed_hz`
and `depth_latency_ms` are the measured values, and the observed figure is an
EMA that includes idle gaps, so it is not a steady-state throughput claim.

## Cadence, staleness and fallback

- Depth cadence is the resolved depth target (default 2 Hz, see above), enforced
  **natively**: the tick only starts when `now - lastDepthStart >= depthIntervalMs`
  and an `AtomicBoolean` in-flight guard is free. Nothing is queued on either
  side and nothing is awaited from the detection callback.
- A map older than **1000 ms** is stale (`depthStaleAfterMs`): the heatmap is
  hidden and every object falls back to the bounding-box estimator.
- A geometry change (rotation or upright dimensions) between submit and result
  discards the map (`DepthFrame.matchesGeometry`).
- Pause and stop stop the native camera, so no tick runs; the freshness timer is
  cancelled and the frame/heatmap dropped. They **keep the model loaded**
  (`stop()` is the pause path), so a resume pays no load cost. Teardown
  (`dispose()`) releases the interpreter and the view's depth executor is shut
  down in `YOLOView.stop()`. Backgrounding is not observed explicitly: the camera
  stops delivering frames, so nothing new is queued and the stale heatmap is
  hidden by the 1000 ms freshness check.
- Failure behaviour is always non-blocking: degraded notice + bbox estimator,
  never a crash, never a block on start/pause/stop/preview.

## Enable / disable lifecycle

The interpreter is resident only while depth is the active distance mode.

| Step | Trigger | Effect |
|---|---|---|
| Arm | `distanceEstimationMode` = `monocularDepth` | `_armDepth()` → `prepare()` loads the depth instance once and its id reaches the streaming config |
| Ticks | instance id in the config | the native view ticks at the depth cadence; events become `DepthFrame`s |
| Disable | `distanceEstimationMode` = `boundingBoxApproximation` | `releaseModel()` (smoother reset): it stops the tick, drops the frame and its heatmap texture, parks the state at `idle` and then disposes the interpreter; the id is withdrawn |
| Re-enable | back to `monocularDepth` | `retry()` → `_armDepth()` → `prepare()` loads exactly one new instance and the state returns to `ready` |

`releaseModel()` details:

- Clears the frame and its heatmap texture, clears the pending/failure state and
  parks `state` at `DepthRunState.idle` — **clear-then-dispose** — and only then
  disposes the loaded instance (`_disposeModel()`), which frees the 5.3 MB model
  and its GPU delegate. The release epoch is bumped first, so a frame or a load
  still in flight is dropped on arrival instead of repopulating the estimator.
- **Does not** dispose the `ValueNotifier`s (unlike `dispose()`), so the
  estimator stays usable: a later `retry()` + re-arm returns to `ready`.
  Idempotent — with no model loaded it only re-parks the state.
- **Preserves** `observedHz` and `lastLatencyMs`, exactly as `stop()` does, so
  telemetry over a toggle has no hole (the screen already reports those only
  while MDE is on).
- A load that was already in flight when the disable landed is disposed on
  arrival rather than adopted, so a toggle during the ~1 s load cannot leave an
  interpreter resident. The re-enable does not join that doomed load: the
  release clears the in-flight slot, so the re-enable starts and adopts its own.
- **Pause, stop and backgrounding do not release.** They only stop the tick, so
  resuming never pays a reload.
- `dispose()` — the screen-teardown path — invalidates loads the same way: it
  marks the estimator disposed *and* bumps the release epoch, so a load in
  flight when the detection screen is torn down lands on the epoch branch, is
  disposed and never writes `ready`. Before this, such a load was adopted: in
  release the 5.3 MB interpreter landed on a dead estimator and leaked, in debug
  the `ready` write asserted on the disposed notifier. Proved by `a load that
  finishes after dispose is released, not adopted`.

The native failure latch is independent of the release: `releaseModel()` never
touches it. It clears in `setStreamConfig` (`YOLOView.kt:210`), `pauseCamera()`
(`:703`) and the full teardown (`:2593`); a disable with the id withdrawn
re-pushes the config, so the next `setStreamConfig` clears it anyway.

**Retry after a failure.** `_retryDepth` re-arms through `_armDepth()` when no
instance exists (`instanceId == null`, the model-load failure case) and only
re-pushes the existing instance id otherwise (the native inference failure case).
`prepare()` shares one in-flight load, so repeated taps cannot spawn duplicates.

## Accelerator policy

Depth accelerator selection is a **build-time measurement knob**, not a runtime
setting: nothing is persisted, `AppSettings` is untouched, and there is no UI.

| Define | Resolved value | Effect on the depth load |
|---|---|---|
| unset, or `EYECUE_DEPTH_ACCELERATOR=auto` | `DepthAccelerator.auto` | asks for the GPU delegate; `LiteRtModel` falls back to CPU when the GPU cannot run the graph |
| `--dart-define=EYECUE_DEPTH_ACCELERATOR=cpu` | `DepthAccelerator.cpu` | `useGpu: false` — no GPU context is created for the depth instance |
| `--dart-define=EYECUE_DEPTH_ACCELERATOR=gpu` | `DepthAccelerator.gpu` | the same request as `auto`, so a run can state its intent explicitly |

`resolveDepthAccelerator(String raw)` in
[`model_config.dart`](../lib/models/model_config.dart) is pure and total: it
trims, lowercases and maps `cpu`/`gpu`, and returns `auto` for everything else —
an unknown or empty value can never silently disable the GPU path.
`DepthAccelerator.useGpu` is the only place the policy becomes a boolean, and
`MonocularDepthEstimator` passes it to `DepthModelFactory(useGpu:)` for every
load. The request is fixed for the estimator's life; switching accelerators means
a rebuild, never a reload.

**`auto` ships.** The knob exists so the device matrix in
[`benchmark-procedure.md`](benchmark-procedure.md) can pin depth to CPU on a
build without a settings screen.

**The reported accelerator is never the request.** `accelerator` returns the
`accelerator` field of the last native depth event, which
`YOLOView.emitDepthEvent` derives from the predictor that actually ran, and is
`null` until that first event or while no model is loaded. A requested GPU that
fell back to CPU therefore reports `cpu`, and `depthStatusFor` passes that
through to telemetry unchanged. Requested policy, build define and reported value
are three different things; only the last one is evidence.

The estimator logs the reported value once per loaded instance —
`[Depth] accelerator reported by native: gpu|cpu (requested useGpu=…)` — on the
first depth event that carries it. The separate `[Depth] first frame …` line
prints `useGpu=`, which is the **requested** policy: it proves the build define
reached the factory, not that the GPU ran.

**`depthStatus` vs. the reported accelerator.** `depthStatus` is a derived
status, not the raw value. While the state is `ready` but no depth event has
arrived yet, the accelerator is still unknown, and `depthStatus` reports
`loading` for that window rather than guessing `gpu`. Telemetry carries the raw
value separately as `depthAccelerator`, so an unknown accelerator stays `null`
instead of becoming a fabricated one.

## Stage timings surface

Produced and **recorded** in the schema-4 telemetry sample (see
[`benchmark-procedure.md`](benchmark-procedure.md) §7). Every field below is
nullable end to end: unknown is `null`, never `0`.

| Side | Value | Null policy |
|---|---|---|
| Detector | `DetectorStageTimings.fromMetrics(YOLOPerformanceMetrics)` → `preMs`, `inferenceMs`, `postMs`, `fps` ([`detector_stage_timings.dart`](../lib/models/detector_stage_timings.dart)) | the native map omits the stage keys unless `includeProcessingTimeMs`/`includeFps` are on and the plugin defaults them to `0`; every value `<= 0` maps to `null` |
| Depth | `MonocularDepthEstimator.stageTimings` → `DepthStageTimings(preMs, inferenceMs, postMs, accelerator, droppedTicks)` | `YOLODepthEvent` parses these as nullable, so an absent key is `null` |

Both types are immutable and every measurement is `null` when it is missing — a
stage nobody measured must never look like a 0 ms one. `DepthStageTimings` is
last-known exactly like `lastLatencyMs`, so it survives `stop()` and
`releaseModel()` and a toggle over a session leaves no hole in the record. The
`.accelerator` inside it is the event's own value; the estimator's `accelerator`
getter additionally requires a loaded instance, so a released estimator reports
"unknown" rather than a stale string.

`droppedTicks` is the **native cumulative** count of depth ticks the view skipped
(interval not elapsed, or an inference already in flight) since the tick last
restarted; `YOLOView.stop()` resets it. It is counted natively rather than
derived in Dart because both drop decisions happen inside the native tick: Dart
only sees completions, so a requested-vs-completed delta could not tell an
interval skip from a tick that was never requested. At a 2 Hz depth target on a
30 fps stream the interval gate dominates the count, so read it as the depth-tick
deficit, not only as lost inferences.

## Settings × behaviour matrix

| Distance mode | Show heatmap | Show boxes | Depth inference | Heatmap | Box renderer | Distance source |
|---|---|---|---|---|---|---|
| monocularDepth | on | on | yes | Flutter `DepthHeatmapView` | Flutter `BoundingBoxPainter` above heatmap | metres → band |
| monocularDepth | on | off | yes | shown | none | metres → band |
| monocularDepth | off | on | yes | hidden | native overlay | metres → band |
| monocularDepth | off | off | yes | hidden | none | metres → band |
| boundingBoxApproximation | (preserved) | on | **no** | hidden | native overlay | box height |
| boundingBoxApproximation | (preserved) | off | **no** | hidden | none | box height |

Presentation flags are resolved by `DepthOverlayState.resolve`; when the
heatmap is visible the native overlay is turned off
(`YOLOViewController.setShowOverlays(false)`) and boxes are painted in Flutter
so labels stay above the heatmap. When it is hidden, native overlays render
boxes as before. Hiding boxes is not "detection off"; hiding the heatmap is not
"MDE off".

The heatmap is **constructed only when it is displayed**. The screen sets
`MonocularDepthEstimator.heatmapEnabled` from `heatmapRequested(mdeEnabled,
showDepthHeatmap)` on every settings change, so while the overlay is hidden
`_publish` never calls the heatmap builder, the frame carries `heatmap: null`
and the grid is untouched — distance estimation and the box layer keep working
exactly as before. Turning it off also replaces the held frame with a
heatmap-less copy and disposes the image, so the GPU texture is released and no
stale overlay can be shown in between; re-enabling fills the very next frame.
The gate is presentation-only: it is not part of the streaming-config key, so
toggling the heatmap never restarts the camera and never stops the depth tick.
Freshness is not part of the gate — a stale map is hidden by
`DepthOverlayState.resolve` for display, and gating construction on freshness
would need the frame the gate governs.

## Distance in the assistive layer

- Meters map onto the existing band vocabulary: `≤ 1.5 m → near`,
  `≤ 4.0 m → medium`, else `far`. Alert policy, ranking and telemetry therefore
  keep working unchanged.
- `DetectionInfo` carries `estimatedMeters`, `distanceSource`
  (`monocularDepth`/`boundingBox`) and `distanceLabel` (`"about 3.5 m"`;
  half-metre rounding under 10 m, whole metres above).
- Speech uses the metric phrase when one exists (`"about 3.5 m"`), otherwise the
  existing `"approximately near/ahead/far"` wording. The bbox path is
  byte-identical to before.
- The distance work adds no telemetry field; the separate stage-timing fields
  on the sample are described in
  [`telemetry-data-dictionary.md`](telemetry-data-dictionary.md).

## Verification performed

Commands run in `/home/nico/repos/eyecue_flutter-cadence` on
`feat/granular-inference-cadence` (2026-10-23):

| Command | Result |
|---|---|
| `flutter analyze --no-pub` | 4 issues, all pre-existing (unused field in `alert_policy.dart`, `onError` return type in `tts_service.dart`, two unnecessary test imports); no new issues |
| `flutter test --no-pub` | **527 passing, 1 failing**; the failure (`tts_service_test.dart` → "a partial signal pair records a reconciliation timeout") fails identically on `dev@94f74d8` |

L1b (native transport) was verified in `/home/nico/repos/eyecue_flutter-playstore`
with the repository gates plus a native build. `flutter analyze` and
`flutter test` do **not** cover `plugins/**`, so the plugin's own Dart surface was
checked with `dart analyze lib` inside `plugins/ultralytics_yolo` (no issues) and
the Kotlin with `flutter build apk --debug`. The payload contract itself is
covered by `test/services/depth_payload_parity_test.dart` (exact key set, grid
bound, rejection of `values`/`originalImage`) and the event → frame derivation by
`test/services/monocular_depth_estimator_test.dart`. Two claims are **not**
test-covered and must not be read as such:

- the **grid arithmetic** inside `DepthEstimator.blockMeanGrid` (single scale,
  640×480 → 96×72) has no automated test. There is no Kotlin test source set for
  `plugins/**`, so the Dart test above pins the payload *shape* it is handed, not
  the native maths that produces it. A real-device or JVM/Robolectric test is
  required before any payload-size tuning.
- the **`depthMaxDim` → estimator wiring** is compile-checked and inspected, not
  executed.
- the **native allocation skip** (L2: no colourisation, no `ARGB` bitmap on the
  stream) is `CONFIRMED-BY-INSPECTION` for the same reason — no Kotlin test
  source set. Its Dart-side counterpart is test-covered: the heatmap builder is
  **not invoked** while disabled, re-enabling rebuilds, disabling disposes the
  held image (`test/services/monocular_depth_estimator_test.dart`), and the
  screen-side gate, the heatmap-agnostic streaming key and the independence of
  the box/heatmap toggles are pinned in
  `test/screens/depth_overlay_state_test.dart`.

Depth accuracy and the achieved on-device cadence remain **unmeasured** — see the
table below.

Earlier MDE-branch evidence (452 passing / 1 failing and an 82.9 MB release APK)
is historical: it belongs to `/home/nico/repos/eyecue_flutter-mde` at base
`dev@94f74d8` and does not verify this merged branch. No release build was run
here, and the packaged library set was not re-inspected.

### Measured vs unmeasured performance

| Metric | Status |
|---|---|
| `flutter analyze --no-pub` / `flutter test --no-pub` | **Measured** (above) |
| APK size | **Not measured on this branch**; the historical MDE-branch release APK was 82.9 MB |
| Detection FPS / inference latency | **Not measured on this branch** (no device). Do not reuse older numbers. |
| Depth inference latency / cadence achieved | **Not measured**. The cadence target is a request, not an observed rate. |
| Depth accuracy (metres) | **Not measured.** Uncalibrated model output. |
| Thermal / battery impact | **Not measured.** |

No FPS, latency, accuracy or calibration figure in this document is an
invention; each remains unmeasured until a device run is recorded. The
measurement protocol — matrix, commands, per-run record and an all-`NOT MEASURED`
results table — is [`benchmark-procedure.md`](benchmark-procedure.md). **No
`CONFIRMED-ON-DEVICE` claim exists** for any figure in this document, and the
1.5 FPS Redmi regression stays open until that matrix runs.

## Manual device validation steps

1. Build and install: `flutter build apk --release && adb install -r
   build/app/outputs/flutter-apk/app-release.apk`.
2. First run (no network needed): start detection, confirm the depth notice
   never appears, then look for `[Depth] Display rotation resolved: …` in logcat.
3. Hold a chair ~1 m, ~3 m and ~6 m away in portrait: speech should say
   "about …" and the band should move near → medium → far.
4. Rotate to landscape: boxes must stay aligned and depth must not drift.
5. Airplane mode, clear app data, start detection: depth must still initialise
   from the bundled asset (no degraded banner); detection keeps running.
6. Settings → Distance & Overlays: switch to "Bounding box"; depth inference
   stops (no depth logs), heatmap disappears, heatmap switch is disabled but
   keeps its value; switch back and it returns.
7. Toggle "Show bounding boxes" off: no boxes, detection and speech continue.
8. Pause / resume / stop: no depth work while paused/stopped; resume restores
   it without leaking a second interpreter.
9. Force a GPU failure (e.g. a device known to reject the model) and confirm the
   single CPU retry path and, if that fails, the degraded banner.
10. Background the app and return: no stale heatmap frame is shown.

## Third-party notices

| Component | License |
|---|---|
| `ultralytics_yolo` Flutter plugin | AGPL-3.0 |
| YOLOv8n detection and YOLO26n-depth weights | AGPL-3.0 |
| LiteRT / TFLite runtime (used by the plugin) | Apache-2.0 |
| `camera` / `camera_android_camerax` | BSD-3-Clause |
| Flutter, Dart, `flutter_tts`, `permission_handler`, `path_provider`, `fl_chart`, `google_fonts` | BSD-3-Clause / MIT / Apache-2.0 as published |

**AGPL compatibility:** EyeCue links `ultralytics_yolo` and ships AGPL-3.0
YOLO26n weights. Distributing the app (or a derivative) therefore requires
releasing the complete corresponding source under AGPL-3.0 and preserving the
notices above. EyeCue is a thesis project distributed as source in this
repository, which satisfies that obligation as long as the repository stays
public and the notices remain. No root `LICENSE` file is added by this branch.
