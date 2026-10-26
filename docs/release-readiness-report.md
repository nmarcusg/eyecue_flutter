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
| `3a41366` | PASS_WITH_NOTES (I — Detection gesture region; verdict in [`play-store-readiness.md`](play-store-readiness.md) §9) |
| `a5ec498` | CHANGES_REQUIRED (J — the launch policy ran behind the unacknowledged disclosure) → remediated in `3eafed0`; no reviewer row for the remediation yet |
| `5ad07bf`, `fc2e948`, `5c78769` | PASS (K — application ID, licence, generated icons) |
| `30d340f` | PASS_WITH_NOTES (K — store material documents; the notes are the reconciliation in the docs commit after `3eafed0`) |
| `3eafed0` | no separate reviewer row yet (remediation of the `a5ec498` finding, §16.1) — review is the next stage, no self-approval |
| the docs commit after `3eafed0` | no separate reviewer row yet (document reconciliation of items 4–9 of the final remediation pass, §16) |

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

These two digests were **reproducible on this host for that tree**: the final
verification pass re-ran both builds (and re-marked the APK) and both files came
back byte-identical, with the same sha256 values and the same 8-permission
manifest.

**Both are now superseded** — the safety fix `3eafed0` and (for the earlier pair)
the generated icons in `5c78769` changed the build input. The current artefacts, their
digests, build times and 16 KB alignment evidence are in §16.4–§16.5.

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
| 7 | ~~`flutter test` carries one known failing TTS test~~ — **closed**: `8595c47` aligned the test with the caller-future contract, and the final pass ran that file 10 consecutive times green (§16.3) |
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
with **0 issues** and passes **653 of 653** tests (§16.3 — the §3 numbers are the
L10/L11 snapshot, superseded by the final pass), builds both release artefacts
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

## 16. Final remediation pass (2026-10-26)

Recorded after the review round that returned `a5ec498` as CHANGES_REQUIRED and
after the I/J/K store-material review. The only code commit in this pass is
`3eafed0`; the documentation commits that follow it change no build input.

### 16.1 The defect that was fixed

`_applyLaunchPolicy()` in [`../lib/navigation/app_shell.dart`](../lib/navigation/app_shell.dart:186)
ran in `initState`, before the first-use disclosure was scheduled. On a fresh install
`autoStartDetection` defaults to `true`, so the launch start intent, the
camera-permission prompt, a medium haptic and the "Detection started" speech all fired
**behind** the unacknowledged modal — over the announcement the user was being asked to
read, and before any consent to run the camera.

The policy is now applied only when `safetyAcknowledged` is true: from `initState`
when it was already persisted, otherwise from `onAcknowledge` after the acknowledgement
is recorded. The new case `withholds the launch policy until the acknowledgement`
drives a fresh `SettingsService` over the **real** pages (no `pagesOverride`): while the
modal is up `pendingStartIntent` is null, the coordinator is `idle` and no haptic is
emitted; after "I understand" exactly one `launch` intent exists and
`EngineDetectionScreen` is cached offstage behind Home. The pre-fix build fails its
first assertion. The shared suite `setUp` still pre-acknowledges, so the navigation
cases keep one modal-free path.

Also in `3eafed0`: the two stale "state-panel area" comments now state that the surface
wraps the live viewport only (non-live panels and the depth notice are outside);
[`../lib/widgets/gesture_surface.dart`](../lib/widgets/gesture_surface.dart:28) carries a
`shortcut:` note that any interactive child added inside the wrapped subtree
re-introduces tap→pause classification, backed by a new case asserting the live subtree
holds no button or tappable; and the second-pointer case in
[`../test/services/gesture_controller_test.dart`](../test/services/gesture_controller_test.dart:185)
now moves the second pointer in *after* a committing move, so it fails against the
pre-fix controller instead of passing by accident.

### 16.2 Machine constraints this pass ran under

