-- L6 hardening for researcher telemetry ingestion. No table is rewritten, no
-- column is dropped and no row is deleted or shortened; the only change to an
-- existing object is the payload size check, dropped and re-added at the end
-- with a wider bound (see the storage-bound comment).
--
-- Assumption (fresh project): this runs against a database created by
-- 202610200001_create_research_telemetry.sql. Two kinds of pre-existing row can
-- make a statement below abort, and neither is deleted here, because both are
-- research decisions rather than migration decisions:
--
--   1. a duplicate (participant_code, client_session_id) pair, which makes the
--      unique index creation fail loudly with the offending key in the error;
--   2. a row whose `telemetry_schema_version` is outside (3, 4). Schema 1 and 2
--      were emitted historically, so an older project can hold them; the check
--      constraint below would abort on such a row.
--
-- Resolution, for both cases, is deliberately manual: either archive the rows
-- (copy them to a table outside this schema) or delete them, then apply this
-- file again. The migration runner records applied versions, so these
-- statements are written to run once (no `if not exists` / `if exists` guards
-- that would silently skip a genuine conflict).

-- Idempotency key. `ingest-telemetry` upserts on this pair with
-- `ignoreDuplicates: true`, so a replayed upload keeps the first row and its
-- payload untouched instead of appending a second copy.
create unique index telemetry_sessions_participant_session_uidx
  on public.telemetry_sessions (participant_code, client_session_id);

-- Server-side schema gate. The function rejects an unsupported
-- `telemetry.schemaVersion` before it writes (400 unsupported_schema_version);
-- this check is the backstop for a writer that bypasses the function. Rows
-- whose header claims 4 but whose sample rows are still schema 3 stay valid,
-- because only the header version is constrained.
alter table public.telemetry_sessions
  add constraint telemetry_sessions_supported_schema_version
  check (telemetry_schema_version in (3, 4));

-- Storage bound. The authoritative size limit is the 2,000,000-byte wire cap
-- enforced by `ingest-telemetry`, measured on the compact JSON body the app
-- sends. 202610200001 repeated that same number against `payload::text`, but a
-- `jsonb` value is re-spaced on text output, so the stored form is larger than
-- the wire body and a body that passed the function could still be refused here
-- as a 500 database_write_failed. This constraint exists only to stop unbounded
-- storage, so it is set well above the wire cap to keep headroom for that
-- re-spacing. The original migration left the check unnamed, so PostgreSQL
-- named it after the table and the referenced payload column.
--
-- Deliberately no `if exists`: dropping a name that does not exist must abort
-- this migration. If PostgreSQL named the original check differently on a real
-- project, a guarded drop would silently no-op and leave the old 2,000,000-byte
-- bound in force beside the new one — the narrower limit keeps rejecting writes
-- the function accepted, with no error anywhere explaining why.
alter table public.telemetry_sessions
  drop constraint telemetry_sessions_payload_check;
alter table public.telemetry_sessions
  add constraint telemetry_sessions_payload_size
  check (octet_length(payload::text) <= 2400000);

-- Row Level Security is deliberately unchanged by this migration: the select
-- policies from 202610200001 (authenticated research members only) remain the
-- whole policy set, and no insert/update/delete policy is granted to any client
-- role. The `ingest-telemetry` Edge Function is the only writer: it validates
-- the envelope, then writes with the server-only secret key, which bypasses
-- RLS. No mobile device holds a database credential, and the publishable key
-- shipped in the app authorises nothing but the function call itself.
comment on table public.telemetry_sessions is
  'Research telemetry, at most one row per (participant_code, client_session_id). Written only by the ingest-telemetry Edge Function using the server secret; RLS grants authenticated research members select only.';
