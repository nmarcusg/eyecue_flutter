# Model assets

This record describes the metadata-enriched TFLite artifact used by the single
Ultralytics detection engine, and the depth model used for optional metric
distance. The metadata suffix is packaging-only: the generated file starts with
the exact bytes of the base FlatBuffer and adds one deterministic stored ZIP
entry named `metadata.json`.

The base (metadata-free) graph is **no longer vendored**; it must be supplied
explicitly when regenerating:

```
dart run tool/package_ultralytics_metadata.dart --input=<base>.tflite
dart run tool/package_ultralytics_metadata.dart --check --input=<base>.tflite
```

## Depth model (metric distance)

| Field | Value |
|---|---|
| Official id | `yolo26n-depth` |
| Runtime artifact | [`assets/yolo26n-depth_w8a32.tflite`](../assets/yolo26n-depth_w8a32.tflite) |
| Base source | official `yolo26n-depth_w8a32.tflite` from the pinned `yolo-flutter-app` GitHub release `v0.6.6`, copied unchanged |
| Size | 5,474,749 bytes |
| SHA-256 | `8c7f242c2a8c339c6721863e103e17e026cbd784c9a3d031a8e902660c364311` |
| Task | `depth`; output `[1,1,640,640]`, input `[1,3,640,640]` (`imgsz` 640×640) |
| Quantization | `w8a32` (declared in `metadata.json` as `args.quantize`) |
| License | AGPL-3.0 (Ultralytics weights) |
| Provenance | bundled, not generated locally — the published file already ends with its own metadata suffix |
| Loaded by | `MonocularDepthEstimator` (second `YOLO` instance, `YOLOTask.depth`) |

The artifact is `FlatBuffer (TFL3)` **plus an appended deflated zip entry**
`metadata.json` (563 bytes):

```json
{"description": "Ultralytics YOLO26n-depth-log model ...", "task": "depth",
 "head": "Depth", "imgsz": [640, 640], "names": {"0": "depth"},
 "args": {..., "quantize": "w8a32"}, "end2end": false,
 "license": "AGPL-3.0 License (https://ultralytics.com/license)", "version": "8.4.104"}
```

The entry is **deflated**, so a raw byte/text grep over the file does not find
the JSON — that is why the earlier record wrongly reported "no metadata". Both
`unzip -l` and `unzip -p <artifact> metadata.json` show it, and the plugin's
`inspectModel` and `YOLOFileUtils.loadModelLabels` decompress it normally.

`MonocularDepthEstimator` still passes `YOLOTask.depth` explicitly rather than
depending on the resolved task, so a metadata regression cannot silently change
the task.

Both runtime models are bundled assets, so detection and depth load offline on
the first run. Release manifests declare `CAMERA` and `INTERNET`; the latter was
added only for the optional manual research-telemetry upload. No model, label,
or metadata is fetched at runtime — depth works offline and the earlier
download-on-first-use path is gone.

Depth values are metres as produced by the model; they are **uncalibrated**.
See [`mde-integration.md`](mde-integration.md).

## Packaging status

`assets/yolov8n_int8_new_metadata.tflite` (detection) and
`assets/yolo26n-depth_w8a32.tflite` (depth) are the **bundled runtime models**
declared in `pubspec.yaml` (alongside `assets/labels.txt`). Workstream 4 had
already removed the Flutter bundle declarations for the base graph
`assets/yolov8n_int8_new.tflite`, the v0.2.2 baseline `assets/yolov8n.tflite`
and the older `assets/yolov8n_int8.tflite`; the later Custom-engine removal then
deleted those three files from the repository. They are neither shipped nor
tracked: regenerate the packaged detection artifact from an externally supplied
base graph with `--input` (above).

## Artifact record

| Field | Value |
|---|---|
| Base graph | not vendored (supply with `--input`) |
| Runtime artifact | [`assets/yolov8n_int8_new_metadata.tflite`](../assets/yolov8n_int8_new_metadata.tflite) |
| Labels source | [`assets/labels.txt`](../assets/labels.txt) |
| Packaging status | generated |
| Label count | 80 |
| Base size | 3481792 bytes |
| Generated size | 3483114 bytes |
| Metadata payload | `1198` bytes |
| Base graph SHA-256 | `63bf9a81fe2e19f01b9ffe32531374c8a1f00d8e11ce5a0ce27008ce611d54fb` |
| Runtime artifact SHA-256 | `3a571033aedd222957e6f8973f30e48b9c55bce1572306c3d8b523b2a7919b6a` |
| Primary-subgraph tensor count | 448 |
| Generated tensor count | 448 |
| Primary-subgraph type counts | `{0: 2, 9: 356, 2: 90}` |

## Native metadata payload

