# Release readiness report (L11)

Final statement for the `feat/play-store-readiness` programme: what was built,
what was measured, what was **not** verified, and one classification.

## 1. Identity

| Field | Value |
| --- | --- |
| Branch | `feat/play-store-readiness` |
| Worktree | `/home/nico/repos/eyecue_flutter-playstore` |
| HEAD at the start of this (resumed L10/L11) run | `423d97a1c1ce162a3646fef78ecea1d7ffe81b9f` |
| HEAD at the end of this run | `842d38b` (L10/L11 docs) + this report commit |
| Base commit | `adfbc5d` (`docs(status): retire obsolete XNNPACK items and dead links`) |
| History | additive only — no prior-item or published commit was rewritten, no force-push, nothing merged into `dev`/`main`; the L11 commit was amended twice before completion (§2.2), `a77024c` → `8c69a28` → `f1ff670` |
| Flutter | 3.44.2, stable channel |
| Artefact source | same worktree, no `--dart-define`, no keystore, no Play Console access |

## 2. Commit ledger (L0–L11)

| Item | Commits | Reviewer verdict |
| --- | --- | --- |
| L0 baseline ledger | `a8e0571`, corrections `e03bc36`, `d3a987a` | `a8e0571` PASS_WITH_NOTES (7 findings, applied) |
| L1a vendored plugin + reviewer notes | `d5390d4`, `fcf4cd0` | PASS_WITH_NOTES |
| L1 native shared-frame depth transport | `63131d5`, docs `3f81cc3`, remediation `15fcf39`, `79eb9c0`, docs `2540470`, `614a6ca` | round 1 CHANGES_REQUIRED (4 major / 5 minor / 2 nit) → round 2 CHANGES_REQUIRED (8 of 9 fixed) → PASS_WITH_NOTES |
| L2 compact depth payload + heatmap gating | `ca35e75`, docs `b523f5e`, housekeeping `8b8e1be` | PASS_WITH_NOTES |
| L3 MDE enable/disable lifecycle | `82dd272`, remediation `f0b659b` | round 1 CHANGES_REQUIRED → PASS_WITH_NOTES |
| L4 accelerator policy + timings + dispose-during-load | `99a40d9`, `fca8ddd`, follow-ups `8f2ab0a` | PASS_WITH_NOTES (backlog review: the `99a40d9` dispose-during-load fix and the `fca8ddd` accelerator/timings work were read at HEAD); the accepted L4 follow-up evidence is carried in the L5 row |
| L5 telemetry perf fields + schema v4 | `3d4d516`, `1f3d279`, `f179e24`, follow-ups `8f2ab0a`, docs `9868c48` | CHANGES_REQUIRED → CHANGES_REQUIRED → PASS_WITH_NOTES; docs follow-up not separately reviewed |
| L6 Supabase idempotency + schema gating | `b0c09c4`, `ff567d8`, `efbcc6e` | CHANGES_REQUIRED → PASS_WITH_NOTES (backlog review of `ff567d8`; its guarded constraint drop was hardened to an unguarded one in `efbcc6e`) |
| L7 dashboard contract compatibility | `ebfcc6e`, `efb3fb5` (Flutter) + `21a3263`, `1581498` (separate dashboard repo) | CHANGES_REQUIRED (11 findings) → PASS_WITH_NOTES |
| L8 R8/WorkManager/Room release verification | `2d0d0cd`, `870c24e` | CHANGES_REQUIRED (2 medium, 5 low) |
| L9 Play Store configuration | `2d0d0cd`, `870c24e` | CHANGES_REQUIRED (same round) |
| L10 attribution + naming | `423d97a` | PASS_WITH_NOTES (backlog review — the L8/L9 round-1 findings are applied) |
| **L10 permission removal + licence/notices/privacy/checklist** | **`8766586`, `842d38b`** | **PASS_WITH_NOTES for `8766586`; CHANGES_REQUIRED (LOW, docs only) for `842d38b` — backlog review** |
| **L11 final readiness report** | **`f1ff670`** | **PASS_WITH_NOTES (backlog review)** |
| **B secure telemetry transport** | **the commit carrying this row** | **implementer summary — no reviewer verdict yet (no self-approval)** |
| **F primary gesture defects: commit-on-release, whole-main-area Detection region, second-pointer invalidation** | **`6a0fe65`** | **implementer summary — no reviewer verdict yet (no self-approval)** |

