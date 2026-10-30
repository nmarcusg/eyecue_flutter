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
  MISSING_UPLOAD_TOKEN,
  RATE_LIMIT_TOKEN_MAX,
  RATE_LIMIT_WINDOW_MINUTES,
  SUPPORTED_SCHEMA_VERSIONS,
  UPLOAD_TOKEN_FAILURES,
  UPLOAD_TOKEN_HEADER,
  UPLOAD_TOKEN_MAX_LENGTH,
  UPLOAD_TOKEN_MIN_LENGTH,
  containsForbiddenKey,
  isBodyTooLarge,
  isForbiddenKey,
  isSupportedSchemaVersion,
  isValidUploadTokenShape,
  readUploadTokenHeader,
  uploadTokenFailure,
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

test('the migration drops the original payload check by name, unguarded', () => {
  // 202610200001 left the check unnamed, so PostgreSQL named it after the
  // table and payload column. The drop must carry no `if exists`: a name
  // mismatch has to abort the migration, because a silent no-op would leave
  // the old 2,000,000-byte bound
  // in force beside the new one.
  assert.match(
    migrationSql,
    /alter table public\.telemetry_sessions\s+drop constraint telemetry_sessions_payload_check;/,
    'the migration must drop telemetry_sessions_payload_check by name',
  )
  assert.ok(
    !/drop constraint if exists/i.test(migrationSql),
    'the drop must not be guarded, or a renamed constraint would be skipped silently',
  )
})

