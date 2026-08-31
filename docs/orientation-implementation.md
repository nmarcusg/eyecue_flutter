# Orientation Architecture — Implementation Summary

> **Status:** The stable v0.2.2 orientation path is implemented and on-device
> validated for back-camera portrait/static input (portrait detections at 0.91
> confidence; static-image baseline byte-identical). The current unreleased
> candidate additionally supports NCHW tensor layout, but its exact APK was not
> installed on the target phone; candidate device behavior remains unverified.
> Landscape physical-hold re-validation is deferred (convention bug already
> found & fixed, see §5).
> **Original implementation date:** 2026-08-01
> **Last reviewed:** 2026-09-01

---

## 1. Files modified

| File | Why it changed |
|------|----------------|
| [`lib/models/box_transform.dart`](../lib/models/box_transform.dart) (NEW) | The single, device-independent source of truth for ALL orientation math: metadata→rotation, upright dims, reversible normalized-box rotation, and the plugin-convention `DeviceOrientation`→degrees mapping. |
| [`lib/services/inference_isolate.dart`](../lib/services/inference_isolate.dart) | `processFrame` carries orientation metadata (`rotationDegrees`, `mirror`, `sensorOrientation`, `deviceDegrees`, `lensFacing`). The isolate rotates + optionally mirrors the square input tensor to UPRIGHT before `interpreter.run()`; the current helper supports both NHWC and NCHW layouts (parser/NMS untouched), and logs per-frame orientation diagnostics. |
| [`lib/models/tensor_rotation.dart`](../lib/models/tensor_rotation.dart) | Pure layout-aware rotation/mirroring helper for interleaved NHWC and planar NCHW buffers; unit-tested independently of the camera. |
| [`lib/screens/camera_screen.dart`](../lib/screens/camera_screen.dart) | Computes the metadata-driven rotation per frame from `controller.value.deviceOrientation` + `CameraDescription.sensorOrientation` + lens; passes it downstream; sizes the preview and the painter with the UPRIGHT image dimensions; feeds sensor/lens into `recordCamera`. |
| [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart) | Removed all sensor-orientation knowledge (`lensDirection`/mirror). The painter is now a pure normalized→pixel mapper over the upright image; it no longer needs to know the lens or rotation. |
| [`lib/services/forensic_log.dart`](../lib/services/forensic_log.dart) | Orientation-related diagnostics only: `recordOrientation` (per-frame) and sensor/lens fields in `recordCamera`. No other logging touched. |

## 2. Why each change

1. **BoxTransform** — centralizes the math so there is exactly ONE place where
   orientation is translated into angles and box transforms; everything else
   consumes it. No duplication.
2. **Isolate tensor rotation** — the model/parser/NMS code is unchanged; the
   only difference is that the pixels fed to the model are pre-rotated to
   upright. This is the mechanism that makes portrait detection actually work
   (a post-NMS box transform alone cannot — see §4).
3. **Camera screen** — computes `rotationDegrees` from the SAME
   `controller.value.deviceOrientation` that `CameraPreview` uses for its own
   rotation, so painter and preview agree by construction.
4. **Painter** — after the isolate emits upright boxes and the screen passes
   upright `imageSize`, the painter needs no orientation knowledge at all.
5. **Forensic** — satisfies the diagnostics requirement (sensor/device/
   rotation/mirror/dims per frame) without touching other logging.

## 3. How the rotation mathematics works

### 3.1 Rotation computation (metadata-driven, no hardcoded angles)

```
deviceDegrees = BoxTransform.deviceDegreesFor(controller.value.deviceOrientation)
                portraitUp → 0, landscapeLeft → 90, portraitDown → 180, landscapeRight → 270

R = displayRotationDegrees(sensorOrientation, deviceDegrees, isFront)
    back : (sensorOrientation − deviceDegrees + 360) % 360
    front: (sensorOrientation + deviceDegrees + 360) % 360      (+ display X-mirror)
```

