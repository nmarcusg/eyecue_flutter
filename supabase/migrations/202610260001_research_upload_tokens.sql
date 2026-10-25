-- Study upload tokens: the server-verifiable credential that replaces "the
-- publishable key is the only gate" for researcher telemetry ingestion (threat
-- T1 in docs/ingest-threat-model.md).
--
-- Additive only: nothing here alters or drops an existing object.
--
-- Why SHA-256 and not bcrypt/argon2: a token is 256 random bits, not a
-- user-chosen password. It has no dictionary to attack and no low entropy to
-- stretch, so the only thing a slow KDF would add is latency on every upload
-- (and an extra per-request secret in memory). A plain SHA-256 of the token is
-- enough to make the stored value useless to anyone who reads the table, and
-- the token itself is never stored anywhere.

create table public.research_upload_tokens (
  id uuid primary key default gen_random_uuid(),
  -- Lowercase hex SHA-256 of the token. Unique so a duplicate issue is refused
  -- rather than silently accepted beside the original.
  token_hash text not null unique,
  study_scenario text not null,
  -- Optional binding: when set, uploads must present this exact participant
  -- code, so a leaked token is not usable under an invented participant.
  -- The pattern is repeated from the envelope rule so an operator typo is
  -- refused at issue time: a malformed bound code could never match a real
  -- upload and would answer participant_mismatch for the token's whole life.
  participant_code text null check (
    participant_code is null or participant_code ~ '^[A-Za-z0-9_-]{1,64}$'
  ),
  max_uses int not null default 1 check (max_uses > 0),
  uses int not null default 0 check (uses >= 0),
  expires_at timestamptz not null,
  revoked_at timestamptz null,
  created_at timestamptz not null default now(),
  note text null
);

comment on table public.research_upload_tokens is
  'Researcher-issued study upload tokens. Only a SHA-256 hash is stored; the token itself exists nowhere server-side. RLS is enabled with no policies, so no client role can read or write this table: the ingest-telemetry Edge Function is the only consumer, through consume_research_upload_token() with the server secret.';
comment on column public.research_upload_tokens.token_hash is
  'Lowercase hex SHA-256 of the token (not bcrypt/argon2: the token is 256 random bits, so there is nothing to stretch).';
comment on column public.research_upload_tokens.study_scenario is
  'Bookkeeping only: which study the token was issued for. It is never compared to the envelope''s study.studyScenario, so it is not an access control; the token gates who may write, not which label they write.';

-- No client policy on purpose. RLS enabled + zero policies means every
-- anon/authenticated access is denied; the security-definer RPCs below are the
-- only path, and they are executable by service_role only.
alter table public.research_upload_tokens enable row level security;
revoke all on table public.research_upload_tokens from anon, authenticated;

-- Rolling-window ledger for ingestion rate limiting (threat T5). One row per
-- finished attempt. `outcome` carries the same strings the function answers
-- with, so the ledger is self-describing when an operator reads it.
create table public.research_ingest_attempts (
  id uuid primary key default gen_random_uuid(),
  token_hash text null,
  participant_code text null,
  outcome text not null,
  created_at timestamptz not null default now()
);

comment on table public.research_ingest_attempts is
  'Rolling-window ledger read by research_ingest_rate_limited(). Holds no token, only its hash, and no client IP. RLS enabled with no policies: written by the ingest-telemetry Edge Function only. Retention: the window only reads the last 10 minutes, so rows older than 30 days are dead weight — see the delete snippet at the end of this file.';

alter table public.research_ingest_attempts enable row level security;
revoke all on table public.research_ingest_attempts from anon, authenticated;

-- The rate limiter's only access pattern is "count rows for this key since a
-- timestamp", hence the composite index. The plain created_at index is for the
-- retention delete below: without it every cleanup is a sequential scan.
create index research_ingest_attempts_token_idx
  on public.research_ingest_attempts (token_hash, created_at);
create index research_ingest_attempts_created_at_idx
  on public.research_ingest_attempts (created_at);

-- Atomic consumption. The row lock is what makes `uses` a real ceiling under
-- concurrency: two simultaneous uploads of the last permitted use serialise
-- here, and the second sees the incremented count and returns 'exhausted'.
--
-- Returns one status string and never any token data:
--   ok | invalid | expired | revoked | exhausted | participant_mismatch
-- `invalid` deliberately covers "no such token" without distinguishing an
-- unknown hash from a malformed one, so the answer is not an oracle.
create or replace function public.consume_research_upload_token(
  p_token_hash text,
  p_participant_code text
) returns text
language plpgsql
security definer
-- Every name below is schema-qualified, so an empty search_path costs nothing
-- and removes the last way a caller-controlled path could shadow a name.
set search_path = ''
as $$
declare
  v_token public.research_upload_tokens%rowtype;
