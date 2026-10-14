# EyeCue — Frontend UI Onboarding Analysis

> **Author role:** Frontend UI developer (analysis only — no code written or modified).
> **Date:** 2026-09-09
> **Scope:** Read-only analysis of `.roo/rules/docs/`, the repository structure, the MCP
> configuration, and `.roo/rules/`. This file is the persistent deliverable for the
> onboarding task and is intentionally placed inside `.roo/rules/docs/` per the task
> instructions.
> **Source-of-truth note:** `.roo/rules/docs/` is a copy of the root `/docs` folder. All
> findings below reference the copy unless the root is explicitly named. See **Task 7**
> for the sync problem and proposed process.

---

## 1. Summarize current state

### 1.1 What the project is

EyeCue is a **real-time, on-device object-detection assistive application for visually
impaired users**, built in **Flutter** and **Android-only** (per the thesis). It captures
camera frames, runs them through a YOLOv8n TFLite model, speaks detected objects via TTS,
and overlays bounding boxes on the camera preview. It is a thesis project; the current
documented release baseline is **v0.2.2**, with a large body of **unreleased** app-only
work (dual inference engines, accessibility, corrections, export, tracking, scene
summaries) present in the repository and covered by **127 passing tests** as of the
2026-09-05 documentation sync.

### 1.2 Architecture (as documented and confirmed in code)

The architecture is a **layered Flutter app** with a clear separation between UI and
non-UI code. Confirmed from the actual `lib/` tree (not guessed):

| Layer | Directory | Role | UI or non-UI? |
|---|---|---|---|
| App entry / theme | [`lib/main.dart`](../lib/main.dart) | `MaterialApp`, dark high-contrast theme, service wiring | UI (theme) + wiring |
| Navigation shell | [`lib/navigation/app_shell.dart`](../lib/navigation/app_shell.dart) | 4-tab bottom nav (Home/Detect/Settings/Help), lazy pages via `IndexedStack`, Logs & Reports pushed as a route | UI |
| Screens | [`lib/screens/`](../lib/screens/) | Home, Detection, Engine Detection, Ultralytics Detection, Settings, Help, Logs & Reports | UI |
| Widgets | [`lib/widgets/`](../lib/widgets/) | Reusable UI: buttons, cards, badges, banners, painters, charts, sheets, panels | UI |
| Models | [`lib/models/`](../lib/models/) | Data classes / DTOs (Detection, settings, metadata, corrections, telemetry export, etc.) | Non-UI (data) |
| Services | [`lib/services/`](../lib/services/) | Business logic: inference isolate, TTS, settings persistence, telemetry, spatial analysis, tracking, scene summaries, engine coordination, correction capture, export | Non-UI (logic/state) |

**State management approach:** The docs state this is settled — plain `ChangeNotifier`
services + `setState`, with **no DI framework** (services are wired in `main.dart` and
passed via constructors). `flutter_riverpod` is declared in `pubspec.yaml` but is
**deliberately unused** (documented repeatedly in `architecture.md`,
`implementation-decisions.md`, `known-issues.md`). Per the task instructions, this is
treated as settled; I do not propose alternatives to it.

**Service injection pattern:** Services are constructed in `main()` and threaded down
through `EyeCueApp` → `AppShell` → screens via constructor parameters. Screens receive
the services they need (e.g. `HomeScreen(settings:, onGoToDetection:)`,
`SettingsScreen(settings:, onOpenLogsReports:)`). New UI must follow this constructor
injection pattern to consume existing services.

### 1.3 Current UI status — what is real, placeholder, or built-but-unused

I inspected the actual screen/widget source (not just docs). Findings:

- **Real, functional screens (not placeholders):** [`home_screen.dart`](../lib/screens/home_screen.dart),
  [`settings_screen.dart`](../lib/screens/settings_screen.dart),
  [`help_screen.dart`](../lib/screens/help_screen.dart),
  [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart),
  [`detection_screen.dart`](../lib/screens/detection_screen.dart),
  [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart),
  [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart).
  These render real content, consume the injected services, and are covered by widget
  tests.
