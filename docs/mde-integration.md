# EyeCue — Monocular Depth Estimation (MDE) Integration

> **Status:** Implemented on branch `codex/mde-integration` (worktree
> `/home/nico/repos/eyecue_flutter-mde`, base `dev@94f74d8`). Statically
> verified (`dart format`, `flutter analyze`, `flutter test`) and a release APK
> builds. **No Android device was attached**, so depth accuracy, on-device
> latency, thermal behaviour and the manual matrix below are **unverified on
> hardware**. Metres are estimates, not measurements.

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

Settings schema version `3 → 4`; the parser is field-tolerant, so older JSON
loads with the defaults and unknown modes fall back to `monocularDepth`.

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
        │                      │                       500 ms, latest-wins
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
| Model ID | `yolo26n-depth` |
| Artifact | `yolo26n-depth_w8a32.tflite` |
| Source | pinned plugin release `v0.6.6` (GitHub release asset) |
| Cache | `<app documents>/mobile-standard-v1/` |
| Load | lazy, on the first submitted frame |
| Accelerator | GPU first, one CPU retry, then degraded |

First use needs network. Offline first run fails the model load, sets the
degraded state and keeps detection working with the bounding-box estimator; the
app never blocks on the download and never retries blindly.

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

`shortcut:` the inset-median heuristic is uncalibrated — lens calibration and
per-device intrinsics are out of scope.

## Cadence, staleness and fallback

- Depth runs at most every **500 ms** (`EyeCueModelConfig.depthMinIntervalMs`),
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

Commands run in `/home/nico/repos/eyecue_flutter-mde`:

| Command | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test tool` | clean — `Formatted 98 files (0 changed)`, exit 0 |
| `flutter analyze` | 4 issues, all pre-existing on `dev@94f74d8` (2 warnings, 2 info); no new issues |
| `flutter test` | **452 passing, 1 failing**; the failure (`tts_service_test.dart` → "a partial signal pair records a reconciliation timeout") fails identically on `dev@94f74d8` before this branch |
| `flutter build apk --release` | success — `build/app/outputs/flutter-apk/app-release.apk`, 82.9 MB (82,882,016 bytes) |

### Release build output (verbatim tail)

```
Running Gradle task 'assembleRelease'...
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): flutter_tts, ultralytics_yolo
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
...
Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 5864 bytes (99.6% reduction). Tree-shaking can be disabled by providing the --no-tree-shake-icons flag when building your app.
Running Gradle task 'assembleRelease'...                          147.1s
✓ Built build/app/outputs/flutter-apk/app-release.apk (82.9MB)
```

The re-run reused the Gradle cache from the first cold build in this worktree
(627.6 s); the artifact size is unchanged. The packaged `lib/` contains
`libLiteRt.so` and `libultralytics.so` and no `libtensorflowlite_jni.so`, so the
removed classic-LiteRT extraction is not shipping anything.

The build emitted **no R8/WorkManager missing-class or startup warnings**; the
`androidx.work:work-runtime:2.11.2` pin is retained. Build success does not
prove runtime startup — that remains a device check (below).

### Measured vs unmeasured performance

| Metric | Status |
|---|---|
| `dart format` / `flutter analyze` / `flutter test` / `flutter build apk --release` | **Measured** (above) |
| APK size | **Measured**: 82.9 MB release |
| Detection FPS / inference latency | **Not measured on this branch** (no device). Do not reuse older numbers. |
| Depth inference latency / cadence achieved | **Not measured**. The 500 ms interval is a configured floor, not an observed rate. |
| Depth accuracy (metres) | **Not measured.** Uncalibrated model output. |
| Thermal / battery impact | **Not measured.** |

No FPS, latency, accuracy or calibration figure in this document is an
invention; each remains unmeasured until a device run is recorded.

## Manual device validation steps

1. Build and install: `flutter build apk --release && adb install -r
   build/app/outputs/flutter-apk/app-release.apk`.
2. First run **online**: start detection, confirm the depth notice never
   appears, then look for `[Depth] Display rotation resolved: …` in logcat.
3. Hold a chair ~1 m, ~3 m and ~6 m away in portrait: speech should say
   "about …" and the band should move near → medium → far.
4. Rotate to landscape: boxes must stay aligned and depth must not drift.
5. Airplane mode, clear app data, start detection: expect the degraded banner
   and bbox distances; detection keeps running.
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
| YOLO26n detection and `yolo26n-depth` weights | AGPL-3.0 |
| LiteRT / TFLite runtime (used by the plugin) | Apache-2.0 |
| `camera` / `camera_android_camerax` | BSD-3-Clause |
| Flutter, Dart, `flutter_tts`, `permission_handler`, `path_provider`, `fl_chart`, `google_fonts`, `flutter_riverpod` | BSD-3-Clause / MIT / Apache-2.0 as published |

**AGPL compatibility:** EyeCue links `ultralytics_yolo` and ships AGPL-3.0
YOLO26n weights. Distributing the app (or a derivative) therefore requires
releasing the complete corresponding source under AGPL-3.0 and preserving the
notices above. EyeCue is a thesis project distributed as source in this
repository, which satisfies that obligation as long as the repository stays
public and the notices remain. No root `LICENSE` file is added by this branch.
