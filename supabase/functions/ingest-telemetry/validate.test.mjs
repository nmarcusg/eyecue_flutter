// CLI-free contract tests for the ingest validation predicates.
//
//   node --test supabase/functions/ingest-telemetry/validate.test.mjs
//
// No dependencies and no package.json: `node --test` is the whole harness, so
// the rules that decide what may enter the research collection are executable on
// a machine without Deno, Docker or a Supabase project.

import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import {
  ALLOWED_KEYS,
  FORBIDDEN_KEYS,
  MAX_BODY_BYTES,
  SUPPORTED_SCHEMA_VERSIONS,
  containsForbiddenKey,
  isBodyTooLarge,
  isForbiddenKey,
  isSupportedSchemaVersion,
  validateEnvelope,
} from './validate.js'

const validEnvelope = () => ({
  ingestionSchemaVersion: 1,
  submittedAt: '2026-10-20T12:00:00.000Z',
  consent: { manualSessionUpload: true },
  study: { participantCode: 'P-001', studyScenario: ' indoor-obstacle-course ' },
  telemetry: {
    schemaVersion: 4,
    appVersion: '1.0.0+1',
    session: { id: 'session-1', durationMs: 1000 },
  },
})

/** Applies `mutate` to a fresh valid envelope and returns the verdict. */
const verdictAfter = (mutate) => {
  const envelope = validEnvelope()
  mutate(envelope)
  return validateEnvelope(envelope)
}

test('the forbidden set is exactly the documented list', () => {
  assert.deepEqual(
    [...FORBIDDEN_KEYS].sort(),
    [
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
    ].sort(),
  )
})

for (const key of FORBIDDEN_KEYS) {
  test(`forbidden key "${key}" is rejected at the top level, nested and array-nested`, () => {
    assert.equal(isForbiddenKey(key), true)
    assert.equal(isForbiddenKey(key.toUpperCase()), false, 'matching is case-sensitive')
    assert.equal(containsForbiddenKey({ [key]: 'x' }), true)
    assert.equal(containsForbiddenKey({ outer: { inner: { [key]: 'x' } } }), true)
    assert.equal(containsForbiddenKey({ rows: [{ ok: 1 }, { [key]: 'x' }] }), true)
    assert.deepEqual(
      verdictAfter((envelope) => {
        envelope.telemetry[key] = 'x'
      }),
      { ok: false, error: 'invalid_telemetry_payload' },
    )
  })
}

test('allowed keys are the exact frameNumber exception only', () => {
  assert.deepEqual([...ALLOWED_KEYS], ['frameNumber'])
  assert.equal(isForbiddenKey('frameNumber'), false)
  assert.equal(containsForbiddenKey({ frameNumber: 4242 }), false)
  assert.equal(containsForbiddenKey({ alertLifecycle: [{ frameNumber: 4242 }] }), false)
  // The allowance is exact, not a prefix rule: `frame` stays forbidden.
  assert.equal(isForbiddenKey('frame'), true)
  assert.equal(isForbiddenKey('frameNumbers'), false)
  assert.equal(containsForbiddenKey({ alertLifecycle: [{ frame: 4242 }] }), true)
  assert.deepEqual(
    verdictAfter((envelope) => {
      envelope.telemetry.alertLifecycle = [{ frameNumber: 4242 }]
    }),
    {
      ok: true,
      envelope: {
        participantCode: 'P-001',
        studyScenario: 'indoor-obstacle-course',
        submittedAt: '2026-10-20T12:00:00.000Z',
        schemaVersion: 4,
        appVersion: '1.0.0+1',
        session: { id: 'session-1', durationMs: 1000 },
        telemetry: {
          schemaVersion: 4,
          appVersion: '1.0.0+1',
          session: { id: 'session-1', durationMs: 1000 },
          alertLifecycle: [{ frameNumber: 4242 }],
        },
      },
    },
  )
})

test('a valid schema-4 envelope is accepted and trimmed', () => {
  const result = validateEnvelope(validEnvelope())
  assert.equal(result.ok, true)
  assert.equal(result.envelope.studyScenario, 'indoor-obstacle-course')
  assert.equal(result.envelope.participantCode, 'P-001')
})

test('a non-object body is rejected', () => {
  for (const body of [null, undefined, 42, 'text', [], [{ a: 1 }]]) {
    assert.deepEqual(validateEnvelope(body), {
      ok: false,
      error: 'invalid_telemetry_payload',
    })
  }
})

