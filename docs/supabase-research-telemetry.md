# Supabase researcher telemetry

EyeCue keeps its JSON/CSV export as the source telemetry contract. Online
collection is an optional, **manual per-session** action in Logs & Reports;
it is not background telemetry and it is disabled in builds that lack the two
required Dart defines.

## What is uploaded

After the researcher confirms the upload, the app sends an ingestion envelope
containing:

- the existing image-free schema-v3 JSON telemetry snapshot. The inference
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
telemetry schema version requires **no migration**: schema-3 cadence data is
stored exactly as sent and older rows keep their original payload. Release
builds request `android.permission.INTERNET` solely for this optional manual
upload; detection and depth stay bundled and work offline.

## Provisioning

1. Create a Supabase project and apply
   [`supabase/migrations/202610200001_create_research_telemetry.sql`](../supabase/migrations/202610200001_create_research_telemetry.sql).
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

The schema-3 envelope, its forbidden-key guard, and the 2 MB body bound are
covered by CLI-free Flutter tests that also read the Edge Function source. Local
database migration and function execution remain **unverified**: the Supabase
CLI, Docker, and containers are intentionally not installed, so none of this has
been executed against a live project.

## Research handling

Before collecting participant data, obtain the required ethics/consent approval
and define retention, access, incident, and deletion procedures for the study.
The app implementation provides a manual upload boundary; it does not by itself
establish legal or institutional compliance.
