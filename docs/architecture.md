# EyeCue architecture

> Current source baseline: local `main` at `aadf9e0` (2026-11-16). EyeCue has
> one native Ultralytics detection pipeline, an optional second depth-model
> instance, and separate `public` and `study` Android flavors. Device accuracy,
> latency, thermal behaviour, and broad lifecycle validation remain open; see
> [`benchmark-procedure.md`](benchmark-procedure.md) and
> [`known-issues.md`](known-issues.md).

## Purpose and supported runtime

EyeCue is an Android Flutter application that detects objects on-device and
provides spoken and visual guidance. Camera frames are processed locally by the
native CameraX/LiteRT path in the vendored `ultralytics_yolo` plugin. Results are
adapted into the app's shared detection model, with optional depth-derived
distance estimates. The application has Android platform code only; no iOS,
web, desktop, or React Native runtime is maintained here.

The bundled detector is the campus-trained 14-class model
[`assets/eyecue_v8_campus_only_w8a32.tflite`](../assets/eyecue_v8_campus_only_w8a32.tflite)
with [`assets/labels.txt`](../assets/labels.txt). A researcher may import one
compatible detector through Settings; this changes the selected model, not the
inference engine. Model identity and supported formats are documented in
[`model-assets.md`](model-assets.md). The optional `yolo26n-depth` model is a
second `YOLO` instance. Both models are bundled and run without app network
access.

## Runtime data flow

```text
CameraX analysis stream
        │
        ├── YOLOView / native LiteRT detector
        │       └── native result + metrics
        │               └── UltralyticsDetectionAdapter → Detection[]
        │
        └── optional native depth tick (same analysis Bitmap)
                └── compact block-mean grid → MonocularDepthEstimator
                         └── fresh, aligned depth → per-track estimate

Detection[] + optional metres
        └── AssistiveDetectionController
                ├── spatial analysis, priority, tracking, scene summary
                ├── track-aware alert policy → serialized TTS / haptics
                ├── correction and operational telemetry
                └── Detection screen overlays and accessible state
```

`YOLOView` owns camera capture and native detector inference. The adapter in
[`ultralytics_detection_adapter.dart`](../lib/services/ultralytics_detection_adapter.dart)
normalizes native results into [`Detection`](../lib/models/detection.dart).
[`AssistiveDetectionController`](../lib/services/assistive_detection_controller.dart)
owns the common post-detection behavior: spatial interpretation, tracking,
alert selection, TTS, haptics, correction records, and operational telemetry.
The app does not run a Dart inference isolate.

Depth uses the existing analysis frame on a native tick. It emits a bounded
block-mean grid and timing metadata, not a camera image. The Dart estimator
matches map geometry to upright detections, samples the inset region, takes a
median, and smooths per track. Valid depth estimates are approximate and
uncalibrated; missing or stale estimates fall back to bounding-box proximity.
The heatmap is a presentation layer and does not gate numerical distance use.
Details: [`mde-integration.md`](mde-integration.md).

## Cadence, configuration, and failure boundaries

[`InferenceCadence.resolve`](../lib/services/inference_cadence.dart) derives
effective detector and depth cadence from stored requests and power mode.
Detection is Automatic or 1–30 Hz; depth is 2–10 Hz. Low-power mode caps them
at 4 Hz and 2 Hz, and depth cannot outpace a numeric detector target. The
bounding-box mode disables depth inference. These are requested/effective
configuration values, not throughput claims. The native depth tick has one
in-flight guard and drops ticks while busy; it does not queue frames.

Depth load/inference, stale maps, and geometry mismatches degrade to the
bounding-box estimate without blocking detection. The shared app-shell-owned
[`EngineCoordinator`](../lib/services/engine_coordinator.dart) provides the
user-facing Detection lifecycle to Home and the Detection wrapper. The native
screen still owns camera/controller mechanics. Readiness is tied to valid
inference payload delivery, including a valid empty detection result.

<a id="speech-scheduling-workstream-1"></a>