- **Real, reusable widgets:** [`accessible_button.dart`](../lib/widgets/accessible_button.dart),
  [`detection_card.dart`](../lib/widgets/detection_card.dart),
  [`priority_badge.dart`](../lib/widgets/priority_badge.dart),
  [`warning_banner.dart`](../lib/widgets/warning_banner.dart),
  [`status_pill.dart`](../lib/widgets/status_pill.dart),
  [`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart),
  [`detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart),
  [`charts.dart`](../lib/widgets/charts.dart),
  [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart),
  [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart).
- **Built but unused by the primary UI (retained legacy/dev):** [`info_panel.dart`](../lib/widgets/info_panel.dart)
  and [`debug_overlay.dart`](../lib/widgets/debug_overlay.dart). The docs explicitly state
  these are "retained, unused in the primary UI." They are dev/metrics panels from the
  pre-v0.2.0 single-screen era.
- **Theme:** defined inline in [`main.dart`](../lib/main.dart) (`_buildTheme()` +
  `_highContrastTextTheme()`). Material 3, dark, high-contrast, seed color `0xFFFFC107`
  (amber), scaffold `0xFF121212`, app bar / nav bar `0xFF1E1E1E`. There is **no separate
  theme/tokens file** — the theme lives entirely in `main.dart`.

**Notable documented UI gaps (from the docs, not yet implemented):** the docs repeatedly
flag that TalkBack/Semantics coverage is broad but **device TalkBack validation remains
manual**, and that the app is not yet validated on-device with a blind user. These are
validation gaps, not missing screens.

### 1.4 What is NOT documented

The docs do **not** document: a formal design-token system, a Figma-to-widget component
inventory, animation/transition guidance, or a UI naming-convention document (see Task 2).
The docs also do not contain any reference to a "frontend onboarding" process or a
`.roo/rules/docs/frontend-onboarding-analysis.md` file (this file is new). I state these
as absent rather than assuming them.

---

## 2. Identify what's missing to start UI work

Checked across all of `.roo/rules/docs/` (all 28 files read):

| Item | Status | Notes / location if found |
|---|---|---|
| **Design tokens** (colors, type scale, spacing, radii) | **MISSING** | No token file or token section exists in any doc. Colors/type/spacing/radii are hardcoded inline in widgets (e.g. `EdgeInsets.all(24)`, `BorderRadius.circular(16)`, `Color(0xFFFFD600)`) and in the theme in `main.dart`. There is no centralized token source of truth. |
| **UI/widget naming conventions** | **MISSING** | No documented convention. *Observed* convention in code: `snake_case.dart` filenames, PascalCase widget classes, `_`-prefixed private helper widgets (e.g. `_StatusCard`, `_HelpCard`, `_SectionHeader`), one widget class per file. This is inferred from code, not documented. |
| **Figma-screen-to-widget component inventory** | **MISSING** | No Figma export, screen-to-widget mapping, or component inventory exists in the docs. The thesis PDF is referenced but not present in `.roo/rules/docs/`. |
| **Documented animation/transition guidance** | **MISSING** | No animation/transition guidance anywhere in the docs. The only motion-related content is gesture *interaction* (thesis gestures), not UI animation policy. |

**Bottom line:** To start UI work cleanly, the project currently lacks (a) a design-token
source of truth, (b) a documented naming convention, (c) a Figma/component inventory, and
(d) animation guidance. These are gaps to be filled (see Tasks 4–6), not blockers — the
existing UI already works and is testable.

---

## 3. Audit current MCP setup (report only — no install/reconfigure/fix)

### 3.1 Where the MCP configuration was found

The MCP configuration is **not** a project-level file. It was located at the **global VS
Code extension storage** path (visible in the open tabs and confirmed by reading it):