7.6 GB RAM (≈2.4 GB available, 11 GB swap) and 6.1 GB free of 91 GB on `/home`
(94 % used). Every Flutter test run used `flutter test --concurrency=2`; a higher
concurrency has OOM-killed this host. **No Gradle setting was changed**: the tracked
[`../android/gradle.properties`](../android/gradle.properties) keeps
`-Xmx8G`, both release builds completed with it, and the file is unmodified in the
tree — no local lowering and no restore was required.

### 16.3 Re-measured verification

| Check | Result |
| --- | --- |
| `flutter analyze` | **0 issues** (the 4 in §3 were fixed in `c07ea1e`/`8595c47`) |
| `dart format --output=none --set-exit-if-changed lib test` | 106 files, 0 changed |
| `flutter test --concurrency=2` | **653 passed, 0 failed** |
| `test/services/tts_service_test.dart`, 10 consecutive `--concurrency=1` runs | 10/10 green, no flake — the known failure recorded in §3 is closed |
| `node --test supabase/functions/ingest-telemetry/validate.test.mjs` | 55/55 |
| `git diff --check` | clean |

§3 is the L10/L11 snapshot and is left as history; the numbers above are the final
state.

### 16.4 Artefacts rebuilt at `3eafed0`

```sh
flutter build appbundle --release              # Gradle bundleRelease 219.3 s (221.7 s wall)
flutter build apk --release                    # Gradle assembleRelease  46.7 s ( 49.2 s wall)
(cd android && ./gradlew markTestSignedApk)    # marks the APK (§3 of release-procedure.md)
```

| Artefact | Path | Size | sha256 |
| --- | --- | --- | --- |
| AAB | `build/app/outputs/bundle/release/app-release-testsigned.aab` | 78 762 272 B | `6425a1e5f6420935b32f547a965e5be5bc11b80dcdc9d0ef9a04caf8d0c0ec56` |
| APK (inspection only) | `build/app/outputs/flutter-apk/app-release-testsigned.apk` | 91 345 913 B | `4df0f2c8a3b7767c5579dc059bd316d8903f9aab14b88afbe7a73bc5d526a573` |

Re-running both builds in the same tree returned the same two digests, but that run
was fully incremental (15.1 s / 8.3 s Gradle) and repackaged nothing, so it shows the
tree still matches the packaged artefacts — **not** byte-level determinism across a
cold rebuild. §6.7 of [`release-procedure.md`](release-procedure.md) states the same
limit.

Superseded (kept as history, valid for no file in the tree): AAB
`6d566ed416f7aa7fc2452f47b43fe80a872576bd8639ef2e67b9772e23ba22c6` (78 607 313 B) and
APK `3c932ed4c2ef3b3057cf0653577a246128769145b08236caa507546a7c3d2974` (91 191 189 B).
They were built before `5c78769` (generated icons) and `3eafed0`, which is also why
this rebuild is ≈155 KB larger per artefact.

### 16.5 16 KB page-size alignment (`targetSdk 36`)

`zipalign -c -P 16 4 build/app/outputs/flutter-apk/app-release-testsigned.apk` →
exit 0 (`16KB-ALIGNED-OK`). Per-library `LOAD` segment alignment from
`readelf -lW` over the APK's libraries (the AAB carries byte-identical copies —
md5-compared for all 29 files):

| ABI | Libraries | `LOAD` align | Verdict |
| --- | --- | --- | --- |
| arm64-v8a | `libapp.so`, `libflutter.so` | `0x10000` | 16 KB aligned (64 KB, a multiple of 16 KB) |
| arm64-v8a | `libc++_shared`, `libdartjni`, `libdatastore_shared_counter`, `libimage_processing_util_jni`, `libLiteRt`, `libLiteRtClGlAccelerator`, `libsurface_util_jni`, `libultralytics` | `0x4000` | 16 KB aligned |
| x86_64 | `libapp.so`, `libflutter.so` | `0x10000` | 16 KB aligned |
| x86_64 | the other eight | `0x4000` | 16 KB aligned |
| armeabi-v7a | `libapp`, `libdartjni`, `libdatastore_shared_counter`, `libimage_processing_util_jni`, `libLiteRt`, `libsurface_util_jni`, `libflutter` | `0x4000` / `0x10000` | not applicable (32-bit ABI) |
| armeabi-v7a | **`libc++_shared.so`, `libultralytics.so`** | `0x1000` | **4 KB — the only two libraries not 16 KB aligned** |

