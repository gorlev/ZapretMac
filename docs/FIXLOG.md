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

## A force-quit left tpws holding the port
Symptom: after ZapretMac was killed, the next start failed with "bind: Address already in use".
Cause: tpws is a child process and keeps running when the app is killed.
Fix: tpws writes a pid file; before starting, the engine stops a leftover process that is our tpws binary.
Rule: every helper process the app starts can be found and stopped by the next launch.

## Transparent mode would have turned itself off at once (caught before shipping)
Symptom: in review, the one-shot XPC call that started tpws closed its connection right after the reply.
Cause: the helper treats a dropped connection as the app being gone and cleans up (S-082), so it would undo the start immediately.
Fix: the connection that starts tpws stays open until stop; on a restart the old one closes only after the new start succeeded.
Rule: when a peer cleans up on disconnect, the connection's lifetime is the feature's lifetime.

## Transparent mode verified on the real Mac (2026-11-25)
Not a bug: the first end-to-end run. With the helper approved, turning the mode on ran tpws as root (`--user=root --port=1088`), released the system proxy, and a `curl --noproxy '*' https://example.com` was redirected by pf to 127.0.0.1:1088 (netstat showed the Mac's LAN address connected to tpws's port) and got 200. Turning it off stopped the root tpws, brought back the user's SOCKS tpws and PAC proxy, and no further connections were redirected.
Note: the running helper predates S-105, so it still had no IPv6 bind; macOS restarts it with the new binary after the app is reinstalled and the helper re-registered or the Mac restarts.
Rule: a feature that changes the system is done only after one real run on a real Mac, with the before-state recorded and restored.