begin
  select * into v_token
    from public.research_upload_tokens
   where token_hash = p_token_hash
   for update;

  if not found then return 'invalid'; end if;
  if v_token.revoked_at is not null then return 'revoked'; end if;
  if v_token.expires_at <= now() then return 'expired'; end if;
  -- `is distinct from` so a token bound to a participant refuses a missing
  -- code, and an unbound token (null) accepts any code.
  if v_token.participant_code is not null
     and v_token.participant_code is distinct from p_participant_code then
    return 'participant_mismatch';
  end if;
  if v_token.uses >= v_token.max_uses then return 'exhausted'; end if;

  update public.research_upload_tokens
     set uses = uses + 1
   where id = v_token.id;

  return 'ok';
end;
$$;

comment on function public.consume_research_upload_token(text, text) is
  'Atomically validates and increments a study upload token (row lock), returning ok | invalid | expired | revoked | exhausted | participant_mismatch. Never returns token data.';

-- Rate limiting, best effort (threat T5). The threshold is the constant below
-- and is mirrored in supabase/functions/ingest-telemetry/validate.js
-- (RATE_LIMIT_TOKEN_MAX / RATE_LIMIT_WINDOW_MINUTES); a node test asserts the
-- two copies agree.
--
--   per token: 10 recorded attempts / 10 minutes
--
-- This is the *only* rate limit. There is no per-participant window, because the
-- participant code does not exist until the envelope is parsed, so the only
-- value available before the body is read is one the caller chose — and a
-- window keyed on a caller-chosen value limits nothing. Keeping a
-- `where participant_code = p_participant_code` branch (never true when null)
-- would have been a documented control that cannot fire.
create or replace function public.research_ingest_rate_limited(
  p_token_hash text
) returns boolean
language sql
security definer
set search_path = ''
as $$
  select count(*) >= 10
    from public.research_ingest_attempts
   where token_hash = p_token_hash
     and created_at > now() - interval '10 minutes';
$$;

comment on function public.research_ingest_rate_limited(text) is
  'Best-effort rolling-window rate limit: 10 recorded attempts / 10 minutes per token hash. No participant-level window exists (the code is not trustworthy before the envelope is validated). Read-only; the Edge Function records attempts separately.';

-- Refund for a replay. The idempotency probe runs *after* consume — it has to,
-- because probing first would answer "this (participant_code, client_session_id)
-- exists" to anyone holding a token — so a retry of a session that is already
-- stored would otherwise spend a use and, at the default max_uses = 1, answer
-- 403 upload_token_exhausted for data the database already holds.
--
-- `uses > 0` is the floor: a double refund cannot manufacture a use. A revoked
-- token is left alone because its refusals never consumed anything.
create or replace function public.refund_research_upload_token(
  p_token_hash text
) returns void
language sql
security definer
set search_path = ''
as $$
  update public.research_upload_tokens
     set uses = uses - 1
   where token_hash = p_token_hash
     and revoked_at is null
     and uses > 0;
$$;

comment on function public.refund_research_upload_token(text) is
  'Returns one use after a replay of an already-stored session, floored at 0. Never returns token data.';

-- Every RPC here is SECURITY DEFINER, so none may be reachable by a client
-- role: CREATE FUNCTION grants EXECUTE to PUBLIC by default, which is exactly
-- the hole this revoke closes.
revoke all on function public.consume_research_upload_token(text, text)
  from public, anon, authenticated;
grant execute on function public.consume_research_upload_token(text, text)
  to service_role;
revoke all on function public.research_ingest_rate_limited(text)
  from public, anon, authenticated;
grant execute on function public.research_ingest_rate_limited(text)
  to service_role;
revoke all on function public.refund_research_upload_token(text)
  from public, anon, authenticated;
grant execute on function public.refund_research_upload_token(text)
  to service_role;

-- Issuing a token is an operator action, not an app action. Generate 256 bits
-- of randomness, hash it, insert the hash, hand the token to the researcher:
--
--   TOKEN=$(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')
--   HASH=$(printf %s "$TOKEN" | sha256sum | cut -d' ' -f1)
--   psql "$DB_URL" -c "insert into public.research_upload_tokens
--     (token_hash, study_scenario, participant_code, max_uses, expires_at, note)
--     values ('$HASH', 'indoor-obstacle-course', 'P-001', 5,
--             now() + interval '14 days', 'P-001 session 1')"
--
-- Revoke with: update public.research_upload_tokens set revoked_at = now()
--              where token_hash = '<hash>';
--
-- Ledger retention. research_ingest_attempts only grows for a token that really
-- exists (a made-up hash is never recorded), but a long study still accumulates
-- rows that the 10-minute window will never look at again. Keep 30 days and run
-- this on a schedule (pg_cron, or by hand before an export):
--
--   delete from public.research_ingest_attempts
--    where created_at < now() - interval '30 days';
--
-- The (created_at) index above is what keeps that from being a sequential scan.
