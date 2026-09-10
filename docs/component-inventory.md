# EyeCue — Figma-to-Widget Component Inventory

> **Status:** Scaffolding only. This is a template with one row per known
> screen; the **Figma screenshot paths are intentionally blank** because actual
> Figma export is a manual step performed outside this scaffolding task. Do not
> fabricate screenshot paths or statuses. Population happens once Figma screens
> are exported into `design-reference/screens/` and `design-reference/components/`.
> **Source-of-truth note:** this is an agent-facing record that lives in
> `.roo/rules/docs/` by design (mirroring `frontend-onboarding-analysis.md`).
> If it should also be visible to humans, mirror it into root `/docs` as well.

## Screens

| Screen name | Figma screenshot path (blank until exported) | Corresponding widget file | Status (placeholder/real/not started) |
|---|---|---|---|
| Home |  | [`lib/screens/home_screen.dart`](../lib/screens/home_screen.dart) | real |
| Detect (Custom EyeCue) |  | [`lib/screens/detection_screen.dart`](../lib/screens/detection_screen.dart) | real |
| Detect (Ultralytics) |  | [`lib/screens/ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart) | real |
| Engine Detection wrapper |  | [`lib/screens/engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart) | real |
| Settings |  | [`lib/screens/settings_screen.dart`](../lib/screens/settings_screen.dart) | real |
| Help |  | [`lib/screens/help_screen.dart`](../lib/screens/help_screen.dart) | real |
| Logs & Reports |  | [`lib/screens/logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) | real |

## Components

> Add one row per reusable widget as Figma component exports become available.
> The widget files below are the current reusable components in the app.

| Component name | Figma screenshot path (blank until exported) | Corresponding widget file | Status (placeholder/real/not started) |
|---|---|---|---|
| Accessible Button |  | [`lib/widgets/accessible_button.dart`](../lib/widgets/accessible_button.dart) | real |
| Detection Card |  | [`lib/widgets/detection_card.dart`](../lib/widgets/detection_card.dart) | real |
| Priority Badge |  | [`lib/widgets/priority_badge.dart`](../lib/widgets/priority_badge.dart) | real |
| Warning Banner |  | [`lib/widgets/warning_banner.dart`](../lib/widgets/warning_banner.dart) | real |
| Status Pill |  | [`lib/widgets/status_pill.dart`](../lib/widgets/status_pill.dart) | real |
| Detection State Panel |  | [`lib/widgets/detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart) | real |
| Detection Correction Sheet |  | [`lib/widgets/detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart) | real |
| Charts |  | [`lib/widgets/charts.dart`](../lib/widgets/charts.dart) | real |
| Bounding Box Painter |  | [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart) | real |
| Gesture Surface |  | [`lib/widgets/gesture_surface.dart`](../lib/widgets/gesture_surface.dart) | real |

## Notes

- Screenshot paths are relative to the repository root and point into
  `design-reference/screens/` or `design-reference/components/`.
- "Status" reflects whether the corresponding widget is a real implementation
  (all current entries are real) versus a placeholder or not-yet-started item.
- This file is scaffolding only; populate it once Figma screens are exported.
