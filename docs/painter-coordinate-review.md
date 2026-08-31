# Painter ↔ Preview Coordinate-Space Review

> **Status:** Mathematical investigation only — NO code changes.
> **Date:** 2026-08-01
> **Evidence sources:** live camera run `run_20260801_194628` (painter logs,
> PID 24472), static-test run `run_20260801_185906` (PID 5415), Flutter
> `camera 0.12.0+1` + `camera_android_camerax 0.7.3` plugin sources (from the
> pub cache), and the then-current `camera_screen.dart` /
> `bounding_box_painter.dart` implementation.
>
> **Historical snapshot notice (2026-09-01):** The former `camera_screen.dart`
> was later retired and removed in favor of [`detection_screen.dart`](../lib/screens/detection_screen.dart).
> The measurements and conclusions below remain a record of the implementation
> examined at the time.

---

## 1. Verdict (preview of the conclusion)

- The painter uses `imageSize = 320×240` (the **sensor/landscape** frame), **not**
  portrait dimensions. **Hypothesis #9 is DISPROVEN.**
- The painter's transform is **numerically identical** to the app's own
  `FittedBox(BoxFit.contain)` layout: both produce image rect
  **(0, 114.5) → (392, 408.5)** for the landscape case (verified to the
  painter's logged `(0,114)-(392,409)`).
- The static-image test (identical `FittedBox` + painter, but with
  `Image.memory` instead of `CameraPreview`) is **pixel-perfect** — proving the
  painter + FittedBox + SizedBox chain is mathematically correct.
- Therefore, in **landscape**, any residual box inaccuracy is **not** explained
  by the painter-vs-FittedBox transform (they are the same). It must come from
  one of:
  1. the extra transforms `CameraPreview` inserts that the painter does **not**
     model (AspectRatio + RotatedBox + camerax rotation correction), and/or
  2. model localization error on the low-res (320×240) nearest-neighbour
     stretched camera frames, and/or
  3. analysis-stream vs preview-stream content differences.

A decisive experiment is specified (§8) to separate these.

---

## 2. Current widget tree and the two "images"

```
SizedBox(previewWidth=392, previewHeight=523)          // 3:4 portrait box
  Stack(fit: StackFit.expand)
    FittedBox(fit: BoxFit.contain)                      // app-level fit
      SizedBox(width: 320, height: 240)                 // = CameraImage dims
        CameraPreview                                    // ← static test used Image.memory here
    CustomPaint(painter: BoundingBoxPainter(...))        // canvas = same 392×523
```

Two different "image" widgets occupy the inner `SizedBox(320×240)`:

| Path | Inner widget | Fills 320×240 exactly with the raw frame? |
|------|--------------|-------------------------------------------|
| Static test | `Image.memory(...)` | **Yes** — trivial fill, verified pixel-perfect |
| Camera | `CameraPreview` = `AspectRatio` → `Stack(expand)` → `RotatedBox(preapplied)` → camerax `RotatedPreviewDelegate` (another `RotatedBox`/`Transform`) → `Texture` | **Not a plain fill** — orientation-dependent transforms interposed |

This structural difference is the **only** difference between the perfect
static overlays and the offset camera overlays, and it is the primary suspect.

## 3. Question-by-question answers with computed values

### Q1 — CameraImage dimensions
`image.width = 320`, `image.height = 240` (verified in `camera.txt`, every run).
These are **sensor-native landscape** dims, unchanged by device orientation.

### Q2 — Tensor dimensions and normalized box space
- Model input `[1, 640, 640, 3]` (square — the 4:3 frame is **stretched**, not
  letterboxed, by `_convertYUV420toRGB`).
- Parser/NMS output: boxes normalized `[0,1]` over the 640×640 stretched space.
- Per-axis uniform scaling preserves normalized coordinates:
  `dstY/640 = srcY/srcH`, `dstX/640 = srcX/srcW` (nearest-neighbour stretch is
  a per-axis linear map). So a normalized box is also valid over the source
  frame and over the preview. **The stretch does not by itself break the
  normalized mapping.**

### Q3 — Preview layout (computed)
- `LayoutBuilder` → maxPreviewHeight = `constraints.maxHeight − 260` (panel).
- previewWidth = `min(constraints.maxWidth, maxPreviewHeight × 3/4)` = **392**
  (measured); previewHeight = 392 / (3/4) = **523** (measured).
- `FittedBox(contain)` of the 320×240 child into 392×523:
  - scale = min(392/320, 523/240) = min(1.225, 2.179) = **1.225**
  - destination = 392 × **294**
  - offset = (0, (523−294)/2) = **(0, 114.5)**
  - child rendered at **(0, 114.5)–(392, 408.5)** (letterboxed top/bottom).

### Q4 — BoundingBoxPainter's assumed space (measured from live logs)
```
[Painter] Screen : 392×523        ← canvas = preview box
[Painter] Image  : 320×240        ← imageSize = sensor dims (NOT portrait)
[Painter] Scale  : 1.23×1.23      ← scaleX = 392/320 = scaleY = 294/240 = 1.225
[Painter] Image rect: (0,114)-(392,409)   ← applyBoxFit(contain) of 320×240
```
- source rect = 320×240, destination rect = 392×294, translation (0, 114.5).
- **This is exactly Q3's FittedBox result (verified numerically, §7).**
- The painter assumes the preview renders the raw 320×240 frame inside that
  rect, unrotated. That is true for `Image.memory` (static test — perfect) and
  **only approximately true for `CameraPreview`**.

### Q5 — Full per-detection walkthrough (real detection: "refrigerator", landscape)
```
YOLO normalized box : x=0.16  y=0.03  w=0.81  h=0.90
↓ sensor pixels (320×240)      : (51.2, 7.2)–(310.4, 223.2)
↓ painter (imageRect 392×294 @ (0,114.5)):
    left  = 0.16×392          = 62.7
    top   = 114.5 + 0.03×294  = 123.3
    width = 0.81×392          = 317.5
    height= 0.90×294          = 264.6
    → painted (62.7,123.3)–(380.2,387.9)
Painter logged                 : (61,123)–(377,389)   ← matches (rounding only)
Expected rectangle             : requires ground-truth object position in the
                                 live frame — NOT derivable from the logs (the
                                 dumped frame ≠ the frame of this detection).
```
The painter transform is internally exact; the "expected" rectangle can only be
established by the §8 experiment (known content on screen).

### Q6 — imageSize vs actual frame orientation
`imageSize = 320×240` = **sensor landscape** (matches `CameraImage`).
The painter is therefore in **sensor space**. It is **not** swapped to
240×320 and does not apply any rotation. So: CameraImage 320×240 ✓ painter
320×240 ✓ — but the **preview** (CameraPreview) may show the feed rotated
per device orientation (see Q7), which the painter does not mirror.

### Q7 — Is the preview showing sensor-space or display-space?
`CameraPreview` shows **display-upright space**: it inverts its `AspectRatio`
in portrait and applies `RotatedBox` quarter-turns (and the camerax plugin
applies a compensating rotation) so the feed appears upright for the current
device orientation. In **landscape** the plugin's rotation math is designed to
net to **0°** (sensor frame shown unrotated), which is why landscape overlays
are "close". In **portrait** the preview shows the frame upright while the
painted boxes are still in sensor space — a 90° inconsistency (this is the
already-documented orientation defect, and it also affects painter alignment in
portrait once detections exist).

### Q8 — applyBoxFit used identically by preview and painter?
- The app-level `FittedBox(contain)` and the painter both call
  `applyBoxFit(BoxFit.contain, 320×240, 392×523)` → identical result
  (verified §7). **At the app level they match.**
- BUT the preview **additionally** has `CameraPreview`'s internal
  `AspectRatio` (aspect depends on orientation) + `RotatedBox` + the camerax
  correction. These extra transforms are **not** replicated by the painter.
  In landscape they are intended to cancel to identity; any residual
  (orientation timing, display-rotation mapping, FutureBuilder async
  correction) is invisible to the painter.

### Q9 — "Painter uses portrait dims while detections are landscape"?
**DISPROVEN.** Evidence:
- Painter logged `Image: 320×240` (landscape), not 240×320.
- `frameSize = Size(_imageWidth=320, _imageHeight=240)` from `camera_screen.dart`.
- If the painter had used portrait 240×320, `applyBoxFit` would yield a
  destination of 392×522.7 (full-height) with a **different** letterbox, and
  the logged image rect would differ from `(0,114)-(392,409)`.

### Q10 — Ranked causes of the residual landscape inaccuracy

| # | Cause | Confidence | Evidence |
|---|-------|-----------|----------|
| 1 | **Residual `CameraPreview` transform not modeled by the painter** (AspectRatio/RotatedBox/camerax correction; net ≠ exact identity in practice, e.g., device-orientation timing, display-rotation mapping, async correction) | **40%** | The only structural difference vs the pixel-perfect static path; painter cannot see it |
| 2 | **Model localization error on stretched low-res frames** (4:3→1:1 stretch at only 320×240 with nearest-neighbour upscale → systematic box bias, especially vertical: 2.67× vs 2.0×) | **35%** | Static (810×1080, crisp) is pixel-perfect; camera (320×240, noisy, stretched) drifts; deterministic, hence "consistent" |
| 3 | **Analysis-stream vs preview-stream content mismatch** (separate CameraX use cases; possible timing lag / different crop) | **15%** | Both streams report 320×240; content timing not measured |
| 4 | Painter imageSize/rect/letterbox errors | **<5%** | Numerically refuted (§7) + static test perfect |
| 5 | Missing orientation transform | **<5% for this landscape symptom** | Rotation ≈ 0 in landscape; it is the portrait cause, not the landscape offset |
| 6 | width/height swapped, canvas origin, clipping | **<5%** | Refuted by the exact logged math |

---

## 4. The exact point of divergence (mathematical statement)

Let `T_fit` = `applyBoxFit(contain, 320×240, 392×523)` (app FittedBox = painter).

Static path: rendered content = `T_fit(Image.memory)` → content rect == painter
rect → **overlay exact** (proven).

Camera path: rendered content = `T_fit( CameraPreview )`, where
`CameraPreview = AspectRatio(o) ∘ RotatedBox(p) ∘ correction(r) ∘ Texture`,
with `o` (aspect) and `p` (quarter-turns) depending on `deviceOrientation`, and
`r` from the camerax display-rotation math. The painter models only `T_fit`.
**Divergence occurs iff `AspectRatio(o) ∘ RotatedBox(p) ∘ correction(r)` ≠
identity over the inner 320×240 box.**

In landscape the plugin *intends* `p + r = 0`; in portrait `p + r = 90°`
(and aspect flips), which is precisely the orientation bug already
documented. The landscape residual (if `p + r ≠ 0`) is a small rotation/scale
error that reads as a consistent offset.

## 5. Why the static test cannot exonerate the camera path

The static test proves `T_fit` + painter + normalized-space decoding are
correct. It does **not** exercise `CameraPreview`'s internal transforms, nor
the 320×240-quality/stretch model input. Both remain candidate contributors to
the landscape offset.

## 6. Remaining evidence needed (specify, do not implement)

| Diagnostic | File / function | Exact values | Why it decides |
|-----------|-----------------|--------------|----------------|
| Log the camera-preview's actual rendered rect on screen | `camera_screen.dart` build (wrap `CameraPreview` in a keyed `LayoutBuilder`/`GlobalKey` and report its `RenderBox` size/position within the Stack) | `previewBox=(392,523)`, `fittedChildRect`, `cameraPreviewRect=(x,y,w,h)` | Proves whether the feed lands at (0,114.5)–(392,408.5) or elsewhere (cause #1) |
| Same-content cross-check: display the static `bus.jpg` on a monitor, run camera mode | capture normalized boxes for the bus/person; compare with static-test normalized boxes | per-object `(x,y,w,h)` both modes | Identical boxes ⇒ model sees same content ⇒ offset is on-screen transform (#1). Different boxes ⇒ camera input quality/stretch (#2) |
| Analysis-vs-preview stream lag | timestamp analysis frame at receipt and preview frame at display | delta in ms | Tests cause #3 |

## 7. Numeric appendix (replicating `applyBoxFit`)

```
LANDSCAPE contain(320×240 → 392×523): scale=1.225, dest=392×294, off=(0,114.5)  ✓ logged (0,114)-(392,409)
STATIC   contain(810×1080 → 392×523): scale=min(0.484,0.484)=0.484, dest=392×522.7, off=(0,0.2) ✓ logged (0,0)-(392,523)
```

## 8. Conclusion

- Painter and app-FittedBox use **identical** transforms (verified numerically).
- The painter is in **sensor space** (320×240) — **not** portrait — so
  hypothesis #9 is false.
- The residual landscape offset therefore cannot be a painter-vs-FittedBox
  mismatch. It is most likely the **un-modeled `CameraPreview` internal
  transforms** (40%) and/or **model localization error on stretched low-res
  camera frames** (35%), with stream-content mismatch (15%) as a third.
- The definitive discriminator is the same-content (bus.jpg-on-monitor)
  experiment plus measuring the preview's actual on-screen rect — no pipeline
  code changes required to run them.
- Only after landscape overlays are pixel-perfect should the device-independent
  orientation architecture (see `docs/orientation-design-review.md`) be
  implemented.