test('the storage bound leaves headroom above the wire cap', () => {
  // `jsonb` text output is larger than the compact body, so a storage check at
  // exactly MAX_BODY_BYTES would reject a body the function accepted. A real
  // margin, not just "greater than": at least 20 % above the wire cap.
  const bound = migrationSql.match(
    /check \(octet_length\(payload::text\) <= (\d+)\)/,
  )
  assert.ok(bound, 'the migration must carry the payload size bound')
  assert.ok(
    Number(bound[1]) >= MAX_BODY_BYTES * 1.2,
    `storage bound ${bound[1]} needs >= ${MAX_BODY_BYTES * 1.2} bytes of headroom`,
  )
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

// ---------------------------------------------------------------------------
// Study upload tokens (docs/ingest-threat-model.md, T1–T4).
// ---------------------------------------------------------------------------

/** A well-formed 256-bit token: 32 bytes base64url-encoded, no padding. */
const VALID_TOKEN = 'q3Yd0n4N0m8Lw2Xc9Vb6Tz1Rf5Jk7Hp0Sg4Da2Em6Ui8'

test('the upload token header name is the documented one', () => {
  assert.equal(UPLOAD_TOKEN_HEADER, 'x-eyecue-upload-token')
})

test('readUploadTokenHeader reads Headers and plain records, or null', () => {
  const headers = new Headers()
  headers.set('X-Eyecue-Upload-Token', VALID_TOKEN)
  assert.equal(readUploadTokenHeader(headers), VALID_TOKEN)

  // Absent.
  assert.equal(readUploadTokenHeader(new Headers()), null)
  // Plain record, any case.
  assert.equal(
    readUploadTokenHeader({ 'X-EYECUE-UPLOAD-TOKEN': VALID_TOKEN }),
    VALID_TOKEN,
  )
  // Nothing at all, or a non-string value.
  assert.equal(readUploadTokenHeader(null), null)
  assert.equal(readUploadTokenHeader(undefined), null)
  assert.equal(readUploadTokenHeader({}), null)
  assert.equal(readUploadTokenHeader({ [UPLOAD_TOKEN_HEADER]: 42 }), null)
  // Empty is absent, not "invalid shape": the two answers are different.
  assert.equal(readUploadTokenHeader({ [UPLOAD_TOKEN_HEADER]: '' }), null)
})

test('the header value is returned unmodified, never trimmed', () => {
  // Repairing a padded header would make a value that was never issued work.
  const padded = ` ${VALID_TOKEN} `
  assert.equal(
    readUploadTokenHeader({ [UPLOAD_TOKEN_HEADER]: padded }),
    padded,
  )
  assert.equal(isValidUploadTokenShape(padded), false)
})

test('a token is 43–128 token-safe characters, unpadded', () => {
  assert.equal(UPLOAD_TOKEN_MIN_LENGTH, 43)
  assert.equal(UPLOAD_TOKEN_MAX_LENGTH, 128)
  // Boundaries.
  assert.equal(isValidUploadTokenShape('a'.repeat(42)), false)
  assert.equal(isValidUploadTokenShape('a'.repeat(43)), true)
  assert.equal(isValidUploadTokenShape('a'.repeat(64)), true)
  assert.equal(isValidUploadTokenShape('a'.repeat(128)), true)
  assert.equal(isValidUploadTokenShape('a'.repeat(129)), false)
  // base64url and hex alphabets, including both separator characters.
  assert.equal(isValidUploadTokenShape(VALID_TOKEN), true)
  assert.equal(isValidUploadTokenShape('-'.repeat(43)), true)
  assert.equal(isValidUploadTokenShape('_'.repeat(43)), true)
  assert.equal(isValidUploadTokenShape('A1'.repeat(32)), true)
})

test('an empty, padded, oversized or non-token-safe token is refused', () => {
  for (const token of [
    '',
    ' ',
    ` ${VALID_TOKEN}`,
    `${VALID_TOKEN} `,
    `${VALID_TOKEN}\n`,
    `${VALID_TOKEN}=`,
    VALID_TOKEN.replace('q', '+'),
    VALID_TOKEN.replace('q', '/'),
    `${VALID_TOKEN}.`,
    `${VALID_TOKEN} ${VALID_TOKEN}`,
    `${VALID_TOKEN}!`,
    'ü'.repeat(43),
    'a'.repeat(500),
  ]) {
    assert.equal(
      isValidUploadTokenShape(token),
      false,
      `token ${JSON.stringify(token.slice(0, 12))}… must be refused`,
    )
  }
  for (const value of [undefined, null, 42, {}, [], true]) {
    assert.equal(isValidUploadTokenShape(value), false, String(value))
  }
})

test('each token status maps to one stable HTTP answer', () => {
  assert.equal(uploadTokenFailure('ok'), null)
  assert.deepEqual(uploadTokenFailure('invalid'), {
    error: 'invalid_upload_token',
    status: 401,
  })
  assert.deepEqual(uploadTokenFailure('expired'), {
    error: 'expired_upload_token',
    status: 401,
  })
  assert.deepEqual(uploadTokenFailure('revoked'), {
    error: 'revoked_upload_token',
    status: 401,
  })
  assert.deepEqual(uploadTokenFailure('exhausted'), {
    error: 'upload_token_exhausted',
    status: 403,
  })
  assert.deepEqual(uploadTokenFailure('participant_mismatch'), {
    error: 'participant_mismatch',
    status: 403,
  })
  assert.deepEqual(MISSING_UPLOAD_TOKEN, {
    error: 'missing_upload_token',
    status: 401,
  })
})

test('an unrecognised status is never treated as success', () => {
  for (const status of ['toString', 'OK', 'nope', 0, null, undefined, {}]) {
    assert.deepEqual(
      uploadTokenFailure(status),
      { error: 'invalid_upload_token', status: 401 },
      `status ${String(status)}`,
    )
  }
  // The remote status list is exactly the six documented strings.
  assert.deepEqual(Object.keys(UPLOAD_TOKEN_FAILURES).sort(), [
    'exhausted',
    'expired',
    'invalid',
    'participant_mismatch',
    'revoked',
  ])
})

test('no token helper echoes the token or logs anything', () => {
  const validatorSource = readFileSync(join(functionDir, 'validate.js'), 'utf8')
  assert.ok(
    !/console\./.test(validatorSource),
    'validate.js must not log at all, so no token can be logged by accident',
  )
  // Every mapping answer is a fixed code/status pair, never the token.
  for (const status of [...Object.keys(UPLOAD_TOKEN_FAILURES), 'ok', 'junk']) {
    const answer = uploadTokenFailure(status)
    assert.ok(
      !JSON.stringify(answer ?? {}).includes(VALID_TOKEN),
      `status ${status} must not echo the token`,
    )
  }
  // The shape check answers a boolean.
  assert.equal(typeof isValidUploadTokenShape(VALID_TOKEN), 'boolean')
})

test('the Edge Function hashes the token and never puts it in a body or row', () => {
  assert.ok(
    indexSource.includes('sha256Hex(uploadToken)'),
    'index.ts must hash the raw token before any database call',
  )
  // No log line carries the raw token.
  for (const match of indexSource.matchAll(/console\.\w+\(([\s\S]*?)\)\n/g)) {
    assert.ok(!match[1].includes('uploadToken'), match[0].slice(0, 60))
  }
  // Nor does any answer body or stored column.
  assert.ok(!/error: uploadToken[),]/.test(indexSource))
  assert.ok(!/token:\s*uploadToken[),]/.test(indexSource))
  assert.ok(!/payload:\s*uploadToken[),]/.test(indexSource))
})

