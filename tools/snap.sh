#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
#        APP_LANG=tr tools/snap.sh   in another language, into /tmp/ZapretMac-shots-tr
set -u
app=~/Applications/ZapretMac.app/Contents/MacOS/ZapretMac
store=/tmp/ZapretMac-test.store
shots=/tmp/ZapretMac-shots${APP_LANG:+-$APP_LANG}
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.gorlev.zapretmac.savedState
# Seed data only fills an empty store, so start from nothing.
rm -f $store $store-shm $store-wal
rm -rf $shots
# English by default, so snapshots do not depend on this Mac's language.
lang=(-AppleLanguages "(${APP_LANG:-en})" -AppleLocale "${APP_LANG:-en}")
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app $lang
