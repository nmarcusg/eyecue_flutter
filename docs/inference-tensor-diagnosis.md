# Inference Tensor-Handling Diagnosis

> **Status:** Investigation only — no code was modified.
> **Scope:** Output/input tensor handling in the inference isolate.
> **Date:** 2026-08-01
> **Companion docs:** [`known-issues.md`](known-issues.md), [`implementation-decisions.md`](implementation-decisions.md)

---

## 1. Executive Summary

The crash `NoSuchMethodError: Class 'Float32List' has no instance method 'reshape'`
is a **Dart type-system bug**, not a model bug:

- [`inference_isolate.dart:257`](../lib/services/inference_isolate.dart:257) calls
  `inputBuffer.reshape(inputShape)` on a variable declared `dynamic`.
- `reshape` is an **extension method** (`ListShape` on `List`) inside
  `tflite_flutter`, **not** an instance method of `Float32List`.
- Dart **never resolves extension methods through dynamic dispatch**, so a
  `dynamic` receiver throws `NoSuchMethodError` at runtime.
- Separately, the **output buffer is architecturally wrong**: a flat `List` can
  never receive the model output because tflite_flutter's `copyTo()` requires the
  destination shape to exactly match the tensor shape `[1, 84, 8400]`. This is a
  latent crash that fires immediately after the input crash is fixed.

Both issues are fixed by passing raw `ByteBuffer`s to `interpreter.run()` —
a zero-copy path that is shape-exempt on both input and output.

---

## 2. Tensor Metadata (read directly from the `.tflite` flatbuffers)

| Property | `assets/yolov8n.tflite` *(loaded)* | `assets/yolov8n_int8.tflite` *(not bundled)* |
|---|---|---|
| File size | 3,333,264 bytes | 3,498,705 bytes |
| **Input name** | `serving_default_images:0` | `images` |
| **Input type** | `FLOAT32` | `FLOAT32` |
| **Input shape** | `[1, 640, 640, 3]` (NHWC) | `[1, 640, 640, 3]` (NHWC) |
| Input quant params | none (scale/zeroPoint absent) | none |
| **Output name** | `PartitionedCall:0` | `Identity` |
| **Output type** | `FLOAT32` | `FLOAT32` |
| **Output shape** | `[1, 84, 8400]` | `[1, 84, 8400]` |
| Output quant params | none | none |
| Tensor histogram | 324 FLOAT32 / 23 INT32 / 62 INT8 | 324 FLOAT32 / 25 INT32 / 62 INT8 |
| Ops / tensors | 253 ops / 409 tensors | 254 ops / 411 tensors |

**Interpretation:**

- **Both** models are **FLOAT32-in / FLOAT32-out**. The 62 `INT8` tensors are
  internal *weights* — this is **weight-quantized (dynamic-range) quantization**,
  *not* full int8 I/O quantization.
- Therefore the app's INT8 input/output branches and the dequantization branch
  in the parser **never activate** with either file. The code's "INT8 model"
  comments (e.g. [`inference_isolate.dart:156-157`](../lib/services/inference_isolate.dart:156))
  are misleading for the file actually loaded.
- The app bundles only `assets/yolov8n.tflite`
  ([`pubspec.yaml:42`](../pubspec.yaml:42)); `yolov8n_int8.tflite` sits in
  `assets/` but is **not declared** and **not loaded**.
- **No automatic dequantization occurs anywhere.** `outputTensor.params` for a
  float32 tensor returns scale `0`, zeroPoint `0`, and the parser correctly skips
  dequantization because `outputType == TensorType.float32`.

---

## 3. Current Implementation

All in [`lib/services/inference_isolate.dart`](../lib/services/inference_isolate.dart):

