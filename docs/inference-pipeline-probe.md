> **Historical: describes the Custom EyeCue engine removed on 2026-10-21.**

# Inference Pipeline Probe — "Objects: 0" Forensic Investigation

> **Status:** Historical investigation record. No pipeline behavior was changed
> as part of this report.
> **Temporary diagnostics:** [`lib/services/inference_probe.dart`](../lib/services/inference_probe.dart) (phases 1–8, removable).
> **Date:** 2026-08-01

> **Historical snapshot notice (2026-09-01):** This report records the
> pre-candidate camera/parser investigation. The later ByteBuffer, NMS, and
> orientation changes are reflected in the current implementation; the
> committed-but-unreleased NCHW/XNNPACK candidate is tracked in
> [`project-status.md`](project-status.md).

---

## ✅ Static-image test — EMPIRICAL CONFIRMATION (2026-08-01)

The camera was removed from the equation with a temporary test-image mode (see
[`docs/static-image-test.md`](static-image-test.md)). A known-good RGB photo
(`assets/test_image.jpg`, bus + people) was converted to I420 planes and pushed
through the **exact same** pipeline (`processFrame()` → `_convertYUV420toRGB` →
run → parser → NMS → painter). On the actual Android device (which reports
"Objects: 0" on camera):

```
[Detection] Frame #1 | Objects: 5 (candidates(before NMS)=44 → after NMS=5)
  person 91.7%  person 90.7%  person 88.8%  bus 86.7%  person 47.0%
```

The model **correctly detects the expected COCO objects**. Round-trip verified
quantitatively (PSNR 36.9 dB vs source; resize/tensor dumps byte-identical).
**Conclusion:** parser, NMS, thresholds, labels, and painter are exonerated —
the remaining "Objects: 0" bug is **isolated to the camera preprocessing path**
(H8, empirically confirmed): the YUV420 planes from `CameraImage` do not match
what `_convertYUV420toRGB` consumes (format/layout, strides, or rotation).

---

## ⚠️ Correction (2026-08-01, verified by graph dump)

**H7 below is REFUTED.** The final box rows of `PartitionedCall:0` are
**normalized [0,1]**, not pixel-space 0–640. Verified directly from the model's
operator graph (`tool/dump_graph_tail.py` / `dump_decode_consts.py`):

| Op | Builtin | Math | Result |
|----|---------|------|--------|
| [245] | MUL (18) | `(x1+x2) × 0.5` | center (grid cells) |
| [246] | SUB (41) | `x2−x1` | w/h (grid cells) |
| [247] | CONCAT (2) | `[cx, cy, w, h]` | per-anchor box (grid cells) |
| [248] | MUL (18) | `× stride` tensor (`8/16/32`, verified) | pixels 0–640 |
| [249] | MUL (18) | `× 0.0015625` = `× 1/640` | **normalized [0,1]** |
| [251] | LOGISTIC (14) | sigmoid on classes | scores [0,1] |
| [252] | CONCAT (2) | boxes + scores | `[1, 84, 8400]` |

The grid (`Const_3`, values 0.5…79.5) and per-anchor strides are **inside the
graph** — the app parser must **not** decode again and must **not** divide by
640. [`_parseYolov8Output`](../lib/services/inference_isolate.dart) treating
`cx/cy/w/h` as normalized `[0,1]` is **correct**.

The real post-processing gaps that make on-device detections *appear* incorrect:
1. **No NMS** — every object fires many overlapping anchors → a jumble of boxes.
   Fixed 2026-08-01 (class-wise NMS, IoU 0.45).
2. **Pre-NMS confidence threshold 0.5 too high** (standard YOLOv8 is 0.25) —
   true detections were dropped while spurious full-frame boxes passed.
   Lowered to 0.25 (2026-08-01).

---

## 1. Investigation Summary

The app always reports `[Detection] Frame #N | Objects: 0` — inference completes
successfully but the parser never emits a detection. This report records every
hypothesis, the evidence gathered (static + probe-based), and the final
diagnosis with ranked likelihoods.

