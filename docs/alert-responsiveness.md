# Automatic obstacle alert responsiveness

Automatic speech uses the latest valid inset-region median from fresh,
geometry-matched numerical depth. The presentation EMA is separate and advances
once per current track/depth observation, so repeated detector callbacks cannot
manufacture distance evidence. Numerical depth publishes before heatmap work;
visualization has one active build and one latest pending image.

New numerical depth can reevaluate cached detections without another detector
result. This does not update tracker hits, append detection rows, increase frame
counts, or extend the original 500 ms monotonic detector freshness bound. Model,
camera, session and geometry boundaries invalidate cached evidence. Heatmap-only
updates retain their observation revision and cannot trigger another evaluation.

## Distance controls

Settings → distance controls offers Alert distance (1–5 m) and Urgent distance
(0.5 m to at least 0.25 m below Alert distance), in 0.25 m steps. Defaults remain
2 m/1.5 m with 0.3 m re-arm hysteresis. Normal eligibility includes its boundary;
urgent eligibility is strictly below its boundary. Both built-in and custom
models use the same centered-obstacle policy. These controls govern automatic
speech, not model recognition range. Per-class overrides are intentionally absent.

Metres are approximate MDE estimates, not calibrated physical measurements.
Bounding-box mode disables these controls while retaining their saved values;
its bounded center/near fallback never invents metres. Invalid persisted pairs
reset together to defaults. Configuration changes invalidate unstarted automatic
work and suppression, preserving active speech and Repeat.

Automatic phrases are obstacle-first and concise. Quick Scan remains detailed.
Equal-priority warnings wait for active speech; strictly higher-priority eligible
warnings retain bounded preemption. Missing detections do not cut active speech.

## Research records

Starting a trial captures a versioned alert configuration (thresholds,
hysteresis, evidence/wording policy, initial depth mode and requested cadence).
Thresholds remain fixed while a draft is open, including paused/restored drafts;
Finish or explicitly discard it before editing. The application settings setter
also enforces the lock. Other cadence/mode changes remain represented by existing
runtime telemetry; the captured configuration describes the trial's initial setup.

The snapshot survives checkpoints, restart, Finish and JSON/CSV/upload export.
Finished exports use captured configuration rather than later Settings. Legacy or
invalid configuration stays unknown. Upload remains manual, retains all local
rows, and refuses bodies exceeding 2,000,000 bytes without thinning. No migration
or Edge Function deployment is required for this additive settings metadata.

## Diagnostics and validation limits

Developers can opt into `TtsService(enableDecisionDiagnostics: true)` for a
bounded 256-entry local monotonic trace. It separates first observed, first
eligible, queued, submitted, confirmed start and terminal/discarded stages, with
raw/display distance and request-time thresholds. It contains no speech text,
images, credentials or device identifiers, and is not respondent upload data.
Missing starts remain absent, never zero latency. Pending same-target refreshes
preserve the first eligibility anchor.

Deterministic tests cover stalled heatmaps, fresh close evidence after far
history, repeated map reuse, stale/context rejection, unchanged counters,
retreat revalidation, threshold boundaries, restored/exported configuration and
speech continuity. These establish application behavior, not audible performance
or depth calibration. Native depth timestamps represent completion/emission,
not camera capture; TTS start callbacks are a platform proxy, not measured sound.
Physical cold/warm latency, noisy depth, thermals, TalkBack and scene testing
remain device validation work. Default inference rates are unchanged.