test('the token migration is additive, locked down and lock-safe', () => {
  const tokenSql = readFileSync(
    join(functionDir, '../../migrations/202610260001_research_upload_tokens.sql'),
    'utf8',
  )
  // No destructive statement anywhere in a purely additive migration.
  assert.ok(!/drop\s+(table|column|constraint)/i.test(tokenSql), 'additive only')
  // Only a hash is stored: no plaintext column exists at all.
  assert.match(tokenSql, /token_hash text not null unique/)
  assert.ok(!/^\s*token text/m.test(tokenSql), 'never store the token itself')
  // RLS on both new tables, with no policy granted to any client role.
  assert.equal(tokenSql.match(/enable row level security/g)?.length, 2)
  assert.ok(!/create policy/i.test(tokenSql), 'no client policy may exist')
  // Atomic consumption: the row is locked, and the statuses are spelled out.
  assert.match(tokenSql, /for update/i)
  assert.match(tokenSql, /security definer/i)
  for (const status of [
    'ok',
    'invalid',
    'expired',
    'revoked',
    'exhausted',
    'participant_mismatch',
  ]) {
    assert.ok(tokenSql.includes(`'${status}'`), status)
  }
  // SECURITY DEFINER functions must not be reachable by a client role.
  for (const fn of [
    'consume_research_upload_token(text, text)',
    'research_ingest_rate_limited(text)',
    'refund_research_upload_token(text)',
  ]) {
    assert.ok(
      tokenSql.includes(
        `revoke all on function public.${fn}\n  from public, anon, authenticated;`,
      ),
      `${fn} must be revoked from every client role`,
    )
    assert.ok(
      tokenSql.includes(
        `grant execute on function public.${fn}\n  to service_role;`,
      ),
      `${fn} must be executable by service_role only`,
    )
  }
  // Every definer function pins an empty search_path; all names inside are
  // schema-qualified, so the path cannot be used to shadow one.
  assert.equal(tokenSql.match(/set search_path = ''/g)?.length, 3)
  assert.ok(
    !/set search_path = public/.test(tokenSql),
    'no definer function may keep a writable search_path',
  )
})

test('the rate-limit thresholds in SQL match the JS constants', () => {
  const tokenSql = readFileSync(
    join(functionDir, '../../migrations/202610260001_research_upload_tokens.sql'),
    'utf8',
  )
  assert.deepEqual([RATE_LIMIT_TOKEN_MAX, RATE_LIMIT_WINDOW_MINUTES], [10, 10])
  // The SQL is the enforcer; the constants above are the documentation the
  // function and the docs quote. A silent divergence would either throttle real
  // uploads or quietly disable the limit.
  assert.ok(
    tokenSql.includes(`interval '${RATE_LIMIT_WINDOW_MINUTES} minutes'`),
    'window must match RATE_LIMIT_WINDOW_MINUTES',
  )
  assert.ok(
    tokenSql.includes('select count(*) >= 10'),
    'per-token ceiling must match RATE_LIMIT_TOKEN_MAX',
  )
  // The per-participant branch was inert (`where participant_code = NULL` is
  // never true) and is gone: no documented control may fail to fire.
  assert.ok(
    !/count\(\*[^)]*participant_code/.test(tokenSql),
    'no per-participant window may remain',
  )
  assert.ok(
    !tokenSql.includes('>= 20'),
    'the removed participant ceiling must not linger',
  )
})