**Key conclusion up front:** Static analysis of the actual model file **eliminates
the parser, the tensor layout, the sigmoid/logit question, the threshold scale,
and the labels** as root causes. The failing stage is almost certainly **upstream
of the parser** — the input pixels reaching the model (preprocessing / camera
format) — or **the output readback**. A decision procedure at the end lets the
two on-device probe logs (`[Probe P3]` and `[Probe P2]`) pin the exact stage in
one run.

---

## 2. Pipeline Stages Under Investigation

```
Camera → YUV420 → RGB → Resize → Normalize → Interpreter.run() → Output tensor → YOLO parser → Threshold → Boxes → Detections
```

---

## 3. Hypotheses Considered

| # | Hypothesis | Verdict |
|---|------------|---------|
| H1 | Output tensor is raw logits; parser must sigmoid before thresholding | ❌ **Refuted** (static) |
| H2 | Output tensor layout is anchors-major `[1, 8400, 84]`, not `[1, 84, 8400]` | ❌ **Refuted** (static, low residual risk) |
| H3 | Parser indexing `[j * numBoxes + i]` reads the wrong region | ❌ **Refuted** (static) |
| H4 | Output needs dequantization (INT8) but isn't dequantized | ❌ **Refuted** (static — output is FLOAT32) |
| H5 | Confidence threshold 0.5 is semantically wrong for the score scale | ❌ **Refuted** (static — scores are [0,1]) |
| H6 | Labels file mismatches (≠80, empty lines) | ❌ **Refuted** (static) |
| H7 | Box coordinates are treated as normalized but the model outputs pixel-space (0–640) | ❌ **Refuted** (graph dump: op 249 `×1/640` → output is normalized [0,1]) |
| H8 | Input pixels are garbage/degenerate (YUV plane format, strides, order, all-black) | 🟡 **Primary suspect** (probe P2/P3) |
| H9 | Output buffer readback returns all zeros (ByteBuffer path) | 🟡 **Strong suspect** (probe P3) |
| H10 | Model/runtime issue on device (e.g., CPU-only XNNPACK-disabled path) | 🟡 Low (probe P3) |

---

## 4. Evidence

### 4.1 Static evidence — model file (`assets/yolov8n.tflite`)

Parsed the actual `.tflite` flatbuffer (tensor metadata + operator graph):

- **Input:** `FLOAT32`, shape `[1, 640, 640, 3]`, no quantization params.
- **Output:** `FLOAT32`, shape `[1, 84, 8400]`, no quantization params.
- **Subgraph:** 1 subgraph, 409 tensors, 253 ops. Internal histogram:
  `{FLOAT32: 324, INT32: 23, INT8: 62}` → weight-quantized, FLOAT32 I/O.

**Operator graph near the output (decisive):**

| Op | Builtin (code) | Inputs | Output |
|----|----------------|--------|--------|
| [237] | SOFTMAX (25) | DFL distribution | `model.22/dfl/Softmax` |
| [238] | CONV_2D (3) | DFL softmax | decoded box distribution |
| [245]–[249] | MUL/DIV/SUB/ADD/CONCAT | decode math | **box coords in pixel space** |
| [251] | **LOGISTIC (14)** | class logits | `tf.math.sigmoid_57/Sigmoid` |
| [252] | **CONCATENATION (2)** | `[decoded boxes (4 rows), sigmoid scores (80 rows)]` | `PartitionedCall:0` = `[1, 84, 8400]` |

**Consequences (each refutes a hypothesis):**

- **H1 refuted:** the graph itself applies `Sigmoid` (op 251) before the final
  concat (op 252). Output class scores are **probabilities in [0,1]**, not logits.
  The parser's `> 0.5` threshold is semantically correct.
- **H2/H3 refuted:** the final concat produces `[box(4) + class(80)] × 8400` →
  features-major `[1, 84, 8400]`. The parser reads `out[(4+c)*8400 + a]`, which is
  exactly row-major `[1][84][8400]`. Indexing is correct; the buffer is flat and
  contiguous, so the shape metadata cannot lie about layout.
