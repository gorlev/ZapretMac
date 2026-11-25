# Security policy

ZapretMac changes your network settings and, in Transparent mode, runs a privileged helper as root. Security reports are taken seriously.

## Reporting a vulnerability

**Please do not open a public issue.** Report it privately instead:

1. Go to the [Security tab](https://github.com/gorlev/ZapretMac/security) of this repository.
2. Click **Report a vulnerability**.

Include what you found, the steps to reproduce it, the ZapretMac version, and your macOS version. You will get a reply as soon as possible. The fix is published before the details are made public, and you are credited in the release notes unless you prefer not to be.

## Supported versions

Only the [latest release](https://github.com/gorlev/ZapretMac/releases/latest) receives security fixes.

## What is in scope

Especially welcome:

- **The privileged helper** (`Sources/ZapretMacHelper`): any way for another app or user to make it run commands, load `pf` rules, or run `tpws` with arguments it should refuse.
- **Network settings**: system proxy or `pf` rules left behind after ZapretMac stops, quits, or crashes.
- **Local data**: site lists or settings exposed to other users or apps.

Bugs in `tpws` itself belong to the [zapret project](https://github.com/bol-van/zapret).

A note on downloads: the release disk images are signed ad hoc, so macOS asks you to approve them on first launch. That is expected, not a vulnerability. If you prefer, build ZapretMac from source and sign it with your own certificate.