The `DeviceOrientation`→degrees mapping uses the camera plugin's own
counter-clockwise convention (verified against
`camera_android_camerax._getRotationConstantFromDeviceOrientation`):
**landscapeLeft→90, landscapeRight→270.** Using the naive clockwise mapping
(landscapeRight→90) produces R=180 instead of 0 in landscape — the bug found
on-device and fixed.

### 3.2 Pipeline (single canonical space)

```
YUV_420_888 (sensor) ──_convertYUV420toRGB──▶ 640×640 NHWC or NCHW (sensor)
        │
        ▼  (new, only orientation code)
rotate/mirror the square tensor by R  ──▶  UPRIGHT input
        ▼
interpreter.run() ─▶ parser ─▶ NMS        (UNCHANGED)
        ▼
boxes are already in UPRIGHT normalized [0,1] space
        ▼
painter maps normalized → pixels over upright imageSize (no orientation logic)
```

- The square 640×640 tensor makes 90°/180°/270° rotations lossless transposes;
  [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) applies the same
  logical transform to interleaved NHWC and planar NCHW storage.
- Mirroring (front camera) is applied in the upright space (X-flip), matching
  the plugin's mirrored front preview (verified equivalent to the plugin's
  orientation-dependent sensor-space mirror).
- Boxes after NMS are already in the same space the painter renders — no
  second transform, no duplication.

### 3.3 Reversible box transform (kept per requirement, used at R=0)

[`BoxTransform.rotateRect`](../lib/models/box_transform.dart) / `invertRect` are
the pure, mutually-inverse normalized-box rotations (90°/180°/270° formulas
with `(x,y,w,h)→(1−y−h,x,h,w)` etc.). They are exercised at rotation 0 in the
pipeline and are available for unit tests / any future sensor-space consumer.

### 3.4 Upright dimensions

`uprightDims(w,h,R)`: 90°/270° → `(h,w)`; 0°/180° → `(w,h)`. The camera
screen uses these for the preview `SizedBox` and the painter's `imageSize`
(e.g., portrait: 240×320 fills the 3:4 preview; landscape: 320×240 letterboxed
top/bottom) — so preview and painter always share one rect.

## 4. Deliberate deviation from requirement 2 (explained)

Requirement 2 said "inference in sensor-space … transform boxes after NMS."
Requirement 6 says "portrait detection quality must match landscape." These are
**physically incompatible**: on-device evidence proved the model sees a
90°-rotated scene in portrait → 0 detections, so there are no boxes to
transform. A post-NMS box transform fixes alignment but cannot fix detection.
**The input is therefore rotated to upright** (the only design satisfying
req 6). Parser/NMS code is unchanged; the "single canonical coordinate
system" is the upright space; the standalone reversible helper
(`BoxTransform`) holds all the math, exactly as req 2's "single pure helper,
no duplication" intended.

## 5. Device independence

- Angles come from `sensorOrientation` (0/90/180/270, per-lens metadata),
  `controller.value.deviceOrientation` (all four holds) and lens direction —
  never hardcoded.
- The mapping matches the plugin's own convention, so it works with
  `camera_android_camerax`, `camera_android`, and iOS (all expose
  `sensorOrientation` + device orientation; iOS has no mirror for the back
  camera and the same formula applies).
- Front camera mirroring is folded into the single tensor step.
- The stable static-image path passes rotation 0 / no mirror → identity →
  verified byte-identical on-device (person 0.9173, 5 detections, same as
  baseline). The current NCHW candidate has initial short live on-device
  evidence, but no formal orientation, accuracy, or comparative performance
  validation yet.

## 6. Validation status

| Case | Status |
|------|--------|
| Back · portrait | ✅ detections at maxConf 0.91 (was 0); `rot=90 in=320×240 out=240×320`; input rotation byte-exact (MAE 0.000) |
| Back · landscape | Convention bug found & fixed; physical-hold re-validation deferred to next session |
| Front · portrait / landscape | Math implemented (verified against plugin convention); device run pending |
| Static-image regression | ✅ `rot=0`, identical detections (person 0.9173, 5 objects) |
| NCHW tensor rotation | ✅ Pure helper covered by unit tests; candidate exercised in a short portrait live run; landscape/front-camera device validation pending |
| `flutter analyze` | ✅ 0 issues |
