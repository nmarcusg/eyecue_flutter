# Model assets

> Current runtime assets at local `main` (`aadf9e0`, 2026-11-16). The earlier
> YOLOv8 COCO and NCHW candidate records in other dated documentation are
> historical and do not identify the current detector.

EyeCue bundles the campus-trained detector and the official Ultralytics depth
model. Both are declared as Flutter assets in [`pubspec.yaml`](../pubspec.yaml)
and are available offline. The public release has no `INTERNET` permission;
the Study flavor adds it only for the optional manual telemetry upload. No
model, labels, or metadata is downloaded at runtime.

## Bundled detector

| Field | Value |
|---|---|
| Runtime artifact | [`assets/eyecue_v8_campus_only_w8a32.tflite`](../assets/eyecue_v8_campus_only_w8a32.tflite) |
| Display identity | `EyeCue campus detector` (`builtin-campus-v1`) |
| Size | 3,452,275 bytes |
| SHA-256 | `91c25102eb1d2f42a94f7a563118f93605ee0e9e3e8ba2a85157f25bb0a8e2a1` |
| Metadata | Ultralytics v8.4.197, task `detect`; artifact metadata declares AGPL-3.0 |
| Labels | 14, in order from [`assets/labels.txt`](../assets/labels.txt) |
| Inference path | Native `YOLOView` using `ultralytics_yolo` |

The ordered class labels are `bench`, `bicycle`, `car`, `cat`, `chair`, `door`,
`fan`, `hand-rails`, `person`, `pole`, `stairs`, `table`, `trash_bin`, and
`warning_marker`. Do not interpret class IDs as COCO IDs. The model was supplied
as a campus-trained artifact; its training pipeline and dataset provenance are
not in this repository. See [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)
for the recorded provenance statement and unresolved review items.

## Optional depth model

| Field | Value |
|---|---|
| Model | `yolo26n-depth` |
| Runtime artifact | [`assets/yolo26n-depth_w8a32.tflite`](../assets/yolo26n-depth_w8a32.tflite) |
| Size | 5,474,749 bytes |
| SHA-256 | `8c7f242c2a8c339c6721863e103e17e026cbd784c9a3d031a8e902660c364311` |
| Source | Official `yolo26n-depth_w8a32.tflite` from pinned `yolo-flutter-app` release `v0.6.6`, copied unchanged |
| Task and shape | `depth`; input `[1,3,640,640]`, output `[1,1,640,640]` |
| Quantization / license | `w8a32`; metadata declares AGPL-3.0 |
| Loaded by | `MonocularDepthEstimator`, as a second `YOLO` instance |

The artifact is a TFLite FlatBuffer with an appended deflated `metadata.json`
entry. The estimator passes `YOLOTask.depth` explicitly. Model depth values are
uncalibrated estimates; see [`mde-integration.md`](mde-integration.md).

## Packaging and imported models

Only the campus detector, depth model, labels, logo, and fonts are bundled by
`pubspec.yaml`. The prior YOLOv8 artifacts described in historical benchmark and
implementation notes are not current runtime assets. The campus detector is
selected by [`EyeCueModelConfig.modelAssetPath`](../lib/models/model_config.dart).

A researcher may import one compatible detector through Settings. It must be a
TFLite detection graph with embedded Ultralytics label metadata; the import
service checks task/class agreement, size and label bounds, then stores an
app-owned fingerprint-named copy. This feature selects another graph in the
same native engine; it does not restore the removed Dart/TFLite engine. Details
and limits are in the import contract below.

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
class `0` cannot inherit a built-in hazard priority.

### Automatic distance alerts

Automatic alerts for built-in and imported models share one configurable
distance policy, while imported models continue to use the verified active
detector identity and label-derived priority. Defaults are **urgent below 1.5 m**,
**normal metric alert from 1.5 m through 2.0 m**, and **no metric-distance alert
beyond 2.0 m**. Metric-distance alerts require a center-path detection. Ranking
precedence is urgent escalation, center-path relevance, model-specific class
priority, eligible metric distance, then confidence.

Only a fresh, valid, geometry-matched MDE estimate within the existing 0.1–80 m
valid range participates in these thresholds. A missing, invalid, stale, or
misaligned estimate is never treated as safe or far. Geometry-only automatic
fallback is limited to center-path detections in the near proximity band and is
always described as approximate; geometry is never metric threshold evidence
and cannot be described as a metric/far/safe result. Metric hysteresis re-arms
beyond the applicable threshold by 0.3 m. Stationary tracks remain deduplicated
through the existing alert lifecycle. User-initiated Quick Scan remains
independent and may narrate objects outside automatic-alert thresholds.

These are centralized initial tuning defaults, not calibrated distance claims.
Thresholds and hysteresis require measured physical-device validation and may be
adjusted through the policy configuration; passing tests does not establish MDE
accuracy, safety, or audible timing.

On startup, a selected custom model whose copy is missing or unreadable falls back
to the bundled detector with a visible message — the app never keeps claiming a
model it cannot load. Device execution of an imported graph remains unverified
(see [`known-issues.md`](known-issues.md)).

## Evidence boundary

The asset byte sizes and SHA-256 digests above identify the files currently in
the checkout. `assets/labels.txt` is the current ordered class list. The campus
detector is a supplied trained model, not an artifact reproducibly generated by
`tool/package_ultralytics_metadata.dart`; that tool's historical YOLOv8
packaging notes do not establish the campus model's training provenance or
accuracy. A successful import validates the import contract, not detector
quality or on-device execution.
