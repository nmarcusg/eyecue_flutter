# Static-Image Test — Camera Removed From the Equation

> **Status:** COMPLETE — evidence collected on-device (Android 13, arm64).
> **Date:** 2026-08-01
> **Temporary mode:** `InferenceService.useTestImage` (`lib/services/inference_isolate.dart`)
> **Test image:** `assets/test_image.jpg` — the canonical YOLO validation photo
> (`bus.jpg` from ultralytics, 810×1080, contains **1 bus + 4 people + 1 dog**).

> **Historical snapshot notice (2026-09-01):** This test report predates the
> current candidate-device retry. Its static-image conclusions remain valid;
> current model/backend status is tracked in [`project-status.md`](project-status.md).

---

## 1. Goal

Remove the camera completely and answer, using a known-good RGB image fed
through the **exact same pipeline**:

1. Does the model correctly detect the expected COCO objects?
2. If not — is the failure in parser / labels / preprocessing / output
   interpretation?
3. If yes — the remaining bug is isolated to the camera preprocessing path.

## 2. Design (what was changed)

The **only** difference between camera mode and test-image mode is the image
source. Everything after acquisition is byte-for-byte identical.

```
CAMERA MODE:        CameraImage (YUV420 planes) ─┐
                                                 ├─▶ processFrame()
TEST-IMAGE MODE:    assets/test_image.jpg ──decode──▶ RGBA ──rgbaToI420()──▶ I420 planes ─┘
                                                          │
                                              (source adapter ONLY — the same
                                              3-plane interface CameraImage exposes)
                                                          ▼
                          _convertYUV420toRGB → resize(640×640) → normalize → interpreter.run()
                                          → _parseYolov8Output (threshold 0.25 + class-wise NMS IoU 0.45)
                                          → _logDetections → ForensicLog → painter
```

