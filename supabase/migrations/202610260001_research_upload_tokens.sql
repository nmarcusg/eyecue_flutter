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
  participant_code text null,
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
  'Rolling-window ledger read by research_ingest_rate_limited(). Holds no token, only its hash, and no client IP. RLS enabled with no policies: written by the ingest-telemetry Edge Function only.';

alter table public.research_ingest_attempts enable row level security;
revoke all on table public.research_ingest_attempts from anon, authenticated;

-- The rate limiter's only access pattern is "count rows for this key since a
-- timestamp", so both lookups get a plain composite index.
create index research_ingest_attempts_token_idx
  on public.research_ingest_attempts (token_hash, created_at);
create index research_ingest_attempts_participant_idx
  on public.research_ingest_attempts (participant_code, created_at);

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
set search_path = public, pg_temp
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

-- Rate limiting, best effort (threat T5). Thresholds are the constants below
-- and are mirrored in supabase/functions/ingest-telemetry/validate.js
-- (RATE_LIMIT_TOKEN_MAX / RATE_LIMIT_PARTICIPANT_MAX / RATE_LIMIT_WINDOW_MINUTES);
-- a node test asserts the two copies agree.
--
--   per token:       10 attempts / 10 minutes  -> uploads per token are capped
--   per participant: 20 attempts / 10 minutes  -> one participant cannot flood
--
-- The participant window only applies when a code is supplied. The function
-- asks before the body is parsed (so before any participant code exists) and
-- passes null; a value taken from an unvalidated body would be attacker-chosen.
create or replace function public.research_ingest_rate_limited(
  p_token_hash text,
  p_participant_code text
) returns boolean
language sql
security definer
set search_path = public, pg_temp
as $$
  select
    coalesce(
      (select count(*) from public.research_ingest_attempts
        where token_hash = p_token_hash
          and created_at > now() - interval '10 minutes') >= 10,
      false)
    or coalesce(
      (select count(*) from public.research_ingest_attempts
        where participant_code = p_participant_code
          and created_at > now() - interval '10 minutes') >= 20,
      false);
$$;

comment on function public.research_ingest_rate_limited(text, text) is
  'Best-effort rolling-window rate limit: 10 attempts / 10 minutes per token hash, 20 / 10 minutes per participant code. Read-only; the function records attempts separately.';

-- Both RPCs are SECURITY DEFINER, so they must not be reachable by any client
-- role: CREATE FUNCTION grants EXECUTE to PUBLIC by default, which is exactly
-- the hole this revoke closes.
revoke all on function public.consume_research_upload_token(text, text)
  from public, anon, authenticated;
grant execute on function public.consume_research_upload_token(text, text)
  to service_role;
revoke all on function public.research_ingest_rate_limited(text, text)
  from public, anon, authenticated;
grant execute on function public.research_ingest_rate_limited(text, text)
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
