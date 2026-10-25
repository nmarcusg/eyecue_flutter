# Supabase researcher telemetry

EyeCue keeps its JSON/CSV export as the source telemetry contract. Online
collection is an optional, **manual per-session** action in Logs & Reports;
it is not background telemetry and it is disabled in builds that lack the two
required Dart defines.

## What is uploaded

After the researcher confirms the upload, the app sends an ingestion envelope
containing:

- the existing image-free schema-4 JSON telemetry snapshot. The inference
  cadence fields (requested/effective detector and depth Hz, observed depth
  cadence and latency, depth status, and the clamp/source-limited flags) travel
  unchanged inside `telemetry`; schema 1 and 2 payloads still parse without them;
- a pseudonymous participant code (`A-Z`, `a-z`, `0-9`, `_`, `-`, maximum 64
  characters); and
- a short study scenario label (maximum 80 characters).

The prompt explicitly warns against names and email addresses. There is no
free-text field in the mobile upload flow. Failed uploads never delete the
session; JSON/CSV export remains available for recovery.

Camera frames, device identifiers, internal paths, technical error detail, and
speech/utterance text must not enter this collection. The Edge Function rejects
those key names before writing to the database. Existing exported detection
bounding boxes are retained because they are part of the research telemetry
contract; they should be treated as research data, not public analytics.

The whole `telemetry` object is stored in a JSONB `payload` column, so a new
telemetry schema version requires **no migration**: schema-4 sample data is
stored exactly as sent and older schema-3 rows keep their original payload.
Every schema-4 key is optional, so a schema-3 row still reads as unknown rather
than `0`. Release
builds request `android.permission.INTERNET` solely for this optional manual
upload; detection and depth stay bundled and work offline.

## Ingestion contract (L6)

### Idempotency

`telemetry_sessions` holds at most one row per
`(participant_code, client_session_id)`.
[`202610250001_harden_research_telemetry.sql`](../supabase/migrations/202610250001_harden_research_telemetry.sql)
creates the unique index that makes the pair a real conflict target, and the
function upserts on it with `ignoreDuplicates: true` (`on conflict do nothing`).

| Situation | Response |
|---|---|
| First write for the pair | `201 { "accepted": true }` |
| Replay: the pair is already stored | `200 { "accepted": true, "duplicated": true }` |

201 vs 200 is decided by a `select id … maybeSingle()` probe **before** the
upsert. That two-step check is the cheapest reliable signal: with
`ignoreDuplicates` the write itself cannot report whether the row was new
without depending on how PostgREST returns conflicting rows. A replay therefore
never creates a second row and never overwrites the stored payload — the probe
short-circuits it, and `on conflict do nothing` covers the narrow race where a
concurrent write lands between the probe and the insert (that write wins; the
race loser still answers `201`).

**What a replay means for the user.** `client_session_id` is minted **once per
app run**, and the upload button re-arms after every attempt. "Upload → keep
detecting 20 minutes → upload again" therefore repeats the same
`client_session_id` with a larger snapshot, and the second snapshot is
**discarded**: the pair already has a row, and a re-upload never overwrites it.
A `2xx` alone does not mean *this* payload was stored, so the app answers a
replay with its own state, `TelemetryUploadResult.alreadyUploaded()` — success-
like, but rendered as "This session was already uploaded earlier and was not
stored again. Save a local export if you have recorded more data since." — and
keeps the plain success text for a first write only. A later snapshot of the
same session reaches the collection only under a **new session id**, and a
session that looks absent on the dashboard can equally have been **discarded as
a duplicate** rather than never uploaded; check `received_at` and the
`(participant_code, client_session_id)` pair before concluding it never arrived.

`validate.js` — not `index.ts` — owns the envelope rules, so
`node --test supabase/functions/ingest-telemetry/validate.test.mjs` exercises
them with no Deno, no Docker and no database.

### Supported schema versions

