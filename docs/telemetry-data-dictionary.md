# Telemetry export data dictionary

> **Status:** export schema version 2 (unreleased Workstream 2 candidate). The
> exporter records bounded alert-lifecycle records, a cumulative scheduler
> counter snapshot, and eight alert-latency summaries in addition to the
> per-frame inference data described below. All alert timings come from the
> app's own speech-scheduler signals, so they describe the app-side path only;
> physical audible-warning latency at the speaker is **not** measured. The
> owning tests were written but not executed, and no analyzer, build, or device
> run has validated this instrumentation.

EyeCue exports an image-free snapshot only after an explicit user action from
Logs & Reports. JSON keeps the same values in nested record arrays. CSV uses one
stable wide header and a `record_type` column; columns that do not apply to a row
are empty.

## Common fields

| CSV column | Meaning | Units / values |
|---|---|---|
| `record_type` | Row kind | `metadata`, `sample`, `detection`, `failure`, `fallback`, `recovery`, `correction`, `alert_lifecycle`, `alert_counter`, or `alert_summary` |
| `schema_version` | Export schema version | Integer; currently `2` |
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

## Alert lifecycle

`alert_lifecycle` CSV rows (JSON `alertLifecycle`) record one terminal outcome
per submitted TTS request as an event delta. The service keeps only the most
recent 500 records, so the summaries and exports describe that retained window,
not a lifetime total.

| CSV column | Meaning | Units / values |
|---|---|---|
| `origin` | What produced the request | `detection`, `generic`, `wayfinding`, `quickScan`, or `repeatLast` |
| `engine` | Inference engine for detection alerts | `custom`, `ultralytics`, or empty |
| `requested_at` | Alert-policy request time | UTC ISO-8601 |
| `submitted_at` | Submission to the speech engine | UTC ISO-8601 |
| `alert_started_at` | Confirmed native `onStart` | UTC ISO-8601 or empty |
| `terminal_at` | Terminal outcome time; also the CSV `timestamp` | UTC ISO-8601 |
| `terminal_state` | Terminal outcome | `completed`, `cancelled`, `dropped`, or `failed` |
| `terminal_cause` | Internal terminal cause identifier (`preempted`, `startNotConfirmed`, `completionNotConfirmed`, `reconciliationTimeout`, or `engineError`) | Text or empty |
| `had_started` | Whether the native start callback was confirmed | Boolean |
| `reconciled_at` | Time paired signals reconciled the outcome | UTC ISO-8601 or empty |
| `frame_number` | Custom frame association | Integer or empty |
| `analysis_received_at` | Custom frame accepted after all dispatch gates | UTC ISO-8601 or empty |
| `inference_started_at` / `inference_completed_at` | Custom worker interpreter boundaries | UTC ISO-8601 or empty |
| `result_received_at` | Result received on the main isolate | UTC ISO-8601 or empty |
| `detection_accepted_at` | Controller entry for the accepted result | UTC ISO-8601 or empty |

- `engine` is populated only for `detection` origin; generic, wayfinding,
  quick-scan, and repeat-last requests are engine-null by construction.
- `alert_started_at` is written only from a confirmed native `onStart`. A
  request that never started leaves it empty, and every interval that needs it
  is skipped for that record.
- `reconciled_at` is truthful rather than optimistic: it carries the terminal
  time only for paired completion, cancellation, or platform drop. Watchdog and
  error failures leave it empty.
- Custom records carry `frame_number` and the analysis/inference/result
  anchors. Ultralytics records carry only `result_received_at` and later
  app-side anchors; pre-result analysis and inference anchors stay empty because
  the plugin exposes no per-result identity for them.
- Any anchor that was never observed is empty. A record can contribute to some
  intervals and not others; empty is not zero.

## Alert counters

`alert_counter` CSV rows (JSON `alertCounters`) hold the latest **cumulative**
scheduler snapshot. Telemetry replaces the stored snapshot with each new value;
values must never be added across rows or exports.

| CSV column | Meaning |
|---|---|
| `counter_name` | Counter key listed below, or `rejectedByReason` |
| `counter_value` | Cumulative count |
| `reason` | Rejection reason name; populated only for `rejectedByReason` rows |