**Every 64-bit library (arm64-v8a and x86_64) is 16 KB aligned**, which is what the
Android 15+ 16 KB page-size requirement covers, and the packaged APK passes
`zipalign -c -P 16`. The two 4 KB objects are `armeabi-v7a` (32-bit) only; 16 KB-page
devices run the 64-bit split, so this is not a blocker. It is stated plainly rather
than glossed: if `armeabi-v7a` were ever in scope for 16 KB, those two libraries would
need to be rebuilt with that alignment.

### 16.6 Bundle inspection at the new HEAD

| Item | Observed |
| --- | --- |
| `applicationId` | `app.eyecue.mobile` |
| Version | `versionCode='1'`, `versionName='1.0.0-testsigned'`; `minSdkVersion='24'`, `targetSdkVersion='36'`, `compileSdkVersion='36'` |
| Permissions | **8** — `CAMERA`, `INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED`, `app.eyecue.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (same set as L10; `RECORD_AUDIO`/`WRITE_EXTERNAL_STORAGE`/`READ_EXTERNAL_STORAGE` absent) |
| Icons | manifest `android:icon` → `mipmap/ic_launcher`, `android:roundIcon` → `mipmap/ic_launcher_round`; `ic_launcher`, `ic_launcher_foreground`, `ic_launcher_monochrome`, `ic_launcher_round` each at mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi; adaptive XML present for both `ic_launcher` and `ic_launcher_round` (`anydpi-v26`) with `background`/`foreground`/`monochrome` |
| Model assets | exactly `yolo26n-depth_w8a32.tflite` (5 474 749 B) and `yolov8n_int8_new_metadata.tflite` (3 483 114 B); `yolov8n.tflite`, `yolov8n_int8.tflite`, `yolov8n_int8_new.tflite` absent |
| ABIs / native libs | `arm64-v8a`, `armeabi-v7a`, `x86_64` (no `x86`), 29 libraries; `libLiteRtClGlAccelerator.so` only on the two 64-bit ABIs |
| Unwanted assets | no `docs/`, `tool/`, `test/` or `design-reference/` entry under `flutter_assets` (scan: 0 hits) |
| R8 | enabled — `isMinifyEnabled = true` + `isShrinkResources = true`, `proguard-android-optimize.txt` + `proguard-rules.pro`; `BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map` (28 876 614 B) is bundled and `build/app/outputs/mapping/release/{mapping,usage,seeds}.txt` were written |
| WorkManager/Room | `apkanalyzer dex packages --defined-only` still reports `C d 33 33 2268 androidx.work.impl.WorkDatabase_Impl` — the class is **defined**, with 33 methods |
| Secret scan (decompressed) | `service_role` / `SUPABASE_SECRET` / `BEGIN PRIVATE KEY` / `eyJhbGciOi`: **0 hits** in the AAB and 0 in the APK |

### 16.7 Still not verified

* **Installed startup: `NOT VERIFIED` — device gate.** No device or AVD on this host;
  the DEX evidence above is not a launch.
* Both artefacts remain **debug-signed test artefacts** (`-testsigned`) — no keystore.
* Data Safety (D3) is undecided; the legal review R1–R7 remains open; the privacy
  policy URL does not exist.
* The Supabase migration and ingest function have never been executed; the research
  dashboard is a separate repository and is not deployed.
* TalkBack read-through of the safety disclosure, and the device feel of the gesture
  and start-up paths, are owed.
