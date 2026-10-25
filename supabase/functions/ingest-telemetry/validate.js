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
