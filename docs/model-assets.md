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
| Model ID | `yolo26n-depth` |
| Android artifact | `yolo26n-depth_w8a32.tflite` |
| Source | plugin-pinned GitHub release `v0.6.6` |
| Cache | `<app documents>/mobile-standard-v1/` |
| Loaded by | `MonocularDepthEstimator` (second `YOLO` instance, `YOLOTask.depth`) |
| Vendored in repo | no (downloaded on first use; offline degrades to bbox distance) |

Depth values are metres as produced by the model; they are **uncalibrated**.
See [`mde-integration.md`](mde-integration.md).

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

## Validation guarantees

- The generated artifact preserves the complete base FlatBuffer byte-for-byte.
- Primary-subgraph input/output indices, tensor shapes, tensor types, buffer
  indices, and internal tensor-type counts match the base artifact.
- The ZIP entry uses fixed timestamps, fixed attributes, and no compression so
  identical inputs produce identical output bytes.
- No weights, operators, tensor buffers, or learned parameters are rewritten.

Regenerate or validate with:

```text
dart run tool/package_ultralytics_metadata.dart
dart run tool/package_ultralytics_metadata.dart --check
```