`telemetry.schemaVersion` must be **3 or 4**
(`SUPPORTED_SCHEMA_VERSIONS` in [`validate.js`](../supabase/functions/ingest-telemetry/validate.js)).
Anything else is
`400 { "error": "unsupported_schema_version", "supported": [3, 4] }`. The
migration repeats the set as a `check` constraint on
`telemetry_schema_version`, so a writer that bypasses the function cannot store
an unknown version either.

The row shape is **never inferred from the header**. `TelemetryExport.toJson`
stamps the current version, so a re-exported schema-3 file says `4` while its
sample rows stay schema 3; that payload is accepted, and only the header value
is constrained.

### Forbidden keys

Matched by **exact name**, at any depth, in objects and arrays inside
`telemetry`. The match is case- and whitespace-sensitive, so a key spelled
`Image` or `" image "` would pass: this is a tripwire against the app's own key
names, not a security boundary. Real protection is that the app never collects
images, audio or device identifiers in the first place.

`image`, `images`, `screenshot`, `screenshots`, `frame`, `frames`, `audio`,
`utterance`, `path`, `paths`, `deviceId`, `technicalDetail`, `serviceRole`,
`secret`, `secrets`, `token`, `tokens`, `apiKey`, `password`

`frameNumber` is the single allowlisted key (`ALLOWED_KEYS` in `validate.js`):
it is a pre-existing frame counter on alert-lifecycle records. The allowance is
one exact name, not a prefix rule — `frame` stays forbidden.

### Error catalogue

Every non-2xx answer is a single-machine-readable-code body.

| Status | Body | Cause | App message |
|---|---|---|---|
| 405 | `{"error":"method_not_allowed"}` | not a `POST` | — (not reachable from the app) |
| 401 | `{"error":"unauthorized"}` | missing/incorrect `apikey` | "This build is not authorised for the research upload. Save a local export and try again later." |
| 413 | `{"error":"payload_too_large"}` | `content-length` or UTF-8 body above 2 000 000 B | "This session is too large to upload. Save a local export to keep the data." |
| 400 | `{"error":"invalid_json"}` | body is not JSON | "The research server rejected this session as invalid. Save a local export; sending it again will not help." |
| 400 | `{"error":"invalid_telemetry_payload"}` | envelope shape/type/consent problem, a forbidden key, or a **syntactically valid body that is not a JSON object** (`[]`, `"text"`, `42` — the parse succeeds, the envelope check fails) | same validation message |
| 400 | `{"error":"unsupported_schema_version","supported":[3,4]}` | header schema outside `{3,4}` | "This app build uses a telemetry format the research server does not accept. Update the app, or save a local export." |
| 500 | `{"error":"database_write_failed"}` | the probe or the upsert failed | "The research server could not accept this session. Save a local export and try again later." |
| 500 | `{"error":"server_configuration_error"}` | the server secret key env var is absent | same server message |
| 201 | `{"accepted":true}` | stored: first write for the pair | "Session uploaded to the research database." |
| 200 | `{"accepted":true,"duplicated":true}` | already stored by an earlier attempt; nothing written | "This session was already uploaded earlier and was not stored again. Save a local export if you have recorded more data since." |

`TelemetryUploadService` maps `401`/`403` → authorisation, `400` →
validation (with the schema-version body split out), `413` → the local size
message and `5xx` → server failure. Every branch keeps the in-memory session,
so the JSON/CSV export still recovers it. The client guard uses the *same* byte
bound as the function's body check — it is not stricter — and its only job is
that an over-cap session is refused before the request is sent; the table adds
a separate storage bound the client does not mirror (see *Payload size*).

### Local execution: BLOCKED-EXTERNAL — disk capacity

**Neither the migration nor the function has been executed anywhere.** This
host has no PostgreSQL server, no Supabase CLI and no cached Supabase container
images, and the volume holds 3.9 GB free of 91 GB (96 % used) — not enough for
the CLI plus its images. Nothing was installed and no image was pulled; the
production project was never contacted.

Exact reproduction on a machine with capacity (throwaway project only):

