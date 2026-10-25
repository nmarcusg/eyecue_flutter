# Telemetry export data dictionary

> **Status:** export schema version 4 (unreleased Workstream 2 candidate).
> Version 4 adds the detector and depth stage timings, the reported depth
> accelerator, the depth grid size, the heatmap build cost and the cumulative
> `depthDroppedTicks` counter to each sample. The exporter records bounded
> alert-lifecycle records, a cumulative scheduler counter snapshot, four
> Ultralytics alert-latency summaries, and the inference cadence configuration in
> addition to the per-frame inference data described below. All alert timings
> come from the app's own speech-scheduler signals, so they describe the app-side
> path only; physical audible-warning latency at the speaker is **not** measured.
> No device run has validated this instrumentation.
>
> **Every schema-4 sample key is optional on read.** A schema-3 payload simply
> lacks them, and an unmeasured value is absent — never `0`.

EyeCue exports an image-free snapshot only after an explicit user action from
Logs & Reports. JSON keeps the same values in nested record arrays. CSV uses one
stable wide header and a `record_type` column; columns that do not apply to a row
are empty.

## Common fields

| CSV column | Meaning | Units / values |
|---|---|---|
| `record_type` | Row kind | `metadata`, `sample`, `detection`, `failure`, `fallback`, `recovery`, `correction`, `alert_lifecycle`, `alert_counter`, or `alert_summary` |
| `schema_version` | Export schema version | Integer; currently `4` |
| `timestamp` | Event or export time | UTC ISO-8601 timestamp |
| `app_version` | Application version | Version string; metadata rows only |
| `session_id` | In-memory session identifier | Opaque session string; metadata/correction rows |
| `session_start` | Session start time | UTC ISO-8601 timestamp; metadata rows only |
| `session_duration_ms` | Session duration at export | Milliseconds; metadata rows only |
| `engine` | Engine that produced a record | `ultralytics` (single engine) |

## Runtime samples

`sample` rows describe an inference update and use:

| CSV column | Meaning | Units / values |
|---|---|---|
| `latency_ms` | Inference or native processing latency | Milliseconds |
| `inference_fps` | Detector observed FPS: the native inference rate the plugin reported | Frames per second; `0` means "not reported", because the plugin defaults a missing rate to `0` and cannot distinguish that from a real zero |
| `object_count` | Number of normalized detections | Count |
| `confidence_threshold` | Active pre-NMS confidence threshold | Unit interval, quantized to the app's configured grid |
| `requested_detection_hz` | Stored detector target | Hz, or empty when the target is Automatic |
| `detection_cadence_automatic` | Detector target is Automatic, not a stored number | Boolean |
| `effective_detection_hz` | Detector cadence actually allowed at sample time | Hz, or empty when uncapped |
| `requested_depth_hz` | Stored depth target | Hz, or empty when unknown |
| `effective_depth_hz` | Depth cadence actually allowed at sample time; `0` when depth work is off | Hz, or empty when unknown |
| `depth_observed_hz` | Observed depth completion cadence: a stop-surviving EMA that includes idle gaps; unsettled for the first samples after a resume | Hz, or empty when not yet measured |
| `depth_latency_ms` | Last completed depth inference | Milliseconds, or empty when not yet measured |
| `depth_status` | Depth model state | `disabled`, `loading`, `gpu`, `cpu`, `degraded`, or empty |
| `detector_pre_ms` | Detector preprocessing (letterbox + normalization) | Milliseconds, or empty when native did not report it |
| `detector_inference_ms` | Detector model inference | Milliseconds, or empty when native did not report it |
| `detector_post_ms` | Detector postprocessing (decode + NMS) | Milliseconds, or empty when native did not report it |
| `depth_pre_ms` | Depth preprocessing | Milliseconds, or empty when native did not report it |
| `depth_inference_ms` | Depth model inference | Milliseconds, or empty when native did not report it |
| `depth_post_ms` | Depth postprocessing | Milliseconds, or empty when native did not report it |
| `depth_accelerator` | Accelerator native resolved for the depth instance | `gpu`/`cpu`, or empty while unknown |
| `depth_grid_width` | Width of the emitted block-mean depth grid | Blocks, or empty before the first depth frame |
| `depth_grid_height` | Height of the emitted block-mean depth grid | Blocks, or empty before the first depth frame |
| `heatmap_build_ms` | Dart-side cost of building the display heatmap | Whole milliseconds (a stopwatch reading, so `0` means "< 1 ms"), or empty while no heatmap is held (overlay hidden, no image built, or depth off) |
| `depth_dropped_ticks` | **Cumulative** native count of depth ticks skipped so far | Count, or empty until a depth event arrives |
| `low_power_clamped` | Low power mode lowered the stored target | Boolean |
| `source_limited` | Depth target exceeds the detector cadence that feeds it | Boolean |

