# Play Store submission checklist

Owner-facing checklist for publishing EyeCue. It records **what has to exist** and
**who has to decide it**. Nothing here is answered on the owner's behalf: every
owner-facing field is marked **OWNER ACTION**, and every policy number or form field
is marked **verify current Google Play policy at submission time** — Play's
requirements change, and this document is not a substitute for the Play Console.

Related documents: [`privacy-and-data-safety.md`](privacy-and-data-safety.md)
(Data safety answers and permission justifications),
[`release-procedure.md`](release-procedure.md) (build, signing, artefacts),
[`release-readiness-report.md`](release-readiness-report.md) (what is and is not
verified), [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) (licensing).

## 0. Prerequisites that are still open

| # | Gate | State |
| --- | --- | --- |
| 1 | Production upload keystore + Play App Signing enrolment | **OWNER ACTION** — no keystore exists; every artefact so far is debug-signed (`-testsigned`) |
| 2 | Final `applicationId` (D1) | **DECIDED** — owner-approved `app.eyecue.mobile`; it cannot change after the first upload |
| 3 | App licence (D2) | **DECIDED** — `AGPL-3.0-only`; text in [`../LICENSE`](../LICENSE) |
| 4 | Installed-startup verification on a real device | **NOT VERIFIED** — no device/AVD on the build host |
| 5 | Privacy policy published at a public URL | **OWNER ACTION** — does not exist |
| 6 | Legal review of AGPL-3.0 obligations | **OWNER ACTION** — items R1–R7 in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §6 |

Do not open a Play Console listing before item 1 is settled; items 4–6 determine
what can honestly be *declared*.

## 1. Privacy policy

| Requirement | State |
| --- | --- |
| Publicly reachable URL, no login, no PDF-only | **OWNER ACTION** |
| States what is collected (camera frames not collected; research telemetry when the user uploads) | content ready in [`privacy-and-data-safety.md`](privacy-and-data-safety.md) §1–§5 |
| States retention period | **OWNER DECISION** — not defined in code (§6 there) |
| States deletion request process | **OWNER DECISION** — no in-app path (§6 there) |
| States the app is intended for research/assistive use and its limits | **OWNER ACTION** — wording is a study/company decision |
| Linked in the Play listing and inside the app | Play listing is owner action; the app currently has **no** in-app link to a policy — that gap must be closed before submission |

*verify current Google Play policy at submission time* — the exact policy URL and
content requirements (and whether a data-deletion URL is mandatory) change.

## 2. Data safety form

Fill it from [`privacy-and-data-safety.md`](privacy-and-data-safety.md) §8, which
answers each field from code or marks it **OWNER DECISION**.

Blocking items before the form can be answered truthfully:

1. **Encryption in transit** — the client only checks that the ingest URL has a
   scheme, not that it is `https` (P3). Declare "encrypted" only after the deployed
   URL is pinned to `https`.
2. **Device model / Android version** — not collected today; if the study wants them,
   the answer and the privacy policy change first.
3. **Deletion request** — a documented manual process is required.
4. **Shared vs processed** — decide how the study's Supabase project is classified.

*verify current Google Play policy at submission time* — the data-type list and the
precise wording of the "collected"/"shared" definitions are Play's, not this file's.

## 3. Sensitive-permission declarations

