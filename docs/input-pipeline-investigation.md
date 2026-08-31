# Input Pipeline Investigation — Why max confidence ≈ 0.05

> **Status:** Historical forensic investigation record. No pipeline behavior was
> changed as part of this report.
> **Temporary instrumentation:** [`lib/services/input_probe.dart`](../lib/services/input_probe.dart)
> (`[InputProbe]` prefix) + a test-image debug mode behind one boolean flag.
> **Date:** 2026-08-01
> **Related:** [`inference-pipeline-probe.md`](inference-pipeline-probe.md) (parser-side forensics).

> **Historical snapshot notice (2026-09-01):** This report captures the
> pre-candidate input investigation. The current pipeline includes the later
> geometry, orientation, and ByteBuffer fixes; current candidate status is
> tracked in [`project-status.md`](project-status.md).

---

## 1. Investigation Summary

The parser, model graph, tensor layout, and sigmoid handling have all been
verified correct (see [`inference-pipeline-probe.md`](inference-pipeline-probe.md)).
The remaining known fact is:

> **Maximum model confidence is ≈ 0.05 → detection count is always 0.**

A sigmoid confidence of ~0.05 means the model is *confidently saying "nothing
here"* for every anchor — it is not merely uncertain. That is the classic
signature of a **low-information / degenerate input image** (near-uniform,
near-black, or structurally broken), or of a **broken output readback** that
returns near-constant tiny values.

This report instruments every stage between `CameraImage` and
`interpreter.run()` so the exact failing stage can be pinned with one device run.

---

## 2. Instrumentation Added (temporary, removable)

| Probe | Stage | Runs on | Logs |
|-------|-------|---------|------|
| `[InputProbe A]` | `CameraImage` plane geometry | main isolate, once | per-plane `bytesLen`, `rowStride(bytesPerRow)`, `pixelStride(bytesPerPixel)`, plane W/H, inferred format (I420 / NV21-NV12 / UNKNOWN) |
| `[InputProbe B]` | after YUV→RGB | isolate, frame 1 | per-channel R/G/B min/max/mean/std + health flags (near-identical channels, near-black, near-white) |
| `[InputProbe C]` | resize | isolate, frame 1 | src→dst→expected tensor resolution + resized min/max/mean |
| `[InputProbe D]` | normalization | isolate, frame 1 | min/max/mean/std; flags: all-zero, all-one, values >1, mean outside 0.3–0.7 |
| `[InputProbe E]` | input tensor before `run()` | isolate, frame 1 | dtype, len vs expected, min/max/mean, first 32 / last 32 / random 32 values, quantization range if quantized |
| `[InputProbe F]` | known-image cross-check | isolate, on demand | max confidence, top-20 classes, detection count for a known asset photo |
| `[InputProbe G]` | output top-k | isolate, frame 1 + test image | top-20 `(anchor, label, confidence)` |
| `[InputProbe H]` | output distribution | isolate, frame 1 + test image | max/mean/median/p95/p99 of per-anchor max scores + counts `>0.01/0.05/0.10/0.25/0.50` |

**How to run:** `flutter run` on the device. For the test-image mode, flip
`InferenceService.useTestImage = true`
([`inference_isolate.dart`](../lib/services/inference_isolate.dart)),
place a real photo of a COCO object at `assets/test_image.jpg`, add it to the
`pubspec.yaml` assets list, and restart. The camera path still runs all other
probes.

---

## 3. Phase-by-Phase Findings & Interpretation

### Phase A — CameraImage validation (what the device actually delivers)

