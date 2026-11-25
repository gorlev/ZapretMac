#!/bin/zsh
# Builds the downloadable copies of ZapretMac: ad hoc signed (no developer
# certificate, so no personal name), for Apple silicon, Intel, and both, each
# as a disk image with an Applications shortcut, plus a zip of each.
# Usage: tools/release.sh            -> ~/Library/Developer/ZapretMac/dist
# Uses build slot 9, so your own installed app is untouched.
set -euo pipefail
here=${0:A:h}
repo=${here:h}
dist="$HOME/Library/Developer/ZapretMac/dist"
slot=9
built="$HOME/Library/Developer/ZapretMac/slot-$slot/ZapretMac.app"
version=$(sed -n 's|.*<key>CFBundleShortVersionString</key><string>\([^<]*\)</string>.*|\1|p' "$repo/Info.plist.in")
rm -rf "$dist"
mkdir -p "$dist"

package() { # name, then build.sh arguments
  local name=$1; shift
  SIGN_IDENTITY=- ZM_SLOT=$slot "$repo/build.sh" "$@" | tail -1
  codesign --verify --deep --strict "$built"
  # Nothing personal may ship: no developer name, team, or home-folder path.
  if LC_ALL=C grep -r -a -l -F "$HOME" "$built" >/dev/null; then
    echo "release failed: $name contains a home-folder path"; exit 1
  fi
  if [[ "$(codesign -dvv "$built" 2>&1 | grep -c '^Authority=')" != 0 ]]; then
    echo "release failed: $name is signed with a certificate, not ad hoc"; exit 1
  fi
  local stage="$dist/stage-$name"
  mkdir -p "$stage"
  ditto "$built" "$stage/ZapretMac.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -quiet -volname "ZapretMac $version" -srcfolder "$stage" -fs APFS -format ULFO \
    "$dist/ZapretMac-$version-$name.dmg"
  (cd "$stage" && ditto -c -k --sequesterRsrc --keepParent ZapretMac.app "$dist/ZapretMac-$version-$name.zip")
  rm -rf "$stage"
  echo "packaged $name"
}

package AppleSilicon --arch arm64
package Intel --arch x86_64
package Universal --universal
(cd "$dist" && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt && cat SHA256SUMS.txt)
echo "wrote $dist"
