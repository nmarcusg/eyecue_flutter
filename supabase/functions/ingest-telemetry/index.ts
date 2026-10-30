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

  // The ledger is a bound on spend, not an audit log: a row is written only for
  // an outcome on a token the database has confirmed. A random, non-existent
  // token hash appends nothing — there is no budget to limit — which is also
  // what stops the table growing without bound under a flood of made-up tokens.
  // Best effort: recording must never change the answer, and a ledger write
  // failure must not turn a stored session into an error the researcher sees.
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
  const reject = (code: string, status: number) => json({ error: code }, status)

  // Idempotency probe: does this (participant_code, client_session_id) pair
  // already have a row? Called only where the token has proven itself real, so
  // the answer never becomes an existence oracle for an arbitrary caller.
  const sessionExists = async (
    participantCode: string,
    clientSessionId: string,
  ): Promise<'found' | 'absent' | 'error'> => {
    const { data, error } = await supabase
      .from('telemetry_sessions')
      .select('id')
      .eq('participant_code', participantCode)
      .eq('client_session_id', clientSessionId)
      .maybeSingle()
    if (error) {
      console.error('ingest: session lookup failed', error.code)
      return 'error'
    }
    return data ? 'found' : 'absent'
  }

  // Rate limiting (T5) before the body is read: the cheapest way to shed a
  // flood. Keyed on the token hash only. There is no per-participant window:
  // the participant code does not exist until the body is parsed, so the only
  // value available here is one the caller chose, and a window keyed on a
  // caller-chosen value limits nothing.
  const { data: rateLimited, error: rateLimitError } = await supabase.rpc(
    'research_ingest_rate_limited',
    { p_token_hash: tokenHash },
  )
  if (rateLimitError) {
    console.error('ingest: rate limit query failed', rateLimitError.code)
    return json({ error: 'database_write_failed' }, 500)
  }
  // Not recorded: a `rate_limited` row would keep the window permanently full.
  if (rateLimited === true) return json({ error: 'rate_limited' }, 429)

  // A chunked body carries no length, so it cannot be bounded before it is
  // buffered: it is refused rather than read whole. The app's sender declares
  // one (`requestHandle.contentLength`, set before the body is written).
  const declaredLength = request.headers.get('content-length')
  const contentLength = Number(declaredLength)
  if (
    declaredLength === null ||
    !Number.isInteger(contentLength) ||
    contentLength < 0
  ) {
    // Distinct from 413 on purpose: a missing length is a transport problem,
    // and answering "too large" would make the app's size message a lie.
    return reject('length_required', 411)
  }
  // Declared length is the cheap gate; the actual bytes below stay the
  // authoritative bound.
  if (isBodyTooLarge(contentLength)) return reject('payload_too_large', 413)

  let body: unknown
  try {
    const text = await request.text()
    // The declared length is the fast gate; this is the check on what actually
    // arrived, for a caller whose header lies.
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
      return json(
        { error: 'unsupported_schema_version', supported: validation.supported ?? [] },
        400,
      )
    }
    return reject('invalid_telemetry_payload', 400)
  }
  const envelope = validation.envelope

  const row = {
    participant_code: envelope.participantCode,
    study_scenario: envelope.studyScenario,
    client_submitted_at: envelope.submittedAt,
    telemetry_schema_version: envelope.schemaVersion,
    app_version: envelope.appVersion,
    // validateEnvelope has already rejected a non-string session id; the JSDoc
    // envelope type only widens it to `unknown`.
    client_session_id: envelope.session.id as string,
    session_started_at: envelope.session.start ?? null,
    session_duration_ms: envelope.session.durationMs,
    payload: envelope.telemetry,
  }

  // Atomic consumption: the row lock inside the RPC is what makes `uses` a real
  // ceiling under concurrent uploads. A use stays spent if the write below then
  // fails (a database fault is not the researcher's budget to absorb), so
  // max_uses should exceed the attempts a researcher needs.
  const { data: tokenStatus, error: consumeError } = await supabase.rpc(
    'consume_research_upload_token',
    {
      p_token_hash: tokenHash,
      p_participant_code: envelope.participantCode,
    },
  )
  if (consumeError) {
    console.error('ingest: token consumption failed', consumeError.code)
    return reject('database_write_failed', 500)
  }
  const tokenFailure = uploadTokenFailure(tokenStatus)
  if (tokenFailure) {
    // `exhausted` can still be a replay of the session this token already
    // stored: that write spent the last use, so consume has nothing left to
    // give and the refund below is never reached. The probe is safe here — the
    // token is real and its participant binding already matched — and it is what
    // keeps a retry at the default max_uses = 1 answering 200 duplicated
    // instead of 403 for data the database already holds. A failed probe falls
    // through to the refusal, which is still a correct answer.
    if (
      tokenStatus === 'exhausted' &&
      (await sessionExists(row.participant_code, row.client_session_id)) ===
        'found'
    ) {
      await recordAttempt('duplicated', envelope.participantCode)
      return json({ accepted: true, duplicated: true }, 200)
    }
    // `invalid` means no row has this hash, so there is no budget to limit and
    // nothing worth recording; every other refusal is a real token spending
    // down, which is what the rolling window counts.
    if (tokenStatus !== 'invalid') {
      await recordAttempt(tokenFailure.error, envelope.participantCode)
    }
    return reject(tokenFailure.error, tokenFailure.status)
  }

  // Idempotency. Checked in two steps because a probe is the cheapest reliable
  // way to tell "first write" from "replay": the upsert itself cannot report it
  // without depending on how PostgREST returns conflicting rows.
  const existing = await sessionExists(row.participant_code, row.client_session_id)
  if (existing === 'error') {
    return reject('database_write_failed', 500)
  }
  if (existing === 'found') {
    // A replay on a token that still had headroom spent a use above for nothing,
    // so give it back: `uses` ends where it started and the retry stays 200
    // duplicated. Best effort like the ledger — the answer is 200 either way.
    // The narrow probe/insert race below still keeps its use, and the exhausted
    // case has no use to return (it was answered before this point).
    const { error: refundError } = await supabase.rpc(
      'refund_research_upload_token',
      { p_token_hash: tokenHash },
    )
    if (refundError) {
      console.error('ingest: token refund failed', refundError.code)
    }
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
    console.error('ingest: session insert failed', error.code)
    return reject('database_write_failed', 500)
  }
  await recordAttempt('accepted', envelope.participantCode)
  return json({ accepted: true }, 201)
})
