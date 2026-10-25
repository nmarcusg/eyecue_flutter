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
fills every one of them (2,000 detections, 400 samples, 500 alert lifecycle
records, 200 failures, 100 fallbacks, 200 recoveries, 2,000 corrections) with
**device-shaped numbers** (Float32-derived box/confidence doubles such as
`0.34545454545454546` and `0.8700000047683716`, not tidy 2-decimal literals) and
every schema-4 sample key populated, and measures **1,850,400 bytes** — 149,600
bytes of headroom under the function's 2,000,000-byte cap and 49,600 bytes under
the internal 1,900,000-byte target.

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

Client-side, `TelemetryUploadService` refuses a body above 2,000,000 bytes and
returns an explicit failure that tells the user to save a local export, so the
server's `413` is never the first signal. In every failure path the session stays
in memory and JSON/CSV export still recovers it; no record is truncated (the
rolling sample window described above is the only data the app discards).

## Research handling

Before collecting participant data, obtain the required ethics/consent approval
and define retention, access, incident, and deletion procedures for the study.
The app implementation provides a manual upload boundary; it does not by itself
establish legal or institutional compliance.
