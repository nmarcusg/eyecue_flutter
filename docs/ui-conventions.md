# EyeCue — UI Conventions

> **Status:** Codified 2026-09-09 as part of the frontend workspace
> scaffolding. These conventions were previously inferred from the codebase;
> they are now documented so new UI follows them without guessing. The
> agent-facing rule files live in `.roo/rules/rules-frontend/` and mirror this
> document.

## Scope boundary

UI work may only modify the UI-owned folders:

- `lib/screens/`
- `lib/widgets/`
- `lib/navigation/`
- `lib/theme/` (design tokens + theme)

`lib/models/` and `lib/services/` are **read-only** for UI work. New UI may
*read* what those layers expose, but must not modify them. If a UI task
requires changing a service/model/logic file, stop and flag it rather than
proceeding.

`lib/main.dart` has two narrow, pre-approved exceptions: (1) initializing the
Marionette runtime-inspection binding (debug-only) and (2) consuming the
extracted theme from `lib/theme/app_theme.dart`. Do not touch service
construction/wiring logic in `main.dart` beyond those two changes.

## Naming convention

- Dart source files use `snake_case.dart` filenames.
- Full-screen widgets live in `lib/screens/` and use the
  `snake_case_screen.dart` suffix (e.g. `home_screen.dart`).
- Reusable widgets live in `lib/widgets/` as one public widget class per
  `snake_case.dart` file (e.g. `accessible_button.dart`).
- Design tokens / theme live in `lib/theme/` as `app_*.dart` files.
- Widget classes use PascalCase (e.g. `AccessibleButton`, `HomeScreen`).
- One public widget class per file.
- Private helper widgets used by only one screen stay as `_`-prefixed classes
  colocated inside that screen's file (e.g. `_StatusCard`, `_HelpCard`,
  `_SectionHeader`).

## Design tokens

All colors, spacing, radii, and type values in new UI must come from the token
layer in `lib/theme/`, not from hardcoded literals:

- `lib/theme/app_colors.dart` — semantic color tokens.
- `lib/theme/app_spacing.dart` — spacing scale.
- `lib/theme/app_radii.dart` — corner-radius scale.
- `lib/theme/app_typography.dart` — the high-contrast `TextTheme` builder.
- `lib/theme/app_theme.dart` — `buildEyeCueTheme()`, the app theme.

New widgets/screens must reference tokens (e.g. `kSpace16`, `kRadius12`,
`kSeedColor`) instead of raw `Color(...)`, `Colors.*`, `EdgeInsets.all(24)`,
or `BorderRadius.circular(16)`. Do not invent new colors or values; if a needed
value is not already a token, add it to the appropriate `app_*.dart` file from
the actual design/usage. Colors already derived from the active
`ThemeData`/`ColorScheme` (e.g. `theme.colorScheme.surface`) are not duplicated
as tokens. Introducing tokens must not change visual output — it is a refactor
of where values live, not a redesign.

## Accessibility

Every new interactive widget must be usable through Android TalkBack without
relying on sight:

- Expose TalkBack semantics: a label, role, state, value, hint, and enabled
  status where applicable.
- Respect large-text scaling. Widget tests must cover 200% text scale with no
  overflow on primary screens.
- Never rely on color or motion alone to convey meaning. Any color-coded or
  animated state must also be available as text/semantics.
- Keep minimum touch targets (48dp+ guidance; see `kMinTouchWidth` /
  `kMinTouchHeight` in `lib/theme/app_spacing.dart`).
- Do not make per-frame camera detections a TalkBack live region — EyeCue TTS
  already announces them. Mark only deliberate status/fallback/warning changes
  as live regions.
- Exclude decorative icons, camera texture, and duplicate visual labels from
  the accessibility tree.

Device TalkBack validation remains a manual step.

## Animation

New UI animation must use Flutter's built-in animation APIs only — do not add
an animation package. Use built-in APIs such as `AnimatedSwitcher`,
`AnimatedContainer`, `AnimatedOpacity`, `Hero`, and `PageRouteBuilder`
transitions. Animation must never block or hitch the camera/inference path;
EyeCue is a real-time camera app, so the preview and detection overlay must not
stutter. Never rely on motion alone to convey meaning, and keep animation
subtle and non-interfering with TalkBack/TTS.

## Verification

UI changes are verified on a **physical Android device** (not an emulator or
web target), consistent with the project docs. Run `flutter analyze` (0 issues)
and `flutter test` after each change, and confirm no RenderFlex overflows or
exceptions in logcat.

`marionette_flutter` is a debug-only companion dependency initialized in
`lib/main.dart` via `MarionetteBinding.ensureInitialized()` guarded by
`kDebugMode`. It must never run in release builds.

The Marionette **MCP server** (`marionette_mcp`) is a separate package from the
app companion. It must be globally activated (`dart pub global activate
marionette_mcp`) and the MCP config must invoke it via
`dart pub global run marionette_mcp` — not `dart run marionette_mcp`, which
fails with "Could not find package" unless `marionette_mcp` is a project
dependency, causing "MCP error -32000: Connection closed".

Whether the Marionette MCP server attaches to a physical Android device over
the Dart VM Service is **Needs Verification** — it has not yet been confirmed
end-to-end on a connected physical device.