| Line | Code | What it is |
|---|---|---|
| 89 | `rootBundle.load('assets/yolov8n.tflite')` | Loads the float32-I/O model |
| 177–178 | `getInputTensor(0)` / `getOutputTensor(0)` | Metadata query — correct |
| 222 | `final dynamic inputBuffer;` | **Type-erased buffer** — root of bug #1 |
| 225 / 228 | `Uint8List(...)` or `Float32List(...)` | Runtime type: `Float32List` (1,228,800 elems) |
| 233 | `final outputBuffer = List.filled(outputElementCount, 0.0);` | **Flat 1-D `List` (705,600 elems)** — root of bug #2 |
| 257 | `inputBuffer.reshape(inputShape)` | ❌ **Crash site** |
| 260 | `interpreter!.run(reshapedInput, outputBuffer)` | Inference call |
| 266–275 | `_parseYolov8Output(outputBuffer, …)` | Parser: flat indexing `[j * numBoxes + i]` |
| 417–478 | `_parseYolov8Output` | Accepts `List`, dequantizes only for int8/uint8 |

---

## 4. Why the Crash Occurs — Line 257 in Detail

### What object owns `reshape()`?

Nothing in the app's call chain owns it as an *instance* method. `reshape<T>` is
declared as:

```dart
// package:tflite_flutter/lib/src/util/list_shape_extension.dart
extension ListShape on List {
  List reshape<T>(List<int> shape) { ... }
}
```

It is an **extension** applied statically to any `List`. `Float32List` implements
`List<double>`, so the extension *does* apply **when the receiver's static type is
`List`**. The package itself relies on this — e.g.
[`tensor.dart:196`](../.pub-cache/…/tensor.dart:196) calls `list.reshape<double>(shape)`
on a plain `List<dynamic>`.

### Why was it called, and where did the assumption come from?

- The author wanted the flat input buffer reshaped into `[1, 640, 640, 3]` so the
  interpreter "sees" the right shape — a reasonable intent.
- The assumption that `.reshape()` exists on the buffer almost certainly came from
  tflite_flutter **examples/README**, which use `TensorBuffer.reshape(...)`.
  `TensorBuffer` (a class with a real `reshape` instance method) lives in the
  companion package **`tflite_flutter_helper`**, which **is not a dependency** and
  does not exist in `tflite_flutter` 0.12.1 core (verified: zero references).

### Is it valid Dart?

As written, **no** — because `inputBuffer` is declared `dynamic`
([`inference_isolate.dart:222`](../lib/services/inference_isolate.dart:222)):

1. `inputBuffer.reshape(...)` compiles to a **dynamic invocation**.
2. Dynamic dispatch looks up **instance methods on the runtime type only**.
3. Extensions are resolved at **compile time from the static type** and are
   **never considered during dynamic dispatch**.
4. Runtime type is `Float32List` → no instance method `reshape` →
   `NoSuchMethodError`. This is exactly the observed error.

If the receiver were statically typed `List`, the same line would compile and run
(calling `_reshape4<double>` → a nested `[1][640][640][3]` list). So the bug is
specifically the `dynamic` type meeting an extension method — a classic Dart trap.

> **Note:** even a "fixed" version that typed the receiver as `List` and called the
> extension would work but be **wasteful**: it builds a 1.2 M-element nested list
> per frame, which `setTo()` then re-flattens element-by-element back to bytes.

---

## 5. Output Tensor Handling — the Second (Latent) Bug

The crash at line 257 fires before `interpreter.run()` is reached, so the output
bug has not been observed yet — but it is deterministic and fires on the first
frame after the input crash is fixed.

`Interpreter.run(output)` →
[`runForMultipleInputs`](../.pub-cache/…/interpreter.dart:176) →
`outputTensors[i].copyTo(dst)` ([`tensor.dart:178`](../.pub-cache/…/tensor.dart:178)):

1. `copyTo` reads the raw tensor bytes and, for FLOAT32, materializes a **nested
   `List` shaped `[1][84][8400]`** via `convertBytesToObject(...)`.
2. Because `dst` is a `List`, it calls `_duplicateList(obj, dst)`
   ([`tensor.dart:219`](../.pub-cache/…/tensor.dart:219)).
3. `_duplicateList` compares `obj.shape` (`[1, 84, 8400]`, 3-D) with `dst.shape`
   (`[705600]`, 1-D) → mismatch →
   `ArgumentError('Output object shape mismatch, interpreter returned output of shape: [1, 84, 8400] while shape of output provided as argument in run is: [705600]')`.

