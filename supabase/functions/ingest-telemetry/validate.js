/**
 * Pure validation predicates for the telemetry ingest Edge Function.
 *
 * Plain ESM JavaScript rather than TypeScript so `node --test` can execute it
 * with no build step and no dependencies (see `validate.test.mjs`), while Deno
 * imports the same file directly from `index.ts`. Types are JSDoc only.
 *
 * @typedef {Record<string, unknown>} JsonRecord
 * @typedef {{
 *   participantCode: string,
 *   studyScenario: string,
 *   submittedAt: string,
 *   schemaVersion: number,
 *   appVersion: string,
 *   session: JsonRecord,
 *   telemetry: JsonRecord,
 * }} Envelope
 * @typedef {{ ok: true, envelope: Envelope }} EnvelopeAccepted
 * @typedef {{ ok: false, error: 'invalid_telemetry_payload' | 'unsupported_schema_version', supported?: number[] }} EnvelopeRejected
 * @typedef {EnvelopeAccepted | EnvelopeRejected} EnvelopeResult
 */

/** Ingest body limit in bytes; mirrors the client guard (2 000 000). */
export const MAX_BODY_BYTES = 2_000_000

/** Telemetry schema versions this function accepts. */
export const SUPPORTED_SCHEMA_VERSIONS = [3, 4]

/**
 * Key names that must never reach the collection. Matching is **exact**: no
 * prefix, suffix or case folding, so a key such as `frameNumber` is unaffected
 * by the `frame` entry.
 */
export const FORBIDDEN_KEYS = new Set([
  'image',
  'images',
  'screenshot',
  'screenshots',
  'frame',
  'frames',
  'audio',
  'utterance',
  'path',
  'paths',
  'deviceId',
  'technicalDetail',
  'serviceRole',
  'secret',
  'secrets',
  'token',
  'tokens',
  'apiKey',
  'password',
])

/**
 * The single narrow exception: `frameNumber` is a pre-existing frame counter on
 * alert-lifecycle records, not a frame. It is allowlisted by exact name and
 * nothing else is, so the allowance cannot grow into a prefix rule.
 */
export const ALLOWED_KEYS = new Set(['frameNumber'])

/** @type {RegExp} */
const participantCodePattern = /^[A-Za-z0-9_-]{1,64}$/

/**
 * @param {unknown} value
 * @returns {value is JsonRecord}
 */
function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

/**
 * @param {string} key
 * @returns {boolean}
 */
export function isForbiddenKey(key) {
  return !ALLOWED_KEYS.has(key) && FORBIDDEN_KEYS.has(key)
}

/**
 * Walks objects and arrays looking for a forbidden key at any depth.
 *
 * @param {unknown} value
 * @returns {boolean}
 */
export function containsForbiddenKey(value) {
  if (Array.isArray(value)) return value.some(containsForbiddenKey)
  if (!isRecord(value)) return false
  return Object.entries(value).some(
    ([key, nested]) => isForbiddenKey(key) || containsForbiddenKey(nested),
  )
}

/**
 * @param {unknown} version
 * @returns {boolean}
 */
export function isSupportedSchemaVersion(version) {
  return (
    typeof version === 'number' &&
    SUPPORTED_SCHEMA_VERSIONS.includes(version)
  )
}

/**
 * @param {number} byteLength
 * @returns {boolean}
 */
export function isBodyTooLarge(byteLength) {
  return byteLength > MAX_BODY_BYTES
}

/**
 * Validates the ingestion envelope. Structural problems are reported as
 * `invalid_telemetry_payload`; a well-formed envelope carrying a schema version
 * outside {@link SUPPORTED_SCHEMA_VERSIONS} is reported separately so the app
 * can tell a format mismatch from a malformed upload.
 *
 * The row shape is never inferred from `telemetry.schemaVersion`: a re-exported
 * schema-3 payload is stamped 4 and accepted with schema-3 sample rows.
 *
 * @param {unknown} body
 * @returns {EnvelopeResult}
 */
export function validateEnvelope(body) {
  /** @type {EnvelopeRejected} */
  const invalid = { ok: false, error: 'invalid_telemetry_payload' }
  if (!isRecord(body)) return invalid

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
    !participantCodePattern.test(study.participantCode) ||
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
    return invalid
  }

  if (!isSupportedSchemaVersion(telemetry.schemaVersion)) {
    return {
      ok: false,
      error: 'unsupported_schema_version',
      supported: SUPPORTED_SCHEMA_VERSIONS,
    }
  }

  return {
    ok: true,
    envelope: {
      participantCode: study.participantCode,
      studyScenario: study.studyScenario.trim(),
      submittedAt: body.submittedAt,
      schemaVersion: telemetry.schemaVersion,
      appVersion: telemetry.appVersion,
      session: telemetry.session,
      telemetry,
    },
  }
}

