# Fix log

## Snapshots used the person's own accent color
Symptom: snapshot runs came out blue after the accent was set to Blue in the real app.
Cause: ThemeStore read and wrote `appearance.accent` in UserDefaults.standard even when APP_STORE pointed at a test store.
Fix: test, seed, and snapshot runs ignore the saved accent and never write it.
Rule: every preference read in a test run comes from a test suite or a default, never the person's real defaults.

## The first site check after turning on could fail
Symptom: a site opened through tpws right after the switch turned on failed with CFNetwork error 310, now and then.
Cause: the engine marked tpws running 600 ms after launch or on its "Running as" line, before the port took connections.
Fix: the engine marks it running only once 127.0.0.1:<port> accepts a connection.
Rule: "ready" means the thing answers, never that time passed or a log line appeared.

## Self-tests hung with no output
Symptom: every self-test run sat idle and printed nothing; the app's main thread waited for events.
Cause: the self-test started from ContentView.task, which never runs when macOS opens no window (a locked screen does that).
Fix: AppDelegate starts the self-test at launch; it needs no window. Snapshots still need an unlocked screen.
Rule: test hooks that need no UI start from app launch, never from a view.