**Conclusion:** a flat output `List` is **never** a valid destination. The valid
destinations are:

| Destination | Valid? | Notes |
|---|---|---|
| Nested `List` matching `[1,84,8400]` | ✅ | Requires parser rewrite to 3-D indexing |
| Raw `ByteBuffer` / `Uint8List` | ✅ | Bytes copied verbatim; read via typed-list view |
| Flat `List` (current) | ❌ | Shape mismatch → `ArgumentError` |

### Parser compatibility

`_parseYolov8Output` ([`inference_isolate.dart:417`](../lib/services/inference_isolate.dart:417))
accepts a flat `List` and indexes `outputBuffer[j * numBoxes + i]` — this is
**correct for the model's transposed `[1, 84, 8400]` layout** (84 feature rows ×
8400 anchors; index = `feature * 8400 + anchor`). Delivering the output as a flat
`Float32List` keeps the parser **unchanged and correct**. `.toDouble()` on float
elements is a no-op. The dequantization branch is dead code for this model but
harmless.

*(Out of scope, flagged only: YOLOv8 box coordinates `cx,cy,w,h` are in pixel
units 0–640, but the parser clamps to 0.0–1.0, which would squash every box. This
is a post-processing correctness issue, not the crash, and was deliberately not
changed.)*

---

## 6. Input Path — Third (Subtle) Issue

Even with line 257 removed, passing the flat `Float32List` directly to `run()`
would misbehave:

- [`getInputShapeIfDifferent`](../.pub-cache/…/tensor.dart:242) computes the
  input's shape via `computeShapeOf` → a 1-D `[1228800]` for a flat `Float32List`.
- `[1228800]` ≠ `[1, 640, 640, 3]` → `resizeInputTensor(0, [1228800])` is called →
  the model's input tensor is **resized to 1-D**, breaking the fixed 640×640 conv
  graph (invoke would fail or emit garbage).
- Only `Uint8List` and `ByteBuffer` inputs short-circuit this check (return `null`,
  no resize) — [`tensor.dart:246`](../.pub-cache/…/tensor.dart:246).

**Fix:** pass the raw **`ByteBuffer`** (`.buffer` of the typed list) to `run()`.
This bypasses resize entirely, and `setTo()` copies the raw bytes straight into the
tensor (`convertObjectToBytes` handles `ByteBuffer` directly) — a true zero-copy
path, and the fastest option available.

---

## 7. The "Isolate Dies / Busy Flag Never Clears" Symptom

Mechanics, verified in [`camera_screen.dart`](../lib/screens/camera_screen.dart):

1. `_isInferring` is set `true` before each frame is sent
   ([`camera_screen.dart:202`](../lib/screens/camera_screen.dart:202)).
2. It is reset **only** when a `result` message arrives
   ([`camera_screen.dart:170`](../lib/screens/camera_screen.dart:170)).
3. The isolate's try/catch **does** catch the `NoSuchMethodError` and reports it as
   `{'type': 'error'}` ([`inference_isolate.dart:288-299`](../lib/services/inference_isolate.dart:288)),
   so the isolate process technically survives.
4. But the main isolate's `error` handler only prints
   ([`inference_isolate.dart:63-69`](../lib/services/inference_isolate.dart:63)) and
   **never clears `_isInferring`** → the frame-dropping gate stays locked forever.

So "isolate dies" is really **pipeline death**: no `result` ever arrives, the busy
flag wedges, and every subsequent frame is dropped. This matches the already-tracked
"Incomplete Error Recovery in Inference Isolate" issue in
[`known-issues.md`](known-issues.md).

---

## 8. Diagnosis

### 8.1 Root cause

1. **Immediate crash:** `inputBuffer.reshape(...)` at
   [`inference_isolate.dart:257`](../lib/services/inference_isolate.dart:257) —
   `reshape` is a `List` *extension method* invoked on a `dynamic` receiver; Dart
   does not resolve extensions via dynamic dispatch, so `Float32List` throws
   `NoSuchMethodError`.
