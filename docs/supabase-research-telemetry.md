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

Beside the envelope, the request carries the
**study upload token** in the `X-Eyecue-Upload-Token` header. It is a credential,
not payload data: it is never in the body, never stored in a row, never logged
and never persisted on the device beyond the request. Its threat model is
[`ingest-threat-model.md`](ingest-threat-model.md); the operational part is
*Study upload tokens* below.

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

### Request order

The function decides in this order, cheapest gate first, so nothing expensive or
unauthenticated runs before it has to:

1. `POST` only → `405 method_not_allowed`
2. publishable key (`apikey`) → `401 unauthorized` — **client identity only**
3. study upload token header present and well-formed →
   `401 missing_upload_token` / `401 invalid_upload_token`
4. rate limit for that token hash → `429 rate_limited`
5. a usable `content-length` (a chunked body cannot be bounded before it is
   buffered, so it is refused rather than read whole) → `411 length_required`.
   The app's sender declares one: `TelemetryUploadRequest.contentLengthBytes` is
   assigned to `HttpClientRequest.contentLength` before the body is written
6. declared body size above 2 000 000 B → `413 payload_too_large`; the byte count
   actually received is re-checked later and is the authoritative bound
7. JSON parse → `400 invalid_json`
8. envelope, consent, forbidden keys, schema version →
   `400 invalid_telemetry_payload` / `400 unsupported_schema_version`
9. token consumption (atomic, `for update`) → `401/403` per status below
10. idempotent probe + upsert (unchanged), with a use refunded on a replay
11. one `research_ingest_attempts` row, only for an outcome on a token the
    database confirmed (best effort)

Steps 3–9 are what stops an APK holder from writing rows: the publishable key
alone now answers `missing_upload_token`.

### Study upload tokens

A token is issued by the researcher, **not** shipped in the APK: 256 random bits,
base64url-encoded (43 characters). Only `sha256(token)` is stored, so a reader of
the table cannot replay a token. SHA-256 rather than bcrypt/argon2 is deliberate:
high-entropy random input has nothing to stretch, and a password KDF would only
add per-upload latency.

[`202610260001_research_upload_tokens.sql`](../supabase/migrations/202610260001_research_upload_tokens.sql)
creates:

| Object | Purpose |
|---|---|
| `research_upload_tokens` | `token_hash` (unique), `study_scenario`, optional `participant_code`, `max_uses`, `uses`, `expires_at`, `revoked_at`, `created_at`, `note`. RLS enabled, **no client policy** |
| `consume_research_upload_token(p_token_hash, p_participant_code)` | `security definer`; `select … for update`, then expiry → revocation → participant binding → `uses`; increments `uses`; returns `ok`, `invalid`, `expired`, `revoked`, `exhausted` or `participant_mismatch`. Never returns token data |
| `research_ingest_attempts` | rolling-window ledger: `token_hash`, `participant_code`, `outcome`, `created_at`. RLS enabled, no client policy. Indexed on `(token_hash, created_at)` for the window and on `(created_at)` for the retention delete |
| `research_ingest_rate_limited(p_token_hash)` | `security definer`; `true` when the window is exhausted: **10 recorded attempts / 10 min per token hash**. The constants are mirrored in `validate.js` (`RATE_LIMIT_TOKEN_MAX`, `RATE_LIMIT_WINDOW_MINUTES`) and a test asserts the two copies agree |
| `refund_research_upload_token(p_token_hash)` | `security definer`; `uses = uses - 1` with a floor of 0, only for a token that is not revoked. Called when the idempotency probe finds the session already stored, so a replay does not cost a use |

**There is no per-participant rate limit.** The participant code does not exist
until the envelope is parsed, so the only value available before the body is read
is one the caller chose; a window keyed on a caller-chosen value limits nothing.
The earlier `where participant_code = p_participant_code` branch (always `null`
from the function, and `= NULL` is never true in SQL) could not fire and was
deleted rather than left documented as a control. The per-token-hash window is
the limiter.

