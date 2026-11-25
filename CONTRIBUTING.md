# Contributing to ZapretMac

Thanks for helping. Bug reports, strategy reports, translations, and code are all welcome.

## Asking and reporting

- **Questions** ("does this strategy work on my provider?", "how do I…?") belong in [Discussions](https://github.com/gorlev/ZapretMac/discussions).
- **Bugs** and **feature ideas** belong in [Issues](https://github.com/gorlev/ZapretMac/issues/new/choose). The forms ask for what helps most: your macOS version, your Mac's chip, how you installed ZapretMac, and the log.
- **Security problems** must not go in a public issue. See [SECURITY.md](SECURITY.md).

ZapretMac is a front end for zapret's `tpws`. If a strategy itself does not get past your provider's filter, try **Find a Strategy** first. If no `tpws` option works, the [zapret project](https://github.com/bol-van/zapret) is the right place to ask.

## Setting up

You need macOS 26 or later and Xcode 26 or later.

```bash
git clone https://github.com/gorlev/ZapretMac.git
cd ZapretMac
./build.sh --open
```

See [Build from source](README.md#option-2-build-from-source-all-features) for signing, and [Development](README.md#development) for how the code is laid out.

## Making a change

1. **Keep logic out of the UI.** Rules and data logic go in `Sources/ZapretMacKit`, with unit tests in `Tests/ZapretMacKitTests`. Views go in `Sources/ZapretMac`.
2. **Follow the Mac.** Use Apple's controls and system styles, SF Symbols, and the spacing tokens in `UI/Grid.swift`. Give every action a menu item and a keyboard shortcut. Never hard-code colors; use `Palette` and the system colors.
3. **Never touch your real data in tests.** The self-test and snapshots run against a store in `/tmp` and refuse to run otherwise.
4. **Don't change the user's system from tests.** Code that runs `networksetup`, `pfctl`, or the privileged helper is tested through pure functions and the fakes in `Engine/`.

## Checking a change

Before you open a pull request:

| Check | Command | Expect |
|---|---|---|
| Build | `./build.sh` | No warnings |
| Unit tests | `swift test --scratch-path ~/Library/Developer/ZapretMac/test-build` | All pass |
| Self-test | `tools/selftest.sh` | `SELFTEST PASS` |
| Layout | `tools/grid-lint.sh` | `PASS` |
| Screenshots (UI changes) | `tools/snap.sh` | Look at the light and dark images in `/tmp/ZapretMac-shots` |
| Translations (text changes) | `tools/l10n-extract.sh`, then `python3 tools/l10n.py check` | `PASS` |

## Text and translations

ZapretMac is in eight languages. UI text is a SwiftUI literal (`Text("…")`) or `String(localized: "…")`.

After adding or changing text, run `tools/l10n-extract.sh`, then add the new strings to every file in `Localization/`. Follow [Localization/BRIEF.md](Localization/BRIEF.md): write each language as a native speaker would, not word for word. If you only speak some of the languages, say so in the pull request and leave the rest for a native speaker.

Improving an existing translation is a great first contribution.

## Pull requests

- Keep each pull request to one change.
- Write the title as what a user can now do, for example "Import site lists from a URL".
- Add screenshots for visible changes, in light and dark mode.

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
