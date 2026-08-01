# Orientation Architecture Review & Implementation Plan

> **Status:** Design review only — NO code changes.
> **Date:** 2026-08-01
> **Context:** `docs/camera-path-forensics.md` identified the remaining camera
> defect as **missing rotation-to-device-orientation** (this device:
> `sensorOrientation = 90°`, frames delivered as 320×240 landscape, never
> rotated; landscape-hold detects at 0.88, portrait-hold ≈ 0).
> **Stack (verified):** `camera 0.12.0+1`, `camera_android_camerax 0.7.3`
> (CameraX — confirmed by `GeneratedPluginRegistrant.java` and the
> `androidx.camera.camera2.pipe`/CXCP logcat), `camera_avfoundation 0.10.1`
> (iOS), `tflite_flutter 0.12.1`.

---

## 1. Does CameraX / Flutter Camera always deliver sensor-native orientation?

**Yes — this is guaranteed, and it is the root of the problem.**

- Android's camera stack (Camera2 and CameraX) always delivers `YUV_420_888`
  analysis frames in the **sensor's native orientation**. Frames are **never
  auto-rotated** to match the device's physical orientation. That is the app's
  responsibility.
- What **varies per device** is the value of `sensorOrientation`
  (0 / 90 / 180 / 270), which is a per-camera-lens static property. Common
  values: back cameras 90° (most phones), front cameras 270° (most phones) —
  but tablets and non-standard HALs can expose 0° or 180°. Therefore **any
  hardcoded angle is wrong**; the metadata must be read at runtime.
- Evidence on this device: the stream is always 320×240 (landscape) in every
  orientation; `[Camera] Sensor orientation: 90°` is logged; detections only
  fire when the phone is held so the sensor frame happens to be upright
  (landscape hold).

## 2. CameraImage orientation semantics per implementation

All Flutter camera implementations expose the **same** contract: analysis
frames in sensor/native orientation, and **no per-frame rotation field** on
`CameraImage`. The app must derive rotation itself.

| Implementation | Frames delivered | Rotation metadata available |
|----------------|------------------|------------------------------|
| `camera_android_camerax` (CameraX) — **this app** | sensor-native YUV_420_888; always landscape-shaped | `CameraDescription.sensorOrientation` (static). CameraX internally computes `imageInfo.rotationDegrees` but the plugin does **not** expose it per frame. |
| `camera_android` (Camera2) | sensor-native YUV_420_888 | `CameraDescription.sensorOrientation` (static) |
| `camera_avfoundation` (iOS) | AVFoundation camera-native frames (landscape-shaped) | `CameraDescription.sensorOrientation` (90 back / 270 front typical); the plugin rotates only the preview, not the stream |
| `camera_web` | browser-vendor dependent | n/a for this task |

**Conclusion:** across CameraX, camera_android, and iOS the semantics are the
same: *native frames + static `sensorOrientation` + current device
orientation*. There is no per-frame orientation in `CameraImage` on any
platform, so a device-independent pipeline must compute it from
`sensorOrientation` + `MediaQuery`/window orientation.

## 3. Where should rotation live architecturally?

Four candidate locations, evaluated:

| Option | What it does | Verdict |
|--------|--------------|---------|
| **(a) Rotate RGB input before inference** | After YUV→RGB, transpose the 640×640 NHWC tensor to upright; YOLO sees upright content; boxes come out upright. | **Valid** (the TFLite-support `ImageProcessingOptions.rotation` pattern). Clean because the input is a **square** 640×640 tensor → 90°/180°/270° rotation is a lossless transpose (no aspect change, no resample). Slight extra code in the isolate's preprocessing path. |
| **(b) Rotate YUV planes before conversion** | Rotate Y/U/V planes (with chroma subsampling + strides) then run the existing converter. | **Not recommended.** Adds heavy complexity (chroma re-sampling, stride handling) for no benefit over (a); risk of new bugs in the very stage we just proved correct. |
| **(c) Rotate the preview** | Rotate only what the user sees. | **Not a fix.** Preview rotation is cosmetic and does not affect inference; YOLO still sees rotated content. |
| **(d) Rotate boxes after inference (sensor-native inference)** | Feed the sensor frame as today (converter/parser/NMS untouched), then rotate each normalized `[0,1]` box from sensor space → display-upright space after NMS. | **Recommended for this codebase.** Zero changes to preprocessing/parser/NMS; matches ML Kit's documented pattern; box rotation in `[0,1]` is exact, closed-form, and cheap. |
| **(e) Camera metadata** | Use `sensorOrientation` + device orientation to *compute* the angle. | **Required input** for every option; this is the metadata that must drive (a) or (d). |

