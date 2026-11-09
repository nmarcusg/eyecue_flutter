# User-selected log exports (EyeCue Study only)

JSON/CSV exports and the Logs & Reports screen are compiled into the Study
variant only. The public EyeCue build has no researcher controls or export UI.

From EyeCue Study version code 2, JSON and CSV export actions open Android's
Save as document picker. The user can choose a filename and any writable location
offered by an installed document provider: Downloads, supported removable storage
or a cloud provider such as Google Drive when installed and available. Android's
protected system/app-private folders are not generally offered by this picker.
No broad storage permission or Supabase token is needed for offline export.

In Logs & Reports:

- Save JSON export / Save CSV export exports the current operational buffer.
  This live buffer is capped; it is not a replacement for a recorded trial.
- Export trial exports the selected finished trial as JSON. Export CSV beside
  it exports the same frozen trial as CSV. All available trial rows are retained,
  including sessions above the current Supabase upload cap.
- The picker can be cancelled without affecting the saved trial. Success is
  reported only after the document provider stream is written, flushed and closed.
  A provider failure remains an error, not an internal-only "saved" notification.

An immutable export file is staged in a unique private cache directory and copied
on a single background worker after the user selects a destination. Data is not
sent as a large platform-channel message. Only that temporary directory is cleaned
up; internal draft/finished-trial storage is independent and remains intact.
A failed destination may contain a partial file; it is not automatically deleted,
because it could be an existing user document. A cloud provider may manage its
own later synchronization after acknowledging the write.

The study build pipeline supplies the recorded app version (for example,
`1.0.0-study+2`); previously recorded trial versions remain unchanged.
JSON stays telemetry schema4, with detector attribution and the frozen trial's
alert configuration. CSV includes the same available records and configuration.
No images, upload tokens, device identifiers or new research-data thinning are
introduced. Existing serialization/precision rules remain unchanged.

This does not import the private sessions from the original EyeCue installation,
and it does not change the 2,000,000-byte Supabase upload cap. The separate Study
package and its retained certificate are unchanged; code2 updates Study code1
while the original EyeCue can stay installed alongside it.
