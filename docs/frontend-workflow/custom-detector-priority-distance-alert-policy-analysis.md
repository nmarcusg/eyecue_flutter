# Custom Detector Priority and Distance Alert Policy — Analysis

**Task type:** logic/alert policy change; no intentional visual changes.

## Scope and repository state

This analysis is limited to the custom detector identity/labels, priority and spatial analysis, alert ranking and speech scheduling, metric-distance freshness/data flow, quick-scan behavior, directly related tests, and the model/architecture documentation that states their current contracts. No source code or existing document was changed as part of the inspection.

Read-only repository status was checked. The checkout is on `main` tracking `origin/main`. These pre-existing modified files must be preserved and are outside the feature's likely scope:

- [`lib/models/detection_info.dart`](../../lib/models/detection_info.dart)
- [`lib/widgets/detection_card.dart`](../../lib/widgets/detection_card.dart)
- [`lib/widgets/detection_information_overlay.dart`](../../lib/widgets/detection_information_overlay.dart)
- [`pubspec.lock`](../../pubspec.lock)
- [`test/services/spatial_analysis_service_test.dart`](../../test/services/spatial_analysis_service_test.dart)
- [`test/widgets/detection_information_overlay_test.dart`](../../test/widgets/detection_information_overlay_test.dart)

No untracked files appeared in the status output. The modified spatial-analysis test overlaps this feature's regression-test area; any future implementation must inspect and preserve those in-progress edits before changing that test.

## Existing behavior and dependency trace

### Detector selection, identity, and labels

- [`DetectorModelService`](../../lib/services/detector_model_service.dart) is the active selection owner. It loads bundled labels for the built-in detector; imported models must expose Ultralytics metadata labels, pass task and class-count validation, and are persisted with a content fingerprint and a sidecar containing their labels. The service keeps one custom import re-selectable while the built-in model is selected.
- [`DetectorModel`](../../lib/models/detector_model.dart) carries kind, display name, fingerprint, path, and the model's own label sequence. `DetectorModelRef` is the compact per-record identity. The custom priority resolver already exists here: built-in priority uses COCO class ID; custom priority uses normalized label text only, with fixed High/Medium sets and Low as the default. It intentionally does not infer custom semantics from a custom class ID.
- [`EyeCueModelConfig`](../../lib/models/model_config.dart) points the bundled detector at `assets/yolov8n_int8_new_metadata.tflite` and `assets/labels.txt`; the depth model is a separate asset and model identity. [`assets/labels.txt`](../../assets/labels.txt) contains the 80 COCO labels. The custom model's labels are not sourced from this file.
- [`UltralyticsDetectionAdapter`](../../lib/services/ultralytics_detection_adapter.dart) maps a returned class index to the supplied active model label list when the index is valid, falling back to the native result class name otherwise.
- [`docs/model-assets.md`](../model-assets.md) documents the import contract and explicitly describes current custom priority as a small fixed name set, independent of custom class IDs.

**Observed version-boundary conflict:** [`docs/architecture.md`](../architecture.md) says the Custom EyeCue *engine* and `tflite_flutter` were removed, while the repository still contains `DetectorModelService`, custom-model settings, and custom-label priority support for imported detector models running through the Ultralytics path. These are distinct meanings of “custom”: do not interpret imported custom detector models as a restored Custom EyeCue inference engine. Update architecture wording only if the feature's approved scope requires it; otherwise treat this as documentation context, not justification to modify architecture broadly.

### Priority resolver and spatial analysis

- [`AssistiveDetectionController.updateDetections`](../../lib/services/assistive_detection_controller.dart) passes normalized detector results, optional index-aligned metric metres, and its mutable `priorityResolver` into [`SpatialAnalysisService.analyzeAll`](../../lib/services/spatial_analysis_service.dart). It then updates tracks, records telemetry, and sends the analyzed `DetectionInfo` plus tracks to speech.
- The production wiring found is in [`UltralyticsDetectionScreen`](../../lib/screens/ultralytics_detection_screen.dart): it sets the resolver to `priorityForClass(_modelKind, d.classId, d.label)`, stamps detector identity, gets the active label list from the selected model, and passes current metric estimates into the shared controller. When no detector service is supplied, its test-compatible fallback uses built-in model kind and asset labels.
- [`SpatialAnalysisService`](../../lib/services/spatial_analysis_service.dart) derives position from normalized box center, priority from the resolver or default COCO class mapping, and proximity from finite metric metres or the unchanged box-height approximation. `analyzeAll` preserves incoming detection order; it does not rank or sort.
- [`DetectionInfo`](../../lib/models/detection_info.dart) retains both the qualitative proximity band and the distance source/optional metric estimate. Existing UI and speech consumers may use the distance label; this task is policy-only absent an explicit product request to alter presentation.

### Alert candidate ranking, decisions, speech scheduling, and revalidation