test('ingestionSchemaVersion must be exactly 1', () => {
  for (const value of [0, 2, '1', null, undefined]) {
    assert.deepEqual(
      verdictAfter((envelope) => {
        envelope.ingestionSchemaVersion = value
      }),
      { ok: false, error: 'invalid_telemetry_payload' },
      `ingestionSchemaVersion ${JSON.stringify(value)}`,
    )
  }
})

test('consent.manualSessionUpload must be exactly true', () => {
  for (const value of [false, 'true', 1, null, undefined]) {
    assert.deepEqual(
      verdictAfter((envelope) => {
        envelope.consent = { manualSessionUpload: value }
      }),
      { ok: false, error: 'invalid_telemetry_payload' },
      `manualSessionUpload ${JSON.stringify(value)}`,
    )
  }
  assert.deepEqual(
    verdictAfter((envelope) => {
      delete envelope.consent
    }),
    { ok: false, error: 'invalid_telemetry_payload' },
  )
})

test('participantCode must match the study code pattern', () => {
  for (const value of ['', 'P 001', 'person@example.com', 'x'.repeat(65), 7, null]) {
    assert.deepEqual(
      verdictAfter((envelope) => {
        envelope.study.participantCode = value
      }),
      { ok: false, error: 'invalid_telemetry_payload' },
      `participantCode ${JSON.stringify(value)}`,
    )
  }
  assert.equal(
    verdictAfter((envelope) => {
      envelope.study.participantCode = 'a'.repeat(64) + '_'
    }).ok,
    false,
  )
})

test('studyScenario must be present, non-blank and at most 80 characters', () => {
  for (const value of ['', '   ', 'x'.repeat(81), 5, null, undefined]) {
    assert.deepEqual(
      verdictAfter((envelope) => {
        envelope.study.studyScenario = value
      }),
      { ok: false, error: 'invalid_telemetry_payload' },
      `studyScenario ${JSON.stringify(value)}`,
    )
  }
  assert.equal(
    verdictAfter((envelope) => {
      envelope.study.studyScenario = `  ${'x'.repeat(80)}  `
    }).ok,
    true,
  )
  assert.deepEqual(
    verdictAfter((envelope) => {
      delete envelope.study
    }),
    { ok: false, error: 'invalid_telemetry_payload' },
  )
})

test('submittedAt must be a string', () => {
  for (const value of [undefined, null, 1761000000000, {}]) {
    assert.deepEqual(
      verdictAfter((envelope) => {
        envelope.submittedAt = value
      }),
      { ok: false, error: 'invalid_telemetry_payload' },
      `submittedAt ${JSON.stringify(value)}`,
    )
  }
})

test('telemetry.schemaVersion must be a number', () => {
  for (const value of [undefined, null, '4', {}, []]) {
    assert.deepEqual(
      verdictAfter((envelope) => {
        envelope.telemetry.schemaVersion = value
      }),
      { ok: false, error: 'invalid_telemetry_payload' },
      `schemaVersion ${JSON.stringify(value)}`,
    )
  }
})

test('telemetry.appVersion must be a string', () => {
  for (const value of [undefined, null, 1, {}]) {
    assert.deepEqual(
      verdictAfter((envelope) => {
        envelope.telemetry.appVersion = value
      }),
      { ok: false, error: 'invalid_telemetry_payload' },
      `appVersion ${JSON.stringify(value)}`,
    )
  }
})

test('telemetry.session must carry an id and a non-negative durationMs', () => {
  for (const session of [
    undefined,
    null,
    [],
    {},
    { durationMs: 1000 },
    { id: 'session-1' },
    { id: 1, durationMs: 1000 },
    { id: 'session-1', durationMs: -1 },
    { id: 'session-1', durationMs: '1000' },
  ]) {
    assert.deepEqual(
      verdictAfter((envelope) => {
        envelope.telemetry.session = session
      }),
      { ok: false, error: 'invalid_telemetry_payload' },
      `session ${JSON.stringify(session)}`,
    )
  }
  assert.equal(
    verdictAfter((envelope) => {
      envelope.telemetry.session = { id: 'session-1', durationMs: 0 }
    }).ok,
    true,
  )
})

test('the supported schema set is exactly 3 and 4', () => {
  assert.deepEqual(SUPPORTED_SCHEMA_VERSIONS, [3, 4])
  assert.equal(isSupportedSchemaVersion(3), true)
  assert.equal(isSupportedSchemaVersion(4), true)
  for (const version of [1, 2, 5, 0, -4, 3.5, '4', null, undefined, NaN]) {
    assert.equal(isSupportedSchemaVersion(version), false, `version ${version}`)
  }
})