```sh
npx supabase@latest --version
npx supabase@latest start        # Postgres/Studio/Edge images, ≈10 GB
npx supabase@latest db reset     # applies 202610200001, then 202610250001
npx supabase@latest db lint
npx supabase@latest functions serve ingest-telemetry
# idempotency proof: two identical POSTs, then count the rows
curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$URL" \
  -H "apikey: $PUBLISHABLE" -H 'content-type: application/json' --data @envelope.json
#   first answer 201, replay 200 {"duplicated":true}
psql "$DB_URL" -c 'select count(*) from public.telemetry_sessions'   # stays 1
# maxed-payload proof: one worst-case envelope, then the stored text size
curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$URL" \
  -H "apikey: $PUBLISHABLE" -H 'content-type: application/json' --data @maxed-envelope.json
psql "$DB_URL" -c "select octet_length(payload::text) from public.telemetry_sessions
  where client_session_id = '<maxed-session-id>'"   # must be below 2400000
npx supabase@latest stop
```

`@maxed-envelope.json` is the envelope built by the Flutter worst-case test
(2 000 detections, 400 samples with every schema-4 key, 500 alert records, 2 000
corrections); it must be under 2 000 000 bytes itself, and its **stored**
`payload::text` must stay under the table's 2 400 000-byte bound.

## Provisioning

1. Create a Supabase project and apply, in order,
   [`supabase/migrations/202610200001_create_research_telemetry.sql`](../supabase/migrations/202610200001_create_research_telemetry.sql)
   and
   [`supabase/migrations/202610250001_harden_research_telemetry.sql`](../supabase/migrations/202610250001_harden_research_telemetry.sql).
2. Create authenticated accounts for researchers, then insert their user IDs
   in `public.research_members` with `researcher` or `admin` role. Do not give
   participant devices database accounts or table privileges.
3. Deploy `supabase/functions/ingest-telemetry`. It is intentionally public at
   the function boundary so a consented mobile device can upload, but the
   function validates a bounded payload and writes using its server-only
   Supabase secret. Tables remain protected by Row Level Security.
4. Build the Android app with these non-secret client values:

   ```text
   --dart-define=EYECUE_TELEMETRY_INGEST_URL=https://<project-ref>.supabase.co/functions/v1/ingest-telemetry
   --dart-define=EYECUE_SUPABASE_PUBLISHABLE_KEY=<publishable-key>
   ```

   Do not put a `secret`/`service_role` key in a Flutter build, source file, or
   dashboard. Supabase's client initialization uses publishable keys; secret
   keys belong only in the server runtime.
5. Open the private researcher dashboard, sign in with a researcher account,
   then enter the project URL and publishable key. It reads sessions under RLS
   and writes additive annotations; it does not modify the uploaded payload.

## Verification status

The envelope rules are covered by `node --test
supabase/functions/ingest-telemetry/validate.test.mjs` (40 cases: every
forbidden key at three depths, the `frameNumber` allowance, case-variant and
padded spellings that pass by design, each mistyped envelope field, both
supported and three unsupported schema versions, the 2 000 000 / 2 000 001-byte
boundary, and three coupling guards that read the migration SQL and `index.ts`
from disk — schema list, unique-index columns against the `onConflict` target,
and the storage bound against the wire cap). The Flutter suite covers the client
error mapping, the duplicate-versus-success states, and re-reads both Edge
Function sources. **Not executed**: the SQL and the TypeScript function
themselves — see *Local execution: BLOCKED-EXTERNAL* above.

## Payload size

Two different limits apply, and they are not the same number:

| Limit | Value | Measured on | Enforced by |
|---|---|---|---|
| Wire cap | 2,000,000 B | the compact JSON body the app sends | `TelemetryUploadService` (client, before sending) **and** `isBodyTooLarge` in the Edge Function |
| Storage bound | 2,400,000 B | `octet_length(payload::text)`, i.e. `jsonb` text output | the `telemetry_sessions_payload_size` check constraint |

