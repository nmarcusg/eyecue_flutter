# Fresh Detection Speech Revalidation — Plan

**Task type:** behavior/logic change; no visual changes expected. The information overlay may clear or update in response to accepted detector results, but its visual design is not in scope.

## Source of truth and scope

- Required analysis: [`fresh-detection-speech-revalidation-analysis.md`](fresh-detection-speech-revalidation-analysis.md).
- This plan follows the explicit decisions in the task prompt where they resolve the analysis questions. No design-spec is required because the work changes freshness and speech behavior, not visual output.
- Limit implementation to the active Ultralytics result callback, the shared assistive/speech pipeline, the TTS scheduler/policy, and direct tests. There is one active detector callback path; do not create or document a separate Custom-screen path.
- Preserve the current one-active/one-pending scheduler, callback reconciliation, cooldown and confirmed-start suppression semantics. Do not change unrelated tracker retention, depth estimation, overlay layout, or storage/server schemas.

## Behavior contract

### Freshness and observation provenance

1. Give each accepted detector result a receipt timestamp from a monotonic elapsed-time source where supported, and an injectable clock seam for deterministic tests. Keep receipt time distinct from native frame production time: the current Ultralytics callback does not expose the latter, so receipt age is the enforceable bound, not proof of source-frame age.
2. Use a configurable maximum automatic-detection age of **500 ms**. Reject automatic detection speech whose observation is older than this bound at the point it could actually start. Do not use tracker-retained entries as evidence that a target remains eligible.
3. Carry result provenance sufficient to reject obsolete state: result receipt time plus session, model and camera-generation identity. Validate these values when accepting a callback, updating the latest observation, and immediately before speech starts. Existing native-view callback epoch checks remain in place and are included in the provenance comparison rather than replaced.
4. Maintain one authoritative latest accepted observation/current visible-target set. It represents the detections in the latest accepted result, not all internally retained tracks. Result receipt time starts the age window; tracker timestamps must not become a substitute freshness clock.
5. An accepted fresh empty result is meaningful: it replaces the current visible-target set with empty, clears the current detection/overlay snapshot through the existing state flow, invalidates unstarted automatic speech for absent targets, and starts the disappearance grace timer for a matching already-started automatic utterance. An empty result is not equivalent to no callback.
6. Revalidate target membership, receipt age, and session/model/camera provenance immediately before the scheduler initiates actual automatic speech. A queued decision is not valid merely because its alert-policy record is still live. Use current observation membership, not parked decision data or retained tracker entries, as the source of eligibility.
7. Keep depth freshness independent. The 500 ms detector observation rule must not change the existing depth age/geometry validation, imply metric depth freshness, or change approximate box-based spatial estimates.

### Scheduler, lifecycle and manual speech

1. Clear unstarted automatic detection speech on pause, stop, app background, camera-generation change, model switch, or session switch. Invalidation removes automatic requests only; it must not free the scheduler to violate in-flight callback reconciliation or create a second active utterance.
2. Preserve explicit Quick Scan and Repeat Last as manual user actions, exempt from automatic detection freshness and automatic-target invalidation. Their existing request-validity bounds and scheduler serialization remain in force. Their text must not become an automatic detection request or commit alert-policy suppression history.
3. Preserve suppression commit only on confirmed platform start. Discarded, expired, invalidated, or cancelled-before-start requests do not commit suppression and do not restart or advance the detection announcement cooldown. Continue reconciling start/completion/cancel callbacks according to the existing serialized callback model; a stop request alone is not evidence that audio ended.
4. For an automatic utterance whose target disappears from an accepted fresh result, use a bounded grace of **250 ms from the first accepted missing-target/empty result**. If the backend exposes a usable cancellation operation, request cancellation only after that grace and only if the latest accepted result still excludes the target. Do not cancel earlier if the target reappears during the grace.
5. Preserve `utteranceStarted` / `utteranceFinished` callback reconciliation for that cancellation path. After the grace-triggered stop request, the active slot remains governed by actual callbacks or existing timeout/recovery behavior; no successor speech starts based solely on requesting stop.
6. If cancellation is unsupported or cannot be reliably requested, document that the current utterance may finish. Do not allow additional or pending automatic speech to proceed unless a fresh current observation validates it. Manual explicit replay remains governed by its existing policy.
7. Background transitions invalidate pending automatic speech and freshness state. On foreground/resume, do not revive a prior observation; require a newly accepted result before automatic speech can qualify. Do not assume OS suspension cancels platform audio.

