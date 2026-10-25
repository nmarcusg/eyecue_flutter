# Privacy and data safety

What EyeCue does with data, answered from the code, plus the answer sheet the
owner needs for the Play Console **Data safety** form. Every claim is either
**answered from code (cited)** or marked **OWNER DECISION** where the code cannot
answer it.

No legal opinion is given. This is the input to gate **D3** in
[`play-store-readiness.md`](play-store-readiness.md) §8.

## 1. Summary

| Data | Collected by the app? | Where it goes |
| --- | --- | --- |
| Camera frames | **No** — frames are consumed in-process by the on-device detector and never persisted or transmitted | device only |
| Detected objects / depth numbers | Yes, **in memory only** for the running session | device only until the user exports or uploads |
| Telemetry metrics (latencies, FPS, counts, timings) | Yes, in memory only | device only; exported/sent only on explicit user action |
| Participant code (researcher-entered string) | only inside an upload the user confirms | study database (Supabase), if configured |
| Device identifiers (`ANDROID_ID`, IMEI, advertising id, install id) | **No** — no such code path exists | — |
| Accounts, names, e-mails, contacts, location, files | **No** | — |

## 2. Camera frames never leave the device

* Detection runs on the CameraX analysis stream inside the app process; the
  `ultralytics_yolo` plugin returns numbers, not images, and the depth path emits a
  block-mean grid
  ([`docs/inference-pipeline-probe.md`](inference-pipeline-probe.md),
  [`docs/mde-integration.md`](mde-integration.md)).
* The export snapshot is explicitly image-free: it serialises records
  (`metadata`, `sample`, `detection`, `failure`, …) with numeric fields only — see
  [`telemetry_export_service.dart`](../lib/services/telemetry_export_service.dart:130)
  and the field list in
  [`telemetry-data-dictionary.md`](telemetry-data-dictionary.md).
