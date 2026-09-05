# Telemetry export data dictionary

EyeCue exports an image-free snapshot only after an explicit user action from
Logs & Reports. JSON keeps the same values in nested record arrays. CSV uses one
stable wide header and a `record_type` column; columns that do not apply to a row
are empty.

## Common fields

| CSV column | Meaning | Units / values |
|---|---|---|
| `record_type` | Row kind | `metadata`, `sample`, `detection`, `failure`, `fallback`, `recovery`, or `correction` |
| `schema_version` | Export schema version | Integer; currently `1` |
| `timestamp` | Event or export time | UTC ISO-8601 timestamp |
| `app_version` | Application version | Version string; metadata rows only |
| `session_id` | In-memory session identifier | Opaque session string; metadata/correction rows |
| `session_start` | Session start time | UTC ISO-8601 timestamp; metadata rows only |
| `session_duration_ms` | Session duration at export | Milliseconds; metadata rows only |
| `engine` | Engine that produced a record | `custom` or `ultralytics` |

## Runtime samples

`sample` rows describe an inference update and use:

| CSV column | Meaning | Units / values |
|---|---|---|
| `latency_ms` | Inference or native processing latency | Milliseconds |
| `inference_fps` | Observed inference rate | Frames per second |
| `object_count` | Number of normalized detections | Count |
| `confidence_threshold` | Active pre-NMS confidence threshold | Unit interval, quantized to the app's configured grid |

## Detections

`detection` rows use:

| CSV column | Meaning | Units / values |
|---|---|---|
| `class_id` | Model class index | Integer; COCO index when using the bundled model |
| `label` | Authoritative label resolved from `labels.txt` | UTF-8 text |
| `confidence` | Detection confidence | Unit interval `[0, 1]` |
| `latency_ms` | Latency associated with the detection update | Milliseconds |
| `priority` | EyeCue priority interpretation | `high`, `medium`, or `low` |
| `position` | Relative horizontal position | EyeCue position label |
| `proximity` | Approximate visual proximity band | EyeCue proximity enum; not a measured distance |
| `track_id` | Optional bounded tracker identifier | Integer or empty |
| `motion` | Optional confirmed movement state | `unknown`, `stable`, `approaching`, or `movingAway` |

## Failures, fallback, and recovery

`failure` rows use `category`, `safe_message`, `recoverable`, `retry_count`, and
`fallback_available`. Technical exception details and internal paths are not
exported.

`fallback` rows use `preferred_engine`, `active_engine`, and `reason` to record
an engine change without changing the persisted preference.

`recovery` rows use `type`, `generation`, `restart_attempt`, and
`failure_category`. They record bounded Custom-worker recovery transitions and
never contain camera frames, model inputs, or exception text.

## Corrections

`correction` rows use `record_id`, `session_id`, `feedback`, `corrected_label`,
`confidence_threshold`, and the original detection's `class_id`, `label`, and
`confidence`. Corrections are image-free research annotations; they do not
modify the live model.

## Privacy and retention

Exports do not include camera images, forensic PNGs, device identifiers,
absolute internal paths, or network-upload fields. The in-memory service keeps
bounded lists and writes files only when the user selects an export action.
