# Phase 1 — Preprocessing Diagnosis After the Converter Fix

> **Status:** Diagnosis only. No code was changed.
> **Evidence base:** raw frame-by-frame `performance.txt`, frame-1 `tensor.txt`,
> `preprocess.txt`, `output.txt`, `parser.txt`, `camera.txt`, and the summary.
> **Date:** 2026-08-01

---

## 1. Verdict: Is preprocessing now fundamentally correct?

**Yes.** The strongest evidence is the raw per-frame `performance.txt`, not the
summary (which is frame-1-only):

| Metric | Before fix | After fix |
|---|---|---|
| Max confidence | ≈0.03 (constant, flat) | 0.01 → **0.8756**, varying naturally |
| Detections | always 0 | **0–27**, appearing/disappearing per frame |
| Output | flat | healthy (frames 16+, 47+, 54+, 76+, 83+, 90+ …) |

A corrupt converter produces a near-uniform input and a flat score map (the old
signature). The new converter produces real, scene-dependent detections — that
is only possible if the model is receiving a meaningful image.

**Geometry verification (computed from the log):**
- Y plane: 239 full rows × 512 + 320-byte final row = 122,688 ✓. Max sampled
  index (row 239, col 319) = 122,687 ≤ 122,687 ✓ in-bounds.
- Chroma (semi-planar, pixelStride 2, rowStride 512): 119 full rows × 512 +
  319-byte final row = 61,247 ✓. Sampling `base = cx·2 + 512·cy` is in-bounds for
  every sample **except** the V byte of the very last chroma sample (index
  61,247 → clamped to 61,246, reads U instead of V). One sample; negligible.

So the stride/interleave indexing is correct and matches the delivered buffers.

---

## 2. Why confidence increased dramatically

- **Old converter:** assumed planar I420 and sampled Y at `row*width` (320)
  while the real rowStride is 512 → row smearing; read the interleaved chroma as
  planar 1-byte samples → garbage U/V.
- **New converter:** honors `rowStride=512`, reads interleaved NV12 chroma
  (U=even, V=odd from the U-led plane), normalization [0,1] unchanged.
- Result: the model went from seeing ~uniform garbage to a real image → max
  sigmoid jumped from ~0.03 to 0.87. This is exactly the expected signature of a
  corrupt→correct input transition.

---

## 3. What the "green image" indicates

The dumps (`frame_rgb.png`, `frame_model_input.png`) are **frame 1**, and the
frame-1 tensor stats prove that frame is ~99.7% black:

```
mean = 0.0012   (raw ≈ 0.3/255)
R: mean 0.0003, max 0.0235
G: mean 0.0030, max 0.3647
B: mean 0.0003, max 0.0157
```

On a near-black frame, BT.601 with small negative chroma yields
`G = Y − 0.344u − 0.714v > 0` while `R = Y + 1.402v` and `B = Y + 1.772u` stay ≈ 0
→ **green-tinted output**. Row-organized chroma content on a settling camera
presents as *green horizontal lines on a black frame*.

Assessment against the candidate causes:
- **PNG encoder misuse — No.** The encoder is validated (CRC/chunks/dims +
  Python pixel-exact decode).
- **Stride/indexing corruption — No.** Geometry verified in-bounds (above).
- **RGB conversion bug — Unlikely for the dark frame.** Same converter produces
  healthy high-confidence detections on later frames.
- **Verdict:** a **dark-frame / camera auto-exposure artifact** rendered green by
  BT.601's green-bias at low luma. Not proof of a fundamental converter bug.