- [`SceneSummaryService.rankCandidates`](../../lib/services/scene_summary_service.dart) is the shared deterministic candidate ranking: priority first, then approaching/motion rank, proximity, confidence, label, and class ID. Alert policy calls this method rather than implementing a separate sort. Quick scan also uses the ranking, then groups up to its configured maximum by left/center/right position.
- [`AlertPolicy.decide`](../../lib/services/alert_policy.dart) chooses the first ranked candidate that is a new track/label identity or has a qualifying risk escalation. A suppressed primary does not cause a lower-ranked non-qualifying substitute to be announced. Risk includes near/approaching, medium proximity or center position; speech priority and preemption eligibility are derived separately from object priority and risk. Existing escalation includes risk tier, approaching transition, proximity transition during pending revalidation, center entry, and box/track height growth.
- Alert identity prefers tracker ID; without a track it falls back to label. State is committed only after a confirmed speech start via `commitStarted`; decisions are read-only and parked decisions are revalidated through `shouldSpeakPending` before speech.
- [`TtsService.announceDetections`](../../lib/services/tts_service.dart) submits policy decisions to a serialized scheduler with one active and one pending request. It applies semantic preemption rules, revalidates a parked policy decision immediately before start, and commits policy history on confirmed start. Any custom-priority/distance change that impacts candidate rank, risk, text, or pending eligibility must preserve these invariants rather than bypassing policy or the scheduler.
- Quick scan is a separate user-initiated speech origin: [`AssistiveDetectionController.quickScan`](../../lib/services/assistive_detection_controller.dart) calls `announceQuickScan`; [`TtsService.announceQuickScan`](../../lib/services/tts_service.dart) builds a full scene summary and submits it with user-initiated priority, without creating an `AlertDecision` or writing alert suppression history. Keep the feature's safety-alert policy separate from this deliberate whole-scene scan unless a confirmed requirement explicitly says otherwise.

### Depth source, freshness, and fallback

- [`UltralyticsDetectionScreen._depthFresh`](../../lib/screens/ultralytics_detection_screen.dart) rejects absent, stale, or geometry-mismatched depth frames; freshness uses `EyeCueModelConfig.depthStaleAfterMs` (currently 1000 ms). `_metersFor` returns no metric list if MDE is disabled or the current frame is not fresh; otherwise it samples each detection's box from the shared frame grid, applies the 12% inset and orientation conversion, takes a median of valid values, and applies tracker-keyed smoothing.
- [`DepthDistanceService`](../../lib/services/depth_distance_service.dart) validates samples and maps metric values to proximity bands (`<=1.5 m` near, `<=4 m` medium, else far). A missing/non-finite metric estimate falls back to bounding-box height and is labeled approximate. The model's metre output is explicitly uncalibrated in [`docs/model-assets.md`](../model-assets.md); it must not be described as a calibrated ground-truth distance.
- The detector and depth models are separate. Depth metres are transient inputs to `DetectionInfo`; depth telemetry is expressly separate from detector identity in [`TelemetryService`](../../lib/services/telemetry_service.dart). Do not attribute depth model identity, freshness, or timing to the imported detector.

## Existing tests and coverage seams

- [`test/models/detector_model_test.dart`](../../test/models/detector_model_test.dart) covers built-in versus custom label-based priority, ignoring custom class IDs, normalization, and detector identity/settings behavior.
- [`test/services/detector_model_service_test.dart`](../../test/services/detector_model_service_test.dart) covers model import/restore, embedded labels, validation and class-shape agreement.
- [`test/services/spatial_analysis_service_test.dart`](../../test/services/spatial_analysis_service_test.dart) covers COCO default priority, custom resolver behavior, metric and heuristic proximity, and mapping all detections. It is pre-modified in this worktree and must be treated as user work.
- [`test/services/alert_policy_test.dart`](../../test/services/alert_policy_test.dart) covers read-only decisions, start-commit lifecycle, track/label identity, suppression, risk escalation, candidate substitution suppression, and priority/gating. Review the remainder of the suite before defining exact new cases.
- [`test/services/scene_summary_service_test.dart`](../../test/services/scene_summary_service_test.dart) covers deterministic priority ordering, quick-scan spatial ordering/bounds, and input-order independence.
- [`test/services/tts_service_test.dart`](../../test/services/tts_service_test.dart) exercises fake TTS signal ordering, scheduler behavior, pending requests, preemption, and lifecycle. Current test status was not run in this analysis.
- [`test/services/metric_distance_test.dart`](../../test/services/metric_distance_test.dart), [`test/services/depth_distance_service_test.dart`](../../test/services/depth_distance_service_test.dart), [`test/services/depth_payload_parity_test.dart`](../../test/services/depth_payload_parity_test.dart), and [`test/screens/ultralytics_depth_status_test.dart`](../../test/screens/ultralytics_depth_status_test.dart) cover metric bands/wording, sampling/freshness, payload geometry/parity, and screen-level depth status/fallback areas respectively.
- [`docs/implementation-decisions.md`](../implementation-decisions.md) records the reason for the lifecycle-aware scheduler and its arbitration constraints. [`docs/testing-plan.md`](../testing-plan.md) explicitly says real Android callback ordering/cancellation and audible-warning latency remain unverified; its reported test totals are dated, not current verification.