2. **Latent crash (next frame):** flat `List` output buffer violates `copyTo()`'s
   shape-equality requirement → `ArgumentError` after the first successful invoke.
3. **Latent data corruption:** a flat `Float32List` input would trigger an
   automatic 1-D `resizeInputTensor`, breaking the fixed-shape model.

### 8.2 Immediate fix (2 lines, [`inference_isolate.dart`](../lib/services/inference_isolate.dart))

```dart
// line 233 — output: typed flat list backed by raw bytes
final outputBuffer = Float32List(outputElementCount);
//   (use Int8List/Uint8List here if outputType is int8/uint8)

// line 257 + 260 — delete the reshape line, pass raw buffers
interpreter!.run(inputBuffer.buffer, outputBuffer.buffer);
```

- Input `ByteBuffer` → no auto-resize; float32 bytes copied in verbatim.
- Output `ByteBuffer` → `copyTo` copies raw bytes into the caller's buffer; the
  `Float32List` view then yields row-major `[1, 84, 8400]` floats.
- `_parseYolov8Output` stays **byte-for-byte unchanged** — flat indexing already
  matches the layout.
- Preprocessing (`_convertYUV420toRGB` writing normalized floats into the
  `Float32List`) is unchanged.

### 8.3 Best long-term architecture

1. **Buffer handling:** either
   - (recommended) keep pre-allocated typed lists + `.buffer` — the documented
     tflite_flutter fast path, or
   - add `tflite_flutter_helper` and use `TensorBuffer`/`TensorBufferFloat`
     (`createFrom(tensor, shape)`) for shape-safe, typed buffer management.
2. **Error recovery:** on `{'type': 'error'}`, reset `_isInferring` in
   [`camera_screen.dart`](../lib/screens/camera_screen.dart) and implement isolate
   restart (already Milestone 4 in [`implementation-plan.md`](implementation-plan.md)).
3. **Type safety:** replace the `dynamic inputBuffer` with an explicit branch or
   sealed type so extension/dynamic-dispatch traps cannot recur.
4. **Cleanup:** correct the stale "INT8 model" comments; either bundle and load
   `yolov8n_int8.tflite` intentionally (still float32 I/O — no dequant needed) or
   delete it.

### 8.4 Risk of changing the tensor representation

- **Low.** The byte layout (row-major float32) is identical to what the model
  consumes today; only the Dart wrapper changes. The parser is untouched.
- Only hazard: passing `.buffer` of a `Float32List` *view* with a nonzero
  `offsetInBytes` would copy the wrong region — freshly allocated lists have
  offset 0, and the converters always write into a fresh buffer.
- Higher risk is the alternative "nested List" route: it would force a parser
  rewrite to 3-D indexing — avoid.

### 8.5 Estimated amount of refactoring

| Scope | Effort |
|---|---|
| Immediate fix | ~2–5 lines in one file; ~10–20 min; no other files touched |
| + error recovery / busy-flag reset | ~15 lines across [`inference_isolate.dart`](../lib/services/inference_isolate.dart) + [`camera_screen.dart`](../lib/screens/camera_screen.dart) |
| + long-term (`TensorBuffer`, type safety, docs, stale comments) | small–medium; 1–2 files + docs |

---

## 9. Confidence

| Claim | Confidence | Basis |
|---|---|---|
| Line 257 is the crash (dynamic + extension) | **High** | Dart semantics + package source (`list_shape_extension.dart`) |
| Output flat `List` is invalid (shape mismatch) | **High** | `copyTo`/`_duplicateList` source traced line-by-line |
| Input auto-resize to 1-D is a real hazard | **High** | `getInputShapeIfDifferent` source |
| Models are float32 I/O, weight-quantized | **High** | Direct flatbuffer parse of both files |
| Busy-flag wedge explains "isolate dies" | **High** | [`camera_screen.dart`](../lib/screens/camera_screen.dart) gate logic |
| ByteBuffer path fixes all three issues | **High** | `convertObjectToBytes`/`copyTo` both short-circuit on `ByteBuffer` |

---

*Report complete. Implementation should proceed only after review of this document.*
