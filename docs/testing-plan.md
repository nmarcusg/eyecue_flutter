# EyeCue — Testing Plan

> See also: [`architecture.md`](architecture.md) (system design), [`implementation-progress.md`](implementation-progress.md) (what's built).

> **Current evidence boundary (local `main`, 2026-11-16):** this document
> contains dated test and device-validation records, not a test run on the current
> checkout. The most recent recorded static suite is dated 2026-11-09
> (`flutter test`: 882 passing, 0 failing; `flutter analyze`: 0 issues). Treat
> those totals as historical evidence. Current campus-model accuracy,
> performance, and broad device lifecycle validation remain open.
>
> The app now has one native Ultralytics detection engine; the old Dart/TFLite
> isolate tests and dual-engine checks below are historical plan items. Research
> sessions, Logs & Reports, and their exports are wired only by the Study
> entrypoint (`lib/main_study.dart`). Public `lib/main.dart` does not wire them.
>
> For speech, code and deterministic tests cover serialization, track-aware
> alert policy, revalidation, and timing records. Native callback ordering,
> audible latency, and safety for independent navigation are not established by
> those tests. Dated device-check notes below preserve their original evidence
> date and are not fresh validation of local `main`.

## Unit Testing Strategy

### Historical Dart/TFLite pipeline test plan (removed runtime)

| Test | Priority | Description |
|------|----------|-------------|
| TFLite model loading | 🔴 P0 | Verify `Interpreter.fromBuffer()` loads without crash; check input/output tensor metadata |
| YUV→RGB conversion correctness | 🔴 P0 | Verify against known test image with pre-computed RGB output |
| YOLOv8 output parsing | 🔴 P0 | Verify argmax with pre-computed synthetic tensor; check class ID, confidence, bounding box |
| INT8 dequantization | 🔴 P0 | Verify scale/zeroPoint math against known values |
| Label loading | 🟢 P2 | Verify 14 campus-model labels parsed correctly from `labels.txt` |
| NHWC/NCHW detection | 🟢 P2 | Test channel-order heuristic with both layout types |
| NHWC/NCHW tensor rotation | 🟢 P2 | Verify identity, 90°/180°/270°, mirror, buffer guards, and logical equivalence across interleaved and planar layouts — ✅ 14 unit tests |
| Detection model serialization | 🟢 P2 | Verify `Detection` class JSON serialization/deserialization |

### Historical inference-isolate tests (removed runtime)

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
| TalkBack operability and de-duplication (2026-11-08) (device-verified) | ✅ | [`detection_action_controls_test.dart`](../test/widgets/detection_action_controls_test.dart): semantic long-press on the lifecycle card stops (ready/paused) or starts (stopped) exactly once, stopped exposes no tap action, and preparing/unavailable expose no long-press; real-screen coverage asserts the audio pill's single mute/unmute node (it no longer exposes Repeat); [`semantics_test.dart`](../test/accessibility/semantics_test.dart): Home exposes one status node, each slider yields one name node plus an adjustable node announced in hertz, and `AccessibleButton` exposes no hint; [`logs_reports_screen_test.dart`](../test/screens/logs_reports_screen_test.dart): section headings and de-duplicated rows produce one stop; [`talkback_no_gesture_hints_test.dart`](../test/architecture/talkback_no_gesture_hints_test.dart): source guard forbids `'Double tap`, `'Hold for three`, and the old `'Swipe left to start! Detection` form |
| TalkBack speech ownership, identity, and granularity (2026-11-09) (device-verified) | ✅ | [`semantics_test.dart`](../test/accessibility/semantics_test.dart): Home's first node is `Home. ` plus the status meaning for every coordinator state, the `EyeCue` wordmark is one `container` + `header` node behind `ExcludeSemantics`, and `Detection Mode` is a `container` + `header` node labelled `Detection`; [`gesture_navigation_direction_test.dart`](../test/screens/gesture_navigation_direction_test.dart): `shouldSpeakLifecycleUtterance()` gates only the four lifecycle utterances under accessible navigation while other speech stays allowed, the viewport is one `Camera view` container with `explicitChildNodes` so overlay rows stay separate non-live nodes, `Repeat last alert` is a custom action on that container, and a failed Repeat raises the transient `Audio guidance is off` / `Nothing to repeat yet` live-region status; [`help_screen_test.dart`](../test/screens/help_screen_test.dart): Gesture Controls exposes one node per bullet behind a single title header |
| Detection alignment and audio capsule (2026-11-09) (device-verified) | ✅ | [`detection_screen_alignment_test.dart`](../test/screens/detection_screen_alignment_test.dart): the header, the `ValueKey('detection-viewport')` viewport and the two action cards share one 16 dp gutter; the audio pill keeps a 64 × 56 target around a content-sized capsule (`ValueKey('audio-pill-capsule')`); a tap in the target margin toggles mute exactly once and is **not** classified as a gesture |
| Depth heatmap geometry (2026-11-09) (device-verified) | ✅ | [`depth_heatmap_view_test.dart`](../test/widgets/depth_heatmap_view_test.dart): nothing renders without a depth image; the image is rotated with `RotatedBox` and centre-cropped (`BoxFit.cover`) rather than stretched; cover fit centres the rotated image and crops the overflow; quarter turns map every rotation including negative angles; the widget is excluded from semantics |
| Chart axis, tick and selector polish (2026-11-09) (device-verified) | ✅ | [`charts_test.dart`](../test/widgets/charts_test.dart): X ticks carry at most one decimal on a wall-clock interval, the rightmost X tick stays inside the chart box, X ticks fit the raised 36 dp bottom band at 200 % text scale, Y ticks are single-line and never carry two decimals, the widest Y tick fits the reserved gutter at 200 %, axes and ticks share `kHomeInkMuted`, and the FPS chart draws no benchmark line while the latency chart keeps its 300 ms line. [`logs_reports_screen_test.dart`](../test/screens/logs_reports_screen_test.dart): the model filter shows `All models (mixed)` whole and as one labelled control node, the Logs filter card shares the Charts gutter, and a log row keeps the latency number and unit together |

## Integration testing strategy and historical engine checks

| Test | Priority | Description |
|------|----------|-------------|
| CameraX → native detector → Detection pipeline | 🔴 P0 | End-to-end: start CameraX, receive native result, adapt detections |
| Detection → TTS pipeline | 🟡 P1 | End-to-end: detection triggers speech |
| Camera permission flow | 🟡 P1 | Full flow: request → grant → initialize; request → deny → fallback UI |
| Dart inference-isolate lifecycle | Historical | The current detector runs in the native plugin; this plan no longer applies |
| Model swap | 🟢 P2 | Dynamic tensor shape query handles different model shapes |
| Engine switching | Not applicable | There is one detection engine; custom-model selection changes the graph, not the engine |
| Ultralytics native path | 🟡 P0 | On-device camera → native preprocessing/inference/NMS → EyeCue adapter/cards ran on Snapdragon 695; controlled TTS/telemetry/delegate validation remains |
| Custom worker lifecycle orchestration (historical) | Historical | Covered the removed Dart inference worker; not current runtime behavior |
| Accessibility semantics and large text (device-verified) | ✅ | Deterministic coverage for actionable labels, live regions, charts, correction controls, 200% text scale, and TalkBack action operability (semantic long-press Stop/Start, Repeat custom action on the `Camera view` container), plus speech-ownership gating, the single failure announcer, screen identity, merged detector-filter node, and per-item Help granularity |

## Manual Testing Checklist

### Camera & Preview
- [ ] Camera preview is smooth (no visible stuttering)
- [ ] Camera initializes within 2 seconds on cold start
- [ ] Camera preview orientation matches device orientation
- [ ] Preview fills screen correctly on different aspect ratios

### Inference
- [ ] Current campus detector loads and returns useful detections under controlled ground-truth evaluation — no such current-model result is recorded here
- [ ] Switching engines does not leave the camera occupied or duplicate speech
- [ ] Detection FPS meets or exceeds target on test device
- [ ] Inference does not cause camera preview hitching
- [ ] Detections are reasonably accurate (qualitative assessment)
- [ ] No memory leaks during sustained use (>5 minutes)

### Audio Feedback (TTS implemented v0.2.0)
- [x] TTS speaks detected objects clearly — ✅ implemented (`tts_service.dart`), dedicated on-device audio validation pending
- [x] TTS scheduler ordering and alert policy are implemented and have deterministic test coverage. Historical suite/device results are recorded above/by date; no new test or device run is claimed for local `main`.
- [ ] TTS latency from detection to speech is acceptable
- [x] TTS / TalkBack speech ownership — the 2026-11-09 device pass is recorded as confirmation for the tested paths; not revalidated on local `main`.

### Accessibility
- [x] All tested interactive elements expose the intended TalkBack semantics (labels, roles, states, actions) — automated coverage exists for labels and for the operability actions (lifecycle long-press Stop/Start, Repeat custom action on the `Camera view` container), plus speech ownership (only lifecycle TTS suppressed under accessible navigation) and the single failure announcer. The previously open real-world checks — long-press delivery, live-region timing, the failed-Repeat announcement, `Camera view` reachability above the native platform view, and focus retention after Stop/Start — were **confirmed on the tested devices**.
- [ ] Gesture controls work (double-tap, swipe)
- [ ] Primary gesture navigation works on-device — automated coverage is complete (`CONFIRMED-BY-TEST`, `6a0fe65`: commit-on-release, whole-main-area Detection region, second-pointer invalidation); this checkbox is the **device gate only**, and it covers **direct-touch** items only — commit latency after release, haptic timing, wayfinding speech, and the provisional 80 px threshold / 1.5 dominance ratio feel still need one physical Android pass. TalkBack interaction is **not** part of this gate: the accessibility programme is complete and device-verified. See [`known-issues.md`](known-issues.md)
- [x] Safety disclosure semantics are complete for TalkBack — automated only (`CONFIRMED-BY-TEST`): one heading node read before the five body nodes, in reading order, with no duplicate announcement at 200 % text scale, for both the Help section and the first-use acknowledgement
- [x] Safety disclosure is understandable in one physical TalkBack read-through — confirmed on the tested devices during the TalkBack pass
- [ ] High-contrast mode is readable
- [x] App is fully navigable without vision — confirmed on the tested devices during the TalkBack pass
- Note (non-blocking, not an accessibility defect): `Camera view` / `Repeat last alert` works and is verified on device, but its interaction and discoverability still need minor UX polish.

### Presentation-Only Visual Redesign (Confirmed 2026-09-29)
- [x] Fixed/non-scrollable Home normal composition and enlarged fixed decorative logo render as required, with shared lifecycle status and shell navigation behavior retained.
- [x] The retained four-tab bottom navigation has the approved light/Home-theme presentation while destination order, selection, callbacks, visibility preference, accessibility override, Back behavior, and gesture ownership remain unchanged.
- [x] Settings control hierarchy/alignment, cyan active controls, icon-free presentation, truthful System Performance values, and the existing Logs entry callback are visually confirmed.
- [x] Help's icon-free cards and app-bar title, plus the consistent fixed light surfaces while Settings, Help, and Logs & Reports scroll, are visually confirmed.
- [x] Both Detection presentations have confirmed title contrast, edge-inset left-aligned information overlay, and two-card action-control treatment; lifecycle, gesture, hold/tap, Quick Scan, and semantics behavior remain unchanged.
- [x] Physical Android visual checks for this redesign were explicitly confirmed by the user. No visual requirements remain outstanding for this redesign.

### Detection alignment, heatmap and chart polish (recorded device evidence, 2026-11-09)
- [x] Header, dark camera viewport and the two action cards share one 16 dp horizontal gutter on the device.
- [x] Depth heatmap pixels correspond to the preview with MDE enabled (layout-aware rotation plus the box mapping's centre-crop).
- [x] The audio pill's ink ripple extends over the whole 64 × 56 target, not only the capsule.
- [x] `Elapsed time (s)` and the axis ticks stay legible at 100 % and 200 % text scale; the reserved 64 dp Y gutter is sufficient.
- [x] The clamped rightmost X tick renders inside the plot box.
- [x] `All models (mixed)` renders whole in the model filter.
- [x] The Logs metadata row keeps the latency number and unit on one line.
- [x] The Logs and Charts filter cards are visually aligned (shared gutter, matching card geometry).
- Note (non-blocking polish, not a defect): `All models (mixed)` at 200 % text scale on a 390 dp width was accepted as-is; chart X ticks for very large elapsed domains (6+ character values) were not separately exercised and still rely on the reserved 36 dp band.

### Error Handling
- [ ] Camera permission denied → shows explanation UI
- [ ] Model fails to load → shows error UI
- [x] Typed Dart-level inference failures → bounded recovery in the removed Custom worker had deterministic orchestration tests (historical); native crashes such as SIGSEGV remain outside Dart guarantees and require device validation
- [ ] Device rotation → no state loss

## Benchmark Plan

See [`benchmark-results.md`](benchmark-results.md) for the recording template.
The paired dual-engine protocol in [`dual-inference-engine-test.md`](dual-inference-engine-test.md) describes a removed runtime; use [`benchmark-procedure.md`](benchmark-procedure.md) for the current single-engine measurement plan.

### Required Benchmarks

1. **Raw Model Latency:** Run each declared model candidate through the TFLite benchmark tool on the target device; the current campus detector has no benchmark recorded in this document
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
2. Force a recoverable native model failure → verify the documented unavailable/retry behavior; native process crashes cannot be recovered by Dart
3. Force camera disconnect → verify app handles gracefully

### Feature: Performance Logging
1. Enable logging → verify FPS, latency, and confidence are recorded — ✅ telemetry records these (v0.2.0)
2. Export logs → verify data is in parseable format (JSON/CSV) — ✅ JSON/CSV export and round-trip coverage implemented
3. Dashboard → verify `fl_chart` renders real-time metrics — ✅ Logs & Reports Overview/Charts/Logs (v0.2.0–v0.2.2)