```
C:\Users\Admin\AppData\Roaming\Code\User\globalStorage\zoocodeorganization.zoo-code\settings\mcp_settings.json
```

There is **no project-level MCP config** in the repository (none found under `.roo/`,
`.vscode/`, or the repo root). The configuration is global to the `zoo-code` extension.

### 3.2 Servers configured and their state

The file declares nine servers. I report each as found (names are as they appear in the
config, not assumed):

| Server (as configured) | Enabled? | Notes |
|---|---|---|
| `postman` | **Disabled** (`"disabled": true`) | stdio via `npx @postman/postman-mcp-server`; has an API key in env |
| `github` | **Disabled** (`"disabled": true`) | docker `ghcr.io/github/github-mcp-server`; has a PAT in env |
| `context7` | **Enabled** (`"disabled": false`) | stdio via `npx @upstash/context7-mcp`; has an API key |
| `playwright` | **Disabled** (`"disabled": true`) | `@playwright/mcp` chromium |
| `sequential-thinking` | **Disabled** (`"disabled": true`) | `@modelcontextprotocol/server-sequential-thinking` |
| `chrome-devtools` | **Disabled** (`"disabled": true`) | `chrome-devtools-mcp` pointing at Brave |
| `shadcn` | **Disabled** (`"disabled": true`) | `shadcn@latest mcp` |
| `dart` | **Enabled** (`"disabled": false`) | `dart mcp-server` (Dart/Flutter tooling daemon) |
| `marionette` | **Enabled** (`"disabled": false`) | `dart run marionette_mcp` (Flutter runtime-inspection server) |

**Connection status in the current session:** I cannot independently confirm live
connection state for each server from the config file alone (the file only records
enabled/disabled and `alwaysAllow`). The enabled servers are `context7`, `dart`, and
`marionette`. Whether they are actually connected in this session is a runtime state I
cannot verify from the static config; this should be confirmed in the running client.

### 3.3 Flutter runtime-inspection server (`marionette`) — companion package check

`marionette` is a Flutter runtime-inspection MCP server. For such a tool to function it
typically requires (a) a companion Flutter-side package as a dependency and (b)
initialization in the app entry point. I checked both:

- **Companion package in `pubspec.yaml`:** **MISSING.** A search for `marionette` across
  `pubspec.yaml`, `pubspec.lock`, and all `.dart` files returned **0 results**. The
  `marionette` package is not a dependency.
- **Initialization in the app entry point ([`lib/main.dart`](../lib/main.dart)):** **MISSING.**
  `main()` calls `WidgetsFlutterBinding.ensureInitialized()`, constructs services, and calls
  `runApp(...)`. There is no marionette initialization call anywhere.

**Conclusion:** The `marionette` MCP server is configured and enabled, but **both** of its
usual companion requirements are absent from the project. It will not be able to inspect
the running Flutter app until the `marionette` package is added as a dependency and
initialized in `main.dart`. **This is reported only — no fix was performed.**

### 3.4 Physical-device support consideration

The docs are explicit that UI changes are verified by running the app on a **physical
Android phone**, not an emulator or web target (see `development-workflow.md`,
`testing-plan.md`, and the session logs, which reference the Snapdragon 695 / API 33
device `2201116SG`). Any runtime-inspection MCP server used for UI verification must
support attaching to a **physical device** (via the Dart VM Service / DTD over a device
connection), not only emulators/simulators. This is a requirement to confirm when the
`marionette` companion setup is completed; the current config does not itself prove
physical-device attach capability.

### 3.5 What's working vs. what still needs action

