### 1. Finalized UI/UX Decisions

**Navigation & Gestures**

* **Global Navigation:** The persistent 4-tab bottom navigation bar is entirely removed. Tab navigation is now handled exclusively via a **two-finger swipe left/right** gesture.
* **Home Screen Start Gesture:** The "Swipe right to start!" copy is a literal, required gesture. Swiping right on the Home screen will actively trigger the Detection start sequence.
* **Detection Screen Gestures:** Do not create on-screen buttons for Start, Stop, or Repeat. These are handled entirely by the global gesture system:
* **Two-finger double-tap:** Start / Stop detection.
* **One-finger swipe-down:** Repeat audio.



**App Initialization & States**

* **Auto-Start:** The app will fire the auto-start sequence immediately when the app opens, rather than waiting for the user to navigate to the Detect tab.
* **Preparing State:** The Home screen must show a *real* "Preparing" state that is directly tied to the actual background initialization of the camera and ML models.

**Screen-Specific Configurations**

* **Detection Screen UI:** Only render **Pause** and **Quick Scan** as visible action cards on the screen.
* **Settings Screen:** Engine selection and sensitivity controls will remain on the Settings screen. The Settings performance card (FPS, MS, ACC) must display **live data** (ensure accuracy metrics respect the app's rules regarding ground truth).
* **Audio Guidance:** This remains a simple **On/Off toggle**; it is not expanding into a multi-mode setting.
* **Secondary Screens (Help, Logs & Reports):** These will be redesigned in this current phase by reusing the newly established components and design tokens.

---

### 2. Layout, Assets & Reference Rules

**Responsiveness & Dimensions**

* **Dynamic Sizing:** Do not hardcode fixed pixel dimensions from the provided screenshots. Calculate relative proportions and spacing ratios from the image and implement them dynamically. All layouts must be built responsively to adapt across Android screen sizes.
* **Orientation & Theme:** The application is strictly **Portrait-only**. There is **no separate toggleable dark mode**; implement the single overarching theme as designed.
* **System UI:** Ignore the clock, battery, and signal row at the top of the screenshots. These are artifacts from the device capture and should not be built into the app UI.

**Assets**

* **Logo Implementation:** Use the existing `assets/logo.png` for the visual mark. Do not use an image for the wordmark; instead, render it as live text using the **IBM Plex Sans** font to ensure accessibility and proper scaling.

---

### 3. Pending Information (Awaiting Your Input)

I am standing by for the remaining reference gaps. Please provide the following when you are ready:

1. **Typography Rules (Gap 3):** Exact IBM Plex Sans font files and which font weights map to which specific text roles.
2. **CSS/Figma Layer Data (Gap 5):** Paste the extracted CSS layers/data. I am ready to analyze it and extract the exact corner radii, border widths, shadows, line heights, and letter spacing needed to complete the design tokens.

# EyeCue — Frontend Design Specification (Extracted from the figma screenshots (css all layers))

## 1. Global Rules & App Behavior

*   **Responsive Layout:** Reference canvas is 390 × 844. **Do not hardcode pixel dimensions.** All positions, widths, and heights must be implemented as relative proportions (%) of the device screen (e.g., using `MediaQuery` or `FractionallySizedBox`) to adapt automatically to all Android viewports.
*   **Theme & Orientation:** The app is strictly Portrait-only. There is a single, unified theme (no toggleable dark mode).
*   **System UI:** Ignore standard OS status bars (clock, battery) seen in screenshots; do not build these into the Flutter UI.
*   **Global Navigation:** The 4-tab bottom navigation bar is completely removed. Tab navigation is handled exclusively via a **two-finger swipe left/right** gesture.
*   **Gestures & Controls:**
    *   **Start:** Right-swipe on the Home screen (literal gesture), or a two-finger double-tap.
    *   **Stop:** Two-finger double-tap.
    *   **Repeat Audio:** One-finger swipe-down.
*   **App Initialization:** Auto-start sequence fires immediately upon app launch.

---

## 2. Design Tokens

### Colors
*   **Backgrounds:**
    *   `surface-base` (`#F5F5F5`): Screen background (all screens).
    *   `surface-card` (`#FFFFFF`): Floating cards, toggle knobs.
    *   `surface-card-96` (`rgba(255,255,255,0.96)`): Status/Ready badge bg.
    *   `surface-dark` (`#0A0A0A`): Camera viewport, System Performance card.
*   **Text & Accents:**
    *   `ink` (`#0A0A0A`): Primary text, logo vectors.
    *   `ink-muted` (`#667085`): Secondary/hint text.
    *   `ink-subtle` (`#99A5AA`): Tertiary labels (units).
    *   `accent-cyan` (`#22C7F2`): Primary accent, ready state, live indicators, active toggles.
    *   `accent-cyan-light` (`#B9EFFF`): Track rails, fill bars.
    *   `accent-cyan-dark` (`#087A9E`): Pause icon glyph.
    *   `warning-amber` (`#F5B942`): Preparing-state dot, Chair detection text.
*   **Overlays & Borders:**
    *   `accent-cyan-wash` (`rgba(185,239,255,0.38)`): Audio Guidance card bg.
    *   `warning-amber-wash` (`rgba(245,185,66,0.9)`): Chair detection box border.
    *   `overlay-white-72` (`rgba(255,255,255,0.72)`): "LIVE CAMERA" label.
    *   `overlay-white-11` (`rgba(255,255,255,0.11)`): Audio transcript bar bg.
    *   `border-neutral` (`#D0D5DD`): Inactive toggle track.
*   **Shadows:**
    *   `shadow-soft`: `0px 6px 18px rgba(10,10,10,0.08)` (Small badges).
    *   `shadow-elevated`: `0px 10px 28px rgba(10,10,10,0.07)` (Large cards).
    *   `shadow-knob`: `0px 2px 5px rgba(0,0,0,0.12)` (Toggle knobs).

### Typography (IBM Plex Sans)
*(Mapped to Material 3 TextTheme in Flutter code)*
*   `displayLarge` (56px, w700): Logo wordmark.
*   `displaySmall` (24px, w700): Performance data numbers.
*   `headlineLarge` (32px, w700): Screen titles.
*   `titleLarge` (24px, w600): Major actions (Pause, Quick Scan).
*   `titleMedium` (18px, w600): List item titles.
*   `bodyLarge` (18px, w500): Live transcripts.
*   `bodyMedium` (18px, w400): Standard paragraphs.
*   `labelLarge` (14px, w600): Button text.
*   `labelMedium` (14px, w500): Badges, tags, hints.
*   `labelSmall` (14px, w500): Dense labels (FPS, MS).

### Shape & Spacing
*   **Radii:** 3px (rails) · 12px (tag pills) · 14px (detection boxes/toggles) · 18px (small badges) · 24px (large cards/camera viewport).
*   **Spacing Scale:** 6, 8, 12, 16, 20, 24 px. Scale padding/gaps proportionally with screen width using 390px as the baseline.

---

## 3. Screen Layouts & Behaviors

### A. Home Screen (Ready & Preparing States)
*   **Logo Implementation:** Render visual mark using `assets/logo.png`. Render "EyeCue" wordmark as live text (`displayLarge`), **not an image**.
*   **Preparing State (Override):** App must show a real "Preparing" state during init. Status badge widens to 27.18% (vs 22.82%), dot becomes `warning-amber`. Copy reads **"PREPARING"** (overriding Figma's static "READY" text).
*   **Start Gesture:** "Swipe Right to Start" card is a literal gesture trigger.

### B. Detection Screen
*   **Camera Viewport:** Main surface (`surface-dark`, 91.79% width, 64.45% height). Contains bounding boxes and transcript overlays relative to the viewport, not the screen.
*   **Action Cards (Constraint):** **Only** render **Pause** (left, 39.74% width) and **Quick Scan** (right, 47.95% width). **Do not render Start, Stop, or Repeat buttons** on the screen.

### C. Settings Screen
*   **Layout:** Contains Intro paragraph, Preferences card, Audio Guidance card, and System Performance card.
*   **Audio Guidance (Override):** Disregard the "Concise" label from the design. Implement this as a standard **On/Off toggle**, matching the other preference rows.
*   **Missing Controls (Override):** Engine Selection and Sensitivity controls must be added into the Settings layout, utilizing the standard `surface-card` and toggle/dropdown components.
*   **Performance Metrics (Override):** Disregard the "SAMPLE PERFORMANCE" label. Display **live data** for FPS, MS, and %ACC.