The code currently assumes **3-plane planar I420** and indexes
`image.planes[1]`/`[2]` for U/V, ignoring `bytesPerRow`/`bytesPerPixel`
(the camera package's names for `rowStride`/`pixelStride`). Android
`ImageFormatGroup.yuv420` (`raw == 35`, YUV_420_888) can be delivered as:

- **3 planar planes** (I420/YV12) — U and V have `bytesPerPixel == 1`.
- **2 planes** (NV21/NV12 semi-planar) — the U/V chroma is **interleaved**
  (`bytesPerPixel == 2`) and `planes[2]` does **not exist**.

**Interpretation matrix:**

| `[InputProbe A]` result | Meaning |
|---|---|
| `planes=3`, U/V `pixelStride=1` | I420 planar — current indexing is at least structurally right |
| `planes=2` or U/V `pixelStride=2` | **Semi-planar NV21/NV12 — the current U/V indexing is WRONG** (it would read interleaved bytes as planar, producing a color-smeared image) |
| `planes=3`, U/V `pixelStride=2` | Semi-planar reported as 3 planes — same mismatch |
| `rowStride != width` | The Y-row indexing `srcY*width + srcX` is misaligned (ignores padding) |

If the camera delivers a format the code does not expect, the converted RGB is
garbage — consistent with maxConf ≈ 0.05.

### Phase B — Per-channel R/G/B stats (first frame)

Healthy natural image (normalized): R/G/B means each in roughly 0.2–0.7 with
**different** channel distributions.

| Flag | Meaning |
|---|---|
| "ALL CHANNELS NEARLY IDENTICAL" | No color information — either a grayscale/black image or chroma is broken |
| "ALL CHANNELS ~0" | Near-black input (e.g., Y plane zeroed / wrong plane sampled) |
| "ALL CHANNELS ~1" | Saturated input |

### Phase C — Resize

Logs `srcW×srcH → 640×640` and the resized min/max/mean. The app uses a
nearest-neighbor **stretch** (no letterbox). A correct stretch still preserves
structure; a broken source yields flat stats here.

### Phase D — Normalization

Expected: `min ≈ 0, max ≈ 1, mean ≈ 0.3–0.7`. Flags for all-zero, all-one,
values >1, or mean outside range. The float path writes `rgb/255.0`, so this
phase verifies the buffer actually received normalized data.

### Phase E — Input tensor immediately before `run()`

Logs dtype, length vs expected, min/max/mean, first/last/random 32 values. This
confirms **exactly which bytes** the interpreter receives. If the buffer is all
zeros here, the problem is upstream (conversion). If it looks like a real image,
the problem is not the input buffer.

### Phase F — Known-image cross-check (the decisive test)

Runs one inference on a **known good photo** (RGBA→RGB, nearest-neighbor
640×640, [0,1], NHWC — the same downstream path as the camera, bypassing only
YUV decoding).

| Result | Conclusion |
|---|---|
| Test image → healthy top-20 (maxConf > 0.5, plausible classes) | **Camera preprocessing is definitively the bug** (YUV/format/plane handling) |
| Test image → also ≈0.05 | The bug is **not** camera preprocessing — it is in the model/runtime/output-readback path (or the resize/normalize in the shared path) |

This single test splits the search space in half.

### Phase G — Top-20 confidences

Distinguishes "all confidences low but sensible classes" (model sees something
vague) from "nonsensical labels at 0.05" (input unrelated to the class space).

### Phase H — Confidence distribution

- **Healthy:** max > 0.5, mean per-anchor ≈ 0.05–0.2, p99 > 0.5, counts at
  `>0.5` ≥ 1.
- **Flat/degenerate:** max ≈ 0.05, p99 ≈ 0.05, counts at `>0.5` == 0.

`[InputProbe H]` prints an explicit verdict line (`FLAT/LOW` vs `HEALTHY`).

---

## 4. Phase I — Comparison Against Official Ultralytics Preprocessing

Official YOLOv8 inference preprocessing (`ultralytics`, `LetterBox` +
`v8_transforms` + `classify_transforms`). **Differences are reported only —
nothing was changed.**

| Aspect | Ultralytics (official) | This app | Same? |
|--------|------------------------|----------|-------|
| Color order fed to model | **RGB** (OpenCV BGR converted to RGB) | RGB (r,g,b computed from YUV) | ✅ Same |
| Resize algorithm | `cv2.resize` **INTER_LINEAR (bilinear)** | **Nearest neighbor** (`.round()`) | ❌ Different (minor quality) |
| Aspect ratio handling | **Letterbox**: preserve AR, pad with gray `(114,114,114)` to 640×640 | **Direct stretch** to 640×640, no padding | ❌ Different (distorts AR; does not zero confidences) |
| Normalization | `img / 255` → [0,1] | `rgb / 255.0` → [0,1] | ✅ Same |
| Channel order / tensor layout | HWC internally; `ascontiguousarray(transpose(2,0,1))` → CHW for torch; **TFLite export expects NHWC** | NHWC `[1,640,640,3]` interleaved | ✅ Same (NHWC) |
| Contiguous memory | `np.ascontiguousarray` | `Float32List` (contiguous) | ✅ Same |
| uint8 → float | `astype(np.float32)` after `/255` | floats written directly | ✅ Same |
| Letterboxing | Yes (114 padding) | No | ❌ Different (see above) |
| Color source | Direct RGB from decoded camera | YUV420 → RGB via BT.601-style coefficients | ⚠️ Same intent, documented slight color shift |

**Phase I conclusion:** the two *algorithmic* differences (no letterbox,
nearest-neighbor) degrade quality but **cannot** produce a maxConf of 0.05 on a
normal scene — a stretched, nearest-neighbor-resized photo of a person is still
recognizably a person to YOLOv8. The normalization, channel order, layout, and
contiguity all match. This redirects suspicion to the **raw pixel data itself**
(Phase A/B) or **output readback** (Phase E/G/H), not to the resize/normalize
math.

---

## 5. Ranked List of Most Likely Root Causes

Ranking after all available evidence (static analysis + instrumentation plan).
The exact split will be finalized by one device run; the probes listed after
each item are the ones that confirm it.

1. **~45% — Camera YUV format/layout mismatch (semi-planar vs planar).**
   The code assumes 3-plane planar I420 and ignores `bytesPerRow`/`bytesPerPixel`
   (`rowStride`/`pixelStride`). If the device delivers NV21/NV12 (2 planes or
   `pixelStride==2`) the decoded RGB is color-smeared/garbage → model sees
   low-information input → maxConf ≈ 0.05.
   *Confirm:* `[InputProbe A]` (plane geometry/format), `[InputProbe B]`
   (channel stats), `[InputProbe F]` (test image healthy ⇒ camera guilty).

2. **~25% — Output readback returns near-constant low values.**
   If the output buffer comes back flat (max ≈ 0.05, p99 ≈ 0.05) while the test
   image also fails, the failure is in `interpreter.run()` / the buffer path,
   not the camera.
   *Confirm:* `[InputProbe F]` (test image also flat), `[InputProbe H]`
   (FLAT verdict), `[InferenceProbe P3]` (`allZero`/max from the prior probe).

3. **~15% — Degenerate camera pixels (near-black / all-same) from a source the
   converter cannot use** (e.g., zeroed Y plane, wrong `image.width/height` vs
   plane geometry, rotation/layout mismatch).
   *Confirm:* `[InputProbe B]` (all channels ~0 / identical), `[InputProbe D]`
   (all-zero), `[InputProbe E]` (input buffer flat).

4. **~10% — Resize/normalize edge case** (e.g., buffer length mismatch, wrong
   dst dims). Low likelihood — the math matches ultralytics.
   *Confirm:* `[InputProbe C/D/E]` (length, min/max/mean, first/last values).

5. **~5% — Model/runtime issue on device** (e.g., CPU-only XNNPACK-disabled
   path producing weak activations on this hardware). Low likelihood — static
   graph inspection shows a standard YOLOv8n.
   *Confirm:* `[InputProbe F]` fails with a healthy input, `[InputProbe H]`
   flat, `[InputProbe E]` input healthy.

> **Decision shortcut:** run Phase F first. If the known photo detects objects,
> the bug is in camera preprocessing (causes #1/#3). If it does not, the bug is
> in the shared model/output path (causes #2/#5), and the input probes will
> then pinpoint where.

---

## 6. Confirmed-but-non-fatal Observations (from this phase)

- **No letterbox** and **nearest-neighbor** resize (vs ultralytics bilinear +
  gray padding): quality-only differences, documented in §4. They will matter
  after detection is restored, not before.
- Box coordinates are decoded to **pixel space (0–640)** by the graph but
  clamped to [0,1] by the parser — a rendering bug, not a count bug
  (already reported in [`inference-pipeline-probe.md`](inference-pipeline-probe.md)).

---

## 7. How to Remove the Instrumentation

1. Delete [`lib/services/input_probe.dart`](../lib/services/input_probe.dart).
2. In [`inference_isolate.dart`](../lib/services/inference_isolate.dart) and
   `camera_screen.dart` (the historical screen name): remove the
   `input_probe.dart` import, all `InputProbe.*` calls, the `useTestImage` /
   `testImageAsset` fields, `runTestImage()` / `_loadTestImageInput()`, the
   `test_image` handler, and the `_ready` completer.
3. Remove `assets/test_image.jpg` (if added) from `pubspec.yaml` assets.
4. `flutter analyze` returns to baseline.
