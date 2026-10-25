-- L6 hardening for researcher telemetry ingestion. Additive only: this file
-- rewrites, shortens and deletes nothing.
--
-- Assumption (fresh project): this runs against a database created by
-- 202610200001_create_research_telemetry.sql that holds no duplicate
-- (participant_code, client_session_id) pair yet. If a duplicate pair exists the
-- unique index creation fails loudly and the migration stops with the offending
-- key in the error; nothing is deleted, because choosing which of two payloads
-- is the real session is a research decision, not a migration decision. Resolve
-- the duplicates deliberately, then apply this file again.
--
-- The Supabase migration runner records applied versions, so these statements
-- are written to run once (no `if not exists` / `if exists` guards that would
-- silently skip a genuine conflict).

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

-- Row Level Security is deliberately unchanged by this migration: the select
-- policies from 202610200001 (authenticated research members only) remain the
-- whole policy set, and no insert/update/delete policy is granted to any client
-- role. The `ingest-telemetry` Edge Function is the only writer: it validates
-- the envelope, then writes with the server-only secret key, which bypasses
-- RLS. No mobile device holds a database credential, and the publishable key
-- shipped in the app authorises nothing but the function call itself.
comment on table public.telemetry_sessions is
  'Research telemetry, at most one row per (participant_code, client_session_id). Written only by the ingest-telemetry Edge Function using the server secret; RLS grants authenticated research members select only.';