test('a replay refunds the use that consume already spent', () => {
  // consume must precede the idempotency probe (probing first would answer
  // whether a (participant_code, client_session_id) pair exists to any token
  // holder), so a retry of a stored session has to give the use back.
  const refundCall = indexSource.indexOf("'refund_research_upload_token'")
  const consumeCall = indexSource.indexOf("'consume_research_upload_token'")
  const firstProbeCall = indexSource.indexOf('await sessionExists(')
  const normalProbe = indexSource.indexOf('= await sessionExists(')
  assert.ok(refundCall > 0, 'index.ts must call the refund RPC')
  // Consume stays first: a probe before it would turn the answer into a
  // pair-existence oracle for any caller.
  assert.ok(
    consumeCall > 0 && firstProbeCall > consumeCall,
    'consume must precede every probe',
  )
  assert.ok(
    normalProbe > 0 && refundCall > normalProbe,
    'the refund belongs after the probe that finds the stored row',
  )
  assert.ok(
    refundCall < indexSource.lastIndexOf('duplicated: true'),
    'the refund must precede the duplicated answer',
  )
  // At the default max_uses = 1 there is no use left to refund, so that replay
  // is answered from a probe on the exhausted refusal instead.
  assert.match(
    indexSource,
    /tokenStatus === 'exhausted' &&\s*\(await sessionExists\(/,
    'an exhausted replay of a stored session must still answer 200 duplicated',
  )

  const tokenSql = readFileSync(
    join(functionDir, '../../migrations/202610260001_research_upload_tokens.sql'),
    'utf8',
  )
  assert.match(
    tokenSql,
    /function public\.refund_research_upload_token\(\s*p_token_hash text\s*\) returns void/,
  )
  assert.match(tokenSql, /set uses = uses - 1/)
  assert.match(tokenSql, /and uses > 0;/, 'the refund floors at 0')
  assert.match(tokenSql, /and revoked_at is null/, 'a revoked token is left alone')
})

test('a missing content-length is a 411, an over-large one a 413', () => {
  // Both gates bound the same body, but only one is a size problem: keeping them
  // apart is what keeps the app's "too large" sentence truthful.
  assert.match(indexSource, /return reject\('length_required', 411\)/)
  assert.match(indexSource, /return reject\('payload_too_large', 413\)/)
})

test('the ledger keeps only outcomes a real token can spend', () => {
  // A random hash never reaches the database, so recording those attempts would
  // grow the table for a window that can never trip.
  assert.match(
    indexSource,
    /if \(tokenStatus !== 'invalid'\) \{\s*await recordAttempt/,
  )
  // Position, not the absence of one known call: any `recordAttempt(` before
  // consume would answer whether a token is real to a caller who cannot spend
  // it, so a future pre-consume write has to fail here.
  const consumeCall = indexSource.indexOf("'consume_research_upload_token'")
  const firstLedgerWrite = indexSource.indexOf('await recordAttempt(')
  assert.ok(consumeCall > 0, 'index.ts must call the consume RPC')
  assert.ok(
    firstLedgerWrite > consumeCall,
    'no recordAttempt( call may precede the consume RPC',
  )
  // Retention needs an index it can use.
  const tokenSql = readFileSync(
    join(functionDir, '../../migrations/202610260001_research_upload_tokens.sql'),
    'utf8',
  )
  assert.match(
    tokenSql,
    /create index research_ingest_attempts_created_at_idx\s+on public\.research_ingest_attempts \(created_at\);/,
  )
  assert.match(tokenSql, /delete from public\.research_ingest_attempts/)
})