### Timing and diagnostics

- Record receipt-to-scheduler-start age and invalidation/cancellation outcomes using existing telemetry/lifecycle diagnostic facilities only where those facilities can represent the event without changing unrelated reporting behavior.
- Do not add database persistence, upload fields, server endpoints, or export schema fields. Any diagnostic-only extension must be scoped to existing in-memory/event telemetry and retain current privacy boundaries.
- Keep monotonic timing for age and grace intervals separate from wall-clock timestamps used for human-readable telemetry if the current telemetry contract requires wall time.

## Justified file scope

Only these files are justified by the required analysis and prompt; implementation must stop and seek approval if investigation shows any additional production file is necessary.

### Production

- [`lib/screens/ultralytics_detection_screen.dart`](../../lib/screens/ultralytics_detection_screen.dart) — attach accepted receipt/provenance at the native callback boundary; invalidate on pause/stop/background and camera/model/session generation changes; preserve the existing native epoch guard; pass the accepted empty result and context to the shared controller. No plugin/native result-envelope expansion is authorized by this plan.
- [`lib/services/assistive_detection_controller.dart`](../../lib/services/assistive_detection_controller.dart) — own or forward the authoritative latest accepted observation/current visible-target state and provenance; replace it for every accepted result including empty results; forward current evidence for pre-speech validation. Avoid a duplicated independent freshness clock.
- [`lib/services/alert_policy.dart`](../../lib/services/alert_policy.dart) — retain its target selection and suppression rules while incorporating current observation eligibility into pending automatic decision validation, only if this is the narrowest existing policy seam confirmed during implementation.
- [`lib/services/tts_service.dart`](../../lib/services/tts_service.dart) — add injectable monotonic-time access as needed; preserve bounded slots and confirmed-start commit; revalidate automatic requests immediately before actual scheduler start; clear pending automatic work on invalidation; implement the bounded disappearance grace and optional cancellation without bypassing callback reconciliation; keep manual Quick Scan/repeat separate.

The exact placement of the authoritative observation snapshot between controller, policy and scheduler must be chosen so there is one source of truth; it must not become three independently updated freshness stores. No changes to [`lib/models/detection_info.dart`](../../lib/models/detection_info.dart), tracker-retention logic, depth services, detection overlay/widget visuals, native plugin, backend, or persistence are currently justified.

### Tests

- [`test/services/assistive_detection_controller_test.dart`](../../test/services/assistive_detection_controller_test.dart) — accepted non-empty and empty observations replace current visibility, receipt/provenance forwarding, and no tracker-retained target eligibility.
- [`test/services/alert_policy_test.dart`](../../test/services/alert_policy_test.dart) — pending automatic decision fails when latest observation omits target, exceeds 500 ms, or has mismatched session/model/camera generation; confirmed-start suppression semantics remain intact.
- [`test/services/tts_service_test.dart`](../../test/services/tts_service_test.dart) — injected monotonic clock boundary cases, revalidation immediately before actual start, automatic queue clearing for each invalidation reason, no cooldown/suppression commit on discarded request, 250 ms grace timing, reappearance during grace, supported/unsupported cancellation behavior, callback reconciliation after stop request, and unchanged Quick Scan/repeat behavior.
- [`test/screens/ultralytics_detection_readiness_test.dart`](../../test/screens/ultralytics_detection_readiness_test.dart) — callback provenance/epoch rejection and lifecycle invalidation at the screen boundary, including background/foreground requiring a new accepted result.

Do not edit the previously modified [`test/services/spatial_analysis_service_test.dart`](../../test/services/spatial_analysis_service_test.dart) or overlay tests: analysis does not establish them as required for this behavior.

