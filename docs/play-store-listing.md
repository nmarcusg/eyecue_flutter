# Play Store material package

**Status: nothing in this package has been uploaded to Play Console.** All text
below is a draft for owner review, and the screenshots do not exist yet — they
are a **device gate**: they must be captured from a real release build on a real
Android device (see §9). No mockup, design-reference image or emulator render may
be presented as the shipped app.

Two kinds of marker appear in this document:

- `VERIFY AT SUBMISSION` — a Play Console limit or asset requirement that was true
  when checked but is enforced by the Console, not by this repository. Re-check it
  in the Console at upload time.
- `PLACEHOLDER — owner action` — content only the owner can supply (a real
  contact address, a published privacy-policy URL).

Where a value was checked, the check date and source are recorded in §11.

## 1. Assets in this package

| Asset | Path | Dimensions | Status |
| --- | --- | --- | --- |
| App icon (512) | [`store-assets/play-icon-512.png`](../store-assets/play-icon-512.png) | 512 × 512, 32-bit RGBA, 29 KB | generated from `assets/logo.png`, committed |
| Feature graphic | [`store-assets/feature-graphic-1024x500.png`](../store-assets/feature-graphic-1024x500.png) | 1024 × 500, 24-bit RGB, no alpha | generated from the same mark, committed |
| Screenshots | — | — | **not created — device gate, §9** |

### 1.1 App icon

- Requirement: **32-bit PNG with alpha, 512 × 512 px, ≤ 1 MB** — checked
  2026-10-25, §11. `VERIFY AT SUBMISSION`.
- The icon is the app's own mark, unchanged in shape, colour and proportion; it
  is a higher-resolution render of the launcher artwork, not a second design. See
  [`icon-generation.md`](icon-generation.md) for the padding (11 % per side), the
  source hash and how to regenerate it.
- No text, badge, price, ranking or Play-category suggestion is drawn on it.

### 1.2 Feature graphic

- Requirement: **JPEG or 24-bit PNG with no alpha, 1024 × 500 px** — checked
  2026-10-25, §11. `VERIFY AT SUBMISSION`.
