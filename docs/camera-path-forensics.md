# Live-Camera Path Forensic Investigation

> **Status:** COMPLETE — camera path empirically isolated on-device (Android 13,
> arm64, back camera, sensorOrientation 90°).
> **Date:** 2026-08-01
> **Ground truth:** static-image test (see `docs/static-image-test.md`) —
> model/parser/NMS/thresholds/labels/painter proven correct.

---

## 1. Verdict (evidence-driven)

**The live-camera path is NOT fundamentally broken.** When pointed at a lit
scene with the phone held in the sensor's native (landscape) orientation, the
exact same downstream pipeline detects people at **0.70–0.88 confidence with
4–8 objects** — statistically indistinguishable from the static-image baseline
(0.86–0.92).

The historical "Camera → 0 detections" is a **compound of three factors**:

| # | Factor | Status |
|---|--------|--------|
| 1 | Pre-NMS confidence threshold was 0.5 (too high) | **FIXED** (now 0.25) |
| 2 | **No image rotation to device orientation** (sensorOrientation 90° never applied) — portrait-hold scenes reach YOLO rotated 90° | **FIXED** (2026-08-01, v0.1.7 — see `docs/orientation-implementation.md`) |
| 3 | Test scenes were sometimes dark/desk-level (frame-1 dumps black) | Not a bug — scene artifact |

All camera-path factors are now resolved. Everything else in the camera path —
plane strides, semi-planar NV12 handling, chroma order, color range, resize,
normalization — is verified correct on-device. The orientation fix (input
rotation to upright, `BoxTransform`) is on-device validated for back portrait
(maxConf 0.91, was 0) and static-image regression; back-landscape physical-hold
re-validation and front-camera runs are pending.

---

## 2. Evidence collected

### 2.1 Plane geometry (5 prior runs + new run, all identical)
```
YUV_420_888 (raw 35), 320×240, 3 planes
Y:      rowStride=512 pixelStride=1 length=122688   (= 239×512 + 320)
chroma: rowStride=512 pixelStride=2 length=61247    (= 119×512 + 319) ×2
```
- Semi-planar interleaved chroma; plane[1]/plane[2] are the **same buffer,
  offset by one byte** (plane2[i] == plane1[i+1]) — the YUV_420_888 NV12/NV21
  representation.
- `plane.width/height` reported as 0 by the plugin on this device (not
  reliable; rowStride/pixelStride/length are).
- Y buffer has 192 bytes/row padding (rowStride 512 vs width 320); the
  converter honors it and this is verified correct.

### 2.2 Raw plane content (new instrumentation, lit scene)
```
Y: len=122688 min=0 max=205 mean=82.4 %zero=37.4   → REAL luma, FULL range
U: mean=80.1 chroma std-around-128=78.3            → REAL color
V: mean=80.1 chroma std-around-128=78.3            → REAL color
luma: FULL range [0..255]  (limited-range 16..235 refuted)
```
The earlier all-black frame-1 dumps (Y mean 0–6 across 5 prior runs) were
**covered/dark-lens scenes**, not a readback bug: the same instrumentation now
shows healthy planes in a lit scene.

### 2.3 RGB conversion (on-device dumps + pixel-level color check)
- Preprocess RGB: R=0.516 G=0.520 B=0.509 (frame 1 lit), max ~1.0, healthy.
- Center (face) pixels of `frame_rgb.png` (U-led/NV12): **RGB=(158,152,146) —
  warm, R>G>B = natural skin**. The V-led (NV21) reference render is
  (147,155,160) — cool/blue = swapped. **The converter's U-led read is
  correct; the device is NV12 per contract.**

### 2.4 Inference results (232-frame live run)
```
maxConf min=0.0025 max=0.8760   42 frames > 0.5   29 frames > 0.7   76 frames with detections
e.g. frame 86: maxConf=0.8760 detections=4   frame 93: 0.8262 detections=7
labels seen: person (0.88), person (0.48...), book, tv, refrigerator
```
Frame-1 of the same run (phone on desk) scored only book 0.23 / person 0.19 —
confirming the low scores in earlier runs were **scene content**, not pipeline.

### 2.5 Orientation-dependence (user observation + code inspection)
- User: *"it detected people when i pointed the phone in its landscape
  position."*
- `[Camera] Sensor orientation: 90°` logged; the app never applies any
  rotation to the 320×240 landscape stream (no Exif/rotation handling in
  `processFrame`/`_convertYUV420toRGB`).
- CameraX delivers sensor-orientation frames (landscape) regardless of device
  orientation. In portrait, YOLO therefore sees the scene rotated 90° →
  ~0 detections; in landscape it sees upright content → detections.

---

## 3. Static-image vs CameraImage path — complete difference list