### 2.1 Source histories incorporated

Each was verified as an ancestor of `HEAD` in the L0 row:

| Source | Commit |
| --- | --- |
| `codex/mde-integration` | `85b48ae` |
| `feat/supabase-research-telemetry` | `12f568b` |
| `feat/waste-reduction` (via merge) | `c325b11` |
| `dev` | `94f74d8` |

The MDE and telemetry histories are joined by merge commit `2722a7b`.

### 2.2 Every commit on the branch, with its reviewer verdict

| Commit | Verdict |
| --- | --- |
| `a8e0571` | PASS_WITH_NOTES |
| `e03bc36` | no separate reviewer row (L0 corrections, applied under `a8e0571`) |
| `d3a987a` | no separate reviewer row (L0 correction docs) |
| `d5390d4` | PASS_WITH_NOTES |
| `fcf4cd0` | CHANGES_REQUIRED |
| `63131d5` | CHANGES_REQUIRED |
| `3f81cc3` | CHANGES_REQUIRED |
| `15fcf39` | CHANGES_REQUIRED (round 2) |
| `2540470` | PASS_WITH_NOTES |
| `79eb9c0` | PASS_WITH_NOTES |
| `614a6ca` | PASS_WITH_NOTES |
| `ca35e75` | PASS_WITH_NOTES |
| `b523f5e` | no separate reviewer row (L2 evidence docs) |
| `8b8e1be` | CHANGES_REQUIRED (round 1, with `82dd272`); the commit's own content is PASS_WITH_NOTES (backlog review) |
| `82dd272` | CHANGES_REQUIRED |
| `f0b659b` | PASS_WITH_NOTES |
| `99a40d9` | PASS_WITH_NOTES (backlog review) |
| `fca8ddd` | PASS_WITH_NOTES (backlog review, with `99a40d9`) |
| `8f2ab0a` | CHANGES_REQUIRED (as part of the L5 round) |
| `3d4d516` | CHANGES_REQUIRED |
| `1f3d279` | CHANGES_REQUIRED |
| `f179e24` | PASS_WITH_NOTES |
| `9868c48` | no separate reviewer row (L5 evidence docs) |
| `b0c09c4` | CHANGES_REQUIRED |
| `ff567d8` | PASS_WITH_NOTES (backlog review) |
| `efbcc6e` | CHANGES_REQUIRED → PASS_WITH_NOTES (with `efb3fb5`) |
| `efb3fb5` | PASS_WITH_NOTES |
| `2d0d0cd` | CHANGES_REQUIRED (L8/L9 round 1) |
| `870c24e` | CHANGES_REQUIRED (L8/L9 round 1) |
| `423d97a` | PASS_WITH_NOTES (backlog review) |
| `8766586` | PASS_WITH_NOTES (backlog review) |
| `842d38b` | CHANGES_REQUIRED (LOW, docs only) |
| this commit (`f1ff670`) | PASS_WITH_NOTES (backlog review) |
| `d28baa4` | PASS_WITH_NOTES (backlog review) |
| the commit carrying this row | no separate reviewer row (B secure telemetry transport; the implementer summary in §2 stands until it is reviewed) |
| the commit carrying the G row | no separate reviewer row (G accessible safety disclosure; the implementer summary in the G row of [`play-store-readiness.md`](play-store-readiness.md) §5 stands until it is reviewed) |

Reviewer-log note: `f1ff670` (this commit) is an amendment of `8c69a28`, which was
itself an amendment of `a77024c`. All three were local and unpushed, and both
amendments happened before this commit was handed to review. No L0–L10 commit and no
published commit was rewritten: every SHA in §2.1 and §2.2 belonging to an earlier
item is unchanged.