- **H4 refuted:** output type is FLOAT32 → dequantization is correctly skipped.
- **H5 refuted:** scores are [0,1]; threshold 0.5 is standard YOLOv8 usage.
- **H6 refuted:** `labels.txt` contains exactly 80 COCO lines, no blanks.
- **H7 REFUTED (2026-08-01):** the box decode (ops 245–249) ends with op 249
  **MUL by `1/640`** — the exported graph normalizes boxes to [0,1]. The parser's
  `(cx - w/2).clamp(0.0, 1.0)` is therefore **correct**; no /640 division or
  extra decode is needed in the app.

**Statistical note:** with ~672k sigmoid outputs (8400 × 80) per frame, *random*
garbage input would almost certainly yield *some* score > 0.5 by chance. A
consistent **exactly-zero** result therefore implies either (a) degenerate
(≈constant) input pixels, or (b) an all-zeros output readback — not mere noise.

### 4.2 Static evidence — preprocessing code

- YUV→RGB uses BT.601-style coefficients (r=Y+1.402V, g=Y−0.344U−0.714V,
  b=Y+1.772U) — standard, only a documented "slight color shift".
- Float path writes `r/255.0, g/255.0, b/255.0` → **[0,1] normalized RGB** —
  correct for an ultralytics YOLOv8 export.
- Resize is nearest-neighbor *stretch* to 640×640 (no letterbox) — aspect
  distortion degrades accuracy but does not zero detections by itself.
- **Unverified statically (needs device):** whether `ImageFormatGroup.yuv420`
  delivers 3-plane I420 (assumed by `image.planes[1]`/`[2]`), the real
  `rowStride`/`pixelStride` of each plane (the code ignores them and assumes
  tightly-packed `width`/`(w+1)~/2` rows), and whether the image is rotated.
  Any of these would feed a degenerate/smeared image to the model.

### 4.3 Static evidence — output readback

`interpreter.run(inputForRun, outputBuffer.buffer)` passes a `ByteBuffer`;
tflite_flutter's `copyTo(ByteBuffer)` writes the raw tensor bytes into the
caller's buffer, and the `Float32List` view reads them back. Traced line-by-line
and verified correct. However the probe's `[Probe P3] allZero=true` check is the
cheap, definitive confirmation that the buffer actually received the output.

### 4.4 On-device probe evidence (to be collected)

Temporary probes are installed (removable) in
[`lib/services/inference_probe.dart`](../lib/services/inference_probe.dart) and
wired into [`inference_isolate.dart`](../lib/services/inference_isolate.dart):

| Probe | What it logs | Decides |
|-------|--------------|---------|
| `[Probe P1]` | model name, I/O types/shapes, scales, zero points, internal tensor summary, classes/anchors, label count | model-loading correctness |
| `[Probe P2]` (frame 1) | src/dst resolution, buffer type & length, first 20 values, min/max/mean, normalization check ([0,1] vs [0,255]) | preprocessing correctness |
| `[Probe P3]` (frame 1) | raw output len vs expected, min/max/mean, NaN/Inf counts, `allZero`, top-20 values+indices | output readback / activation health |
| `[Probe P4]` (frame 1) | anchors 0,1,10,100,1000,8399: bbox + top-3 class scores + best; global best score/anchor/class | parser-level read of values |
| `[Probe P5]` (frame 1) | max + detection counts at thresholds 0.01…0.60 for layout A (features-major) **and** layout B (anchors-major) | score scale + layout |
| `[Probe P6]` (frame 1) | first 20 anchors with score > 0.25: box values, negative/NaN/Inf/out-of-range flags | box-decode sanity |
| `[Probe P7]` (frame 1) | layout statement (see P5 sweep) | layout |
| `[Probe P8]` (every frame) | frame, latency, max confidence, detection count | latency↔confidence correlation |

**Run:** `flutter run` on the device, point at a well-lit object, capture logcat,
and report the `[Probe P2]` / `[Probe P3]` / `[Probe P5]` blocks.

### 4.5 Decision procedure (one run → exact stage)

1. **`[Probe P3] allZero=true`** → output readback bug (H9). Inspect the
   ByteBuffer write path / tensor index. *Fix is in the run/output plumbing.*
