#!/bin/zsh
# Rebuilds Localization/en.json from every string the compiler sees as
# localizable. A clean build each time: an incremental one skips unchanged files.
set -euo pipefail
here=${0:A:h}
repo=${here:h}
scratch=$(mktemp -d)
out=$(mktemp -d)
trap 'rm -rf "$scratch" "$out"' EXIT
swift build -c debug --package-path "$repo" --scratch-path "$scratch" \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$out" 2>&1 | grep -E "error" || true
python3 "$here/l10n_extract.py" "$out"
python3 "$here/l10n.py" check || true