## Implementation sequence

1. Recheck the worktree before editing, per the analysis caveat; inspect pre-existing changes in any selected file and preserve them.
2. Define one observation/provenance contract and injectable monotonic clock seam, keeping native result-production time explicitly unavailable.
3. Update screen callback acceptance and lifecycle invalidation to stamp and forward receipt/provenance, including accepted empty results.
4. Update shared controller/policy eligibility so only the latest visible target with matching provenance can qualify for automatic speech.
5. Update TTS scheduler invalidation and last-moment validation while preserving the bounded queue, confirmed-start suppression, cooldown, and manual replay separation.
6. Add the 250 ms disappearance grace and backend-capability-aware cancellation, retaining active-slot ownership until callback reconciliation or existing recovery timeout.
7. Add the focused unit/screen tests listed above; run targeted tests, then `flutter test` and `flutter analyze`.
8. Perform physical Android verification of actual TTS start/completion/cancellation ordering, target disappearance and reappearance, pause/stop/background transitions, and absence of stale automatic speech. Report device/backend cancellation limitations rather than treating requested stop as confirmed cancellation.
9. Update only directly relevant root documentation if implementation changes a documented contract; do not update `.roo/rules/docs/` unless an allow-listed root document changes, and do not alter unrelated telemetry/export schemas.

## Acceptance criteria

- Automatic detection speech starts only if the latest accepted result includes that target, is no older than 500 ms according to monotonic elapsed time, and matches current session/model/camera provenance at actual scheduler start.
- A fresh empty result clears visible targets and invalidates queued automatic speech; tracker retention cannot restore eligibility.
- Pending automatic requests are invalidated at all listed lifecycle/generation boundaries, and foreground requires a new detector result.
- An already-started automatic utterance is allowed the bounded 250 ms disappearance grace before a supported cancellation request; cancellation is not treated as completion, and callback reconciliation remains authoritative.
- A backend without reliable cancellation may finish the current utterance, but invalid pending automatic speech does not follow it.
- Quick Scan and Repeat Last remain explicit manual replay paths and are not invalidated by automatic freshness rules.
- Discarded requests do not commit suppression or restart cooldown; confirmed platform start remains the only suppression commit point.
- Depth freshness rules and visual layout remain unchanged; no new persistence or server schema is introduced.
- Targeted tests, full test suite and static analysis pass; physical-device observations and any unsupported backend behavior are documented.

## Open Questions / Needs Verification

- **250 ms disappearance grace — [product-decision] / Needs Verification:** this is the requested bounded default proposal, not an explicitly confirmed product value. Confirm the selected duration before implementation; if not confirmed, keep 250 ms as a clearly identified proposed default and do not silently present it as settled.
- **Cancellation capability — Needs Verification:** confirm whether the active Android TTS backend can reliably cancel a started utterance and how its callbacks are ordered. If unsupported, current audio may finish; the plan still requires blocking subsequent stale automatic speech.
- **Monotonic clock implementation — Needs Verification:** confirm the project/toolchain's available monotonic elapsed-time source and lifecycle behavior. Retain an injectable clock for tests. Do not fall back to wall-clock age silently if monotonic elapsed time is available.
- **Source-frame age limitation — Needs Verification:** the native result callback currently supplies no production timestamp/correlation token. This plan enforces receipt-age freshness and known generation provenance but cannot prove the underlying frame itself is at most 500 ms old. Native/plugin envelope changes require separate approval.
- **Existing telemetry representation — Needs Verification:** verify whether existing lifecycle/telemetry records can capture the scoped timing and invalidation reasons without schema or reporting changes. If not, omit the extra metric rather than expanding persistence/export/server contracts.
- **Worktree status — Needs Verification:** analysis could not check current git status and recorded a prior snapshot of modified files. Recheck before implementation and avoid overwriting unrelated user changes.
- **Physical-device validation — Needs Verification:** callback timing, audible cancellation latency, lifecycle background behavior, and post-resume freshness remain unobserved until verified on the Android device.