2. **`[Probe P3] max < ~0.5` (e.g. 0.0–0.3)** → model is producing weak/late
   activations → **input problem (H8)**. Check `[Probe P2]` min/max/mean: if mean
   ≈ 0 or all values identical → degenerate image (YUV plane/stride/format or
   black frames). If values are in [0,255] instead of [0,1] → normalization path
   is broken.
3. **`[Probe P3] max > 0.5` but `[Probe P5] layoutA count(>0.50) == 0`** → the
   layout is actually anchors-major (H2 residual); verify `layoutB` count.
4. **`[Probe P5] layoutA count(>0.50) > 0` but production still logs 0** →
   parser/behavior divergence (would contradict static analysis — investigate
   immediately; report the P8 line too).

---

## 5. Final Diagnosis

**Root cause (best-supported):** The failing stage is **preprocessing / input
pixel correctness (H8)**, with **output readback (H9)** as the runner-up. The
parser — indexing, layout, sigmoid semantics, threshold, dequantization — is
verified correct against the actual model graph and can be ruled out.

Why "always zero" specifically: with correct input, a stock YOLOv8n produces
multiple sigmoid scores > 0.5 for real objects; with degenerate input it
produces a uniformly low score map that never clears 0.5. The two probes that
distinguish this are `[Probe P2]` (input pixel stats) and `[Probe P3]`
(output `allZero` / `max`).

**Post-processing gaps (fixed 2026-08-01):** the parser is numerically correct
(boxes arrive normalized [0,1]); the real gaps were **missing NMS** (duplicate
overlapping boxes per object) and a **pre-NMS threshold of 0.5** that was too
high (standard YOLOv8 uses 0.25). Both fixed in
[`_parseYolov8Output`](../lib/services/inference_isolate.dart).

---

## 6. Confidence Level

| Claim | Confidence | Basis |
|-------|-----------|-------|
| Sigmoid already applied in graph (not logits) | **Very high** | Op [251] LOGISTIC feeds final CONCAT [252] |
| Layout is features-major [1,84,8400]; parser indexing correct | **Very high** | Final CONCAT structure + row-major flatbuffer |
| Output is FLOAT32 (no dequant needed) | **Very high** | Tensor metadata parse |
| Labels correct (80) | **High** | File check |
| Box decode output is normalized [0,1] (not pixel-space) | **Very high** | Op 249 MUL by 1/640 confirmed in graph dump |
| Failing stage is preprocessing input (H8) or output readback (H9) | **Medium–High** | Elimination of all parser-side causes; needs `[Probe P2/P3]` to finalize |
| Model itself is broken | **Low** | Standard YOLOv8n structure |

---

## 7. Suggested Fix (analysis only — NOT implemented)

1. **Confirm with probes first** (one device run): the `[Probe P2]` and
   `[Probe P3]` blocks pin the stage.
2. **If input is degenerate (H8):** use the real plane geometry from the camera
   image (`image.planes[i].rowStride`, `pixelStride`, `bytesPerRow`) instead of
   assuming tightly-packed I420; confirm the delivered format is 3-plane; add a
   letterbox resize to 640×640 instead of aspect-stretching. Verify a saved
   frame is a recognizable RGB image.
3. **If output readback is zero (H9):** re-verify the `ByteBuffer` path against
   tflite_flutter 0.12.1 `copyTo` (or switch to a nested-list output matching
   `[1,84,8400]`).
4. **Post-processing (implemented 2026-08-01):** add class-wise NMS (IoU 0.45)
   and lower the pre-NMS confidence threshold to 0.25. Do **not** divide box
   coords by 640 — the graph already normalizes them (op 249 `× 1/640`).

---

## 8. How to Remove the Probes

1. Delete [`lib/services/inference_probe.dart`](../lib/services/inference_probe.dart).
2. In [`lib/services/inference_isolate.dart`](../lib/services/inference_isolate.dart):
   remove the `inference_probe.dart` import and all `InferenceProbe.*` calls
   (marked `// TEMPORARY forensic probe`).
3. `flutter analyze` should return to the pre-probe baseline.