The backlog pass that closed the `pending review` rows re-measured every number in §3 and §4 and recorded its verdicts in [`play-store-readiness.md`](play-store-readiness.md) §9. It also added the two commits this table originally omitted (`d3a987a`, `d28baa4`), so §2.2 now covers every commit on the branch.

## 3. Verification

All commands run in `/home/nico/repos/eyecue_flutter-playstore` on 2026-10-25.

| Check | Command | Result |
| --- | --- | --- |
| Formatting | `dart format --output=none --set-exit-if-changed lib test` | **PASS** — `Formatted 104 files (0 changed)`, exit 0 |
| Static analysis | `flutter analyze` | **PASS** — `4 issues found`: **0 errors, 2 warnings, 2 infos**. Warnings: `unused_field` (`_clock`) at `lib/services/alert_policy.dart:124` and `invalid_return_type_for_catch_error` at `lib/services/tts_service.dart:671`. Infos: `unnecessary_import` at `test/services/assistive_detection_controller_test.dart:9` and `test/services/tts_service_test.dart:11`. Both warnings are **pre-existing**: neither file is touched by any commit in this programme (`git diff adfbc5d..HEAD -- lib/services/alert_policy.dart lib/services/tts_service.dart` is empty), so they were left alone rather than silenced. |
| Unit/widget suite | `flutter test` | **589 passed, 1 failed** — `test/services/tts_service_test.dart: alert lifecycle telemetry a partial signal pair records a reconciliation timeout`, the known pre-existing TTS failure recorded since L0; not introduced here and not fixed here |
| Ingest validator | `node --test supabase/functions/ingest-telemetry/validate.test.mjs` | **PASS** — `1..41`, 41 pass, 0 fail |
| Dashboard contract | `node --test` in the separate dashboard repo | 21/21 as recorded in the L7 row; **not re-run in this workspace** (different repository, not modified by L10/L11) |
| Whitespace | `git diff --check` | **PASS** — exit 0, no output |
| Conflict markers | `grep -rn` for the seven-`<` / seven-`>` merge-marker runs over `--include=*.dart --include=*.kt --include=*.ts --include=*.js --include=*.md` | **PASS** — 0 hits outside this sentence's own wording (the pattern is described, not quoted, so the scan stays clean) |
| Secret scan (decompressed AAB) | `unzip -p <aab> '*' \| grep -ac 'service_role\|SUPABASE_SECRET\|BEGIN PRIVATE KEY\|eyJhbGciOi'` | **PASS** — 0 hits |
| Test-signed marking | `cd android && ./gradlew markTestSignedApk` run against the already-renamed artefact set | **FAILS CLOSED as intended** — `Execution failed for task ':app:markTestSignedApk'` → `EyeCue: …/flutter-apk/app-release.apk is missing, so it cannot be marked test-signed`; exit non-zero, nothing renamed, both artefact digests unchanged. `--dry-run` configures the script cleanly, so the task is still wired |
| Worktree state | `git status --porcelain` | clean after the commit series |

## 4. Artefacts

Built from the L10 tree; both are **debug-signed test artefacts** (`-testsigned`)
because no keystore exists on the host.

```sh
flutter build appbundle --release              # Gradle bundleRelease 27.6 s (incremental)
flutter build apk --release                    # Gradle assembleRelease  9.9 s (incremental)
(cd android && ./gradlew markTestSignedApk)    # marks the APK (§3 of release-procedure.md)
```

| Artefact | Path | Size | sha256 |
| --- | --- | --- | --- |
| AAB | `build/app/outputs/bundle/release/app-release-testsigned.aab` | 78 607 313 B | `6d566ed416f7aa7fc2452f47b43fe80a872576bd8639ef2e67b9772e23ba22c6` |
| APK (inspection only) | `build/app/outputs/flutter-apk/app-release-testsigned.apk` | 91 191 189 B | `3c932ed4c2ef3b3057cf0653577a246128769145b08236caa507546a7c3d2974` |

