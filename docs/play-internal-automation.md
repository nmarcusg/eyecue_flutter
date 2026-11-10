# EyeCue Play internal testing automation

The Android cloud build can upload a production-signed **EyeCue** AAB to the
Play Console **internal** track. EyeCue Study and test-signed builds are never
uploaded. A successful upload requests an internal rollout (`completed`); Google
may still require review. This does not publish to the production track.

## One-time setup

1. Create EyeCue in Play Console and manually upload the first signed AAB.
   Complete the first internal release and any required Google review before
   relying on automatic rollouts. The Publishing API requires a previously
   uploaded artifact.
2. In Google Cloud, create or choose a project and enable the **Google Play
   Developer API**. Create a service account for this workflow.
3. In Play Console **Users and permissions**, invite the service-account email
   and grant access only to EyeCue. Grant **Release apps to testing tracks**;
   add other app-scoped permissions only if Play reports they are needed. Do not
   grant production-release or account-admin permissions for this workflow.
4. Create a JSON key for that service account and add its complete contents as
   the repository Actions secret `EYECUE_PLAY_SERVICE_ACCOUNT_JSON`. Do not
   commit, paste in chat, or share the JSON. Keep any downloaded copy secure;
   follow your organisation's credential and backup policy. Workload identity
   federation is preferable where configured, but this workflow uses a JSON key.
5. Keep the separate `EYECUE_KEYSTORE_*` and `EYECUE_KEY_*` signing secrets
   configured. Play API access does not sign the AAB.

Google setup: https://developers.google.com/android-publisher/getting_started
Google permissions: https://support.google.com/googleplay/android-developer/answer/9844686

## Running

In GitHub Actions, run **Android cloud build** on `main`, enable
`signed_release`, leave `study_build` off, and leave `upload_internal` enabled.
The upload happens only on a manually dispatched, signed public build. Pushes,
pull requests, and Study builds cannot trigger it. The signed artifacts are
saved to GitHub before the Play upload, so a Play failure leaves them available.
To produce a signed artifact without changing Play, uncheck `upload_internal`.

The default version code is the workflow run number. If you override it, use a
code greater than every previously uploaded version; Play rejects reused codes.
A retry of an already uploaded version may also be rejected. Verify the state in
Play Console before retrying. If Play Console was changed during an API edit,
retry after it finishes, because concurrent edits can invalidate each other.
A missing or malformed service-account secret fails the workflow before build.

The Play action is pinned to a full commit of `r0adkll/upload-google-play`
v1.1.5. The workflow writes the credential to a restricted temporary file and
removes it in an always-run cleanup step. Uploaded secrets are never printed.