| Item | State | Action still needed |
|---|---|---|
| `context7` MCP | Enabled | None for UI work (docs lookup) |
| `dart` MCP | Enabled | None for UI work (Dart/Flutter tooling) |
| `marionette` MCP | Enabled but non-functional for this app | Add `marionette` as a dependency in `pubspec.yaml` **and** initialize it in `lib/main.dart`; confirm it can attach to a physical Android device |
| Other servers (`postman`, `github`, `playwright`, `sequential-thinking`, `chrome-devtools`, `shadcn`) | Disabled | Not needed for frontend UI work; leave as-is |

---

## 4. Recommend UI packages

Recommendations are grounded only in what the docs establish: **Android-only**, **real-time
camera + inference performance constraints**, **accessibility-first (TalkBack, large text,
high contrast)**, and the **existing dependency set** already listed in the docs.

### 4.1 State management

**Settled — do not change.** The docs state the decision: plain `ChangeNotifier` services +
`setState`, constructor injection, no DI framework, `flutter_riverpod` declared but
deliberately unused. New UI must consume services via constructor injection exactly as the
existing screens do. No alternative is proposed.

### 4.2 Component / theming approach

**Recommendation: stay on Material 3 with the existing `ThemeData`/`ColorScheme` approach,
and extract a centralized design-token layer rather than adding a third-party component
library.**

Rationale from the docs:
- The app already uses Material 3 (`useMaterial3: true`) with a high-contrast dark theme
  defined in `main.dart`. Adding a heavyweight component library (e.g. a shadcn-style
  port) would conflict with the accessibility-first, high-contrast, large-text design and
  the performance constraints of a real-time camera app.
- The docs' `shadcn` MCP server is disabled and shadcn/ui is a web/React ecosystem — not a
  natural fit for a Flutter Android app.
- The real gap is **tokenization**, not a new component kit: colors, type scale, spacing,
  and radii are currently hardcoded inline. A small, project-owned token layer (see Task 5)
  gives consistency without new dependencies.

**Recommendation:** Introduce a lightweight `lib/theme/` (or `lib/ui/`) token module that
centralizes the values currently scattered across `main.dart` and the widgets, and keep
Material 3 `ColorScheme`/`TextTheme` as the mechanism. No new third-party theming package
is recommended.

### 4.3 Animation

**Recommendation: use Flutter's built-in animation APIs only; do not add an animation
package.**

Rationale:
- The docs contain **no** animation/transition guidance and the app is a real-time camera
  app where the camera preview and detection overlay must not hitch. Heavy animation
  packages add risk with no documented need.
- Flutter's built-in `AnimatedSwitcher`, `AnimatedContainer`, `AnimatedOpacity`,
  `Hero`, and `PageRouteBuilder` transitions are sufficient for any assistive UI polish and
  are dependency-free.
- Any animation must respect the accessibility constraints (no reliance on motion alone,
  no interference with TalkBack/TTS). This should be codified in `.roo/rules/` (Task 6).

### 4.4 Routing

**Recommendation: keep the current imperative `Navigator` + `MaterialPageRoute` approach;
do not add `go_router` or another routing package.**

Rationale:
- The docs describe the current navigation as a 4-tab bottom nav (`IndexedStack` in
  `app_shell.dart`) with Logs & Reports pushed as a `MaterialPageRoute`. This is simple,
  works, and is already tested.
- The app is Android-only with no web deep-linking requirement, so the URL-based routing
  benefits of `go_router` do not apply. Adding it would be scope creep with no documented
  need.
- If deep links are ever required (the docs mention them only as a possible future Android
  consideration under package identity), that would be the trigger to revisit — not now.

### 4.5 Summary of package recommendations

| Concern | Recommendation | New dependency? |
|---|---|---|
| State management | Keep `ChangeNotifier` + `setState` + constructor injection (settled) | No |
| Theming/components | Material 3 + project-owned token layer | No |
| Animation | Flutter built-in animation APIs | No |
| Routing | Keep `Navigator` + `MaterialPageRoute` | No |

**Net recommendation: no new UI packages are required.** The existing stack is sufficient;
the work is tokenization, convention documentation, and component inventory, not new
dependencies.