- Composition: the app's light card surface (`kHomeSurfaceCard`, `#FFFFFF`) as a
  rounded panel on the app's dark scaffold field (`kScaffoldBackground`,
  `#121212`), with the same logo mark centred. Both colours are tokens from
  [`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart:18).
- **No fabricated UI is shown**: there is no fake screenshot, no invented chart
  and no device frame. Any text or device imagery must be added by the owner only
  if it is truthful; the generated file deliberately contains none (no font is
  bundled, so type would not be reproducible).

## 2. Title

**Limit: 30 characters — checked 2026-10-25, §11. `VERIFY AT SUBMISSION`.**

```
EyeCue: on-device detection
```

27 characters. "On-device" is a factual property of the build (no frame leaves the
phone; the app works offline), not a performance claim.

## 3. Short description

**Limit: 80 characters — checked 2026-10-25, §11. `VERIFY AT SUBMISSION`.**

```
Speaks nearby objects aloud using on-device detection. Research prototype.
```

74 characters. It states the research framing in the same field as the
capability, so the short description cannot be read as a safety product claim.

## 4. Full description

Draft. The safety section quotes the app's own disclosure **verbatim** — the
single source of truth is
[`lib/widgets/safety_disclosure.dart`](../lib/widgets/safety_disclosure.dart:15),
rendered by both the permanent Help section and the first-use acknowledgement. Do
not reword it here: if the app's copy changes, this section changes with it (item
G's wording, not a second notice).

```text
EyeCue is an experimental research and assistive Android app. It looks at what the
camera sees, detects common objects on the device itself, and speaks what it finds.
Nothing is analysed in the cloud: the models are bundled with the app, and
detection works offline.

WHAT IT DOES
• Live detection. Camera frames are analysed on the phone and the names of
  detected objects are announced with text-to-speech. Detections can also be shown
  as boxes on the preview.
• Estimated distance. An optional on-device depth model estimates how far away the
  main objects are. These distances are estimates, not measurements.
• Priority and alerting. Detections are ranked by proximity and movement, with
  vibration and speech following a fixed alert policy instead of speaking every
  frame.
• Gestures. Single tap, two-finger double-tap, three-finger tap and swipe down,
  so the app can be operated without looking at the screen.
• Settings. Audio guidance, vibration, auto-start, low-power mode, bounding boxes,
  depth heatmap, detector and depth cadence.
• Logs & Reports. On-device charts of detections, alert counts and performance,
  with local CSV and JSON export to the app's own folder.
• Optional research upload. A session can be sent to the study database manually,
  one session at a time, with a study participant code and a study token supplied
  by the study coordinator. The upload contains numeric detection and performance
  records only — no camera frames, no name, no email address, no device ID. It is
  opt-in, can be declined, and only the first upload per app run is stored; export
  locally to keep later data.

SAFETY AND LIMITATIONS
The following is the wording the app itself shows, in Help → Safety and
Limitations and in the first-use acknowledgement:

• EyeCue is an experimental research and assistive application. Treat it as a
  prototype: it is not a medical device, and it cannot guarantee your safety.
• Object detection and estimated distances may be delayed, inaccurate or
  incomplete, so check what is around you yourself.
• EyeCue does not replace a white cane, a guide dog, trained orientation and
  mobility practice, your own situational awareness, or any other primary
  mobility aid.
• Do not rely on EyeCue as the only way to avoid hazards or to navigate
  independently.
• Stop using EyeCue if it becomes unsafe or distracting.

ASSISTIVE USE
EyeCue is built to be used with a screen reader and with speech and haptics
instead of the screen, and it is intended as an additional source of information
for people with visual impairments. It is an assistive aid, not a mobility aid: it
does not replace the aids listed above and it is not certified as an accessibility
or medical product.

PRIVACY
Camera frames never leave the device and are never stored. Research telemetry stays
local unless the user uploads a session manually. The privacy policy is at:
<privacy-policy URL — PLACEHOLDER — owner action>

LICENCE AND SOURCE
EyeCue is licensed AGPL-3.0-only. The corresponding source for every released
build is published; see the licence and third-party notices shipped with the app.
```

`VERIFY AT SUBMISSION`: the full-description character limit enforced by the
Console was **not** re-measured during this task; check the counter in the Console
when pasting.

## 5. Release notes — template for `versionName 1.0.0` / `versionCode 1`

The version is `version: 1.0.0+1` in [`pubspec.yaml`](../pubspec.yaml:4)
(`versionName 1.0.0`, `versionCode 1`). This is the first public listing, so the
notes describe the app rather than a change. Fill the bracketed lines from the
build's own evidence; do not claim a device-measured figure that the release notes
do not have.

```text
First release (1.0.0).

• On-device object detection that speaks detected objects aloud, with an optional
  distance estimate from a local depth model.
• Hands-off gestures: single tap, two-finger double-tap, three-finger tap,
  one-finger swipe down.
• Settings for audio, vibration, auto-start, low power and detection cadence.
• Logs & Reports with on-device charts and local CSV/JSON export.
• Optional, manual research upload of image-free study data.

EyeCue is an experimental research and assistive app, not a medical device. Read
Help → Safety and Limitations before relying on it.
```

`VERIFY AT SUBMISSION`: the per-release notes field limit and its formatting rules
(plain text, no HTML beyond the allowed tags) — check in the Console.

## 6. Support contact and privacy policy

| Field | Value | Status |
| --- | --- | --- |
| Support email | `PLACEHOLDER — owner action` | must be a monitored mailbox before submission |
| Support URL (optional) | `PLACEHOLDER — owner action` | optional |
| Privacy policy URL | `PLACEHOLDER — owner action` | **required external gate**: the policy must be published at a public HTTPS URL and must match [`privacy-and-data-safety.md`](privacy-and-data-safety.md) |

The privacy policy text itself is not drafted here: the answers it must agree with
are in [`privacy-and-data-safety.md`](privacy-and-data-safety.md) §1, §4.1, §5 and
§6, including the review items (retention period, deletion process) that must be
decided before a policy can truthfully be published.

## 7. Category recommendation

**Recommendation: `Tools`** (alternatives: `Education`, `Productivity`).

Rationale, one line: it is an on-device utility whose primary interaction is
speech and haptics rather than a media, health or education experience, and
`Tools` avoids implying a medical or diagnostic purpose — which the app explicitly
disclaims.

Accessibility/assistive framing: Play has no dedicated accessibility category, so
the assistive nature belongs in the title (kept factual), in the short description
("Research prototype") and in the `ASSISTIVE USE` section of the full description
rather than in a category or tag that would suggest certification.

`PLACEHOLDER — owner action`: the category/tags selection is applied in the Console.
`VERIFY AT SUBMISSION`: the currently available category list.

## 8. Content-rating preparation (no rating is decided here)

This section prepares the questionnaire; it does not answer it. The rating is
produced by the Console's questionnaire and only the owner can submit it.

What the app **does** contain:

- a live camera preview of the user's surroundings, shown on screen;
- spoken object names and haptic alerts;
- an optional depth heatmap (a colour overlay of estimated distance);
- charts and logs of the app's own detection/performance counters;
- an optional manual upload of numeric session records to a research database.

What the app **does not** contain:

- no user-to-user communication, chat, forum or comments;
- no user-generated content that is shared with anyone;
- no ads, no in-app purchases, no gambling or simulated gambling;
- no violence, gore, sexual content, nudity, profanity, drugs, alcohol or tobacco;
- no location sharing, no contacts/calendar/messages access, no microphone use
  (the permission is removed in the manifest);
- no third-party analytics, advertising or crash-reporting SDK — see
  [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §4.

Items the owner must be ready to answer: the camera permission's purpose (the
core function, described in-app before first use), whether the app is aimed at
children (default assumption: **no**, it is a research/assistive tool for adults;
if that changes, the Families policy applies), and the research-upload flow (it is
not user-generated content, but the questionnaire asks about data sharing — see
§10).

## 9. Screenshot capture plan

Screenshots must be captured **from the real release build, on a physical device,
with real detection running**. They are an **external device gate**: nothing can
be substituted for them, and no mockup, design-reference image
([`design-reference/`](../design-reference)) or emulator render may be presented
as the shipped app. This package therefore ships **no screenshots**.

Required screens, in this order:

| # | Screen | Must show |
| --- | --- | --- |
| 1 | Home | the idle/ready state, app identity, entry to Detection |
| 2 | Detection — live | camera preview with bounding boxes **and** the depth heatmap overlay |
| 3 | Detection — MDE off / bounding box mode | the same scene with the heatmap off, boxes only (the depth layer is optional and the difference must be visible) |
| 4 | Settings | preferences, audio guidance, overlays and cadence controls |
| 5 | Logs & Reports | on-device charts and the export actions |
| 6 | Help — Safety and Limitations section | the disclosure text, readable at screenshot scale |
| 7 | First-use disclosure | the acknowledgement shown before first use |

Device sizes: capture on at least a **portrait phone** profile and one large
screen. `VERIFY AT SUBMISSION`: the Console's current phone screenshot count
(minimum 2, maximum 8), pixel band, aspect ratio, per-file size limit and format —
re-read them in the Console's Graphics section, they are console-enforced and were
not re-measured here.

Rules for the person capturing them: no fabricated UI, no added promotional text
or device frames that misrepresents the app, no personally identifying content in
the camera view (faces, documents, screens), and the safety section must be legible
without zooming.

## 10. Data safety cross-reference

Do **not** answer the Data safety form from this document. The answers, their code
citations and the open owner decisions are maintained in
[`privacy-and-data-safety.md`](privacy-and-data-safety.md) §8 ("Data safety answer
sheet") and §8.1 (review items). The Play form is binding; that section is the
single place to change.

The one field this package must keep in sync is the privacy-policy URL in §6, whose
policy text must agree with §8 of that document.

## 11. Licence, source and what was checked

- **Licence**: `AGPL-3.0-only` — [`LICENSE`](../LICENSE).
- **Third-party components, model licences and obligations** —
  [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) (§1 inventory, §4 SDK
  inventory, §6 obligations, §7 review items).
- **Source-distribution procedure** — [`release-procedure.md`](release-procedure.md)
  §7 "Publishing the corresponding source (AGPL-3.0-only)": tag the exact
  `versionName`+`versionCode` commit, publish the source archive produced from that
  tag, keep it available while the matching binaries are distributed.

Requirements checked on **2026-10-25** against Google's live Play Console help
pages (no value below is quoted from memory):

| Requirement | Value | Source page |
| --- | --- | --- |
| App icon | 32-bit PNG with alpha, 512 × 512 px, ≤ 1024 KB | `support.google.com/googleplay/android-developer/answer/9866151` |
| Feature graphic | JPEG or 24-bit PNG with no alpha, 1024 × 500 px | same |
| App title | 30 characters or less | `.../answer/13393723` |
| Short description | 80 characters or less | same |

Everything else in this document that reads as a rule carries `VERIFY AT
SUBMISSION` because it is enforced by the Console form, not by this repository.

## 12. Status summary

| Item | State |
| --- | --- |
| App icon 512 | generated and committed |
| Feature graphic | generated and committed |
| Title, short and full description | drafted, none uploaded |
| Release notes | template for 1.0.0 / 1 (not yet used) |
| Category | recommended `Tools`, not applied |
| Content rating | preparation notes only, no rating decided |
| Support contact | `PLACEHOLDER — owner action` |
| Privacy policy URL | `PLACEHOLDER — owner action` (external gate) |
| Screenshots | **not created — device gate** |
| Data safety answers | in [`privacy-and-data-safety.md`](privacy-and-data-safety.md) §8 |
| Uploaded to Play Console | **no** |