- **Residual uncertainty:** U/V ordering (NV12 vs NV21). A dark frame cannot
  reveal color correctness. Needs a *lit-frame* check (diagnostic #2).

---

## 4. Do the later detections mean the model sees a real image?

**Yes.** Frames 16–100 show maxConf varying naturally (0.2 → 0.87), detections
counts moving 0 → 27 → 0, tracking the scene. A corrupted input cannot produce
coherent, scene-correlated detections at 0.87 confidence. The later frames are
healthy; the frame-1 PNGs are simply the wrong frame to judge color from.

---

## 5. Tensor statistics — consistent with a valid camera image?

Frame 1 is consistent with a **camera's first frame before auto-exposure
settles** (frame-1 `cameraFps=0.3`, latency 663 ms — the camera had just
started). It is NOT consistent with a lit scene, but that is a camera-start
condition, not evidence of corruption — later frames demonstrably recover.
**Gap:** we have input stats for frame 1 only; later-frame input health is
inferred from output health (see diagnostics #1).

---

## 6. Remaining suspicious metrics (raw logs)

1. **Latency 500–800 ms/frame** — extremely high for YOLOv8n. The forensic layer
   adds a *second* full 8400×80 = 672k-element scan every frame
   (`ForensicLog._maxConfidence`) plus a synchronous flushed file append per
   frame; the production parser already does one 672k scan. Instrumentation is a
   significant, removable contributor (model-on-CPU is also inherently slow
   without XNNPACK).
2. **Frame-1 input ≈ black with green tint** — camera auto-exposure (see §3);
   benign if later frames are lit (unverified directly).
3. **droppedFrames climb ~13–20 per processed frame** — arithmetic consequence of
   ~600 ms/frame at a 22 fps camera (45 ms/frame): ~13–17 drops per processed
   frame. Matches the log exactly. Not a bug — a latency symptom.
4. **Summary "Output FAIL / FLAT / top class keyboard"** — computed from frame 1
   only; misleading. Frames 16+ are healthy. (Known diagnostic limitation.)
5. **Chroma last-byte clamp** — the final sample's V byte is out of the 61,247-byte
   buffer and is clamped; one sample, negligible (but fixable).
6. **`frame_original.png` "looks correct" while `_grayRgba` ignores Y rowStride**
   (it reads the Y buffer tightly packed) — the dump is subtly wrong (diagnostic
   only; does not affect inference).
7. **Frames 110–113 maxConf collapse to ~0.005–0.19** — scene/occlusion or
   another exposure event; monitor.

---

## 7. Ranked most-likely remaining root causes

| # | Cause | Evidence | Confidence | Inspect |
|---|-------|----------|-----------|---------|
| 1 | **Forensic instrumentation dominates measured latency (~500–800 ms)** | Every frame does a full 672k maxConf scan + sync file I/O on top of the parser's 672k scan; dropped-frame arithmetic matches exactly | **80%** | `lib/services/forensic_log.dart` (`recordPerformance`, `_maxConfidence`, `_val`, `ForensicLogger.append` — open+flush per line) and its call site in `lib/services/inference_isolate.dart` |
| 2 | **Frame-1 dark/green input = camera auto-exposure settling** | mean 0.0012, R/B≈0, G 0.003, cameraFps 0.3 at frame 1; later frames healthy | **65%** exposure (not a code bug) | camera start config (`lib/screens/camera_screen.dart`); confirm with diagnostic #1 |
| 3 | **NV12 vs NV21 (U/V order) ambiguity** | green-dominant dark frame; contract says plane[1]=U but never verified against ground truth; a swap shifts hue (green/magenta) without killing detections | **40%** | `_convertYUV420toRGB` semi-planar branch (`lib/services/inference_isolate.dart`) |
| 4 | **Forensic dump inaccuracies (diagnostics only)** | `_grayRgba` ignores Y rowStride; last-chroma-byte clamp | **90%** dump-specific | `lib/services/forensic_log.dart` (`_grayRgba`, `_yuvToRgbRgba`) |
| 5 | **Parser / box handling** | **ELIMINATED:** raw boxes are normalized [0,1] (cx 0.49, w 0.97); the parser's `clamp(0,1)` is correct for this export | **90% eliminated** | — |

---

## 8. Targeted fixes (recommendations only — no code changed)

1. **Cut forensic per-frame cost:** compute max confidence only every N frames
   (or from a decimated sample), and write `performance.txt` in batches
   (keep the file handle open / flush every N frames). Files:
   `lib/services/forensic_log.dart`, `lib/services/inference_isolate.dart`.
2. **Fix `_grayRgba`** to honor Y rowStride (use `py*yRow + px`).
   File: `lib/services/forensic_log.dart`.
3. **Fix the last-chroma-byte clamp** by reading V from the V-plane view at
   `min(base+1, len-1)` — one line. File: `lib/services/inference_isolate.dart`.
4. **Only if a U/V swap is confirmed on a lit frame:** swap the two reads in the
   semi-planar branch. File: `lib/services/inference_isolate.dart`.

No pipeline redesign, no library/model changes are warranted by the evidence.

---

## 9. Additional diagnostics needed (exact)

1. **Periodic input stats (every 20th frame)** — append `[G]/mean/max` per
   channel for frames 20, 40, … to `preprocess.txt`.
   *Where:* `inference_isolate.dart` frame loop → a periodic `ForensicLog`
   append. *Why:* proves later frames are lit and correctly colored,
   separating "exposure settling" from "converter corruption".
2. **Lit-frame PNG dump** — dump `frame_rgb.png` for the first frame where
   `maxConf > 0.5` (or frame 20), not just frame 1.
   *Where:* `forensic_log.dart` `dumpFrameImages` gating. *Why:* a dark frame
   cannot validate color/UV order; a lit frame shows a U/V swap or hue error
   immediately.
3. **Plane-interleave check** — log the first ~32 bytes of `plane[1]` and
   `plane[2]` and test `plane2[k] == plane1[k+1]`.
   *Where:* `camera_screen.dart` frame 1 → `camera.txt`. *Why:*
   conclusively confirms the shared interleaved (NV12) assumption and validates
   the semi-planar V read — if the equality fails, the two planes are separate
   and the V-read is wrong.
4. **Y-luma check across frames** — log Y min/max/mean for frame 1 vs frame 20.
   *Where:* isolate → `preprocess.txt`. *Why:* confirms the dark frame is a
   luma/exposure event, not a Y-sampling bug (eliminates cause #2 cleanly).

---

## Bottom line

The converter fix is **fundamentally correct**: real detections (up to 27) and
max confidence 0.87 prove the model now receives meaningful RGB. The remaining
evidence points to (1) forensic-instrumentation latency overhead, (2) frame-1
dark-frame/green artifact from camera exposure, and (3) an unverified U/V-order
assumption — none of which justify a pipeline redesign. The two high-value
diagnostics are a lit-frame `frame_rgb.png` dump and periodic input stats.
