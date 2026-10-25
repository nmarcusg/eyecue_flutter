import { createClient } from 'npm:@supabase/supabase-js@2'

import {
  MISSING_UPLOAD_TOKEN,
  isBodyTooLarge,
  isValidUploadTokenShape,
  readUploadTokenHeader,
  uploadTokenFailure,
  validateEnvelope,
} from './validate.js'

const json = (body: Record<string, unknown>, status = 200) =>
  Response.json(body, { status, headers: { 'content-type': 'application/json' } })

// SHA-256 hex of the token. The raw token lives only in this request's memory:
// it is never logged, never echoed and never written to a row. SHA-256 rather
// than a password KDF because the token is 256 random bits — there is no
// dictionary and no low entropy to stretch.
const sha256Hex = async (value: string) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)),
    ),
  )
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)
  const publishableKeys = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') ?? '{}')
  if (
    typeof publishableKeys.default !== 'string' ||
    request.headers.get('apikey') !== publishableKeys.default
  ) {
    return json({ error: 'unauthorized' }, 401)
  }

  // Client identity (the publishable key baked into the APK) is never enough on
  // its own: the study upload token is the credential that authorises a write
  // (threats T1/T2 in docs/ingest-threat-model.md).
  const uploadToken = readUploadTokenHeader(request.headers)
  if (uploadToken === null) {
    return json({ error: MISSING_UPLOAD_TOKEN.error }, MISSING_UPLOAD_TOKEN.status)
  }
  if (!isValidUploadTokenShape(uploadToken)) {
    return json({ error: 'invalid_upload_token' }, 401)
  }
  const tokenHash = await sha256Hex(uploadToken)

  const secretKeys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}')
  const secretKey = secretKeys.default
  if (typeof secretKey !== 'string') return json({ error: 'server_configuration_error' }, 500)
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, secretKey)

  // One ledger row per finished attempt, so the rolling window counts repeated
  // failures as well as successes. Best effort: recording must never change the
  // answer, and a ledger write failure must not turn a stored session into an
  // error the researcher sees.
  const recordAttempt = async (
    outcome: string,
    participantCode: string | null = null,
  ) => {
    try {
      const { error } = await supabase
        .from('research_ingest_attempts')
        .insert({
          token_hash: tokenHash,
          participant_code: participantCode,
          outcome,
        })
      if (error) console.error('ingest: attempt ledger write failed', error.code)
    } catch (_) {
      // Nothing to do: the ledger is advisory.
    }
  }
  const reject = async (
    code: string,
    status: number,
    participantCode: string | null = null,
  ) => {
    await recordAttempt(code, participantCode)
    return json({ error: code }, status)
  }

  // Rate limiting (T5) before the body is read: the cheapest way to shed a
  // flood. The participant code is null here on purpose — it does not exist
  // until the body is parsed, and a value taken from an unvalidated body would
  // be chosen by the caller.
  const { data: rateLimited, error: rateLimitError } = await supabase.rpc(
    'research_ingest_rate_limited',
    { p_token_hash: tokenHash, p_participant_code: null },
  )
  if (rateLimitError) return json({ error: 'database_write_failed' }, 500)
  // Not recorded: a `rate_limited` row would keep the window permanently full.
  if (rateLimited === true) return json({ error: 'rate_limited' }, 429)

  const contentLength = Number(request.headers.get('content-length') ?? 0)
  if (isBodyTooLarge(contentLength)) return reject('payload_too_large', 413)

  let body: unknown
  try {
    const text = await request.text()
    if (isBodyTooLarge(new TextEncoder().encode(text).byteLength)) {
      return reject('payload_too_large', 413)
    }
    body = JSON.parse(text)
  } catch (_) {
    return reject('invalid_json', 400)
  }

  // Envelope shape, forbidden keys and the supported schema set are decided in
  // validate.js, which `node --test` can exercise without Deno or a database.
  const validation = validateEnvelope(body)
  if (!validation.ok) {
    if (validation.error === 'unsupported_schema_version') {
      await recordAttempt('unsupported_schema_version')
      return json(
        { error: 'unsupported_schema_version', supported: validation.supported ?? [] },
        400,
      )
    }
    return reject('invalid_telemetry_payload', 400)
  }
  const envelope = validation.envelope

  // Atomic consumption: the row lock inside the RPC is what makes `uses` a real
  // ceiling under concurrent uploads. A use is spent even if the write below
  // then fails, so max_uses should exceed the attempts a researcher needs.
  const { data: tokenStatus, error: consumeError } = await supabase.rpc(
    'consume_research_upload_token',
    {
      p_token_hash: tokenHash,
      p_participant_code: envelope.participantCode,
    },
  )
  if (consumeError) {
    return reject('database_write_failed', 500, envelope.participantCode)
  }
  const tokenFailure = uploadTokenFailure(tokenStatus)
  if (tokenFailure) {
    return reject(tokenFailure.error, tokenFailure.status, envelope.participantCode)
  }

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
  if (probeError) {
    return reject('database_write_failed', 500, envelope.participantCode)
  }
  if (existing) {
    await recordAttempt('duplicated', envelope.participantCode)
    return json({ accepted: true, duplicated: true }, 200)
  }

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
  if (error) {
    return reject('database_write_failed', 500, envelope.participantCode)
  }
  await recordAttempt('accepted', envelope.participantCode)
  return json({ accepted: true }, 201)
})