---

## 5. Propose file structure and separation of concerns for new UI work

The existing structure already separates UI (`screens/`, `widgets/`, `navigation/`) from
non-UI (`models/`, `services/`). New UI work should extend the existing UI folders and
**must not** restructure the non-UI code identified in the Role & Scope section.

### 5.1 New screens

Place new full-screen widgets in [`lib/screens/`](../lib/screens/) following the existing
`snake_case_screen.dart` naming (e.g. `home_screen.dart`). Register them either as a new
tab in [`lib/navigation/app_shell.dart`](../lib/navigation/app_shell.dart) or as a pushed
`MaterialPageRoute` (as Logs & Reports is), depending on whether they belong in the primary
4-tab workflow or a secondary route.

### 5.2 New reusable widgets

Place new reusable widgets in [`lib/widgets/`](../lib/widgets/) as one class per
`snake_case.dart` file (matching the observed convention). Private helper widgets used by
only one screen should stay as `_`-prefixed classes inside that screen's file (as
`_StatusCard`, `_HelpCard`, `_SectionHeader` already are).

### 5.3 New design tokens / theme (recommended addition)

Because there is currently **no** token source of truth, I recommend a new UI-owned folder
that does not disturb existing non-UI code:

```
lib/
  theme/            (NEW — UI-owned)
    app_colors.dart     # semantic color tokens (currently hardcoded in main.dart/widgets)
    app_spacing.dart    # spacing scale (currently inline EdgeInsets values)
    app_radii.dart      # radius scale (currently inline BorderRadius values)
    app_typography.dart # optional: reference to the high-contrast TextTheme
    app_theme.dart      # optional: move _buildTheme()/_highContrastTextTheme() out of main.dart
```

This keeps tokens UI-scoped and does not touch `models/` or `services/`. The existing
`main.dart` theme could be refactored to consume these tokens, but that is an
implementation decision for a later task, not part of this analysis.

### 5.4 Separation-of-concerns guardrails

- New UI may **read** `models/` and `services/` to consume what is exposed, but must not
  modify them.
- If a UI task requires changing a service/model/logic file, **stop and flag it** rather
  than proceeding (per the Role & Scope).
- Keep camera/inference/engine-specific widgets (painters, gesture surface, detection
  screens) separate from generic reusable widgets, matching the current split.

---

## 6. Recommend what belongs in `.roo/rules/`

The following agent-facing rules should be established so future sessions behave
consistently. These are recommendations only — no rule files were created.

1. **Frontend scope boundary rule** (mirroring the existing `rules-code/01-scope.md` but
   UI-specific): state that UI work may only modify `lib/screens/`, `lib/widgets/`,
   `lib/navigation/`, and (new) `lib/theme/`; `lib/models/` and `lib/services/` are
   read-only; any required change to non-UI code must be flagged and stopped.
2. **UI naming convention rule:** document the observed convention — `snake_case.dart`
   filenames, PascalCase widget classes, one public widget class per file, `_`-prefixed
   private helpers colocated with their screen. Codify it so it is no longer inferred.
3. **Design-token rule:** require all colors, spacing, radii, and type values to come from
   the token layer (`lib/theme/`) rather than being hardcoded inline in new widgets.
4. **Accessibility rule:** every new interactive widget must expose TalkBack semantics
   (label/role/state/hint), respect large-text scaling, and not rely on color or motion
   alone. This aligns with the existing accessibility work in the docs.
5. **Animation rule:** new UI animation must use Flutter built-in APIs, be non-blocking to
   the camera/inference path, and not be the sole carrier of meaning.
6. **Doc-update requirement rule:** any UI change that adds a screen, token, component, or
   convention must update the corresponding doc in **both** the root `/docs` and the
   `.roo/rules/docs/` copy (see Task 7 for the sync process).
