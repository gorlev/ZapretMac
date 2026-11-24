# ZapretMac

An open-source native Mac app that runs zapret's `tpws` DPI-bypass engine with one switch, for people who want blocked sites to open without touching the terminal.

## Replaces
Running `/opt/zapret/init.d/macos/zapret` and editing `config` / `tpws` flags by hand in Terminal.

## Main jobs
1. Turn bypass on or off in one click, from the window or the menu bar, and see whether it is working.
2. Pick a bypass strategy (built-in presets such as split, disorder, TLS record split, host case) or build a custom one from tpws options, and test it.
3. Choose which sites it acts on: all traffic, or only a domain list (with an exclude list).
4. Read the live tpws log when something does not work.

## Data
- Strategy: name, symbol, tpws arguments (split positions, disorder, oob, tlsrec, host tricks, filters), built-in or custom
- DomainList entry: domain, kind (include / exclude), enabled
- Settings (UserDefaults): SOCKS port, set-system-proxy on/off, launch at login, active strategy, scope (all / list)

## Shape
Sidebar window (Overview, Strategies, Domains, Log) plus a menu bar extra with the on/off switch, macOS 26 or later.
Local data. Works offline. No accounts.

## Engine
`tpws` is built from zapret's source (vendored under `Vendor/zapret`, `make mac`, universal binary) and shipped inside the app bundle. It runs as the user in SOCKS5 mode on `127.0.0.1:<port>` (no root needed). The app can point the Mac's system SOCKS proxy at it with `networksetup` (one admin prompt) and restores the previous proxy when it stops or quits.

## System hooks
Menu bar extra, launch at login (SMAppService), system SOCKS proxy via `networksetup`.

## Reference
zapret's own option set and `blockcheck.sh` presets; no GUI reference.

## Look
Native macOS 26 (Liquid Glass sidebar and toolbar) with a teal accent and one large status "shield" control on Overview.

## Not in version one
- Transparent pf redirection mode (needs root + a privileged helper)
- nfqws / UDP / QUIC bypass (not supported by zapret on macOS)
- Automatic blockcheck strategy search