The native Ultralytics loader accepts the following deterministic JSON shape and
converts the numeric `names` keys into class-index order:

```json
{"task":"detect","names":{"0":"person","1":"bicycle","2":"car","3":"motorcycle","4":"airplane","5":"bus","6":"train","7":"truck","8":"boat","9":"traffic light","10":"fire hydrant","11":"stop sign","12":"parking meter","13":"bench","14":"bird","15":"cat","16":"dog","17":"horse","18":"sheep","19":"cow","20":"elephant","21":"bear","22":"zebra","23":"giraffe","24":"backpack","25":"umbrella","26":"handbag","27":"tie","28":"suitcase","29":"frisbee","30":"skis","31":"snowboard","32":"sports ball","33":"kite","34":"baseball bat","35":"baseball glove","36":"skateboard","37":"surfboard","38":"tennis racket","39":"bottle","40":"wine glass","41":"cup","42":"fork","43":"knife","44":"spoon","45":"bowl","46":"banana","47":"apple","48":"sandwich","49":"orange","50":"broccoli","51":"carrot","52":"hot dog","53":"pizza","54":"donut","55":"cake","56":"chair","57":"couch","58":"potted plant","59":"bed","60":"dining table","61":"toilet","62":"tv","63":"laptop","64":"mouse","65":"remote","66":"keyboard","67":"cell phone","68":"microwave","69":"oven","70":"toaster","71":"sink","72":"refrigerator","73":"book","74":"clock","75":"vase","76":"scissors","77":"teddy bear","78":"hair drier","79":"toothbrush"}}
```

`labels.txt` remains authoritative. The packaging utility rejects empty or
duplicate labels and requires exactly 80 entries, so class index 41 resolves to
`cup` in the native metadata and in EyeCue's normalized detection adapter.

## Supported custom-model contract

A researcher can import their own detector from the Settings → Detector Model
card. What the app accepts (all enforced in
[`detector_model_service.dart`](../lib/services/detector_model_service.dart)):

| Requirement | Bound / rule |
|---|---|
| File type | A valid TFLite FlatBuffer, rejected when the structure cannot be parsed |
| Label source | Embedded Ultralytics metadata (`metadata.json` with `names`), read through the plugin's model inspection — labels are never guessed from a filename |
| Task | A task reported by native `inspect()` must be `detect`; a model whose metadata carries no task string is accepted when one output dimension matches `4 + classCount`, and refused when an in-range channel count exists but none matches the labels |
| Class agreement | The label count must equal the graph's class output; a mismatch is refused |
| File size | At most 40 MB (`kMaxImportBytes`) |
| Label count | At most 1 000 non-empty labels (`kMaxImportLabels`) |
| Display name | Researcher-entered, at most 40 characters |

Storage: the committed copy is `<fingerprint>.tflite` plus a
`<fingerprint>.labels.json` sidecar under the app's
`eyecue_models` documents directory, named by content fingerprint so a stale
graph cannot be served from a native filename/size cache. At most one custom
copy is retained; a replacement import deletes the previous one, and switching to
the built-in model deletes nothing so the last import stays re-selectable. The
bundled assets are never modified and the researcher's original file is never
touched (the picker's temporary copy is removed).

Not supported, and not promised: segmentation, classification, pose/keypoint or
any non-`detect` graph; ONNX, TensorFlow `SavedModel`/`.pb`, TFJS or TFLite
bundles that lack embedded label metadata. No accuracy, mAP, precision or recall
figure is produced for a custom graph, and none is implied by a successful
import. A custom model is not translated: its labels are shown and spoken as
written. Priority for a custom model is judged only by label text (a small fixed
high set such as person/vehicle/road-hazard names, a medium set for common
objects and structure, low for everything else), never by `classId`, so a custom
class `0` cannot inherit COCO person priority.

On startup, a selected custom model whose copy is missing or unreadable falls back
to the bundled detector with a visible message — the app never keeps claiming a
model it cannot load. Device execution of an imported graph remains unverified
(see [`known-issues.md`](known-issues.md)).

## Validation guarantees

- The generated artifact preserves the complete base FlatBuffer byte-for-byte.
- Primary-subgraph input/output indices, tensor shapes, tensor types, buffer
  indices, and internal tensor-type counts match the base artifact.
- The ZIP entry uses fixed timestamps, fixed attributes, and no compression so
  identical inputs produce identical output bytes.
- No weights, operators, tensor buffers, or learned parameters are rewritten.

Regenerate or validate with:

```text
dart run tool/package_ultralytics_metadata.dart --input=<base>.tflite
dart run tool/package_ultralytics_metadata.dart --check --input=<base>.tflite
```

This document is hand-maintained. The packaging tool now only writes an optional
measurement report when `--report=<path>` is passed explicitly, so running it
never replaces the depth and packaging sections above.
