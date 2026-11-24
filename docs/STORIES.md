# ZapretMac stories

Snapshot pages: overview, overview-off, strategies, editor, domains, log, settings-general, settings-appearance, settings-about.

## M1 Core loop (done)

### S-001 Turn the bypass on and off
As the user, I click the round switch (or press Command-B) and tpws starts as a SOCKS5 proxy on 127.0.0.1.
Screens: overview-light.png, overview-off-light.png
Acceptance:
- [self] Turning on starts tpws; a site opens through it; turning off stops it.
- [snap] On: teal switch, "Bypass is on", stats count up. Off: grey switch, dashes.
Status: done

### S-002 Pick a built-in strategy
As the user, I pick a strategy from the Overview menu or a card on Strategies; a running tpws restarts with it.
Screens: strategies-light.png
Acceptance:
- [self] tpws accepts every built-in strategy (dry run).
- [snap] The chosen card has a teal border and "In use".
Status: done

### S-003 Choose which sites go through the bypass
As the user, I switch between All sites and My list, and add sites to Sites to Unblock or Never Touch.
Screens: domains-light.png
Acceptance:
- [unit] Pasted URLs become clean domains, once each.
- [self] The hostlist files hold the enabled sites; list scope passes --hostlist.
Status: done

### S-004 Read the live log
As the user, I open Log and see tpws output, filtered by sites or errors.
Screens: log-dark.png
Acceptance:
- [self] The log counts connections and names the site.
Status: done

### S-005 Check whether a site opens
As the user, I type an address on Overview and click Check; I see the result with and without ZapretMac.
Screens: overview-light.png
Acceptance:
- [self] A site opens through tpws.
Status: done

## M2 Make it yours (done)

### S-010 Make a custom strategy
As the user, I click New Strategy, set options in the form, check them with tpws, and save.
Screens: editor-light.png
Acceptance:
- [self] Saving selects it; editing keeps one; deleting the active one falls back to the default.
Status: done

### S-011 Undo a delete
As the user, I delete sites or a strategy and press Command-Z to bring them back.
Acceptance:
- [manual] Edit > Undo Delete Sites restores the rows and the hostlist file.
Status: done

### S-012 Send every app through the bypass
As the user, I turn on System proxy; macOS's SOCKS proxy points at tpws and is put back when it stops.
Acceptance:
- [manual] System Settings > Network > Proxies shows SOCKS 127.0.0.1:<port> while on, the old value after.
Status: done

### S-013 Switch from the menu bar
As the user, I use the shield in the menu bar to turn the bypass on or off and change the strategy.
Acceptance:
- [manual] The menu shows the state, the switch, the strategy and sites pickers.
Status: done

## M3 Find what works

### S-020 Find a working strategy for a blocked site
As the user, I type a blocked site in Find Strategy and ZapretMac tries each built-in strategy in turn, then shows which ones open it, fastest first, with a button to use one.
Screens: finder-light.png (new sheet snapshot)
Acceptance:
- [unit] Results sort working strategies by time, failed ones last.
- [self] Testing example.com reports at least one working strategy and leaves the running bypass as it was.
- [snap] A sheet lists each strategy with a progress, check, or cross, and "Use" on working rows.
Status: done

### S-021 Know when tpws stops by itself
As the user, when tpws quits unexpectedly ZapretMac restarts it once; if it fails again I get a notification and the menu bar shield shows a warning.
Acceptance:
- [self] Killing tpws makes the engine restart it within two seconds.
- [manual] A second crash posts "ZapretMac stopped" with the error.
- [snap] The menu bar icon is shield-with-exclamation in the failed state.
Status: done

## M4 Speed

### S-030 Reopen on the page I left
As the user, I quit and reopen ZapretMac and it shows the same sidebar page.
Acceptance:
- [self] The sidebar page is saved and read back (real runs only).
Status: done

### S-031 Share a strategy as text
As the user, I copy a strategy's tpws flags from its context menu, and paste flags into New Strategy to create one.
Acceptance:
- [unit] Pasted flags round-trip through StrategyOptions.
- [manual] Copy Flags puts the command line on the clipboard.
Status: done

## M5 Language

### S-040 Use ZapretMac in my language
As a user whose Mac is set to Turkish, German, Spanish, Italian, French, Brazilian Portuguese, or Russian, I see every label, menu, and message written naturally in that language; English stays the base.
Acceptance:
- [unit] Every key in Localizable.xcstrings has a value in all eight languages, and format specifiers match the English ones.
- [snap] All pages with APP_LANG=<code> show the language with no clipping.
- [manual] A native speaker reads it as written in the language, not translated.
Status: todo

## Later
- Transparent pf mode with a privileged helper (no proxy setup per app)
- A PAC file so only listed sites use the proxy
- Download community hostlists from a URL
- Global shortcut for the switch

## Dropped
- Accounts, sync, telemetry: a local tool for one person.
- nfqws / UDP / QUIC: zapret does not support it on macOS.
- Full blockcheck.sh port: S-020 covers the useful part for tpws.
