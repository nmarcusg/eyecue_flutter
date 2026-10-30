# Research telemetry ingestion — threat model

Scope: the `ingest-telemetry` Edge Function, the study upload token credential,
and the two tables that back it
([`202610260001_research_upload_tokens.sql`](../supabase/migrations/202610260001_research_upload_tokens.sql)).
This is the binding threat model for the ingestion path; the implementation is
measured against it, not the other way round.

## Assets

| Asset | Why it matters |
|---|---|
| Research session payloads | the study's primary data; fabricated rows corrupt the corpus |
| Integrity of the research corpus | a forged or replayed write is worse than a missing one |
| The database | the collection is the only copy of an uploaded session |
| Researcher identity | a stolen credential is a person's access, not just a token |

## Adversary

Anyone who has the published APK — hence the ingest URL and the publishable key,
both extractable — and anyone who obtains a study upload token out of band.
No assumption is made that the app binary, the publishable key, the URL or the
database schema is secret. The only secret in the system is a study upload
token, and it is never shipped in the APK.

## Threats and mitigations

| # | Threat | State before this change | Required mitigation | Where it lives |
|---|---|---|---|---|
| T1 | Forged session submission | the publishable key was the only gate, so any APK holder could insert rows and self-assert `consent.manualSessionUpload: true` | a server-verifiable upload token per study | `X-Eyecue-Upload-Token` header → `research_upload_tokens` → `consume_research_upload_token()`; a write is refused unless the token is present, well-formed, unexpired, unrevoked, unused and (if bound) matched to the participant code |
| T2 | Endpoint/key extraction from the APK | trivially extractable | **accepted**: they identify the app, not a participant, and must be insufficient alone | the key check stays first (client identity only); every write also needs a valid token, so possession of the key alone yields `missing_upload_token` |
| T3 | Replay of a valid upload | idempotency on `(participant_code, client_session_id)` already prevented duplicates | keep it; replay of a *valid* token is bounded by `uses` | unchanged probe + `on conflict do nothing` upsert; `uses`/`max_uses` and the row lock in the consume RPC bound how often a token may be spent |
| T4 | Participant-code guessing | regex-validated but unauthenticated | bind the token to an optional `participant_code`; guessing yields nothing without a token | `research_upload_tokens.participant_code` + `participant_mismatch`; the token itself is 256 random bits, so guessing a token is not the cheap path the code was |
| T5 | Request flooding / abuse | none | DB-level rate limiting + a token `uses` ceiling | `research_ingest_rate_limited(p_token_hash)` over `research_ingest_attempts`: **10 recorded attempts / 10 min per token hash**, plus `max_uses`. **No per-participant window exists** — the participant code is not trustworthy before the envelope is validated, so a window keyed on it would limit nothing; the earlier `where participant_code = NULL` branch could never fire and was removed rather than documented as a control |
| T6 | Payload-size abuse | 2 000 000 B wire cap (client and function), 2 400 000 B table bound | keep; verify on the token path too | the size check runs *after* the token and rate-limit gates, so **a caller without a well-formed token** cannot make the function read a 2 MB body, and a request with no declared `content-length` (chunked) is refused rather than buffered whole; the caps themselves are unchanged |
| T7 | Unauthorised DB reads | RLS: research members only; the function uses the server secret | keep unchanged | `telemetry_sessions` policies untouched; the two new tables have RLS enabled with **no** client policy, and all three RPCs are `security definer` with an empty `search_path` and `execute` revoked from `public`/`anon`/`authenticated` |
| T8 | Accidental disclosure of research data | payload key scan + forbidden-key list + no images/paths | keep; ensure no token or secret is ever logged or stored in a payload | `FORBIDDEN_KEYS` unchanged; the token is *never* in the body — it travels as a header, is hashed immediately, is stored only as a hash, and no log line, message or row carries it |

## Token handling

* **Entropy.** Issued as ≥ 256 random bits (32 bytes from `/dev/urandom`,
  base64url-encoded → 43 characters). Not derivable from anything in the APK.
* **Storage.** Only `sha256(token)` — lowercase hex — is stored. **SHA-256, not
  bcrypt/argon2**: a token is high-entropy random data, so there is no dictionary
  and no low-entropy secret to stretch; a password KDF would only add latency per
  upload and another secret in memory. This reasoning is repeated as a comment in
  the migration.
* **Shape.** 43–128 characters from `[A-Za-z0-9_-]`, no padding. The client
  checks the shape as a UX courtesy only
  ([`ResearchSessionMetadata.hasValidUploadToken`](../lib/services/telemetry_upload_service.dart:159));
  the server re-checks it
  ([`isValidUploadTokenShape`](../supabase/functions/ingest-telemetry/validate.js))
  and trusts only the database for validity.
* **Lifecycle.** `expires_at` (required), `revoked_at` (nullable), `max_uses`
  (default 1) and `uses`, all checked inside one locked transaction by
  `consume_research_upload_token()`. Statuses: `ok`, `invalid`, `expired`,
  `revoked`, `exhausted`, `participant_mismatch`.
* **No logging.** The raw token exists only in the request's memory: the function
  hashes it first and the string is never interpolated into a message, a log line
  or a row. `validate.js` contains no `console` call at all, and a `node --test`
  case asserts that the function's only log line cannot carry the token.

## Residual risks

These are accepted, not solved:

1. **A stolen token is usable until it expires or is revoked.** The design bounds
   *how much* a stolen token can do (`max_uses`, expiry, optional participant
   binding) but cannot detect theft. Operational answer: issue one token per
   participant/session, short expiry, revoke after the session.
2. **Rate limiting is best-effort, and it is per token hash only.** The window is
   a row count over `research_ingest_attempts`, read before the attempt is
   recorded, so a burst arriving in parallel can overshoot the threshold by the
   number of in-flight requests. A flood of *distinct random* token hashes never
   trips the per-token counter, and such a hash is never recorded in the ledger
   at all (nothing exists to limit), so the bound on that traffic is the
   platform's own invocation limits — nothing here is a rate limiter for a
   determined attacker with many source addresses. The ledger itself stays
   bounded: only attempts on a token the database confirms are recorded, and rows
   older than the 30-day retention are deleted (see the migration).
3. **The token is entered by a researcher and can be shoulder-surfed.** It is a
   typed/pasted credential on a phone screen. It is never persisted, never
   logged and never rendered after submission, but the field itself is visible
   while it is being typed.
4. **The study label is not enforced.** `research_upload_tokens.study_scenario`
   records which study a token was issued for, and the envelope's
   `study.studyScenario` is stored as sent. A holder of a valid token can claim a
   different scenario label; the token gates *who may write*, not *which label
   they write*. Treat the label as data, not as an access control.
5. **A use is refunded for a replay, but not for a database fault.** A replay of
   an already-stored session hands its use back
   (`refund_research_upload_token()`), so retrying a successful upload costs
   nothing and still answers `200 {duplicated:true}`. `consume_research_upload_token()`
   still increments `uses` *before* the row is written, so a genuine write
   failure costs one use — `max_uses` should therefore exceed the attempts a
   researcher is expected to need.
6. **Nothing in this file has been executed against a database.** See
   *Local execution: BLOCKED-EXTERNAL* in
   [`supabase-research-telemetry.md`](supabase-research-telemetry.md). The SQL,
   the RPCs and the function are reviewed by inspection and by the pure
   `node --test` contract tests only.
