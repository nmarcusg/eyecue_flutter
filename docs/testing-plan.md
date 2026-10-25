# EyeCue — Testing Plan

> See also: [`architecture.md`](architecture.md) (system design), [`implementation-progress.md`](implementation-progress.md) (what's built).

> **Verification status (2026-10-23):** the totals in the next paragraph are **historical**, recorded before the Workstream 1 TTS relocation onto `origin/dev`. The current branch runs `flutter analyze --no-pub` (4 pre-existing issues) and `flutter test --no-pub` (527 passing, 1 known pre-existing `tts_service_test` failure); no Gradle, build, emulator or device command has been run. Treat every passing count below as dated evidence, not current verification.
>
> For the speech layer specifically: tests exist for the serialized scheduler, alert policy, escalation, semantic pending revalidation, preemption/anti-churn, and idle-only wayfinding, and they run in the current suite. Real Android callback ordering and cancellation latency are unverified on device. `flutter_tts` provides **no utterance identifier**, so callback correlation relies on serialization plus paired signals, with a bounded quiet-period mitigation. Alert-latency telemetry is implemented and its owning tests run in the current suite; the recorded intervals are app-side only (the Ultralytics interval is `app-side / post-inference`), so neither inference timing nor these summaries may be treated as physical audible-warning latency. Prompt, correct audible warnings are **not** proven for independent navigation.

> **Historical suite (2026-09-29 — pre-relocation):** at that revision `flutter test` reported **343 passing, 0 failing** and `flutter analyze` reported **0 issues**; these figures do **not** describe the current branch. Existing automated coverage lives in [`test/`](../test/): navigation shell (including primary gesture navigation), screen smoke tests, widgets (priority badge, detection card, warning banner, accessible button, charts, correction flows, and the Detection redesign's [`detection_action_controls_test.dart`](../test/widgets/detection_action_controls_test.dart)), services (TTS, settings, spatial, telemetry, gesture controller, engine coordination, recovery lifecycle, metadata/export), theme regression, NHWC/NCHW tensor-rotation tests, engine-setting persistence, per-engine telemetry, and Ultralytics-result adaptation. The 59-test v0.2.2 suite remains the historical release baseline; the tables below distinguish deterministic automated coverage from physical-device/manual validation that is still pending.

## Unit Testing Strategy

### Core Pipeline Tests (Critical Path)

| Test | Priority | Description |
|------|----------|-------------|
| TFLite model loading | 🔴 P0 | Verify `Interpreter.fromBuffer()` loads without crash; check input/output tensor metadata |
| YUV→RGB conversion correctness | 🔴 P0 | Verify against known test image with pre-computed RGB output |
| YOLOv8 output parsing | 🔴 P0 | Verify argmax with pre-computed synthetic tensor; check class ID, confidence, bounding box |
| INT8 dequantization | 🔴 P0 | Verify scale/zeroPoint math against known values |
| Label loading | 🟢 P2 | Verify 80 COCO labels parsed correctly from `labels.txt` |
| NHWC/NCHW detection | 🟢 P2 | Test channel-order heuristic with both layout types |
| NHWC/NCHW tensor rotation | 🟢 P2 | Verify identity, 90°/180°/270°, mirror, buffer guards, and logical equivalence across interleaved and planar layouts — ✅ 14 unit tests |
| Detection model serialization | 🟢 P2 | Verify `Detection` class JSON serialization/deserialization |

### Inference Isolate Tests

| Test | Priority | Description |
|------|----------|-------------|
| Isolate spawn and communication | 🟡 P1 | Verify SendPort/ReceivePort message passing works |
| Frame dropping logic | 🟡 P1 | Verify `_isInferring` gate prevents concurrent inference |
| Error propagation and bounded recovery | 🟡 P1 | Verify typed isolate errors reach the main isolate, worker generations reject stale messages, retries are bounded, and disposal cancels pending recovery |
| Buffer reuse | 🟢 P2 | Verify pre-allocated buffers are reused (no new allocations per frame) |

### Edge Function contract tests (CLI-free)

```sh
node --test supabase/functions/ingest-telemetry/validate.test.mjs
```

36 cases over [`validate.js`](../supabase/functions/ingest-telemetry/validate.js): every
forbidden key at three depths, the `frameNumber` allowance, each mistyped envelope
field, supported and unsupported schema versions, and the 2 000 000 / 2 000 001-byte
body boundary. No Deno, Docker, Supabase CLI or `package.json` is involved. The SQL
migration and the function's own TypeScript are still not executed anywhere
(`BLOCKED-EXTERNAL` — see [`play-store-readiness.md`](play-store-readiness.md) §7).

## Widget Testing Strategy

| Test | Priority | Description |
|------|----------|-------------|
| Detection screen renders | 🟡 P1 | Verify camera preview widget mounts |
| Detection overlay renders | 🟡 P1 | Verify `CustomPainter` draws boxes correctly |
| Permission-denied UI | 🟡 P1 | Verify fallback UI renders when permission is denied |
| Loading state UI | 🟢 P2 | Verify loading spinner renders during camera init |
| Error state UI | 🟡 P1 | Verify error message renders on isolate failure |
| Pause/resume button | 🟢 P2 | Verify toggle changes detection state |
| Screen/navigation smoke tests | ✅ | Home / Settings / Help screens + 4-tab shell (implemented) |
| Primary gesture navigation | ✅ | One-finger linear non-wrapping shell navigation, boundary attempts, second-pointer invalidation, feedback origin, accessibility/bar truth table, real Slider ownership, route/Back isolation, and cached Detection page preservation (implemented) |
| Gesture pointer contract (2026-10-25) | ✅ | Commit-on-release and exactly-one-pointer enforced by deterministic recognizer-controller tests, no wall-clock sleeps: [`gesture_controller_test.dart`](../test/services/gesture_controller_test.dart) — a valid single-finger swipe, a long swipe (16 incremental moves), a fast swipe (one jump), nothing committed before `onPointerUp` in any of them, a second pointer invalidating the whole sequence, a second pointer that enters and then leaves unable to re-arm it, a cancelled directional move never firing, a clean sequence after an invalidated one still working, and the existing tap/two-finger/three-finger/swipe-down arbitration; [`app_shell_test.dart`](../test/navigation/app_shell_test.dart) — long and fast swipes moving exactly one tab with the tab asserted unchanged after every move, a short swipe not navigating, a second pointer entering and leaving (first pointer then completing a full-length swipe) not navigating, a second pointer without movement still invalidating, and system Back from another tab returning to Home with no gesture feedback; [`gesture_navigation_direction_test.dart`](../test/screens/gesture_navigation_direction_test.dart) — the real screen pumped on a 390×844 surface: the gesture surface spans the whole main area and stops at the action-controls row, a swipe in that area navigating exactly once and only on release, long/fast swipes navigating exactly once each, a swipe starting on the action-controls row not navigating, and a second pointer invalidating a Detection sequence |
| Gesture surface bounds | ✅ | The Detection gesture region is the whole flexible main area (top bar and action-controls row excluded), so horizontal navigation is not confined to the camera viewport |
| Safety disclosure (2026-10-25) | ✅ | [`help_screen_test.dart`](../test/screens/help_screen_test.dart): the permanent Help section renders the heading plus the five required points in order, the wording carries every required prohibition ("does not replace", "white cane", "guide dog", "stop using") with no certification/proof/safety-guarantee claim, and both the Help section and the first-use dialog are complete with no exception at 200 % text scale; [`semantics_test.dart`](../test/accessibility/semantics_test.dart): one `isHeader` node read before its five body nodes in one group, the title announced exactly once; [`app_shell_test.dart`](../test/navigation/app_shell_test.dart): the first-use surface appears for a fresh settings state, a barrier tap does not dismiss it, only the explicit "I understand" action does, the acknowledgement persists so a second shell shows nothing, and the Help copy stays readable afterwards; [`settings_service_test.dart`](../test/services/settings_service_test.dart): the acknowledgement defaults to unacknowledged, notifies and round-trips (implemented) |
| Assistive widgets | ✅ | Priority badge, detection card, warning banner, accessible button (implemented) |
| Charts | ✅ | Latency/FPS/frequency chart bounds incl. empty/very-high/constant data (implemented) |
| Detection redesign controls (PD2) | ✅ | [`detection_action_controls_test.dart`](../test/widgets/detection_action_controls_test.dart): coordinator-outcome label/secondary-text/enabled mapping, physical Quick Scan gating, pointer-down 0% progress across the full three-second hold, `kLongPressTimeout` `KEEP HOLDING` classification without progress restart, early-release tap mapping, abandoned-hold suppression, single-dispatch lock, and cancellation (implemented) |
| Detection redesign overlay (PD3) | ✅ | Compact two-row overlay selection (stable High promotion preserving source order, no Medium-over-Low ranking), non-live informational semantics, and hidden-outside-Ready behavior (implemented) |

## Integration Testing Strategy

| Test | Priority | Description |
|------|----------|-------------|
| Camera → Isolate → Detection pipeline | 🔴 P0 | End-to-end: start camera, receive frame, run inference, get detections |
| Detection → TTS pipeline | 🟡 P1 | End-to-end: detection triggers speech |
| Camera permission flow | 🟡 P1 | Full flow: request → grant → initialize; request → deny → fallback UI |
| Isolate lifecycle | 🟡 P1 | Spawn at startup, survive multiple inferences, dispose on app exit |
| Model swap | 🟢 P2 | Dynamic tensor shape query handles different model shapes |
| Engine switch | 🟡 P0 | One-device bidirectional smoke pass completed after fixing a late-result disposal race; repeated/rotated/background lifecycle coverage remains |
| Ultralytics native path | 🟡 P0 | On-device camera → native preprocessing/inference/NMS → EyeCue adapter/cards ran on Snapdragon 695; controlled TTS/telemetry/delegate validation remains |
| Custom worker lifecycle orchestration | ✅ | Deterministic coverage for respawn, stale generations, busy-gate release, delayed retry, terminal failure, disposal during backoff, and healthy recovery |
| Accessibility semantics and large text | ✅ | Deterministic coverage for actionable labels, live regions, charts, correction controls, and 200% text scale |

## Manual Testing Checklist

### Camera & Preview
- [ ] Camera preview is smooth (no visible stuttering)
- [ ] Camera initializes within 2 seconds on cold start
- [ ] Camera preview orientation matches device orientation
- [ ] Preview fills screen correctly on different aspect ratios

### Inference
- [x] Both engine modes load the same model and thresholds — shared configuration plus APK/device smoke verification
- [ ] Switching engines does not leave the camera occupied or duplicate speech
- [ ] Detection FPS meets or exceeds target on test device
- [ ] Inference does not cause camera preview hitching
- [ ] Detections are reasonably accurate (qualitative assessment)
- [ ] No memory leaks during sustained use (>5 minutes)

### Audio Feedback (TTS implemented v0.2.0)
- [x] TTS speaks detected objects clearly — ✅ implemented (`tts_service.dart`), dedicated on-device audio validation pending
- [x] TTS does not overlap/spam — ✅ strict serialized speech (one active utterance, one pending slot), track-aware suppression, confirmed-`onStart` commits, semantic escalation/revalidation, and controlled preemption are implemented. Automated tests exist but have **not** been executed since the relocation, and physical Android validation remains pending.
- [ ] TTS latency from detection to speech is acceptable
- [ ] TTS works with screen reader (TalkBack) active

### Accessibility
- [x] All tested interactive elements have TalkBack labels — broad semantics coverage is automated; device TalkBack validation remains manual
- [ ] Gesture controls work (double-tap, swipe)
- [ ] Primary gesture navigation works on-device — automated coverage is complete (`CONFIRMED-BY-TEST`, `6a0fe65`: commit-on-release, whole-main-area Detection region, second-pointer invalidation); this checkbox is the **device gate only** — the committed feel, haptic/TTS timing and TalkBack interaction still need one physical Android pass. See [`known-issues.md`](known-issues.md)
- [x] Safety disclosure is reachable and understandable with TalkBack — automated semantics coverage exists (one heading node, five body nodes in reading order, no duplicate announcements at 200 % text scale); the first-use acknowledgement and the Help section still need one physical TalkBack read-through
- [ ] High-contrast mode is readable
- [ ] App is fully navigable without vision

### Presentation-Only Visual Redesign (Confirmed 2026-09-29)
- [x] Fixed/non-scrollable Home normal composition and enlarged fixed decorative logo render as required, with shared lifecycle status and shell navigation behavior retained.
- [x] The retained four-tab bottom navigation has the approved light/Home-theme presentation while destination order, selection, callbacks, visibility preference, accessibility override, Back behavior, and gesture ownership remain unchanged.
- [x] Settings control hierarchy/alignment, cyan active controls, icon-free presentation, truthful System Performance values, and the existing Logs entry callback are visually confirmed.
- [x] Help's icon-free cards and app-bar title, plus the consistent fixed light surfaces while Settings, Help, and Logs & Reports scroll, are visually confirmed.
- [x] Both Detection presentations have confirmed title contrast, edge-inset left-aligned information overlay, and two-card action-control treatment; lifecycle, gesture, hold/tap, Quick Scan, and semantics behavior remain unchanged.
- [x] Physical Android visual checks for this redesign were explicitly confirmed by the user. No visual requirements remain outstanding for this redesign.

### Error Handling
- [ ] Camera permission denied → shows explanation UI
- [ ] Model fails to load → shows error UI
- [x] Typed Dart-level inference failures → bounded Custom-worker recovery is covered by deterministic orchestration tests; native crashes such as SIGSEGV remain outside Dart guarantees and require device validation
- [ ] Device rotation → no state loss

## Benchmark Plan

See [`benchmark-results.md`](benchmark-results.md) for the recording template.
For the two selectable runtime modes, follow the paired protocol in [`dual-inference-engine-test.md`](dual-inference-engine-test.md).

### Required Benchmarks

1. **Raw Model Latency:** Run each declared model candidate through the TFLite benchmark tool on the target device; the current NCHW/XNNPACK candidate has initial short-run device evidence, but has not yet received a formal benchmark
2. **End-to-End Pipeline FPS:** Measure detection FPS on target device under sustained use
3. **Preprocessing Latency:** Profile YUV→RGB conversion time
4. **Memory Usage:** Monitor heap usage during 5-minute continuous detection
5. **Battery Consumption:** Measure battery drain per minute of active detection
6. **Thermal Behavior:** Record device temperature during sustained use

## Validation Steps for Major Features

### Feature: TTS Audio Feedback
1. Start app → point camera at a person → verify "person" is spoken within 500ms
2. Point camera at multiple objects → verify highest-confidence object is spoken
3. Keep camera on same object → verify TTS cooldown prevents spam
4. Switch objects → verify new object is spoken immediately

### Feature: Bounding Box Overlay
1. Start app → verify boxes appear over detected objects
2. Move camera → verify boxes track objects smoothly
3. Multiple objects → verify multiple distinct boxes (one per object — class-wise NMS at IoU 0.45 suppresses duplicates)
4. Box scaling → verify boxes are correctly positioned regardless of preview size

### Feature: Error Recovery
1. Force model load failure → verify error UI appears
2. Force inference crash → verify isolate restarts automatically
3. Force camera disconnect → verify app handles gracefully

### Feature: Performance Logging
1. Enable logging → verify FPS, latency, and confidence are recorded — ✅ telemetry records these (v0.2.0)
2. Export logs → verify data is in parseable format (JSON/CSV) — ✅ JSON/CSV export and round-trip coverage implemented
3. Dashboard → verify `fl_chart` renders real-time metrics — ✅ Logs & Reports Overview/Charts/Logs (v0.2.0–v0.2.2)
