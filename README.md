# ZapretMac

A native macOS app for [zapret](https://github.com/bol-van/zapret)'s DPI bypass engine, with one switch, ready-made strategies, site lists, and a live log. Free and open source.

On macOS zapret runs `tpws`, a proxy that splits and rewrites the first packets of each connection so filters cannot read the site name. ZapretMac ships `tpws` inside the app and runs it as a SOCKS5 proxy on `127.0.0.1` without root. It can point the Mac's system proxy at it and puts the old setting back when it stops.

## Features

- **One switch**, in the window or the menu bar (Command-B).
- **Strategies**: six built-in ones from zapret, plus your own built from tpws options in a form, checked with `tpws --dry-run`.
- **Sites**: bypass all sites or only your list; a "Never touch" list for banks or sites a strategy breaks. Paste many at once or import a text file.
- **Check a site**: opens an address directly and through tpws, and tells you whether the strategy helps.
- **Log**: tpws output, live, filtered by sites or errors, with the exact command to copy.
- **System proxy**: on with one admin prompt, restored on stop, quit, or after a crash. With "My list", a PAC file sends only listed sites through tpws.
- **Transparent mode**: every app's web traffic goes through tpws with no proxy settings. A small helper (installed from Settings > Advanced, approved in Login Items) runs tpws as root and loads pf rules into the `com.apple/zapretmac` anchor; `/etc/pf.conf` is never edited, and the rules are removed when the app stops, quits, or crashes.
- **Find a Strategy**: tries the built-in strategies, or blockcheck's whole tpws list, on one or more blocked sites; save what works.
- **Site-list subscriptions**: zapret-style hostlists (gzip too) by URL, refreshed daily.
- **Global shortcut** to turn the bypass on or off from any app.
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

- IPv6 in Transparent mode
- UDP and QUIC bypass (`nfqws` does not run on macOS)

## License

MIT. `tpws` and everything under `Vendor/zapret` is zapret by bol-van, MIT license (`Vendor/zapret/LICENSE.txt`).