7. **Verification rule:** UI changes are verified on a physical Android device (not
   emulator/web), consistent with the existing docs; note that `marionette` companion setup
   is still required before runtime inspection is available.

---

## 7. Map docs to future edits, including the root/copy sync problem

### 7.1 Which file to update for each kind of future change

| Kind of future change | File(s) to update |
|---|---|
| New screen | [`docs/architecture.md`](architecture.md) (folder structure + component table); [`docs/changelog.md`](changelog.md); [`docs/implementation-progress.md`](implementation-progress.md); [`docs/session-log.md`](session-log.md) |
| New token / theme change | [`docs/architecture.md`](architecture.md) (theme/design section); [`docs/changelog.md`](changelog.md) |
| New reusable component | [`docs/architecture.md`](architecture.md) (widgets table); [`docs/changelog.md`](changelog.md) |
| New convention (naming, tokens, animation, accessibility) | A new doc (e.g. `docs/ui-conventions.md`) plus a `.roo/rules/` rule file; both must be created and kept in sync |
| New dependency | [`docs/architecture.md`](architecture.md) (External Dependencies table); [`pubspec.yaml`](../pubspec.yaml); [`docs/changelog.md`](changelog.md) |
| Any UI behavior change | [`docs/changelog.md`](changelog.md); [`docs/session-log.md`](session-log.md); [`docs/implementation-progress.md`](implementation-progress.md) |

### 7.2 The root/copy sync problem

`.roo/rules/docs/` is a **copy** of the root `/docs` folder, kept in the repo so agents have
current context without re-reading the whole repo. The task explicitly warns this copy will
go stale relative to root `/docs` once implementation begins. The two must be updated
together.

**Proposed concrete process (recommended):**

1. **Make root `/docs` the single source of truth.** All human-facing documentation edits
   happen in the root `/docs` folder first.
2. **Re-copy root `/docs` → `.roo/rules/docs/` after every doc-affecting change.** Because
   the copy is a plain mirror (not a symlink — symlinks are fragile across the Windows/Git
   environment and are not currently used), the reliable mechanism is a **deterministic
   re-copy** of the whole folder after each change, so the two never diverge.
3. **Treat the copy as read-only context for agents.** Agents read `.roo/rules/docs/` for
   context but do not hand-edit it independently; they edit root `/docs` and then trigger
   the re-copy.
4. **Automate the re-copy** where possible (a small script or a documented manual step in
   the workflow) so it is not forgotten. Until automated, the rule is: *any commit that
   touches root `/docs` must also refresh `.roo/rules/docs/` in the same commit.*
5. **Exception for this deliverable:** this analysis file was explicitly requested to be
   written into `.roo/rules/docs/`. Because it is an agent-facing onboarding record (not a
   root `/docs` product doc), it lives only in the copy by design. If it should also be
   visible to humans, mirror it into root `/docs` as well — but that is a separate decision.

**Sync rule to codify in `.roo/rules/`:** "Root `/docs` is authoritative. After any change
to a file under root `/docs`, re-copy the entire `/docs` directory into `.roo/rules/docs/`
in the same change. Do not edit `.roo/rules/docs/` files independently of root `/docs`
(except agent-facing records that are intentionally copy-only, like this analysis)."

---

## Open Questions / Needs Verification

- **Marionette physical-device attach:** whether the `marionette` MCP server, once its
  companion package is added and initialized, can attach to a physical Android device (not
  just emulator) is **Needs Verification** — the config does not prove it.
- **Live MCP connection state:** whether `context7`, `dart`, and `marionette` are actually
  connected in the current session is a runtime state not derivable from the static config
  file.
- **Figma source:** no Figma export or screen-to-widget inventory exists in the docs; if a
  Figma design is the intended source of truth for new UI, it has not been provided in the
  repository.
- **Token-layer location:** the recommendation to add `lib/theme/` is a proposal; the exact
  folder name and whether to refactor `main.dart`'s theme into it is an implementation
  decision for a later task.