| Permission | Declaration needed | Source of the justification text |
| --- | --- | --- |
| `CAMERA` | Play's camera-permission declaration + the in-app core-function explanation | [`privacy-and-data-safety.md`](privacy-and-data-safety.md) §7 |
| `RECORD_AUDIO` | **not declared by this app any more** — removed in L10 with evidence | [`release-procedure.md`](release-procedure.md) §6.2 |
| `WRITE_EXTERNAL_STORAGE` / `READ_EXTERNAL_STORAGE` | **not declared any more** | same |
| `FOREGROUND_SERVICE*`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED` | inherited from LiteRT/WorkManager; no user-facing data use | same |

*verify current Google Play policy at submission time* — Play periodically re-scopes
which permissions require a declaration form.

## 4. Camera and telemetry disclosure (store listing text)

The listing must say, in the owner's own words:

* the app uses the camera **on the device** to detect obstacles — frames are not
  stored, not uploaded, not shared;
* an **optional**, manual, per-session upload of image-free numeric research
  telemetry exists, is triggered by the user, and is described in the dialog quoted
  in [`privacy-and-data-safety.md`](privacy-and-data-safety.md) §4.1;
* detection is a **supplement**, not a replacement for a white cane, a guide dog or
  other mobility aids — assistive-technology claims need owner/study wording and
  should match what was actually validated (nothing is device-verified yet).

**OWNER ACTION**: the claim wording. Do not let marketing copy exceed the evidence in
[`release-readiness-report.md`](release-readiness-report.md).

## 5. Manual-upload consent description

Play requires a prominent disclosure when data leaves the device. The disclosure
exists in-app (dialog text, §4.1 of the privacy doc) and must also appear in the
listing/privacy policy, covering:

* what is sent: image-free session metrics + participant code + study scenario;
* when: only after the user taps Confirm upload;
* what is **not** sent: camera frames, device IDs, names, e-mails;
* that the upload is optional and the app works without it.

## 6. Content rating (IARC questionnaire)

**OWNER ACTION** — answer the questionnaire truthfully. Inputs this repository can
attest to:

* no user-generated content, no chat, no social features, no ads, no in-app purchases;
* no violence/gambling/substances content;
* camera use is functional (obstacle detection), not user imagery;
* no data sharing with ad networks.

The rating itself is issued by IARC; it cannot be pre-filled here.

*verify current Google Play policy at submission time.*

## 7. Target audience and content

**OWNER ACTION** — declare the target age group. Facts that matter: the app is aimed
at visually impaired adults and their researchers; it has no child-directed content,
no ads, and does not knowingly collect children's data. Whether the study's actual
participants include minors is an owner/ethics decision, not a code fact.

*verify current Google Play policy at submission time* (the Families policy applies
only if the app targets children).

## 8. Category and contact details

| Field | Value |
| --- | --- |
| Category | **OWNER ACTION** (assistive/medical-adjacent apps are commonly listed under *Tools* or *Health & Fitness*; choosing *Medical* carries extra declaration duties) |
| Tags | **OWNER ACTION** |
| Support e-mail | **OWNER ACTION** — must be monitored |
| Support website / privacy policy URL | **OWNER ACTION** |
| Developer name / address | **OWNER ACTION** |

## 9. Store listing copy

| Asset | Requirement | State |
| --- | --- | --- |
| App name | within Play's title length limit | **OWNER ACTION** — `EyeCue` is the launcher label |
| Short description | within Play's limit | **OWNER ACTION** |
| Full description | within Play's limit | **OWNER ACTION** — must respect §4 |
| What's new | per release | **OWNER ACTION** |

*verify current Google Play policy at submission time* — character limits are set by
Play and are not reproduced here on purpose, so a stale number cannot be trusted.

## 10. Screenshots and feature graphic

**OWNER ACTION** — capture from a **real device build**, not from the design
references in `design-reference/` (those are mockups and must not be presented as the
shipped UI). Play's count/size/format rules:

*verify current Google Play policy at submission time* — screenshot counts, minimum
dimensions and the feature-graphic size are policy values.

Assets that exist and can be reused: `assets/logo.png` (app mark, 13 446 B in the
bundle). The launcher, adaptive and monochrome icons and the 512 Play icon are now
generated from it ([`icon-generation.md`](icon-generation.md)); the listing text,
feature graphic and screenshots are drafted in
[`play-store-listing.md`](play-store-listing.md).

## 11. Data deletion behaviour (no accounts)

* The app has **no accounts** and stores no profile — say exactly that in the
  privacy policy and, where Play asks about account deletion, state that no account
  exists.
* An uploaded research session **can** be deleted by a research member in the study
  database; there is no in-app "delete my data" button.
* The deletion request channel (who to contact, what happens, how long it takes) is an
  **OWNER DECISION** and must be written down before submission.

*verify current Google Play policy at submission time* — Play's data-deletion
requirements differ for apps with and without accounts.

## 12. Internal testing track procedure (owner, in Play Console)

1. Create the app in Play Console, choose the default language, accept the
   declarations, and complete §6–§10.
2. Upload a **production-signed** AAB (`flutter build appbundle --release` with the
   upload keystore present — without it the artefact is `-testsigned` and Play
   refuses it; see [`release-procedure.md`](release-procedure.md) §3).
3. Create an **Internal testing** release, add tester e-mails, and roll out.
4. Install from the internal-testing opt-in link on a real device and complete the
   startup/device gate in [`benchmark-procedure.md`](benchmark-procedure.md) §5.1.
5. Only after item 4 passes should a closed/open track be considered.

*verify current Google Play policy at submission time* — track names, tester limits
and rollout mechanics are Play's.

## 13. Closed / open testing requirements

* Closed testing with a defined tester list is the usual next step after internal
  testing; Play sometimes **requires** a closed test of a minimum duration and tester
  count before production access for new developer accounts.
* **That minimum is a current Play policy value and is deliberately not stated here.**

*verify current Google Play policy at submission time* — including whether a
production-access application is required for this account type.

## 14. Pre-submission gate summary

| Gate | Blocking? | State |
| --- | --- | --- |
| Production signing material (gate 1) | yes | **OWNER ACTION** |
| Final `applicationId` (gate 2) | no — decided | **DECIDED** — `app.eyecue.mobile` |
| App licence (gate 3) | no — decided | **DECIDED** — `AGPL-3.0-only` (§15) |
| Device startup verification (gate 4) | yes for any quality claim | **NOT VERIFIED** |
| Privacy policy live (gate 5) | yes | **OWNER ACTION** |
| Legal review (gate 6) | yes | **OWNER ACTION** |
| Data safety form answerable as-is | no — P3/P2/P4 open | [`privacy-and-data-safety.md`](privacy-and-data-safety.md) §8.1 |
| Listing copy / screenshots | yes | **OWNER ACTION** |
| Complete source published for each released binary (AGPL-3.0 §5/§6) | yes | **OWNER ACTION** — §15 |

## 15. Licence and source offer (AGPL-3.0-only)

The application is licensed **`AGPL-3.0-only`** ([`../LICENSE`](../LICENSE)), the same
licence as the vendored plugin and the bundled model weights, so the AGPL obligations
apply to the app's own code too. The obligations are identified in
[`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §1, §6 and §7; the mechanics
are in [`release-procedure.md`](release-procedure.md) §7. No legal review has been
performed.

| Item | State |
| --- | --- |
| Store listing names the licence | **OWNER ACTION** — state `AGPL-3.0-only` and link the source in the listing |
| Complete corresponding source for every released binary | **OWNER ACTION** — archive from the release tag; includes the modified vendored plugin and the build instructions ([`release-procedure.md`](release-procedure.md) §7) |
| Tag matches the artefact's `versionName`+`versionCode` | **OWNER ACTION** — verify before publishing the archive |
| Written offer names a place and a period (AGPL-3.0 §6) | **OWNER ACTION** — no offer exists yet |
| `-testsigned` artefacts used as a release or source tag | **never** — debug-signed test artefacts, not releases (`release-procedure.md` §3) |
| Obligations reviewed by counsel (R1–R7) | **NOT PERFORMED** — [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §6 |