**Recommendation:** **(d)** — keep YOLO in sensor space, transform boxes after
NMS. Rationale: the user's constraint is "do not touch preprocessing/parser/
NMS"; (d) touches nothing before the parser, is mathematically exact, and is
the industry-standard (ML Kit) pattern. (a) is the acceptable fallback if the
team prefers an upright input tensor.

## 4. Should YOLOv8 consume sensor orientation and transform boxes afterward?

**Yes.** This is the correct default for real-time mobile pipelines:

- The model is trained on upright natural images. Feeding it upright maximizes
  accuracy; but rotating the **input** and rotating the **boxes** are
  mathematically equivalent outcomes — the difference is only where the
  transform is applied.
- Sensor-native inference + box transform:
  - keeps the verified-correct preprocessing/parser/NMS untouched,
  - avoids a second pixel pass (box math is ~N boxes vs 1.2M pixels),
  - keeps the model's 640×640 input identical in both camera and static-image
    paths (only the *interpretation* of boxes changes),
  - is exactly what ML Kit's `ImageLabeler`/`ObjectDetector` ecosystem does
    (`InputImage` carries rotation; the overlay transforms boxes to display).

## 5. Would a fixed 90° rotation be incorrect on other devices?

**Yes — a fixed angle is incorrect.** `sensorOrientation` ∈ {0, 90, 180, 270}
varies by device and lens, and the required display rotation also depends on
the current device orientation. Example (back camera, portrait):

| sensorOrientation | rotation to make frame upright (portrait) |
|-------------------|-------------------------------------------|
| 0°  | 0° |
| 90° | 90° (this device) |
| 180° | 180° |
| 270° | 270° (i.e., −90°) |

A fixed 90° would render 0°/180°/270° devices and **every front camera**
incorrect (front also needs X-mirroring). The pipeline must read
`sensorOrientation` from `CameraDescription` at runtime.

## 6. Device-independent orientation pipeline (design)

### 6.1 Canonical coordinate spaces

Define exactly three spaces and one transform:

1. **Sensor space** — the YUV_420_888 frame (W_s × H_s, e.g., 320×240).
   This is what the converter, model, parser, and NMS operate on **today**.
2. **Display-upright space** — the same scene rotated so "up" matches the
   physical world as shown by the (plugin-rotated) `CameraPreview`
   (portrait → H_s × W_s, e.g., 240×320).
3. **Screen space** — the preview box pixels.

The **only** new transform is **sensor → display-upright**, applied to
normalized boxes after NMS. Preprocessing/parser/NMS remain in sensor space.

### 6.2 Rotation math (single source of truth)

Compute once per frame on the main isolate (cheap, metadata-only):

```
deviceRot = device orientation from MediaQuery/window:
            0 = portrait up, 90 = landscape-left, 180 = portrait upside-down,
            270 = landscape-right
sensorRot = CameraDescription.sensorOrientation   (0/90/180/270)

back :  R = (sensorRot − deviceRot + 360) % 360     // rotate sensor→upright
front:  R = (sensorRot + deviceRot + 360) % 360     // mirrored convention
```

Pass `R` to the isolate as a frame-field (like `cameraFps`) — a number, no
code changes to conversion.

### 6.3 Box transform after NMS (normalized [0,1], sensor → upright)

For a normalized box `(x, y, w, h)` (left, top, width, height):

```
R = 90°  (CW):   (x', y', w', h') = (1 − y − h, x,        h, w)
R = 180°        : (x', y', w', h') = (1 − x − w, 1 − y − h, w, h)
R = 270°  (CCW): (x', y', w', h') = (y,        1 − x − w, h, w)
R = 0°          : unchanged
```

Mirroring (front camera) can be folded into the same step (flip X in upright
space) **or** left to the painter's existing `lensDirection` logic — pick one
and document it. Recommendation: fold mirroring into the isolate transform so
the painter becomes a pure normalized→pixel mapper, then disable the painter's
internal mirror (single source of truth).

### 6.4 Where each stage sits (unchanged vs new)

| Stage | Space | Change |
|-------|-------|--------|
| YUV→RGB conversion | sensor | **unchanged** |
| Resize / normalize / run | sensor | **unchanged** |
| Parser / NMS / thresholds | sensor | **unchanged** |
| **Box transform (NEW)** | sensor → display-upright | add after NMS |
| Painter `imageSize` | display-upright dims (swap W/H if R ∈ {90,270}) | update `frameSize` for camera |
| Preview | display-upright (plugin already rotates) | unchanged |

### 6.5 All hold orientations + lenses (device-independent)

| Hold | deviceRot | R back (sensor 90) | R front (sensor 270) |
|------|-----------|--------------------|----------------------|
| portrait up | 0 | 90 | 270 (then mirror X) |
| landscape left | 90 | 0 | 0 (then mirror X) |
| portrait upside-down | 180 | 270 | 90 (then mirror X) |
| landscape right | 270 | 180 | 180 (then mirror X) |