All three functions are `revoke`d from `public`, `anon` and `authenticated`, and
granted to `service_role` only, so the Edge Function is the only caller. Every one
of them pins `set search_path = ''` (all names inside are schema-qualified).

**Ledger retention.** Only outcomes for a token the database confirmed are
recorded — a made-up hash is never written, because there is no budget to limit.
The window reads 10 minutes, so older rows are dead weight; keep 30 days:

```sh
psql "$DB_URL" -c "delete from public.research_ingest_attempts
  where created_at < now() - interval '30 days'"
```

The `(created_at)` index is what keeps that from being a sequential scan. Run it
on a schedule (pg_cron) or by hand before an export.

Issuing and revoking a token is an operator action, documented at the end of the
migration file:

```sh
TOKEN=$(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')
HASH=$(printf %s "$TOKEN" | sha256sum | cut -d' ' -f1)
psql "$DB_URL" -c "insert into public.research_upload_tokens
  (token_hash, study_scenario, participant_code, max_uses, expires_at, note)
  values ('$HASH', 'indoor-obstacle-course', 'P-001', 5,
          now() + interval '14 days', 'P-001 session 1')"
# revoke: update public.research_upload_tokens set revoked_at = now()
#         where token_hash = '<hash>';
```

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

**A replay costs no use.** Token consumption runs *before* the probe, and it has
to stay that way: probing first would answer "this
`(participant_code, client_session_id)` pair exists" to anyone holding a token.
Two cases follow from that order, and both answer `200 { "accepted": true,
"duplicated": true }`:

| Token state on the retry | What happens |
|---|---|
| a use was still available | consume spends it, the probe finds the stored row, and `refund_research_upload_token()` hands the use back — `uses` is unchanged (floor 0, revoked tokens untouched) |
| `uses` already at `max_uses` (the default `max_uses = 1`) | consume refuses with `exhausted`, so nothing was spent and nothing needs refunding; the function probes once on that refusal and answers the same `200 duplicated` when the pair is already stored |

So a network timeout after a successful write never forces a researcher to
re-issue a token for data the database already holds. The probe on the
`exhausted` path is safe because `consume` has already proved the token is real,
and — for a token issued *with* a participant code — that its binding matches; a
token hash the table does not know returns `invalid` and is never probed, so the
answer stays useless as an existence oracle for an unknown caller. What it does
allow is for the holder of a real token to confirm a
`(participant_code, client_session_id)` pair, and for a token issued *without* a
participant code nothing is verified against a participant at all, so that
holder can confirm any pair: the session ids are microsecond timestamps, so it is
a pair they can guess rather than one they must already know, and every probe is
a recorded ledger row counting against the same 10 attempts / 10 minutes window
as a real upload. Accept that rather than the retry burning a token.

A use is still spent when the *write* fails: that is a server fault, not a
replay.