- `requested_detection_hz` empty means Automatic; it is never a fabricated
  default rate. `effective_detection_hz` empty means uncapped.
- `requested_depth_hz` and `effective_depth_hz` are empty when the sample
  predates cadence telemetry. Empty means unknown, never `0`.
- `depth_observed_hz`, `depth_latency_ms`, and `depth_status` are empty when the
  sample predates cadence telemetry or the engine never observed a value. Empty
  means unknown, never `0`.
- `depth_observed_hz` is an exponential moving average that survives detection
  stops and includes idle gaps, so it is not a steady-state throughput figure
  and is unsettled for the first samples after a resume.
- `depth_status` reports `disabled` when distance estimation is off, otherwise
  the model state (`loading`/`degraded`) or the accelerator of the loaded model
  (`gpu`/`cpu`). `loading` also covers an enabled estimator that has not started
  yet.
- Cadence values are frozen into each sample when it is recorded: a settings
  change is attributed from the next sample onward.
- The stage timings, `depth_accelerator`, the grid size, `heatmap_build_ms` and
  `depth_dropped_ticks` are frozen the same way, and are recorded only while
  distance estimation is on. `detector_*` values come from the native streaming
  metrics; `depth_*` values come from the last completed native depth event.
- Every one of those keys is **omitted** when it has no value, so a schema-3
  reader and a schema-4 reader agree that an absent key is unknown. `0` is never
  written in place of an unknown, and a real `0 ms` stage is reported as `0`.
- `depth_accelerator` and `depth_status` are different things: the first is
  exactly what native resolved, the second folds in `disabled`/`loading`/
  `degraded`. `depth_status` reads `loading` while the estimator is ready but no
  depth event has arrived yet, because the accelerator is still unknown then.
- `depth_dropped_ticks` is a **cumulative** native counter, not a per-sample
  drop count: derive a per-interval delta by differencing consecutive samples
  (or by resetting at a known tick restart). It counts skipped depth *ticks* —
  an interval that had not elapsed, or an inference already in flight — so at a
  2 Hz depth target on a 30 fps stream it mostly measures the cadence gate. It
  is not a dropped-frame count.
- There is no `depth_queue_wait_ms` column. Depth cadence, latest-frame-wins and
  the in-flight guard are native, so no frame ever waits in a Dart queue and a
  number here would be fabricated; exporting a constant `null` was 12 KB of
  padding at the sample cap and was removed.
- `heatmap_build_ms` is presentation cost only: it prices the overlay, not the
  depth pipeline. It is absent while no heatmap is held — it is cleared when the
  overlay is hidden, when the frame is cleared (pause/release/dispose) and it is
  only written when the builder actually returned an image — so it never goes
  stale while depth is still on.
- **The tertiary perf keys are thinned to every fifth sample.** `detector_pre_ms`,
  `detector_inference_ms`, `detector_post_ms`, `depth_pre_ms`,
  `depth_inference_ms`, `depth_post_ms`, `depth_accelerator`, `depth_grid_width`,
  `depth_grid_height`, `heatmap_build_ms` and `depth_dropped_ticks` are written on
  samples 0, 5, 10, … only, and are empty on the samples between them. The
  cadence, `inference_fps`, `latency_ms`, `object_count` and the boolean flags
  stay on every sample. Thinning itself drops no record; the rolling window
  described below is the one cap that does drop samples. Read medians and
  `depth_dropped_ticks` deltas from the samples that carry the keys.
- `inference_fps` **is** the detector observed FPS. The same number used to be
  duplicated into `detector_observed_fps` (nullable, `null` for unreported),
  which cost about 12.5 KB at the sample cap; the duplicate key was removed.
  `inference_fps: 0` therefore means "not reported".
- Session wall-clock lives on the export header (`session.durationMs`, CSV
  `session_duration_ms`), not on each sample: it is one value per export, and
  repeating it on all 400 retained samples would only inflate the payload.

## Rolling sample window

The service keeps the most recent **400** samples and discards the **oldest** ones
as new ones arrive (`_maxSamples`). At a 0.5 Hz cadence that is ≈13 minutes of
history; the window slides for the whole session and never grows. Consequences a
researcher must account for:

- **`sample 0` is the oldest *retained* sample, not the session's first sample.**
  In a long session it sits ≈13 minutes before export time, so a "start of
  session" reading taken from sample 0 is wrong; use `session.start` and
  `session.durationMs` from the header instead.
- **The strided perf keys can differ between exports of the same growing
  session.** Samples leave in arrival order, so the survivors stay contiguous,
  but which survivor holds the perf keys (samples 0, 5, 10, …) shifts as the
  window slides. Aggregate the perf keys by value; never key them to an absolute
  sample index.
