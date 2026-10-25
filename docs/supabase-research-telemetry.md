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

The schema-4 envelope, its forbidden-key guard, and the 2 MB body bound are
covered by CLI-free Flutter tests that also read the Edge Function source. Local
database migration and function execution remain **unverified**: the Supabase
CLI is not installed, and no local Supabase stack was started or executed, so
the migration and function behaviour have never run against a live project.

## Payload size

The largest session the app can build is bounded by fixed collection caps. A test
fills every one of them (2000 detections, 400 samples, 500 alert lifecycle
records, 200 failures, 100 fallbacks, 200 recoveries, 2000 corrections) with every
schema-4 sample key populated, and measures **1,878,480 bytes** — 121,520 bytes of
headroom under the function's 2,000,000-byte cap, and under the 1,900,000 target.

This was a real defect, not a hypothetical: the same worst case measured
**2,027,180 bytes** with the schema-4 sample keys (≈2,040,680 including the
`detectorObservedFps` duplicate), so the whole upload would have been rejected
with `413 payload_too_large` and the session lost with no user-visible
diagnosis. Three changes bought the space, and none truncates a record:

- `depth_queue_wait_ms` was removed: a constant `null` because no Dart-side depth
  queue exists, ≈12 KB at the sample cap.
- `detector_observed_fps` was removed: it duplicated `inference_fps`, which *is*
  the detector observed FPS (`0` = not reported, because the plugin cannot
  distinguish 0 from unreported), ≈13 KB at the cap.
- The eleven tertiary perf keys (detector/depth stage timings, accelerator, grid
  size, heatmap cost, dropped ticks) are thinned to every fifth sample (≈94 KB),
  and the sample cap is 400 instead of 500 (≈43 KB). Cadence, `inference_fps`,
  `latency_ms`, `object_count` and the flags stay on every sample.

Client-side, `TelemetryUploadService` refuses a body above 2,000,000 bytes and
returns an explicit failure that tells the user to save a local export, so the
server's `413` is never the first signal. In every failure path the session stays
in memory and JSON/CSV export still recovers it; nothing is truncated.

## Research handling

Before collecting participant data, obtain the required ethics/consent approval
and define retention, access, incident, and deletion procedures for the study.
The app implementation provides a manual upload boundary; it does not by itself
establish legal or institutional compliance.
