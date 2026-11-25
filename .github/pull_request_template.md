## What a user can now do

<!-- One or two sentences. The title should say it too, e.g. "Import site lists from a URL". -->

## How it works

<!-- The approach, and anything a reviewer should look at closely. -->

## Checks

- [ ] `./build.sh` builds with no warnings
- [ ] Unit tests pass (`swift test --scratch-path ~/Library/Developer/ZapretMac/test-build`)
- [ ] `tools/selftest.sh` prints `SELFTEST PASS`
- [ ] `tools/grid-lint.sh` prints `PASS`
- [ ] UI changes: screenshots below, in light and dark mode (`tools/snap.sh`)
- [ ] Text changes: `tools/l10n-extract.sh` run, strings added in every language, `python3 tools/l10n.py check` passes

## Screenshots

<!-- Before and after, light and dark. Delete this section if nothing visible changed. -->