Signing status: `apksigner verify --print-certs` →
`Signer #1 certificate DN: C=US, O=Android, CN=Android Debug`, certificate SHA-256
`868520e241cd5ddaeae5df20322077885bb87b2f7207919934e75a7dc07e2bea`. Play refuses a
debug-signed bundle. Both earlier digests (`feaab199…`, `99ac0da9…` at `870c24e`)
are superseded by these and are no longer valid for any file in the tree.

These two digests are **reproducible on this host for this tree**: the final
verification pass re-ran both builds (and re-marked the APK) and both files came
back byte-identical, with the same sha256 values and the same 8-permission
manifest.

## 5. Bundle inspection

`aapt2 dump badging` on the APK:

```
package: name='app.eyecue.mobile' versionCode='1' versionName='1.0.0-testsigned'
         compileSdkVersion='36' platformBuildVersionCode='36'
minSdkVersion:'24'   targetSdkVersion:'36'
application-label:'EyeCue'
launchable-activity: name='app.eyecue.mobile.MainActivity'
```

Effective permissions — **8**, down from 11:

```
CAMERA, INTERNET, FOREGROUND_SERVICE, FOREGROUND_SERVICE_DATA_SYNC,
WAKE_LOCK, ACCESS_NETWORK_STATE, RECEIVE_BOOT_COMPLETED,
app.eyecue.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
```

`RECORD_AUDIO`, `WRITE_EXTERNAL_STORAGE` and the merger-implied
`READ_EXTERNAL_STORAGE` are gone; the injectors, the removal rules, the proof and
the residual risk are in [`release-procedure.md`](release-procedure.md) §6.2.

AAB contents: `base` module + 23 `BUNDLE-METADATA` debug-symbol entries, 229 files.
Model assets are exactly:

| Asset | Size |
| --- | --- |
| `base/assets/flutter_assets/assets/yolo26n-depth_w8a32.tflite` | 5 474 749 B |
| `base/assets/flutter_assets/assets/yolov8n_int8_new_metadata.tflite` | 3 483 114 B |

together with `labels.txt`, `logo.png` and four IBM Plex `.ttf` files. The
tooling-only models are absent; no `docs/`, `tool/`, `test/` or `design-reference/`
entry is bundled. Three ABIs (`arm64-v8a`, `armeabi-v7a`, `x86_64`), no `x86`.

## 6. R8 / WorkManager — class stripping closed by DEX evidence, startup NOT verified

`unzip -p <apk> 'classes*.dex' | strings | grep -c`: `androidx/work/impl/WorkDatabase`
→ 2, `androidx/work/impl/WorkDatabase_Impl` → 1. The single `classes.dex` defines
`androidx.work.impl.WorkDatabase_Impl` with a public no-arg constructor, so the
reflective lookup that once failed should find its target.

**Verdict: class-stripping is closed by evidence. Installed startup at app launch is
NOT VERIFIED** — only a running app exercises that construction.

## 7. Device gate

No Android device and no AVD exist on this host, and creating one is not permitted
(disk). `CONFIRMED-ON-DEVICE` does not exist anywhere in this programme. The exact
commands to close it are in [`benchmark-procedure.md`](benchmark-procedure.md) §5.1.
This is why §6 and the camera/TTS/model-load claims remain proxies.

## 8. Supabase local-stack gate

**BLOCKED-EXTERNAL — disk capacity.** No PostgreSQL server, no Supabase CLI and no
cached Supabase images on this host; nothing was installed. The Edge Function and
migrations are verified only by the 41-case validator and by reading the SQL. The
deployed-project behaviour (RLS, idempotency, RPC) is unverified.

## 9. Dashboard compatibility

The research dashboard is a **separate repository**
(`/home/nico/Documents/ChatGPT/Eyecue/research-dashboard-cadence`, branch
`feat/dashboard-cadence`), verified with `node --test` only (21/21 at L7) and **not
deployed**. The Flutter side keeps the schema-4 contract; L10/L11 changed no payload
field, so dashboard compatibility is unchanged by this run.

## 10. Licensing and source compliance

