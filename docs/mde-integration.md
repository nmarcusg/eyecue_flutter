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
                │   • originalImage (JPEG q90, SENSOR) │  ← only when MDE is on
                └──────────────┬───────────────────────┘
                               │
        ┌──────────────────────┼───────────────────────────┐
        ▼                      ▼                           ▼
 Detection parse        Depth sampler                Depth estimator
 YOLODetectionResults   inset 12% → sensor box       second YOLO instance
 → Detection[]          → median over map values     (YOLOTask.depth,
        │               → EMA α=0.4 per trackId       useMultiInstance: true)
        │                      │                       configured cadence, latest-wins
        ▼                      ▼                           │
 SpatialAnalysisService  estimatedMeters                 ▼
 (band, priority, pos)        │                    DepthFrame + heatmap
        │                      │                    (ui.Image per frame)
        ▼                      ▼
 AssistiveDetectionController / AlertPolicy / TtsService
        │
        ▼
 Detection screen stack:
 YOLOView → DepthHeatmapView → BoundingBoxPainter → DetectionInformationOverlay
          → GestureSurface
```

### Why a second `YOLO` instance (not a plugin fork)

The plugin exposes depth through the same single-image `YOLO` API. A second
instance with `useMultiInstance: true` gets its own channel and interpreter, so
depth work never shares state with the camera-bound `YOLOView` instance, and no
vendored package or second inference framework is needed.

### Why the JPEG bridge

`YOLOView` is camera-bound and cannot be fed a frame. Its streaming config can
attach the analysis frame as a JPEG (`includeOriginalImage: true`), which is the
only public path that exposes the exact pixels the detector saw. That JPEG
exists only for **delivered** stream frames, so the depth cadence is bounded by
the detection stream rather than every camera frame.

## Depth model

| Item | Value |
|---|---|
| Official id | `yolo26n-depth` |
| Artifact | [`assets/yolo26n-depth_w8a32.tflite`](../assets/yolo26n-depth_w8a32.tflite), bundled |
| Format | `FlatBuffer (TFL3)` + appended **deflated** zip entry `metadata.json` (563 bytes): `task: depth`, `imgsz` 640×640, `w8a32`, `names {"0":"depth"}`, AGPL-3.0, version `8.4.104` |
| Source | official Ultralytics export from the pinned plugin release `v0.6.6` |
| Load | lazy, on the first submitted frame |
| Accelerator | GPU first, one CPU retry, then degraded |

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

- Depth cadence follows the resolved depth target (default 2 Hz, see above),
  with **one** pending frame slot and **one** in-flight request. A newer frame
  replaces the pending one; nothing is ever queued or awaited from the
  detection callback.
- A map older than **1000 ms** is stale (`depthStaleAfterMs`): the heatmap is
  hidden and every object falls back to the bounding-box estimator.
- A geometry change (rotation or upright dimensions) between submit and result
  discards the map.
- Pause and stop cancel the freshness timer and drop the pending frame and
  image; `dispose()` releases the interpreter. Backgrounding is not observed
  explicitly: the native camera stops delivering frames, so nothing new is
  queued and the stale heatmap is hidden by the 1000 ms freshness check.
- Failure behaviour is always non-blocking: degraded notice + bbox estimator,
  never a crash, never a block on start/pause/stop/preview.

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
- Telemetry and Supabase payload shapes are unchanged (no new fields).

## Verification performed

Commands run in `/home/nico/repos/eyecue_flutter-cadence` on
`feat/granular-inference-cadence` (2026-10-23):

| Command | Result |
|---|---|
| `flutter analyze --no-pub` | 4 issues, all pre-existing (unused field in `alert_policy.dart`, `onError` return type in `tts_service.dart`, two unnecessary test imports); no new issues |
| `flutter test --no-pub` | **527 passing, 1 failing**; the failure (`tts_service_test.dart` → "a partial signal pair records a reconciliation timeout") fails identically on `dev@94f74d8` |

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
invention; each remains unmeasured until a device run is recorded.

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