| JSON key | Meaning |
|---|---|
| `dropped` | Submissions that ended with result `0`, no start callback, and no locally requested stop |
| `cancelledBeforeStart` / `cancelledAfterStart` | Paired cancellations before/after a confirmed start |
| `failedBeforeStart` / `failedAfterStart` | Failed submissions before/after a confirmed start |
| `reconciliationTimeout` | Failures that ended on the reconciliation timeout |
| `watchdogRecovery` | Watchdog-triggered recoveries that actually started |
| `quietPeriodCapReached` | Quiet-period quarantine reached its maximum duration |
| `recoveryFailed` | Recovery attempts that failed |
| `quarantinedCallback` | Callbacks received during quarantine and ignored |
| `lateCallbackIgnored` | Late result callbacks ignored after a terminal state |
| `callbackOrderViolation` | Out-of-order lifecycle callbacks |
| `preemptionRequested` | Preemption attempts |
| `preempted` | Confirmed preempted cancellations |
| `superseded` | Pending requests displaced by a newer request, any alert type |
| `muted` | Decisions rejected because audio was muted, any alert type |
| `staleDecision` | Parked decisions discarded as stale when the queue drained |
| `rejectedAfterRecovery` | Decisions rejected after recovery exhausted its retries |
| `rejectedByReason` | Map of alert-policy rejection reason name to count |

## Alert summaries

`alert_summary` CSV rows (JSON `alertSummaries`) contain eight rows: four
intervals for each inference engine.

| CSV column | Meaning |
|---|---|
| `engine` | `custom` or `ultralytics` |
| `interval` | `receivedToAccepted`, `acceptedToStarted`, `submittedToStarted`, or `receivedToStarted` |
| `label` | Human-readable interval label; the Ultralytics variants name the app-side boundary |
| `p50_ms`, `p95_ms`, `max_ms` | Nearest-rank percentile and maximum, in milliseconds |
| `sample_count` | Number of retained records that qualified |

| Interval | Custom start → end | Ultralytics start → end |
|---|---|---|
| `receivedToAccepted` | `analysis_received_at` → `detection_accepted_at` | `result_received_at` → `detection_accepted_at` |
| `acceptedToStarted` | `detection_accepted_at` → `alert_started_at` | `detection_accepted_at` → `alert_started_at` |
| `submittedToStarted` | `submitted_at` → `alert_started_at` | `submitted_at` → `alert_started_at` |
| `receivedToStarted` | `analysis_received_at` → `alert_started_at` | `result_received_at` → `alert_started_at` |

- Samples are detection-origin records whose `engine` exactly matches the row
  and whose two endpoints are both present. Negative intervals are excluded;
  zero-duration intervals are kept.
- Percentiles use nearest rank over the retained samples: `p50` = rank
  `ceil(0.50 × n)`, `p95` = rank `ceil(0.95 × n)`, and `max` is the last sorted
  value. When nothing qualifies, `sample_count` is `0` and all values are `0`;
  Logs & Reports then shows `No samples` instead of a percentile.
- Custom anchors start at analysis receipt after the app's pause/busy/low-power
  gates and run through worker inference and result publication. Ultralytics has
  no pre-result anchors, so its `receivedToStarted` label is exactly
  `Result received → alert started (app-side / post-inference)`. It is never
  full inference latency and never end-to-end latency.

## Privacy and retention

Exports do not include camera images, forensic PNGs, device identifiers,
absolute internal paths, or network-upload fields. The alert lifecycle, counter,
and summary payloads add no utterance text, image, bounding box, device
identifier, internal path, exception detail, or secret; they contain timing,
outcome, and count metadata only. The in-memory service keeps bounded lists and
writes files only when the user selects an export action.

## Schema compatibility

Schema version 2 only adds keys and rows; no existing key or column changes
meaning. Reading a schema-v1 JSON export yields empty `alertLifecycle` and
`alertSummaries` lists and the default zero `alertCounters` snapshot, so older
files stay loadable.