| # | Stage | Static-image path | CameraImage path | Divergent? |
|---|-------|-------------------|------------------|------------|
| 1 | Source | decoded RGBA (JPEG) | YUV_420_888 planes | yes (intended) |
| 2 | Source adapter | `rgbaToI420` (BT.601 full-range, exact inverse of converter) | CameraX/Camera2 HAL YUV | yes (device-dependent) |
| 3 | Chroma layout | planar I420, pixelStride 1 | semi-planar interleaved, pixelStride 2 (NV12, U-led) | yes (handled & verified) |
| 4 | Row strides | tight (w / (w+1)~/2) | Y=512, chroma=512 (padding), short last rows | yes (handled & verified) |
| 5 | Color range | full-range 0..255 / 128 | full-range (verified 0..255 / 128) | **no** |
| 6 | YUV→RGB | `_convertYUV420toRGB` | `_convertYUV420toRGB` (identical) | **no** |
| 7 | Resize | NN 810×1080 → 640×640 | NN 320×240 → 640×640 (2.67× vert stretch) | yes (magnitude only) |
| 8 | Normalize | /255.0 [0,1] | /255.0 [0,1] | **no** |
| 9 | run/parser/NMS | identical | identical | **no** |
| 10 | **Orientation** | image already upright (portrait) | **landscape sensor frame, never rotated** | **YES — THE BUG** |
| 11 | Resolution | 810×1080 source | 320×240 source (low) | yes (quality) |

Stages 3–4 were verified correct by healthy planes + correct colors + working
detections. **Stage 10 is the only semantic divergence that flips detection
success on/off.**

---

## 4. Ranked hypotheses (final)

| Rank | Hypothesis | Evidence | Confidence | Symptom | Minimal targeted fix |
|------|-----------|----------|-----------|---------|----------------------|
| 1 | **Image rotation/orientation not applied** (sensorOrientation 90° ignored) | 90° sensor; landscape→detects (0.88), portrait→0; no rotation code exists; input/color verified healthy | **90%** | portrait: 0 detections; landscape: detections | Rotate the 640×640 RGB input (or planes) 90°/270° per device orientation before inference; rotate normalized boxes back for the painter. |
| 2 | Frame-1 scene darkness (desk/covered lens) | all 5 prior frame-1 dumps black; lit scene → healthy | 100% (as scene artifact; NOT a bug) | black input only when lens covered | none (dumps now trigger on first bright frame) |
| 3 | Chroma order NV21 vs NV12 | U-led render warm skin (158,152,146); V-led cool (147,155,160); contract says U-led | **refuted** (was 35%) | — | none |
| 4 | rowStride/pixelStride misread | geometry honored; healthy RGB + detections | **refuted** (was 30%) | — | none |
| 5 | Color range (limited 16-235) | luma full-range 0..255/205 | **refuted** (was 15%) | — | none |
| 6 | Low res 320×240 + NN stretch (quality only) | detections still hit 0.88 | partial (20%) | blocky, lower ceiling than static | optional: letterbox or higher-res preset |

---

## 5. Instrumentation implemented (log-only, zero behavior change)

All changes are diagnostics only — nothing in inference/preprocessing/parser/NMS
was modified.

| Change | File / function | What it logs | Conclusively resolved |
|--------|-----------------|--------------|----------------------|
| `recordCamera` extended | `lib/screens/camera_screen.dart` `_processCameraImage` + `lib/services/forensic_log.dart` `recordCamera` | plane width/height, first/last bytes, definite layout classification (planar vs semi-planar, plane1==plane2) | I420 vs NV12/NV21 geometry, definitively |
| `recordPlaneStats` (new) | `lib/services/forensic_log.dart` + `inference_isolate.dart` (on dumped frames) | raw Y/U/V min/max/mean/%zero/first-16, chroma std-around-128, luma range note | camera-black vs readback-broken; color-range (16-235) |
| `frame_rgb_nv21.png` (new) | `forensic_log.dart` `dumpFrameImages` (`_yuvToRgbRgba` `swapUV`) | same planes under V-led interpretation | NV12 vs NV21 chroma order (pixel-level) |
| Bright-frame dump trigger | `inference_isolate.dart` frame loop (`dumpNow = frame1 \|\| first bright`) | full forensic set on the first frame with input mean > 0.1 | captures a real lit scene instead of only the desk frame |
| Per-frame `yMean` | `recordPerformance` + `_yPlaneMean` | raw Y-plane mean each frame in performance.txt | input brightness over time (35–145 in use) |

Expected new files per run: `frame_rgb_nv21.png`; `preprocess.txt` gains `Raw
plane stats`; `performance.txt` gains `yMean=`.

---

## 6. Recommended minimal fix (not implemented — analysis only)

Apply orientation before inference, in the isolate after YUV→RGB (buffer
transpose of the 640×640 NHWC tensor), rotating by the angle that makes the
sensor frame upright for the current device orientation:

- `rotationDegrees = sensorOrientation - deviceOrientation` (mod 360) for the
  back camera (sensorOrientation 90°; portrait device 0 → 90° CW; landscape →
  0°).
- After inference, rotate each normalized box by `-rotationDegrees` so the
  painter maps onto the portrait preview correctly.
- Front camera additionally needs mirroring (already handled by the painter's
  `lensDirection`).

Equivalent alternative: rotate the Y/U/V planes before conversion (or set the
analysis target rotation if the stream API exposes it). The static-image test
(which already produces upright content) is unaffected.

---

## 7. Open items

1. ~~Implement + verify rotation fix~~ — ✅ Done (v0.1.7): portrait detections
   0 → 0.91 maxConf on-device; static-image regression byte-identical. See
   [`orientation-implementation.md`](orientation-implementation.md). Remaining:
   back-landscape physical-hold re-validation and front-camera portrait/
   landscape device runs.
2. Optional closed-loop color probe: point at a pure-red object and confirm it
   renders red (chroma order is already strongly refuted, this is belt-and-
   braces).