* The test image is converted to **I420 YUV planes** (full-range BT.601, the
  exact inverse of the converter's coefficients) and pushed through the same
  `processFrame()` entry point as the camera.
* **No preprocessing code is duplicated.** `_convertYUV420toRGB`, resize,
  normalization, `interpreter.run()`, parser, NMS, and painter are all reused.
* The isolate has **no** special test-image branch — the frame arrives as a
  normal camera-style frame message.
* The screen renders the asset image in the same 3:4 contain-fit preview box
  with the identical `BoundingBoxPainter` overlay.

Files touched (all temporary/diagnostic):
| File | Change |
|------|--------|
| `lib/services/input_probe.dart` | removed duplicated `testImageToInputBuffer`; added `rgbaToI420()` source adapter |
| `lib/services/inference_isolate.dart` | `useTestImage=true`; `runTestImage()` builds I420 planes → `processFrame()`; removed the old Float32List `test_image` branch; parser now also reports pre-NMS candidate count |
| `lib/screens/detection_screen.dart` | test mode renders the asset image + painter instead of a spinner |
| `pubspec.yaml` | added `assets/test_image.jpg` |

To disable: set `InferenceService.useTestImage = false`.

## 3. On-Device Results (Android 13, arm64 — the exact device that shows "Objects: 0" on camera)

### 3.1 Model load (runtime introspection)
```
Model        : yolov8n.tflite            (weight-quantized, FP32 I/O)
Input  shape : [1, 640, 640, 3]  type: float32
Output shape : [1, 84, 8400]     type: float32   (features-major, 80 classes)
Classes: 80   Anchors: 8400   Needs in-quant: false   Needs out-dequant: false
```

### 3.2 Inference result (full pipeline, identical to camera)
```
[Detection] Frame #1 | Objects: 5 (candidates(before NMS)=44 → after NMS=5)

  1. person 91.7%   box norm [left=0.276 top=0.377 w=0.150 h=0.418]
  2. person 90.7%   box norm [left=0.828 top=0.356 w=0.170 h=0.452]
  3. person 88.8%   box norm [left=0.067 top=0.369 w=0.226 h=0.469]
  4. bus    86.7%   box norm [left=0.012 top=0.210 w=0.981 h=0.486]   ← spans full frame width
  5. person 47.0%   box norm [left=0.000 top=0.511 w=0.093 h=0.296]
```

The **bus** box (0.981 wide, centered) and the four **person** boxes match the
ground-truth layout of `bus.jpg` (people standing left/center/right of the bus).

### 3.3 Parser forensics (`parser.txt`, on-device)
```
anchor 8227 person 0.9173 rawBox=[cx=0.3511 cy=0.5860 w=0.1496 h=0.4179] decoded=[0.2762,0.3771,...]
anchor 8189 bus    0.8672 rawBox=[cx=0.5026 cy=0.4532 w=0.9811 h=0.4865] decoded=[0.0121,0.2100,...]
detections after threshold(0.25)+NMS: 44
```
Boxes are already normalized `[0,1]` by the graph (op 249 `×1/640`), parser
decodes them correctly — matches the static graph analysis.

### 3.4 Preprocessing forensics (`preprocess.txt`, on-device)
```
Source: 810x1080 → Target: 640x640 (NHWC)
R mean=0.4605  G mean=0.4523  B mean=0.4629  (spread 0.0106, not flat/black/white)
After normalization: min=0 max=1 mean=0.4586  negatives=0  (>1)=0
errors.txt: (empty)
```

### 3.5 Image-round-trip verification (independent, quantitative)
* Source vs on-device reconstructed RGB (`frame_rgb.png`): **MAE=1.785,
  PSNR=36.9 dB** — the RGB→I420→YUV→RGB round-trip on-device preserves the
  scene (4:2:0 chroma subsampling is the only loss).
* `frame_resized` vs `frame_model_input` (on-device dumps): **MAE=0.000** —
  the resize stage and final tensor are byte-identical.
* Nearest-neighbor 640×640 stretch (Dart rounding) vs `frame_model_input`:
  MAE=2.07 — matches within the expected chroma round-trip tolerance.
* Gemini vision on `frame_rgb.png`: *"A recognizable natural scene depicting a
  blue and white city bus and pedestrians walking along a city street… Bus,
  People/Pedestrians, Building with windows, Sidewalk, Bollards, Trees."*

### 3.6 Painter verification (on-device)
```
[Painter] Screen 392×523  Image 810×1080  Scale 0.484×0.484  Mirror false
[Painter] Rendered #1 "person": (108,197)-(167,416) [norm 0.28,0.38 0.15×0.42]
```
Box mapping is mathematically exact (392×0.276=108, 523×0.377=197, …).

## 4. Conclusion

**The model, parser, NMS, confidence threshold, label mapping, and painter all
work correctly on the actual Android device.** With a known-good RGB image
flowing through the identical post-acquisition pipeline, the model detects the
expected COCO objects (bus + people) at high confidence (0.47–0.92), with sane
pre-NMS (44) and post-NMS (5) counts and correctly placed boxes.

Therefore the remaining "Objects: 0" bug in camera mode is **isolated to the
camera preprocessing path** — specifically, the YUV420 planes that `CameraImage`
delivers on this device do not match what `_convertYUV420toRGB` consumes.
Candidates (to be confirmed by `camera.txt` on a camera run):
* plane format/layout mismatch (3-plane I420 vs 2-plane semi-planar),
* real `rowStride`/`pixelStride` differing from the tightly-packed assumption,
* rotation/EXIF orientation not applied before inference.

This is consistent with (and now empirically confirms) the earlier H8 diagnosis
in `docs/inference-pipeline-probe.md`.

## 5. How to reproduce

```
# 1. (already set) enable the mode
#    lib/services/inference_isolate.dart  →  static const bool useTestImage = true;
flutter run -d <device>          # camera is skipped; test image runs once
# watch for: [Detection] Frame #1 | Objects: 5 (candidates(before NMS)=44 → after NMS=5)
# forensic run: <app_docs>/debug/run_*/  (preprocess.txt, output.txt, parser.txt, frame_*.png)

# 2. restore camera mode
#    lib/services/inference_isolate.dart  →  static const bool useTestImage = false;
```