## Exact policy boundary / potential conflict to resolve before implementation

The code already supports custom detector label priority and depth-derived distance in the common pipeline. Therefore, an implementation should not assume that custom-label priority or metric distance is currently absent. The feature's title signals a desired change to how custom-detector priorities and distance affect alerts, but the request supplied here does not define the new mapping, thresholds, precedence, wording, or whether it applies only to automatic safety alerts versus Quick Scan. Those are product-policy gaps, not inferable implementation details.

The current ranking elevates object priority before motion and distance; distance affects the proximity band, and proximity follows motion in rank. Alert risk/priority/preemption then use the ranked candidate's proximity, position, movement, and object priority. If the feature intends a different priority-vs-distance precedence, it will alter an established shared policy for both built-in and custom models unless the resolver/policy explicitly scopes the change to custom models. Existing custom priority is static label-derived; depth distance is available for the same detection independent of model kind. A safe implementation plan needs to state whether custom-only behavior changes just ranking/risk or also the resolver/utterance.

## Minimum likely implementation files

This list is conditional on the unresolved policy. It is a direct-dependency set, not approval to modify every listed file:

- [`lib/models/detector_model.dart`](../../lib/models/detector_model.dart) — only if the custom label-to-priority classification or its normalization changes.
- [`lib/services/scene_summary_service.dart`](../../lib/services/scene_summary_service.dart) — only if candidate ordering needs a custom-aware policy input or spoken alert/quick-scan ordering changes.
- [`lib/services/alert_policy.dart`](../../lib/services/alert_policy.dart) — only if automatic alert risk, priority, escalation, suppression, or preemption policy changes.
- [`lib/services/assistive_detection_controller.dart`](../../lib/services/assistive_detection_controller.dart) and [`lib/screens/ultralytics_detection_screen.dart`](../../lib/screens/ultralytics_detection_screen.dart) — only if policy context needs to be passed beyond the existing resolved `DetectionInfo` and its active detector model metadata. Current resolver and metric plumbing already operate here.
- [`test/models/detector_model_test.dart`](../../test/models/detector_model_test.dart), [`test/services/scene_summary_service_test.dart`](../../test/services/scene_summary_service_test.dart), [`test/services/alert_policy_test.dart`](../../test/services/alert_policy_test.dart), and/or [`test/services/assistive_detection_controller_test.dart`](../../test/services/assistive_detection_controller_test.dart) — targeted regression coverage according to the actual changed boundary.
- [`test/services/spatial_analysis_service_test.dart`](../../test/services/spatial_analysis_service_test.dart) is not safe to edit until its pre-existing working-tree changes are reviewed and reconciled with the requested behavior.
- Documentation: [`docs/model-assets.md`](../model-assets.md) only if custom-priority contract changes; [`docs/implementation-decisions.md`](../implementation-decisions.md) only if an existing scheduler/policy decision is intentionally revised; [`docs/testing-plan.md`](../testing-plan.md) only if this feature adds/changes verification requirements. No change is justified yet.

No visual files, asset bytes, `pubspec.yaml`, detector import validation, depth model, TTS platform adapter, or broad architecture documentation change is currently justified by the stated task alone.

## Open Questions / Needs Verification

- **[product-decision]** Define the desired custom detector priority tiers: labels/categories or model-provided metadata, behavior for unknown/unmatched labels, and whether current fixed High/Medium sets remain or are replaced.
- **[product-decision]** Define priority-versus-distance precedence for alert candidate ranking. Current behavior is priority → motion → proximity → confidence → label/class ID; confirm whether custom detectors should use a distinct ordering and whether the built-in detector must remain unchanged.
- **[product-decision]** Define what makes a distance-based warning eligible: metric bands, box-approximation fallback, and/or approaching motion; confirm thresholds and whether distance can promote an otherwise low-priority custom object.
- **[product-decision]** Confirm whether the change applies only to automatic detection alerts, or also changes Quick Scan ordering/wording. Current Quick Scan is deliberately separate from alert suppression and uses scene ranking.
- **[product-decision]** Specify any utterance changes and preemption/escalation semantics. Current alert wording differentiates urgent and normal decisions, and scheduler history is committed only on confirmed speech start.
- **[Needs Verification — inferred-from-codebase]** Confirm whether the requirement is for imported custom models only (currently run via the Ultralytics engine) or also includes the bundled model. The repository no longer contains the separate Custom EyeCue inference engine, despite older documents and terminology that may use “custom” ambiguously.
- **[Needs Verification — source unavailable in this task]** Physical-device depth freshness, actual metric estimate reliability, and TTS callback ordering/cancellation latency were not verified; project docs explicitly record these runtime safety limitations.
- **[Needs Verification — worktree constraint]** The existing modifications to `test/services/spatial_analysis_service_test.dart` must be inspected before any future implementation touches that file.