test('a schema-3 payload is accepted with schema-3 rows', () => {
  const result = verdictAfter((envelope) => {
    envelope.telemetry.schemaVersion = 3
    envelope.telemetry.samples = [{ latencyMs: 42.5 }]
  })
  assert.equal(result.ok, true)
  assert.equal(result.envelope.schemaVersion, 3)
})

test('a re-exported schema-3 payload stamped 4 is accepted (no row-shape inference)', () => {
  const result = verdictAfter((envelope) => {
    envelope.telemetry.schemaVersion = 4
    // No schema-4 sample keys at all: the header must not be used to reject it.
    envelope.telemetry.samples = [{ latencyMs: 42.5, inferenceFps: 12.5 }]
  })
  assert.equal(result.ok, true)
  assert.deepEqual(result.envelope.telemetry.samples, [
    { latencyMs: 42.5, inferenceFps: 12.5 },
  ])
})

test('an unsupported schema version is reported separately with the supported set', () => {
  for (const version of [2, 5, 3.5]) {
    assert.deepEqual(
      verdictAfter((envelope) => {
        envelope.telemetry.schemaVersion = version
      }),
      { ok: false, error: 'unsupported_schema_version', supported: [3, 4] },
      `schemaVersion ${version}`,
    )
  }
})

test('case-variant and padded forbidden-key spellings pass by design', () => {
  // Matching is exact and whitespace-sensitive on purpose: this is a tripwire
  // against the app's own key names, not a security boundary. A payload that
  // called its image `Image` or ` image ` would pass here.
  for (const key of ['Image', 'IMAGE', ' image ', 'image\t', 'deviceID']) {
    assert.equal(isForbiddenKey(key), false, key)
  }
})

const functionDir = dirname(fileURLToPath(import.meta.url))
const migrationSql = readFileSync(
  join(functionDir, '../../migrations/202610250001_harden_research_telemetry.sql'),
  'utf8',
)
const indexSource = readFileSync(join(functionDir, 'index.ts'), 'utf8')

test('the migration schema check matches SUPPORTED_SCHEMA_VERSIONS', () => {
  const match = migrationSql.match(
    /check \(telemetry_schema_version in \(([\d,\s]+)\)\)/,
  )
  assert.ok(match, 'the migration must carry the supported-schema check')
  assert.deepEqual(
    match[1].split(',').map((version) => Number(version.trim())),
    [...SUPPORTED_SCHEMA_VERSIONS],
  )
})

test('the migration unique index matches the onConflict target', () => {
  const indexColumns = migrationSql.match(
    /create unique index telemetry_sessions_participant_session_uidx\s+on public\.telemetry_sessions \(([^)]+)\)/,
  )
  assert.ok(indexColumns, 'the migration must create the idempotency index')
  const onConflict = indexSource.match(/onConflict: '([^']+)'/)
  assert.ok(onConflict, 'index.ts must upsert on the idempotency pair')
  const columns = (value) =>
    value
      .split(',')
      .map((column) => column.trim())
      .join(',')
  assert.equal(columns(indexColumns[1]), columns(onConflict[1]))
})

test('the storage bound leaves headroom above the wire cap', () => {
  // `jsonb` text output is larger than the compact body, so a storage check at
  // exactly MAX_BODY_BYTES would reject a body the function accepted.
  const bound = migrationSql.match(
    /check \(octet_length\(payload::text\) <= (\d+)\)/,
  )
  assert.ok(bound, 'the migration must carry the payload size bound')
  assert.ok(Number(bound[1]) > MAX_BODY_BYTES)
})

test('the body bound is 2 000 000 bytes, inclusive', () => {
  assert.equal(MAX_BODY_BYTES, 2_000_000)
  assert.equal(isBodyTooLarge(0), false)
  assert.equal(isBodyTooLarge(MAX_BODY_BYTES - 1), false)
  assert.equal(isBodyTooLarge(MAX_BODY_BYTES), false)
  assert.equal(isBodyTooLarge(MAX_BODY_BYTES + 1), true)
  assert.equal(isBodyTooLarge(2_000_001), true)
  // The measured worst-case envelope is 1 850 400 bytes: still accepted.
  assert.equal(isBodyTooLarge(1_850_400), false)
})
