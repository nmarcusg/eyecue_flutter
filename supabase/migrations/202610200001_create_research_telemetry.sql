-- EyeCue researcher telemetry storage. Apply through the Supabase CLI or SQL
-- editor after a project has been created. The mobile app never receives a
-- database secret and has no direct access to these tables.

create extension if not exists pgcrypto;

create table if not exists public.research_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('researcher', 'admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.telemetry_sessions (
  id uuid primary key default gen_random_uuid(),
  participant_code text not null check (participant_code ~ '^[A-Za-z0-9_-]{1,64}$'),
  study_scenario text not null check (char_length(study_scenario) between 1 and 80),
  client_submitted_at timestamptz not null,
  received_at timestamptz not null default now(),
  telemetry_schema_version integer not null,
  app_version text not null,
  client_session_id text not null,
  session_started_at timestamptz,
  session_duration_ms bigint not null check (session_duration_ms >= 0),
  payload jsonb not null,
  check (octet_length(payload::text) <= 2000000)
);

create index if not exists telemetry_sessions_received_at_idx
  on public.telemetry_sessions (received_at desc);
create index if not exists telemetry_sessions_participant_code_idx
  on public.telemetry_sessions (participant_code, received_at desc);

create table if not exists public.session_annotations (
  id uuid primary key default gen_random_uuid(),
  telemetry_session_id uuid not null references public.telemetry_sessions(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete restrict,
  annotation_type text not null check (annotation_type in ('protocol', 'quality', 'outcome')),
  note text not null check (char_length(note) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists session_annotations_session_idx
  on public.session_annotations (telemetry_session_id, created_at desc);

alter table public.research_members enable row level security;
alter table public.telemetry_sessions enable row level security;
alter table public.session_annotations enable row level security;

-- Only authenticated researchers can use the dashboard. The public ingest
-- function uses the server-only secret key and bypasses these policies.
create policy "research members can read own membership"
  on public.research_members for select to authenticated
  using (user_id = auth.uid());

create policy "researchers can read telemetry"
  on public.telemetry_sessions for select to authenticated
  using (
    exists (
      select 1 from public.research_members
      where user_id = auth.uid() and role in ('researcher', 'admin')
    )
  );

create policy "researchers can read annotations"
  on public.session_annotations for select to authenticated
  using (
    exists (
      select 1 from public.research_members
      where user_id = auth.uid() and role in ('researcher', 'admin')
    )
  );

create policy "researchers can add annotations"
  on public.session_annotations for insert to authenticated
  with check (
    author_id = auth.uid() and exists (
      select 1 from public.research_members
      where user_id = auth.uid() and role in ('researcher', 'admin')
    )
  );