- Every other collection is capped the same way, oldest first: 2,000
  detections, 2,000 corrections, 500 alert-lifecycle records, 200 failures, 200
  recoveries, 100 fallbacks.
- No record is ever partially written, re-ordered, or shortened.

## Serialised precision

Device numbers are Float32-derived doubles: a normalised box coordinate arrives
as `0.34545454545454546` and a detection confidence as `0.8700000047683716`. The
exporter rounds **only the serialised output** so the payload stays inside the
ingest bound; the stored samples keep full precision, so band and priority
classification, in-app comparisons and speech text are unaffected.

| Field(s) | Decimal places |
|---|---|
| box `left`, `top`, `width`, `height` (detections and a correction's embedded detection) | 4 |
| `confidence`, `confidence_threshold` | 3 |
| `latency_ms`, `inference_fps`, `depth_observed_hz`, `p50_ms`, `p95_ms`, `max_ms` | 1 |
| `detector_pre_ms`, `detector_inference_ms`, `detector_post_ms` | 2 |

4 dp on a normalised coordinate is ≈0.1 px of a 1080 px frame, and 2 dp keeps a
4.75 ms stage timing intact where 1 dp would report 4.8 ms.

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
| `engine` | Inference engine for detection alerts | `ultralytics`, or empty; legacy exports may contain `custom` |
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
- New records are Ultralytics-only: they carry `result_received_at` and later
  app-side anchors, while pre-result analysis and inference anchors stay empty
  because the plugin exposes no per-result identity for them. The
  `frame_number` and analysis/inference columns remain in the schema for legacy
  Custom exports; the Custom engine was removed on 2026-10-21.
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

`alert_summary` CSV rows (JSON `alertSummaries`) contain four rows, one per
interval, for the single Ultralytics engine.

| CSV column | Meaning |
|---|---|
| `engine` | `ultralytics` |
| `interval` | `receivedToAccepted`, `acceptedToStarted`, `submittedToStarted`, or `receivedToStarted` |
| `label` | Human-readable interval label; the Ultralytics variants name the app-side boundary |
| `p50_ms`, `p95_ms`, `max_ms` | Nearest-rank percentile and maximum, in milliseconds |
| `sample_count` | Number of retained records that qualified |

| Interval | Start → end |
|---|---|
| `receivedToAccepted` | `result_received_at` → `detection_accepted_at` |
| `acceptedToStarted` | `detection_accepted_at` → `alert_started_at` |
| `submittedToStarted` | `submitted_at` → `alert_started_at` |
| `receivedToStarted` | `result_received_at` → `alert_started_at` |

- Samples are detection-origin records whose `engine` exactly matches the row
  and whose two endpoints are both present. Negative intervals are excluded;
  zero-duration intervals are kept.
- Percentiles use nearest rank over the retained samples: `p50` = rank
  `ceil(0.50 × n)`, `p95` = rank `ceil(0.95 × n)`, and `max` is the last sorted
  value. When nothing qualifies, `sample_count` is `0` and all values are `0`;
  Logs & Reports then shows `No samples` instead of a percentile.
- Ultralytics work has no pre-result anchors, so `receivedToStarted` starts at
  result receipt; its label is exactly
  `Result received → alert started (app-side / post-inference)`. It is never
  full inference latency and never end-to-end latency. Legacy Custom records
  (removed engine) started at analysis receipt after the app's pause/busy gates
  and ran through worker inference and result publication.

## Privacy and retention

Exports do not include camera images, forensic PNGs, device identifiers,
absolute internal paths, or network-upload fields. The alert lifecycle, counter,
and summary payloads add no utterance text, image, bounding box, device
identifier, internal path, exception detail, or secret; they contain timing,
outcome, and count metadata only. The in-memory service keeps bounded lists and
writes files only when the user selects an export action.

## Schema compatibility

Schema versions 3 and 4 only add keys and columns (version 4 later dropped the
`detector_observed_fps` and `depth_queue_wait_ms` columns, which repeated or
always-null data); no surviving key or column changes meaning. Reading a
schema-v1 JSON export yields empty `alertLifecycle` and `alertSummaries` lists
and the default zero `alertCounters` snapshot. Reading a schema-v1 or schema-v2
sample without the cadence keys yields `null`/empty cadence values rather than
`0`, so older files stay loadable and “unknown” stays distinguishable from
“zero”.

`TelemetryExport.toJson` always stamps the current `schemaVersion`, so
re-exporting a restored schema-3 file produces a header saying `4` while its
sample rows are still schema 3 (no schema-4 keys). That is harmless because every
schema-4 key is optional — but a reader must not infer the row shape from the
header alone. Server-side gating must keep accepting rows that lack the schema-4
keys instead of rejecting a payload because its header claims schema 4.
