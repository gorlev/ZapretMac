# Fix log

## Snapshots used the person's own accent color
Symptom: snapshot runs came out blue after the accent was set to Blue in the real app.
Cause: ThemeStore read and wrote `appearance.accent` in UserDefaults.standard even when APP_STORE pointed at a test store.
Fix: test, seed, and snapshot runs ignore the saved accent and never write it.
Rule: every preference read in a test run comes from a test suite or a default, never the person's real defaults.
