#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
# ZM_SLOT=<n> tests that worker's own build (see build.sh) on its own store and port.
set -u
slot="${ZM_SLOT:-}"
app=~/Applications/ZapretMac.app/Contents/MacOS/ZapretMac
[[ -n "$slot" ]] && app=~/Library/Developer/ZapretMac/slot-$slot/ZapretMac.app/Contents/MacOS/ZapretMac
[[ -z "$slot" ]] && rm -rf ~/Library/Saved\ Application\ State/com.gorlev.zapretmac.savedState
store=/tmp/ZapretMac-self${slot:+-$slot}.store
rm -rf $store $store-shm $store-wal $store-files
APP_STORE=$store $app --selftest -AppleLanguages "(en)" -AppleLocale en -ApplePersistenceIgnoreState YES