The gap is deliberate. The wire cap is the authoritative limit; the
storage bound exists only to stop unbounded storage and is set above it, because
`jsonb` re-spaces the JSON on text output so the stored form is roughly 10–15 %
larger than the compact body. A storage bound set at the wire cap would reject,
as a `500 database_write_failed`, a body the function had just accepted. The
client guard is *identical* to the function's wire cap — not stricter — and its
only advantage is ordering: it fires before the request is sent, so the server's
`413` is never the first signal that a session was too large.

The largest session the app can build is bounded by fixed collection caps. A test
fills every one of them (2,000 detections, 400 samples, 500 alert lifecycle
records, 200 failures, 100 fallbacks, 200 recoveries, 2,000 corrections) with
**device-shaped numbers** (Float32-derived box/confidence doubles such as
`0.34545454545454546` and `0.8700000047683716`, not tidy 2-decimal literals) and
every schema-4 sample key populated, and measures **1,850,400 bytes** — 149,600
bytes under the 2,000,000-byte wire cap and 49,600 bytes under the internal
1,900,000-byte test target. That 149,600-byte figure is headroom against the
*wire* cap only; it says nothing about the storage bound, which is why the
storage bound is derived from the wire cap rather than assumed equal to it.

One thing *is* dropped, deliberately: `_maxSamples` is capped at 400, so a session
longer than that keeps a **rolling window** of its most recent 400 samples
(≈13 minutes at 0.5 Hz) and discards its **oldest** samples as new ones arrive.
The window slides; it does not grow, and it is the only lossy cap. The other
collections are caps too (oldest entries dropped at 2,000 detections, 500 alert
records, 2,000 corrections, 200 failures, 100 fallbacks, 200 recoveries), but no
individual record is ever *partially* written or shortened.

This was a real defect, not a hypothetical: the same worst case measured
**2,027,180 bytes** even with tidy 2-decimal literals (≈2,040,680 including the
`detectorObservedFps` duplicate), so the upload would have been rejected with
`413 payload_too_large` and the session lost with no user-visible diagnosis. The
first fix removed the constant `depth_queue_wait_ms` (≈12 KB), removed
`detector_observed_fps` as a duplicate of `inference_fps` (≈13 KB), thinned the
eleven tertiary perf keys to every fifth sample (≈94 KB) and capped samples at
400 (≈43 KB).

A re-review then showed that fixture still lied about number width. On device a
box coordinate is a Float32 plugin value divided in double arithmetic, so it
serialises as a 17–19-character decimal — ≈+74 B on every detection-bearing
record. Measured with device-shaped numbers the envelope was **2,018,480 bytes**,
still above the cap. The export layer therefore applies a documented precision
contract before serialising (see the data dictionary): box coordinates 4 dp,
confidence/probability-like scores 3 dp, latency and Hz 1 dp, sub-ms stage
timings 2 dp. Rounding happens in the serialised output only — the stored
samples, banding, in-app comparisons and speech text keep the full value.

The same rounding is applied to the JSON and CSV file exports, because the
upload wraps the export snapshot: **an archived export is no more precise than
the payload that reached this function.** Study analyses (L10 materials) must
work from the exported values; the unrounded doubles exist only in the phone's
in-memory samples for the life of the session.

Client-side, `TelemetryUploadService` refuses a body above 2,000,000 bytes and
returns an explicit failure that tells the user to save a local export, so the
server's `413` is never the first signal. The session then still has one way to
lose data that no size limit can report: a **replayed** upload is discarded by
the idempotency pair (see *Idempotency*), which is why that answer carries its
own message instead of the success text. In every failure path the session stays
in memory and JSON/CSV export still recovers it; no record is truncated (the
rolling sample window described above is the only data the app discards).

## Research handling

Before collecting participant data, obtain the required ethics/consent approval
and define retention, access, incident, and deletion procedures for the study.
The app implementation provides a manual upload boundary; it does not by itself
establish legal or institutional compliance.