| Item | State |
| --- | --- |
| Application licence | **`AGPL-3.0-only`** (D2 decided) — canonical AGPL v3 in [`LICENSE`](../LICENSE), byte-identical to the vendored plugin's copy (sha256 `4df3c306dddaaf4baffdff5ca820cc679ac8cd6dc263c6a74517783e42fa7a3b`, 660 lines) |
| Vendored plugin (AGPL-3.0) | licence text preserved verbatim; eight native deviations plus four Dart-surface files recorded in `plugins/ultralytics_yolo/VENDORED.md` and [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §2.1 |
| Bundled models | both AGPL-3.0 (Ultralytics); provenance, sizes and digests in the notices §3 |
| Pub / native inventories | [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §4–§5 |
| AGPL source-distribution procedure | [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §7 (tag ↔ `versionCode`, in-repo sources, archive step) and [`release-procedure.md`](release-procedure.md) §7 (what to publish, `-testsigned` never tagged) |
| Legal review | **NOT PERFORMED** — obligations identified (R1–R7 in the notices §6), not reviewed by counsel; nothing here claims AGPL compliance is verified |

## 11. Remaining owner actions

1. `applicationId` (D1) is **decided** — `app.eyecue.mobile`, owner-approved and
   final; it must not change (irreversible per listing).
2. Provide the upload keystore / `EYECUE_KEYSTORE_*` and enrol Play App Signing.
3. Licence (D2) is **decided** (`AGPL-3.0-only`); what remains is the qualified legal
   review of R1–R7 in the notices §6 and publishing the corresponding source per
   release ([`release-procedure.md`](release-procedure.md) §7).
4. Answer the Data Safety form (D3) — items P1–P5 in
   [`privacy-and-data-safety.md`](privacy-and-data-safety.md) §8.1: P3 (`https`
   enforcement) is **resolved in code**; P1 retention, P2 participant-code
   interpretation, P4 processor-versus-third-party and P5 privacy-policy URL remain
   owner decisions.
5. Publish the privacy policy and fill the store listing
   ([`play-store-checklist.md`](play-store-checklist.md) §1, §6–§10).
6. Run the device gate (install, launch, camera path, TTS, model load).
7. Stand up the Supabase project (or a local stack on a host with disk) and re-run
   the ingestion tests against it.
8. Deploy the research dashboard if researchers are to use it.

## 12. Known risks

| # | Risk |
| --- | --- |
| 1 | Installed startup is unverified; the R8 result is DEX evidence, not a launch |
| 2 | Permissions were removed by manifest rule only — a future camerax upgrade could reintroduce another permission, and no device test checks this |
| 3 | Removing `RECORD_AUDIO`/storage permissions would break camerax video-with-audio and shared-storage capture paths (unused today) |
| 4 | Every artefact is debug-signed; Play will refuse it |
| 5 | AGPL-3.0 obligations — for the app's own code, the vendored plugin and the models — are unanalysed by counsel |
| 6 | Data Safety answers cannot all be given truthfully yet (no retention policy, no deletion process). The former third clause — `https` not enforced — is closed: the client validates the ingest endpoint and refuses any non-`https` scheme (see the B row in [`play-store-readiness.md`](play-store-readiness.md) §5) |
| 7 | `flutter test` carries one known failing TTS test; a real regression there would not be distinguishable from it |
| 8 | Dashboard contract verified only in the separate repository, not deployed |
| 9 | `applicationId` is the owner-approved final `app.eyecue.mobile`; `auditor.md`, `chat_spec.md` and the dated audit documents still quote the historical `com.example.eyecue_flutter` (time-stamped snapshots, deliberately not rewritten) |
| 10 | The APK `-testsigned` name depends on the manual `markTestSignedApk` task: `flutter build apk --release` alone still yields a plain-named, debug-signed `app-release.apk`. The AAB, which is what Play consumes, is renamed automatically by `bundleRelease` |
| 11 | The marking task now fails closed (§3), but that only catches a moved artefact at task-run time — a renamed *directory* is not detected at configuration time; a second `markTestSignedApk` run against an already-marked set also fails, because the task declares no outputs |
| 12 | The AAB is discovered by globbing the release directory with a "first `.aab` wins" fallback, so a stale `-testsigned.aab` sitting beside a fresh plain one would be the file reported |
| 13 | The two analyzer warnings are now described accurately (§3), but they are permanent fixtures of the "4 issues" count: a genuinely new warning is indistinguishable from them, so they must be fixed before that count is used as a regression gate |
| 14 | Telemetry ingest is authenticated by the publishable key alone, and that key ships inside the APK: any holder of a build can insert sessions, and the `consent` field is self-asserted. No token, attestation or rate limit exists, so the study table is an open write target until the ingestion threat model lands |

## 13. Rollback

The branch is additive on `adfbc5d`; no prior-item or published commit was rewritten
(the L11 commit was amended twice locally before completion, §2.2).

```sh
# discard the whole programme
git worktree remove /home/nico/repos/eyecue_flutter-playstore
git branch -D feat/play-store-readiness
```

To drop only the L10/L11 work, `git revert --no-commit 842d38b 8766586` followed by
a single revert commit restores the pre-L10 tree (undoes the manifest rules, the
Gradle naming change, the new docs and this report) without touching L0–L9.
Blast radius (`CONFIRMED-BY-INSPECTION`): no protected branch modified, no prior-item
or published commit rewritten, no stash created or dropped, no external system
(Supabase project, Play Console, signing infrastructure) touched. Artefacts under
`build/` are regenerated, not tracked.

## 14. Safety confirmation

* No push, no deploy, no Play Console interaction, no keystore created, no rewrite of
  any prior-item or published commit (the L11 commit was amended twice locally before
  completion, §2.2), no new dependency.
* Nothing inside this worktree was modified except the on-disk release artefacts,
  which the build regenerates in place. One exception is **UNVERIFIABLE**: the
  `/tmp/eyecue_base` scratch worktree (`94f74d8`, `dev`) no longer exists on disk and
  nothing was recorded about it before removal, so no claim is made about what was
  modified under that path. `git worktree list` reports it as `prunable`, and
  `git worktree prune --dry-run` would drop its record.
* The pre-existing `.aab`/`.apk` were replaced by a rebuild from the L10 tree; the
  old digests are recorded as superseded (§4).
* No secret, token or keystore path was written into the tree (secret scan: 0 hits).
* The user-facing safety wording now has exactly one source:
  [`lib/widgets/safety_disclosure.dart`](../lib/widgets/safety_disclosure.dart),
  rendered by the permanent Help section and by the first-use acknowledgement.
  The store-listing safety/accessibility statement (item K) **must mirror this
  wording**; no second in-app notice exists, and none is planned.

## 15. Classification

**`CODE_READY_WITH_EXTERNAL_GATES`**

The release engineering work is complete and measured: the tree formats, analyses
with 0 errors and 2 pre-existing warnings (§3), passes 589 of 590 tests (the single
failure is the known pre-existing TTS test), builds both release artefacts
reproducibly enough to inspect, and now declares eight permissions with the three
unused ones removed and
proved absent by `aapt2`. Everything that remains cannot be produced from inside
this repository: installed startup is unverified because no device exists, the
artefacts are debug-signed because no keystore exists, the `applicationId` is decided
(`app.eyecue.mobile`) and irreversible per listing, the Data Safety answers cannot be
given truthfully until retention and deletion are decided (`https` enforcement no
longer blocks them — it is enforced in code), and the AGPL-3.0 obligations on the
application itself, the vendored plugin and the bundled models have had no legal
review. Those are owner gates, not engineering defects — but they are gates.

**`READY_FOR_PLAY_STORE_SUBMISSION` is not available for this tree.** The app cannot
be submitted today: the artefact Play would receive is debug-signed and would be
rejected, startup has never run on a device, the privacy and Data Safety positions are
undecided, and the AGPL-3.0 obligations the app now inherits have had no legal review.
None of that is softened by the green checks in §3.
