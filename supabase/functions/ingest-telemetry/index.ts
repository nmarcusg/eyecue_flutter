import { createClient } from 'npm:@supabase/supabase-js@2'

import { isBodyTooLarge, validateEnvelope } from './validate.js'

const json = (body: Record<string, unknown>, status = 200) =>
  Response.json(body, { status, headers: { 'content-type': 'application/json' } })

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)
  const publishableKeys = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') ?? '{}')
  if (
    typeof publishableKeys.default !== 'string' ||
    request.headers.get('apikey') !== publishableKeys.default
  ) {
    return json({ error: 'unauthorized' }, 401)
  }
  const contentLength = Number(request.headers.get('content-length') ?? 0)
  if (isBodyTooLarge(contentLength)) return json({ error: 'payload_too_large' }, 413)

  let body: unknown
  try {
    const text = await request.text()
    if (isBodyTooLarge(new TextEncoder().encode(text).byteLength)) {
      return json({ error: 'payload_too_large' }, 413)
    }
    body = JSON.parse(text)
  } catch (_) {
    return json({ error: 'invalid_json' }, 400)
  }

  // Envelope shape, forbidden keys and the supported schema set are decided in
  // validate.js, which `node --test` can exercise without Deno or a database.
  const validation = validateEnvelope(body)
  if (!validation.ok) {
    if (validation.error === 'unsupported_schema_version') {
      return json(
        { error: 'unsupported_schema_version', supported: validation.supported ?? [] },
        400,
      )
    }
    return json({ error: 'invalid_telemetry_payload' }, 400)
  }
  const envelope = validation.envelope

  const secretKeys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}')
  const secretKey = secretKeys.default
  if (typeof secretKey !== 'string') return json({ error: 'server_configuration_error' }, 500)
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, secretKey)
  const row = {
    participant_code: envelope.participantCode,
    study_scenario: envelope.studyScenario,
    client_submitted_at: envelope.submittedAt,
    telemetry_schema_version: envelope.schemaVersion,
    app_version: envelope.appVersion,
    client_session_id: envelope.session.id,
    session_started_at: envelope.session.start ?? null,
    session_duration_ms: envelope.session.durationMs,
    payload: envelope.telemetry,
  }

  // Idempotency. Checked in two steps because a probe is the cheapest reliable
  // way to tell "first write" from "replay": the upsert itself cannot report it
  // without depending on how PostgREST returns conflicting rows.
  const { data: existing, error: probeError } = await supabase
    .from('telemetry_sessions')
    .select('id')
    .eq('participant_code', row.participant_code)
    .eq('client_session_id', row.client_session_id)
    .maybeSingle()
  if (probeError) return json({ error: 'database_write_failed' }, 500)
  if (existing) return json({ accepted: true, duplicated: true }, 200)

  // `ignoreDuplicates` makes this `on conflict do nothing`: a replay that lands
  // between the probe and this write inserts nothing and never overwrites the
  // stored payload. The unique index added in migration 202610250001 is what
  // makes the conflict target real.
  const { error } = await supabase
    .from('telemetry_sessions')
    .upsert(row, {
      onConflict: 'participant_code,client_session_id',
      ignoreDuplicates: true,
    })
  if (error) return json({ error: 'database_write_failed' }, 500)
  return json({ accepted: true }, 201)
})