* The upload payload is the exported snapshot plus study metadata
  ([`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart:183)).
  No image, frame, or bitmap is ever placed in either structure.
* The release APK requests `CAMERA` because the app *is* a camera app; the
  permission is used at runtime only for the preview/analysis stream.

## 3. Telemetry is local by default

* `TelemetryService` is an in-memory `ChangeNotifier`
  ([`telemetry_service.dart`](../lib/services/telemetry_service.dart:334)); nothing
  writes telemetry to disk during a session.
* Export is a manual action from Logs & Reports and writes a JSON/CSV file into the
  **app's own documents directory**
  ([`telemetry_export_service.dart`](../lib/services/telemetry_export_service.dart:424)),
  not shared storage. (This is why the manifest removes
  `WRITE_EXTERNAL_STORAGE`; see §7.)
* No background uploader, no scheduler-driven network call: the only HTTP client in
  the app is `TelemetryUploadService`, invoked from the upload button.

## 4. Upload is manual, per session, and consent-gated

Two independent guards:

1. **Configuration and transport** — the ingest URL and the publishable key are both
   supplied at build time (`--dart-define`), and the URL is validated before a socket
   is opened: [`validateTelemetryEndpoint`](../lib/services/telemetry_upload_service.dart:58)
   accepts `https` only, requires an absolute URI with a host, and rejects embedded
   credentials. Every other scheme (`http`, `ftp`, `javascript`, `file`, custom) is
   refused, and
   [`TelemetryUploadService.upload`](../lib/services/telemetry_upload_service.dart:277)
   returns that refusal instead of sending anything. "Encrypted in transit" is
   therefore enforced by **code**, not assumed from how the deployment is configured.
   The one exception is a debug build pointed at a loopback host
   ([`_isDebugLoopback`](../lib/services/telemetry_upload_service.dart:92)); a release
   build rejects even `http://localhost`. The release artefacts built here carry no
   defines at all, so the upload is structurally impossible in them
   ([`docs/release-procedure.md`](release-procedure.md) §6.5).
2. **Explicit user confirmation** — the upload button opens a dialog
   ([`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:222)) and only
   a confirmed dialog proceeds
   ([`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:112)).

The payload records that consent as
`"consent": {"manualSessionUpload": true}`
([`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart:186)).

### 4.1 Consent text (verbatim, as shown to the user)

> Upload this session?
>
> This manually sends the current image-free session to the research database. It
> does not include camera frames or device IDs. Use only a study participant code,
> never a name or email address. Only the first upload per app run is stored; export
> locally to keep later data.
>
> Participant code … Study scenario … [Cancel] [Confirm upload]

Source: [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:222).

The participant-code field is validated against `^[A-Za-z0-9_-]{1,64}$`
([`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart:46)),
so a name with a space or an `@` is rejected — but the app cannot tell a code from a
name that happens to match the pattern. That residual risk is stated in the copy
("never a name or email address") and is review item **P2** below.

## 5. What the study database stores

Migration [`202610200001_create_research_telemetry.sql`](../supabase/migrations/202610200001_create_research_telemetry.sql:13):

| Column | Content |
| --- | --- |
| `participant_code` | the researcher-entered code |
| `study_scenario` | free text ≤ 80 chars, entered by the researcher |
| `client_submitted_at`, `received_at` | timestamps |
| `telemetry_schema_version`, `app_version` | schema/app version strings |
| `client_session_id`, `session_started_at`, `session_duration_ms` | session identity/timing |
| `payload` | the image-free telemetry snapshot (`jsonb`, ≤ 2 400 000 octets — the table's storage bound, **not** the wire cap) |

Two different limits apply to that `payload`; they are not interchangeable:

* **2 000 000 B — the wire cap.** The size of the JSON body the app sends. Refused on
  the client before the request is built
  ([`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart:229))
  and again by the ingest function.
* **2 400 000 B — the table's storage bound.** The
  `telemetry_sessions_payload_size` check on the stored `jsonb`
  ([`202610250001_harden_research_telemetry.sql`](../supabase/migrations/202610250001_harden_research_telemetry.sql:56)),
  deliberately above the wire cap so the client's limit is the one a researcher hits
  first. [`supabase-research-telemetry.md`](supabase-research-telemetry.md) documents
  the same pair under *Payload size*.

There is **no** device-model, Android-version, IP, or advertising-id column, and the
ingest function does not add one
(`grep -rn 'device_model\|android_version' supabase/migrations/` → no matches). The
app has no accounts: `research_members` rows are created by the owner in the database,
not by the app, and the mobile client never authenticates as a user — it sends the
publishable key only.

## 6. Retention and deletion

* **In the app**: telemetry lives only in memory; it disappears when the process
  ends. Export files live in the app's documents directory and are removed by
  uninstalling the app (or by the user deleting them).
* **In the study database**: nothing deletes rows automatically — no TTL, no
  scheduled job, no cron (`grep -rn 'retention\|pg_cron' supabase/` → no matches).
  Rows persist until a research member deletes them, and there is **no in-app
  deletion path** for an uploaded session.
* Because there are **no user accounts**, there is no "delete my account" flow to
  implement; a participant's deletion request has to be executed by a research
  member against `telemetry_sessions` (rows are keyed by `participant_code` +
  `client_session_id`).

| Item | State |
| --- | --- |
| Retention period for uploaded sessions | **OWNER DECISION** — none defined in code; the privacy policy must state one |
| Deletion request process (who, how fast) | **OWNER DECISION** — no code exists; must be written into the privacy policy and honoured manually |
| Local export retention | user-controlled (uninstall or delete the file) |
| In-app account deletion | not applicable — no accounts |

## 7. Permission justifications for the Play declaration

Effective permission set of the release APK (`aapt2 dump badging`, L10 rebuild —
[`release-procedure.md`](release-procedure.md) §6.2), and the justification to enter
in the Play Console:

| Permission | Declared by | Used by the app? | Justification to declare |
| --- | --- | --- | --- |
| `CAMERA` | this app | yes — the only frame source for on-device detection | "Camera frames are processed on the device to describe the scene; nothing is stored or uploaded." |
| `INTERNET` | this app | yes — the optional, user-initiated research telemetry upload | "Used only when the researcher explicitly uploads a session; models are bundled and detection works offline." |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | `com.google.ai.edge.litert:litert:2.1.5` | indirectly (LiteRT NPU path) | framework requirement of the on-device inference runtime; no user-facing data use |
| `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED` | `androidx.work:work-runtime:2.11.2` | indirectly (WorkManager initialisation on the startup path) | framework requirement of WorkManager; removing them risks `SecurityException` during startup, which cannot be tested without a device |
| `app.eyecue.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `androidx.core:core:1.18.0` (auto-generated, signature-level) | framework-internal | not user-visible, not removable |

Removed in L10, so they no longer appear in the declaration and need no
justification: `RECORD_AUDIO`, `WRITE_EXTERNAL_STORAGE`, `READ_EXTERNAL_STORAGE`
(evidence and residual risk: [`release-procedure.md`](release-procedure.md) §6.2).
No runtime prompt exists for any permission except `CAMERA`.

## 8. Data safety answer sheet

Every answer is either **from code** (with a citation) or **OWNER DECISION**. The
owner must not answer from this table without reading the citations; the Play form is
binding.

| Play Data safety field | Answer | Basis |
| --- | --- | --- |
| Does your app collect or share any of the required user data types? | **Yes — only when the researcher uploads a session** (App activity / "Other in-app actions": numeric detection & performance records) | [`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart:183), §4 |
| Is all data encrypted in transit? | **Yes — enforced by code for the upload path** | [`validateTelemetryEndpoint`](../lib/services/telemetry_upload_service.dart:58) accepts `https` only and reports `insecureScheme` for everything else, and [the service refuses to send](../lib/services/telemetry_upload_service.dart:277) on any non-`valid` status. TLS itself comes from the platform trust store via `dart:io`'s `HttpClient`; no certificate pinning is implemented. Proven by the transport unit/service/widget cases — see §4 |
| Is data collected ephemerally (in memory only)? | The local session is; the **uploaded** snapshot is stored in the study database | §3, §5 |
| Data type: **Location** | No | no location API anywhere in `lib/` |
| Data type: **Personal info** (name, e-mail, phone, address, ID numbers) | No — the only identity field is a researcher code, validated to `^[A-Za-z0-9_-]{1,64}$` | [`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart:46) |
| Data type: **Device or other IDs** | **No** — no `ANDROID_ID`, advertising id, install id or device fingerprint is read (`grep -rn 'ANDROID_ID\|deviceInfo\|installationId' lib/` → no matches) | §1 |
| `deviceModel` / `androidVersion` specifically | **Not collected** (no column, no code path). If the owner wants them for research, the Data Safety answer and the privacy policy must change **before** the code does — **OWNER DECISION** | §5 |
| Data type: **Photos and videos** | No — camera frames are never stored or transmitted | §2 |
| Data type: **Audio** | No — the microphone permission is removed from the manifest | §7 |
| Data type: **Files and docs** | No — exports are written to the app's own directory and never uploaded automatically | §3 |
| Data type: **Contacts / Calendar / Messages / Health / Financial / Web browsing / App info & performance (crash logs)** | No — none of these are read, and no crash reporter is bundled | `pubspec.lock` inventory in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §4 |
| Data type: **App activity — other in-app actions** | **Yes**, when a session is uploaded: detection counts, latencies, FPS, stage timings, alert lifecycle counters | [`telemetry-data-dictionary.md`](telemetry-data-dictionary.md) |
| Is this data **shared** with third parties? | **OWNER DECISION** — the Supabase project is operated by the owner/study; whether that counts as a processor or a third party depends on the deployment. No analytics SDK, ad SDK or crash reporter is bundled | [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §4 |
| Is data required for the app to work? | No — users can decline the upload and keep using the app; upload is opt-in per session | §4 |
| Users can request data deletion | **OWNER DECISION** — no in-app path; a documented manual process must exist before submission | §6 |
| Data collected for **analytics / advertising / personalisation / fraud prevention** | No analytics or advertising SDK; the telemetry is research instrumentation, not product analytics | `pubspec.lock` |
| Prominent disclosure for sensitive data | Not needed for `CAMERA` (it is the core function), but the **upload** must be described in the privacy policy — see [`play-store-checklist.md`](play-store-checklist.md) §4 | — |

### 8.1 Review items for this document

| # | Item | Why |
| --- | --- | --- |
| P1 | Retention period and deletion SLA | §6 has none; a policy statement is required |
| P2 | A participant code can be a disguised name | validation cannot distinguish; the study protocol must be the control |
| P3 | ~~Ingest URL scheme is not enforced to be `https`~~ — **RESOLVED**: `https` is now the only accepted scheme and a non-`https` endpoint is refused before sending (§4) | was: "encrypted in transit" could not be declared from code. Now covered by [`telemetry_upload_service_test.dart`](../test/services/telemetry_upload_service_test.dart:747) (validator matrix, refusal, debug loopback both ways) and the screen case at [`logs_reports_screen_test.dart`](../test/screens/logs_reports_screen_test.dart:865) |
| P4 | Whether the Supabase project counts as a processor or a third-party share | depends on the deployment and the study's agreements |
| P5 | Privacy-policy URL | does not exist yet; required by Play |