**What a replay means for the user.** Upload acts on one **finished research
trial**. The trial id minted at Start becomes the envelope's
`telemetry.session.id`
([`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart)),
so `client_session_id` is per **trial**, not per app run: the existing
`(participant_code, client_session_id)` key stores **one immutable record per
participant/trial**. "Upload → keep recording → upload the same trial again"
repeats the same pair, and the second body is **discarded**: the pair already has
a row, and a re-upload never overwrites it. A **new** trial mints a new id, so a
second trial for the same participant is stored as its own record.
A `2xx` alone does not mean *this* payload was stored, so the app answers a
replay with its own state, `TelemetryUploadResult.alreadyUploaded()` — success-
like, but rendered as "This session was already uploaded earlier and was not
stored again. Save a local export if you have recorded more data since." — and
keeps the plain success text for a first write only. A session that looks absent
on the dashboard can therefore have been **discarded as a duplicate** rather than
never uploaded; check `received_at` and the `(participant_code,
client_session_id)` pair before concluding it never arrived.

**The live app session cannot be uploaded once a trial exists.** The live buffer
keeps its app-lifetime session id, and from the moment a trial is started in that
run it also holds that respondent's rows under that id. `LogsReportsScreen`
therefore refuses the live upload and explains it: *"A research trial was started
in this run, so this live session cannot be uploaded. Upload the finished trial
from the stored trials list instead."* Local JSON/CSV export of the live session
stays available, and every stored finished trial keeps its own upload control.
The study token remains **header-only** (`X-Eyecue-Upload-Token`): it never
enters the body, the export, a stored trial file or a failure message, and it is
entered per upload and never persisted.

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
| 401 | `{"error":"missing_upload_token"}` | the `X-Eyecue-Upload-Token` header is absent or empty | "No study upload token was sent. Enter the token the study coordinator gave you; the session was not uploaded. Save a local export." |
| 401 | `{"error":"invalid_upload_token"}` | header present but not a well-formed token (padded, too short, non-token-safe), or no such token | "The research server did not recognise the study upload token. Check it with the study coordinator; the session was not uploaded. Save a local export." |
| 401 | `{"error":"expired_upload_token"}` | `expires_at` has passed | "The study upload token has expired. Ask the study coordinator for a new one; the session was not uploaded. Save a local export." |
| 401 | `{"error":"revoked_upload_token"}` | `revoked_at` is set | "The study upload token has been revoked. Ask the study coordinator for a new one; the session was not uploaded. Save a local export." |
| 403 | `{"error":"upload_token_exhausted"}` | `uses >= max_uses` | "This study upload token has no uploads left. Ask the study coordinator for a new one; the session was not uploaded. Save a local export." |
| 403 | `{"error":"participant_mismatch"}` | the token is bound to a different participant code | "The study upload token belongs to a different participant code. Check both values; the session was not uploaded. Save a local export." |
| 429 | `{"error":"rate_limited"}` | 10 recorded attempts / 10 min for this token hash | "Too many upload attempts from this token. Wait a few minutes and try again; the session was not uploaded. Save a local export to keep the data." |
| 411 | `{"error":"length_required"}` | no usable `content-length` at all: a chunked body carries no length, so it is refused rather than buffered | "The upload could not be sent in a form the server accepts. Save a local export." |
| 413 | `{"error":"payload_too_large"}` | `content-length`, or the UTF-8 bytes actually received, above 2 000 000 B | "This session is too large to upload. Save a local export to keep the data." |
| 400 | `{"error":"invalid_json"}` | body is not JSON | "The research server rejected this session as invalid. Save a local export; sending it again will not help." |
| 400 | `{"error":"invalid_telemetry_payload"}` | envelope shape/type/consent problem, a forbidden key, or a **syntactically valid body that is not a JSON object** (`[]`, `"text"`, `42` — the parse succeeds, the envelope check fails) | same validation message |
| 400 | `{"error":"unsupported_schema_version","supported":[3,4]}` | header schema outside `{3,4}` | "This app build uses a telemetry format the research server does not accept. Update the app, or save a local export." |
| 500 | `{"error":"database_write_failed"}` | the probe or the upsert failed | "The research server could not accept this session. Save a local export and try again later." |
| 500 | `{"error":"server_configuration_error"}` | the server secret key env var is absent | same server message |
| 201 | `{"accepted":true}` | stored: first write for the pair | "Session uploaded to the research database." |
| 200 | `{"accepted":true,"duplicated":true}` | already stored by an earlier attempt; nothing written | "This session was already uploaded earlier and was not stored again. Save a local export if you have recorded more data since." |

`TelemetryUploadService` maps each study-token code to its own sentence (the
table above), then `401`/`403` without a token code → authorisation, `400` →
validation (with the schema-version body split out), `411` → its own transport
message, `413` → the local size
message and `5xx` → server failure. A token refusal is never folded into the
generic authorisation text, because "your token expired" and "this build is not
authorised" need different actions. Every branch keeps the in-memory session, so
the JSON/CSV export still recovers it, and no message interpolates the token or
the publishable key. The client guard uses the *same* byte bound as the
function's body check — it is not stricter — and its only job is that an over-cap
session is refused before the request is sent; the table adds a separate storage
bound the client does not mirror (see *Payload size*).

### Transport: `https` is enforced client-side

The endpoint is checked before a request is built, so an insecure deployment cannot
silently downgrade the upload. [`validateTelemetryEndpoint`](../lib/services/telemetry_upload_service.dart:58)
returns a `TelemetryEndpointStatus`:

| Status | Condition | Result |
|---|---|---|
| `valid` | absolute URI, scheme `https`, non-empty host, no `userInfo` | the upload proceeds |
| `notConfigured` | ingest URL or publishable key empty (the release artefacts here) | refused, "not configured" message |
| `insecureScheme` | scheme is anything but `https` — `http`, `ftp`, `javascript:`, `file:`, custom | refused, HTTPS message |
| `malformed` | unparsable, no scheme, or padded/space-wrapped input | refused, "not a valid HTTPS address" message |
| `missingHost` | `https://` or `https:///path` | refused, "does not name a server" message |
| `hasCredentials` | non-empty `userInfo` (`https://user:pass@host/…`) | refused, embedded-credentials message |

Only scheme and host are constrained: port, path and query are free, so
`https://<ref>.supabase.co/functions/v1/ingest-telemetry` is valid. A defective URL
is **rejected, never repaired** — no trimming, no scheme substitution. Every refusal
happens before the payload is built, so no request is made and the in-memory session
is untouched ([`TelemetryUploadService.upload`](../lib/services/telemetry_upload_service.dart:298)).

One tolerance is documented rather than fixed: there is no host-shape rule and no
port-range check, so `https://.com`, `https://example..com`,
`https://exam ple.com` (Dart percent-encodes the space) and a port above 65535 all
pass validation and fail as "could not be reached" on the first request. The URL
is a maintainer-set `--dart-define`, so the typo is caught in the build. The
`shortcut:` comment on the validator says so, and a test pins it.

**Debug-only exception.** Plain `http` is accepted for a loopback host
(`localhost`, `127.0.0.1`, `::1`) **and only when `kDebugMode` is true**, so a local
ingest function can be exercised from a debug build
([`_isDebugLoopback`](../lib/services/telemetry_upload_service.dart:98)). A release
build rejects loopback `http` like any other insecure scheme, and non-loopback `http`
is rejected in both modes. Both sides are asserted in
[`telemetry_upload_service_test.dart`](../test/services/telemetry_upload_service_test.dart:999)
by injecting `debugMode` rather than relying on the compile-time constant — including
one case that proves `debugMode: false` refuses loopback `http` **even though**
`flutter test` runs with `kDebugMode` true, so the injected value is what decides.

No refusal message contains the endpoint URL, the publishable key, or any part of
either; a test asserts that for the credentials case, which carries both.

### Local execution: BLOCKED-EXTERNAL — disk capacity

**None of the SQL, the RPCs or the function has been executed anywhere.** This
host has no PostgreSQL server, no Supabase CLI and no cached Supabase container
images, and the volume holds 7.7 GB free of 91 GB (92 % used) — not enough for
the CLI plus its images. Nothing was installed and no image was pulled; the
production project was never contacted. Everything below is
`CONFIRMED-BY-INSPECTION` plus the pure `node --test` contract tests, which read
the SQL and the function source from disk without running either.

Exact reproduction on a machine with capacity (throwaway project only):

```sh
npx supabase@latest --version
npx supabase@latest start        # Postgres/Studio/Edge images, ≈10 GB
npx supabase@latest db reset     # 202610200001, 202610250001, 202610260001
npx supabase@latest db lint
npx supabase@latest functions serve ingest-telemetry

# token proof: issue one, then use it
TOKEN=$(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')
HASH=$(printf %s "$TOKEN" | sha256sum | cut -d' ' -f1)
psql "$DB_URL" -c "insert into public.research_upload_tokens
  (token_hash, study_scenario, participant_code, max_uses, expires_at)
  values ('$HASH', 'indoor-obstacle-course', 'P-001', 2, now() + interval '1 day')"
# no header -> 401 {"error":"missing_upload_token"}
curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$URL" \
  -H "apikey: $PUBLISHABLE" -H 'content-type: application/json' --data @envelope.json
# padded token -> 401 {"error":"invalid_upload_token"}
curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$URL" \
  -H "apikey: $PUBLISHABLE" -H "X-Eyecue-Upload-Token: $TOKEN " \
  -H 'content-type: application/json' --data @envelope.json
# correct token -> 201, replay -> 200 {"duplicated":true}
curl -sS -w '\n%{http_code}\n' -X POST "$URL" \
  -H "apikey: $PUBLISHABLE" -H "X-Eyecue-Upload-Token: $TOKEN" \
  -H 'content-type: application/json' --data @envelope.json
psql "$DB_URL" -c 'select count(*) from public.telemetry_sessions'   # stays 1
# uses exhausted after max_uses -> 403 {"error":"upload_token_exhausted"}
psql "$DB_URL" -c 'select uses, max_uses from public.research_upload_tokens'
# expired / revoked / participant_mismatch -> update the row and repeat
# rate limit -> 11 POSTs in 10 min -> 429 {"error":"rate_limited"}
# replay with max_uses = 1 -> 200 {"duplicated":true} and uses stays at 1
psql "$DB_URL" -c 'select uses, max_uses from public.research_upload_tokens'
# retention -> old ledger rows only
psql "$DB_URL" -c "delete from public.research_ingest_attempts
  where created_at < now() - interval '30 days'"

# maxed-payload proof: one worst-case envelope, then the stored text size
curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$URL" \
  -H "apikey: $PUBLISHABLE" -H "X-Eyecue-Upload-Token: $TOKEN" \
  -H 'content-type: application/json' --data @maxed-envelope.json
psql "$DB_URL" -c "select octet_length(payload::text) from public.telemetry_sessions
  where client_session_id = '<maxed-session-id>'"   # must be below 2400000
npx supabase@latest stop
```

`maxed-envelope.json` is the file the `--data @` sigil above reads: the envelope
built by the Flutter worst-case test (2 000 detections, 400 samples with every
schema-4 key, 500 alert records, 2 000 corrections); it must be under 2 000 000
bytes itself, and its **stored** `payload::text` must stay under the table's
2 400 000-byte bound.

## Provisioning

1. Create a Supabase project and apply, in order,
   [`supabase/migrations/202610200001_create_research_telemetry.sql`](../supabase/migrations/202610200001_create_research_telemetry.sql),
   [`supabase/migrations/202610250001_harden_research_telemetry.sql`](../supabase/migrations/202610250001_harden_research_telemetry.sql)
   and
   [`supabase/migrations/202610260001_research_upload_tokens.sql`](../supabase/migrations/202610260001_research_upload_tokens.sql).
2. Create authenticated accounts for researchers, then insert their user IDs
   in `public.research_members` with `researcher` or `admin` role. Do not give
   participant devices database accounts or table privileges.
3. Issue at least one **study upload token** per participant/session (see
   *Study upload tokens*), and hand the token to the researcher out of band.
   Without a token every upload answers `401 missing_upload_token`, so a
   deployment that skips this step collects nothing.
4. Deploy `supabase/functions/ingest-telemetry`. It is intentionally public at
   the function boundary so a consented mobile device can upload, but the
   function requires a valid study token, validates a bounded payload and writes
   using its server-only Supabase secret. Tables remain protected by Row Level
   Security.
5. Build the Android app with these non-secret client values:

   ```text
   --dart-define=EYECUE_TELEMETRY_INGEST_URL=https://<project-ref>.supabase.co/functions/v1/ingest-telemetry
   --dart-define=EYECUE_SUPABASE_PUBLISHABLE_KEY=<publishable-key>
   ```

   Do not put a `secret`/`service_role` key in a Flutter build, source file, or
   dashboard. Supabase's client initialization uses publishable keys; secret
   keys belong only in the server runtime.
6. Open the private researcher dashboard, sign in with a researcher account,
   then enter the project URL and publishable key. It reads sessions under RLS
   and writes additive annotations; it does not modify the uploaded payload.

## Verification status

The envelope **and token** rules are covered by `node --test
supabase/functions/ingest-telemetry/validate.test.mjs` (**54 cases**: every
forbidden key at three depths, the `frameNumber` allowance, case-variant and
padded spellings that pass by design, each mistyped envelope field, both
supported and three unsupported schema versions, the 2 000 000 / 2 000 001-byte
boundary, and four coupling guards that read the migration SQL and `index.ts`
from disk — schema list, unique-index columns against the `onConflict` target,
the storage bound at least 20 % above the wire cap, and the unguarded `drop
constraint telemetry_sessions_check` that must abort on a renamed constraint).
The token cases cover: the header name, reading a `Headers` instance and a plain
record, returning the value unmodified (never trimmed), the 43/128-character
boundaries, empty/padded/oversized/non-token-safe values, every status →
`{error, status}` mapping including an unrecognised status never reading as
success, the assertion that no helper logs or echoes the token, that `index.ts`
hashes it and never puts it in an answer body or a row, and four coupling guards
on the new migration (additive only, RLS with no client policy, `for update`,
`security definer`, `revoke`/`grant` for all three RPCs each with an empty
`search_path`, and the rate-limit threshold matching the JS constant with no
per-participant branch left). The replay guard asserts the refund call sits
*after* the probe and *before* the `duplicated` answer, and that the RPC floors
`uses` at 0 and skips a revoked token; the ledger guard asserts no outcome
before consume is recorded and that the retention index and delete exist.

The Flutter suite covers the client error mapping for every token code, the
dialog requiring the field, the header actually carrying the token, the token
never appearing in the body/`toJson()`/`toString()`/any message, the
duplicate-versus-success states, and re-reads both Edge Function sources.
**Not executed**: the SQL, the RPCs and the TypeScript function themselves — see
*Local execution: BLOCKED-EXTERNAL* above. The token is proven absent from the
wire body and the UI by test; the hash-and-consume path is
`CONFIRMED-BY-INSPECTION` only.

## Payload size

Two different limits apply, and they are not the same number:

| Limit | Value | Measured on | Enforced by |
|---|---|---|---|
| Wire cap | 2,000,000 B — `CONFIRMED-BY-TEST` | the compact JSON body the app sends | `TelemetryUploadService` (client, before sending) **and** `isBodyTooLarge` in the Edge Function |
| Storage bound | 2,400,000 B — `INFERRED-UNVERIFIED` | `octet_length(payload::text)`, i.e. `jsonb` text output | the `telemetry_sessions_payload_size` check constraint |

The gap is deliberate. The wire cap is the authoritative limit; the
storage bound exists only to stop unbounded storage and is set above it.

**`INFERRED-UNVERIFIED` — both numbers in that sentence are reasoned, not
measured.** Nothing on this host has ever executed the migration, so no session
has been stored and no `payload::text` has been read back:

- the **2,400,000 B** bound comes from the arithmetic in the next paragraph
  (2,000,000 × 1.2), not from an observed stored size;
- the **10–15 % `jsonb` re-spacing factor** is the assumed per-character cost of
  `jsonb`'s text output (a space after every `:` and `,`, added quotes on some
  values), applied to a compact body whose key/value mix is assumed from the
  worst-case fixture. It has not been measured on PostgreSQL.

Proof step, on a machine with capacity — the only thing that converts the label
to `CONFIRMED-BY-MEASUREMENT`: upload one worst-case envelope and read the stored
size back, as in the blocked reproduction above:

```sh
psql "$DB_URL" -c "select octet_length(payload::text),
                          length(payload::text)::numeric
                          / length('<compact-body>') as spacing_factor
                   from public.telemetry_sessions
                   where client_session_id = '<maxed-session-id>'"
#   first column must stay below 2400000; second should land in 1.10–1.15
```

If the measured factor is at or above 1.20, the bound is too tight and the
migration must be re-cut with a wider number — that is why the factor is quoted
as an assumption rather than a fact.

A storage bound set at the wire cap would reject, as a `500
database_write_failed`, a body the function had just accepted. The client guard
is *identical* to the function's wire cap — not stricter — and its only advantage
is ordering: it fires before the request is sent, so the server's `413` is never
the first signal that a session was too large.

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
