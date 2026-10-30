-- Explicit privileges for the server-only ingestion role. BYPASSRLS bypasses
-- row policies, but does not supply ordinary table privileges. Do not depend
-- on project-specific default grants for tables created by earlier migrations.
-- The endpoint probes session IDs, then inserts with ON CONFLICT DO NOTHING;
-- it does not update or delete stored sessions.
grant select, insert on table public.telemetry_sessions to service_role;

-- Attempt bookkeeping writes directly through the server client. Token RPCs
-- retain their existing SECURITY DEFINER access and service-only execution.
grant insert on table public.research_ingest_attempts to service_role;

-- No grants to anon/authenticated and no RLS policy changes.
