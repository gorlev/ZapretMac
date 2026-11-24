#!/bin/zsh
# Builds ZapretMac and installs it to ~/Applications/ZapretMac.app.
# Build products live in ~/Library/Developer/ZapretMac, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
set -euo pipefail
here=${0:A:h}
name="ZapretMac"
scratch="$HOME/Library/Developer/$name/build"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
  exit 1
fi

# tpws, zapret's bypass engine, built from Vendor/zapret/tpws as a universal
# binary. Rebuilt only when its sources change.
tpws_dir="$HOME/Library/Developer/$name/tpws"
if [[ ! -x "$tpws_dir/tpws" || -n "$(find "$here/Vendor/zapret/tpws" -newer "$tpws_dir/tpws" -type f | head -1)" ]]; then
  echo "building tpws"
  mkdir -p "$tpws_dir"
  rsync -a --delete --exclude tpws "$here/Vendor/zapret/tpws/" "$tpws_dir/"
  rm -f "$tpws_dir/tpws"
  make -s -C "$tpws_dir" mac >/dev/null 2>"$tpws_dir/build.log" || { cat "$tpws_dir/build.log"; echo "tpws build failed"; exit 1; }
fi

app="$HOME/Applications/$name.app"
mkdir -p "$HOME/Applications"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
cp "$bin" "$app/Contents/MacOS/$name"
cp "$tpws_dir/tpws" "$app/Contents/Helpers/tpws"
commit=$(cat "$here/Vendor/zapret/COMMIT" 2>/dev/null || echo unknown)
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" -e "s/__ZAPRET_COMMIT__/$commit/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  car="$here/Resources/Assets.car"
  if [[ ! -f "$car" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$car" | head -1)" ]]; then
    "$here/tools/make_icon.sh"
  fi
  cp -X "$car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
fi
xattr -cr "$app"
codesign --force --options runtime --sign "$identity" "$app/Contents/Helpers/tpws" 2>&1 | grep -v "replacing existing signature" || true
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