The scheduler in [`tts_service.dart`](../lib/services/tts_service.dart) allows
one in-flight and one pending utterance, with track-aware policy and confirmed
start callbacks. Callback timing is an app-side proxy; audible latency has not
been established. See [`alert-responsiveness.md`](alert-responsiveness.md).

## Distribution flavors and privacy boundary

Gradle defines two distribution flavors:

| Flavor | Application ID | Entrypoint | Research features | Network permission |
|---|---|---|---|---|
| `public` | `app.eyecue.mobile` | `lib/main.dart` | Research sessions and Logs & Reports are not wired; Help exposes the privacy policy | No `INTERNET` permission in the release manifest |
| `study` | `app.eyecue.mobile.study` | `lib/main_study.dart` | Research-session persistence, Logs & Reports, manual export/upload | Adds `INTERNET` for explicit telemetry upload |

The flavor distinction is enforced in the entrypoint and manifests, not merely
by hiding controls. Camera detection and depth inference are offline in both
flavors. The Study upload is a user-initiated action and contains image-free
numeric telemetry; see [`supabase-research-telemetry.md`](supabase-research-telemetry.md)
and [`privacy-and-data-safety.md`](privacy-and-data-safety.md).

## Research sessions and telemetry

The Study entrypoint creates [`ResearchSessionService`](../lib/services/research_session_service.dart),
loads local trials, and watches detector model changes. A trial captures
detections, runtime samples, failures, fallbacks, recoveries, corrections, and
alert lifecycle records. Pause freezes study capture while live guidance and
operational telemetry continue. Draft checkpoints persist rows; local export
keeps the available trial data, while uploads over 2,000,000 bytes are refused
without thinning or deleting the local trial.

Operational `TelemetryService` is in-memory and bounded. Export schema is 4;
schema-4 adds depth/detector stage timings, cadence, alert-lifecycle details, and
detector attribution. Unknown values remain absent/null as specified by
[`telemetry-data-dictionary.md`](telemetry-data-dictionary.md). Public startup
does not instantiate research-session or Logs & Reports UI services.

## Source map

| Area | Main files | Responsibility |
|---|---|---|
| App startup | [`main.dart`](../lib/main.dart), [`main_study.dart`](../lib/main_study.dart), [`app.dart`](../lib/app.dart) | Public and Study dependency wiring, theme, app shell |
| Navigation and lifecycle | [`app_shell.dart`](../lib/navigation/app_shell.dart), [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart), [`engine_coordinator.dart`](../lib/services/engine_coordinator.dart) | Shared screen lifecycle and navigation |
| Camera and detection UI | [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart), `plugins/ultralytics_yolo/` | Native camera/inference UI and vendored plugin |
| Detection pipeline | [`ultralytics_detection_adapter.dart`](../lib/services/ultralytics_detection_adapter.dart), [`assistive_detection_controller.dart`](../lib/services/assistive_detection_controller.dart) | Native-result normalization and shared assistive behavior |
| Depth | [`monocular_depth_estimator.dart`](../lib/services/monocular_depth_estimator.dart), [`depth_distance_service.dart`](../lib/services/depth_distance_service.dart), [`depth_heatmap_view.dart`](../lib/widgets/depth_heatmap_view.dart) | Depth model lifecycle, distance sampling and display |
| Settings and model selection | [`app_settings.dart`](../lib/models/app_settings.dart), [`detector_model_service.dart`](../lib/services/detector_model_service.dart) | Persisted preferences and compatible model import/selection |
| Alerts and speech | [`alert_policy.dart`](../lib/services/alert_policy.dart), [`tts_service.dart`](../lib/services/tts_service.dart) | Track-aware eligibility and serialized speech |
| Study data | [`research_session_service.dart`](../lib/services/research_session_service.dart), [`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart) | Local trials and explicit Study upload |

## Historical implementation note

The earlier Dart/TFLite Custom inference engine, `tflite_flutter`, and its
camera-frame isolate were removed from the current build. Historical design
records in [`implementation-decisions.md`](implementation-decisions.md) and
older dated benchmark notes remain evidence about that prior implementation;
they do not describe the current runtime. `chat_spec.md` is an older
specification, not an implementation source of truth.