// ---------------------------------------------------------------------------
// Study upload tokens (see docs/ingest-threat-model.md, threat T1).
//
// Everything below is shape- and transport-level only: the token's *validity*
// is decided in the database by consume_research_upload_token(), which is the
// single place that knows expiry, revocation, uses and participant binding.
// No helper here returns, echoes or logs a token — they return booleans, a
// status string, or the header value the caller already holds.
// ---------------------------------------------------------------------------

/** Header carrying the researcher-issued study upload token. */
export const UPLOAD_TOKEN_HEADER = 'x-eyecue-upload-token'

/**
 * Accepted token length range, in characters.
 *
 * 256 random bits base64url-encoded is 43 characters and hex is 64, so 43 is
 * the floor for anything with real entropy. The 128 ceiling only stops an
 * absurd paste from reaching a hash and a database lookup.
 */
export const UPLOAD_TOKEN_MIN_LENGTH = 43
export const UPLOAD_TOKEN_MAX_LENGTH = 128

/** Token-safe alphabet: base64url + hex, i.e. no padding, no separators. */
const uploadTokenPattern = /^[A-Za-z0-9_-]+$/

/**
 * Rate-limit constants, mirrored by `research_ingest_rate_limited()` in
 * `202610260001_research_upload_tokens.sql`. A test asserts the two copies
 * agree, because a silent divergence would either throttle real uploads or
 * quietly disable the limit.
 */
export const RATE_LIMIT_TOKEN_MAX = 10
export const RATE_LIMIT_PARTICIPANT_MAX = 20
export const RATE_LIMIT_WINDOW_MINUTES = 10

/**
 * Reads the upload token out of request-like headers.
 *
 * Supports a `Headers` instance (has `get`) and a plain record (looked up
 * case-insensitively). Returns the value **unmodified**: trimming it here would
 * repair a defective header instead of reporting it, so `" abc… "` is returned
 * as-is and rejected by {@link isValidUploadTokenShape}.
 *
 * @param {{ get(name: string): string | null } | Record<string, unknown> | null} headers
 * @returns {string | null}
 */
export function readUploadTokenHeader(headers) {
  if (headers === null || headers === undefined) return null
  let value
  if (typeof headers.get === 'function') {
    value = headers.get(UPLOAD_TOKEN_HEADER)
  } else if (isRecord(headers)) {
    const key = Object.keys(headers).find(
      (name) => name.toLowerCase() === UPLOAD_TOKEN_HEADER,
    )
    value = key === undefined ? undefined : headers[key]
  }
  return typeof value === 'string' && value.length > 0 ? value : null
}

/**
 * Shape check only — presence, no padding, sane length, token-safe alphabet.
 *
 * Deliberately says nothing about whether the token exists: an in-range,
 * well-formed random string is indistinguishable from a real token here, which
 * is the point (threat T4 — guessing yields nothing without a valid token).
 *
 * @param {unknown} token
 * @returns {boolean}
 */
export function isValidUploadTokenShape(token) {
  if (typeof token !== 'string') return false
  // Reject padded input instead of repairing it: leading/trailing whitespace
  // means the token was mangled somewhere, and a trimmed guess would silently
  // "work" for a value that was never issued.
  if (token !== token.trim()) return false
  if (
    token.length < UPLOAD_TOKEN_MIN_LENGTH ||
    token.length > UPLOAD_TOKEN_MAX_LENGTH
  ) {
    return false
  }
  return uploadTokenPattern.test(token)
}

/**
 * @typedef {{ error: string, status: number }} IngestFailure
 */

/** Answer for an absent header: a client-side bug, not a bad token. */
export const MISSING_UPLOAD_TOKEN = /** @type {IngestFailure} */ ({
  error: 'missing_upload_token',
  status: 401,
})

/**
 * Every terminal answer of `consume_research_upload_token()` except `ok`.
 * `invalid` covers both a malformed and an unknown hash, so the answer is not
 * an oracle for "does this token exist".
 *
 * @type {Record<string, IngestFailure>}
 */
export const UPLOAD_TOKEN_FAILURES = {
  invalid: { error: 'invalid_upload_token', status: 401 },
  expired: { error: 'expired_upload_token', status: 401 },
  revoked: { error: 'revoked_upload_token', status: 401 },
  exhausted: { error: 'upload_token_exhausted', status: 403 },
  participant_mismatch: { error: 'participant_mismatch', status: 403 },
}

/**
 * Maps a token status to the HTTP answer. `ok` is `null` (proceed); anything
 * unrecognised — including a non-string — is treated as `invalid`, never as
 * success.
 *
 * @param {unknown} status
 * @returns {IngestFailure | null}
 */
export function uploadTokenFailure(status) {
  if (status === 'ok') return null
  if (typeof status === 'string' && Object.hasOwn(UPLOAD_TOKEN_FAILURES, status)) {
    return UPLOAD_TOKEN_FAILURES[status]
  }
  return UPLOAD_TOKEN_FAILURES.invalid
}
