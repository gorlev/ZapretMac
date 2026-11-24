# ZapretMac

A native macOS app for [zapret](https://github.com/bol-van/zapret)'s DPI bypass engine, with one switch, ready-made strategies, site lists, and a live log. Free and open source.

On macOS zapret runs `tpws`, a proxy that splits and rewrites the first packets of each connection so filters cannot read the site name. ZapretMac ships `tpws` inside the app and runs it as a SOCKS5 proxy on `127.0.0.1` without root. It can point the Mac's system proxy at it and puts the old setting back when it stops.

## Features

- **One switch**, in the window or the menu bar (Command-B).
- **Strategies**: six built-in ones from zapret, plus your own built from tpws options in a form, checked with `tpws --dry-run`.
- **Sites**: bypass all sites or only your list; a "Never touch" list for banks or sites a strategy breaks. Paste many at once or import a text file.
- **Check a site**: opens an address directly and through tpws, and tells you whether the strategy helps.
- **Log**: tpws output, live, filtered by sites or errors, with the exact command to copy.
- **System proxy**: on with one admin prompt, restored on stop, quit, or after a crash.
- Open at login, start on launch, light and dark mode.
- In English, Türkçe, Deutsch, Español, Italiano, Français, Português (Brasil), and Русский, following the Mac's language (or a per-app language in System Settings).

## Build

Needs macOS 26 and Xcode command-line tools.

```bash
./build.sh --open
```

`build.sh` builds `tpws` from `Vendor/zapret/tpws` (a universal binary, `make mac`), builds the app, and installs `~/Applications/ZapretMac.app`.

Checks:

```bash
swift test --scratch-path ~/Library/Developer/ZapretMac/test-build
tools/selftest.sh
tools/snap.sh
```

## Not yet

- Transparent pf redirection (needs a privileged helper)
- UDP and QUIC bypass (`nfqws` does not run on macOS)
- Automatic strategy search like `blockcheck.sh`

## License

MIT. `tpws` and everything under `Vendor/zapret` is zapret by bol-van, MIT license (`Vendor/zapret/LICENSE.txt`).