Works for sensorOrientation 0/90/180/270 because everything is derived from
metadata, never hardcoded.

### 6.6 Static-image path consistency

The test-image path must pass `R = 0` (its image is already upright) so the
camera and static-image pipelines remain semantically identical after the fix
— the only difference stays the source.

## 7. Exact insertion point (for the implementation plan)

1. **`camera_screen.dart` `_processCameraImage` / frame send:** compute `R`
   (6.2) and add `'rotation': R` to the `processFrame` message. Also send the
   display-upright dims (or let the painter derive them from R).
2. **`inference_isolate.dart` frame loop:** after `_parseYolov8Output` (after
   NMS), apply the 6.3 transform to each `Detection.box` when `R != 0`.
   Parser and NMS untouched.
3. **`camera_screen.dart` build / painter:** `frameSize` for the camera =
   display-upright dims (swap sensor W/H for 90/270); `BoundingBoxPainter`
   keeps `BoxFit.contain` mapping (now operating on upright-space boxes).
   If mirror was folded into the isolate, pass `lensDirection = back` (or add
   a `mirror` flag) so boxes aren't double-mirrored.
4. **`info_panel` / metrics:** unaffected.

This keeps preprocessing, inference, parser, and painter **mathematically
consistent**: boxes are defined in the same space the painter renders, and the
preview already shows that space.

## 8. How production systems handle orientation

| System | Pattern |
|--------|---------|
| **ML Kit (Google)** | `InputImage.fromMediaImage(image, rotation)`; inference runs on the (possibly internally rotated) image; **bounding boxes are returned in the original image space and transformed by the caller's overlay using the same rotation**. Sensor-native inference + box transform. |
| **TFLite support / object detection sample** | `ImageProcessingOptions.builder().setRotation(...)` rotates the **input** for the model; result boxes are in the rotated (upright) space; the sample maps them to the display. Input-rotation pattern. |
| **Google Lens** | Not public, but consistent with the metadata-driven overlay approach: inference aligned to display via rotation transforms; UI draws in display space. |
| **Ultralytics mobile examples (Flutter/React Native)** | Rotate the camera frame to upright before inference (or rotate boxes); the model itself is orientation-agnostic but performs best on upright content. |

Net: both the "rotate input" and "rotate boxes" patterns are used in
production; the invariant is **one canonical box space, transformed exactly
once, consistent with the preview**. ML Kit's sensor-native + box-transform is
the lowest-risk match for this codebase.

## 9. Alternative explanations for the observed symptoms (ranked)

Beyond orientation, for the specific observed behavior (portrait ≈ 0
detections, landscape ≈ detections at 0.88), ranked by likelihood:

| # | Alternative | Likelihood | Evidence / why it's lower |
|---|-------------|-----------|---------------------------|
| 1 | **Orientation not applied** | **90%** | sensorOrientation 90°, no rotation code, orientation-dependent detections |
| 2 | **Painter coordinate-space mismatch (latent)** | 10% now / becomes 100% once detections exist in portrait | The painter maps *sensor-space* boxes onto the *upright* preview. This is invisible today only because portrait detections are ~0. The orientation fix must update the painter's `imageSize`/space or boxes will appear rotated/offset. |
| 3 | **Chroma order (NV12 vs NV21) on OTHER devices** | 5% (this device refuted) | Verified U-led correct on this device (warm skin (158,152,146)); vendor HALs can vary → include an optional chroma-order auto-detect for portability |
| 4 | **Limited-range YUV (16–235) on other devices** | 5% (this device refuted) | Luma verified full-range here; some devices deliver limited range → washed colors, lower confidence |
| 5 | **Low-res 320×240 + NN stretch** | 15% (quality, not on/off) | contributes to lower confidence ceiling vs static image; not the on/off switch |
| 6 | **Exposure / dark scenes** | scene-only | prior black frame-1s were covered-lens artifacts |
| 7 | **CameraX buffer reuse / plane timing** | <2% | no supporting evidence; planes stats healthy |

The implementation plan above eliminates #1 and #2 together (single transform
in one place), which is why the box-space/painter consistency (6.3–6.4) is
specified as part of the same change.

## 10. Suggested implementation order (review only — not executed)

1. Add `rotation` field to the frame message; compute `R` in
   `_processCameraImage` from `sensorOrientation` + `MediaQuery`.
2. In the isolate, after NMS, transform boxes per 6.3 (pure function +
   unit-testable with the 6.3 table).
3. Update the camera `frameSize`/painter space to display-upright dims; verify
   box alignment against the preview on all four holds + front/back.
4. Verify portrait detections match landscape parity (target: same classes at
   ≥0.8 confidence).
5. Keep the static-image path at `R = 0` and re-run the static test to confirm
   the ground-truth baseline is unchanged.
