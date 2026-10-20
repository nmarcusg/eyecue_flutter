import { createClient } from 'npm:@supabase/supabase-js@2'

const maxBodyBytes = 2_000_000
const participantCode = /^[A-Za-z0-9_-]{1,64}$/

const json = (body: Record<string, unknown>, status = 200) =>
  Response.json(body, { status, headers: { 'content-type': 'application/json' } })

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function containsForbiddenKey(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsForbiddenKey)
  if (!isRecord(value)) return false
  for (const [key, nested] of Object.entries(value)) {
    if (['image', 'images', 'deviceId', 'technicalDetail', 'path', 'utterance'].includes(key)) {
      return true
    }
    if (containsForbiddenKey(nested)) return true
  }
  return false
}

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
  if (contentLength > maxBodyBytes) return json({ error: 'payload_too_large' }, 413)

  let body: Record<string, unknown>
  try {
    const text = await request.text()
    if (new TextEncoder().encode(text).byteLength > maxBodyBytes) {
      return json({ error: 'payload_too_large' }, 413)
    }
    const parsed: unknown = JSON.parse(text)
    if (!isRecord(parsed)) return json({ error: 'invalid_json' }, 400)
    body = parsed
  } catch (_) {
    return json({ error: 'invalid_json' }, 400)
  }

  const study = body.study
  const telemetry = body.telemetry
  const consent = body.consent
  if (
    body.ingestionSchemaVersion !== 1 ||
    !isRecord(study) ||
    !isRecord(telemetry) ||
    !isRecord(consent) ||
    consent.manualSessionUpload !== true ||
    typeof study.participantCode !== 'string' ||
    !participantCode.test(study.participantCode) ||
    typeof study.studyScenario !== 'string' ||
    study.studyScenario.trim().length === 0 ||
    study.studyScenario.trim().length > 80 ||
    typeof body.submittedAt !== 'string' ||
    typeof telemetry.schemaVersion !== 'number' ||
    typeof telemetry.appVersion !== 'string' ||
    !isRecord(telemetry.session) ||
    typeof telemetry.session.id !== 'string' ||
    typeof telemetry.session.durationMs !== 'number' ||
    telemetry.session.durationMs < 0 ||
    containsForbiddenKey(telemetry)
  ) {
    return json({ error: 'invalid_telemetry_payload' }, 400)
  }

  const secretKeys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}')
  const secretKey = secretKeys.default
  if (typeof secretKey !== 'string') return json({ error: 'server_configuration_error' }, 500)
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, secretKey)
  const { error } = await supabase.from('telemetry_sessions').insert({
    participant_code: study.participantCode,
    study_scenario: study.studyScenario.trim(),
    client_submitted_at: body.submittedAt,
    telemetry_schema_version: telemetry.schemaVersion,
    app_version: telemetry.appVersion,
    client_session_id: telemetry.session.id,
    session_started_at: telemetry.session.start ?? null,
    session_duration_ms: telemetry.session.durationMs,
    payload: telemetry,
  })
  if (error) return json({ error: 'database_write_failed' }, 500)
  return json({ accepted: true }, 201)
})
