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
- [script] `tools/l10n.py check` passes: every key of en.json has a value in all seven translations, placeholders match, plural forms follow CLDR, no value sits under the wrong key. build.sh refuses to build otherwise.
- [snap] All pages with APP_LANG=<code> show the language with no clipping.
- [manual] A native speaker reads it as written in the language, not translated.
Status: done

## M6 Find what works, like blockcheck

blockcheck.sh skips nfqws on macOS (`SKIP_PKTWS=1` for Darwin) and runs only its tpws tests, so its whole tpws matrix applies here. Its macOS rules: `--oob` and `--disorder` together are tested only on Linux ("other systems retransmit oob byte without URG tcp flag and poison tcp stream"), `--mss` only on Linux, `--fix-seg` only on Linux.

### S-090 Scan thoroughly, like blockcheck
As the user, I pick Quick or Thorough in Find a Strategy. Quick tries the built-in strategies (today's behavior). Thorough runs blockcheck's tpws matrix for HTTPS: split positions `2`, `1`, `sniext+1`, `sniext+4`, `host+1`, `midsld`, `1,midsld`, `1,sniext+1,host+1,midsld,endhost-1`, and TLS records `--tlsrec=midsld`, `--tlsrec=sniext+1 --split-pos=midsld`, `--tlsrec=sniext+4 --split-pos=midsld`, `--tlsrec=sniext+1 --split-pos=1,midsld`, `--tlsrec=sniext+4 --split-pos=1,midsld`, each alone, with `--oob`, and with `--disorder` (39 tries). For an http:// address it runs the HTTP set: `--hostcase`, `--hostspell=hoSt`, `--hostdot`, `--hosttab`, `--hostnospace`, `--domcase`, `--hostpad=1024…16384`, splits `method+2`, `midsld`, `method+2,midsld` (alone, with `--hostcase`, `--oob`, `--disorder`), `--methodspace`, `--unixeol`, `--methodeol`.
Screens: finder-light.png (Thorough results)
Acceptance:
- [unit] The Kit builds exactly blockcheck's HTTPS and HTTP lists, never pairing `--oob` with `--disorder` and never adding `--mss`.
- [self] A thorough scan of example.com finishes, lists every try, and leaves the bypass running unchanged.
- [snap] Rows show the flags under a short name; a progress line says "Try 12 of 39".
Status: done

### S-091 Save a strategy the scan found
As the user, I click "Save as Strategy…" on any working row, and the editor opens with those flags and a suggested name.
Depends: S-090
Acceptance:
- [self] Saving a found row creates a custom strategy with the same flags and selects it.
Status: done

### S-092 Check several sites at once
As the user, I paste a few blocked sites (one per line) into Find a Strategy; each strategy is tried on all of them, and a row works only if every site opens.
Depends: S-090
Acceptance:
- [unit] A trial with sites A and B is "works" only if both open; its time is the slowest.
- [snap] Each row shows "2 of 3 sites" when some failed.
Status: done

### S-093 Use one strategy for HTTP and another for HTTPS
As the user, when the scan finds the best HTTP and the best HTTPS strategy separately, I save them as one strategy that tpws applies per port (two profiles joined with `--new`, `--filter-tcp=80` and `--filter-tcp=443`).
Depends: S-090
Acceptance:
- [unit] Two option sets join into one argument list with `--filter-tcp=80 … --new --filter-tcp=443 …`, and parse back.
- [self] tpws accepts the joined flags (dry run).
Status: done

### S-094 More built-in strategies from blockcheck
As the user, I find four more ready-made strategies that blockcheck tries early: TLS record in the middle of the domain (`--tlsrec=midsld`), split at the server-name field (`--split-pos=sniext+1`), multi-split (`--split-pos=1,sniext+1,host+1,midsld,endhost-1`), and Host padding for plain HTTP (`--hostpad=1024`).
Acceptance:
- [self] tpws accepts every new preset (dry run).
- [snap] The Strategies grid shows ten cards, names and blurbs in all eight languages.
Status: done

### S-095 The editor knows what macOS can and cannot do
As the user, the strategy editor warns me when I turn on both "out-of-band byte" and "disorder" (they break connections on macOS), never suggests `--mss` (Linux only), and offers the two HTTP options it lacks: Host spelling (`--hostspell`) and Host padding (`--hostpad`).
Acceptance:
- [unit] StrategyOptions round-trips `--hostspell=hoSt` and `--hostpad=2048`.
- [snap] Turning on both toggles shows an orange warning under them.
Status: done

## M7 System

### S-070 Subscribe to a community site list
As the user, I paste the address of a hostlist (a text file with one domain per line, gzip allowed, like zapret's own lists) under Sites > Subscriptions; ZapretMac downloads it and uses it with My list.
Acceptance:
- [unit] A downloaded list is parsed with the same rules as pasted sites; gzip is unpacked.
- [self] A list served from a local test file adds its domains to the hostlist file tpws reads.
- [snap] Subscriptions shows each list with its domain count and when it was last updated.
Status: done

### S-071 Keep subscribed lists fresh
As the user, subscribed lists update once a day in the background and when I click Update Now; a failed download keeps the last good copy.
Depends: S-070
Acceptance:
- [self] A failed refresh keeps the old domains and shows the error on the row.
Status: done

### S-072 Send only listed sites through the proxy
As the user, with My list and System proxy on, only the sites in my lists go through tpws; everything else connects directly (a PAC file served on 127.0.0.1, set with `networksetup -setautoproxyurl`, restored on stop).
Acceptance:
- [unit] The PAC script returns the SOCKS proxy for a listed domain and its subdomains, DIRECT for others.
- [manual] Safari opens a listed site through tpws and an unlisted one directly.
Status: done

### S-073 Turn the bypass on and off from anywhere
As the user, I set a global shortcut in Settings and press it in any app to turn the bypass on or off; a small HUD says which.
Acceptance:
- [manual] The shortcut works with another app in front.
- [snap] Settings > General shows the shortcut recorder.
Status: done

## M8 Transparent mode

### S-080 Install the privileged helper
As the user, I turn on Transparent mode once and approve ZapretMac's helper in System Settings > Login Items; the helper runs as root and only accepts requests from ZapretMac.
Acceptance:
- [manual] Approving the helper in System Settings lets ZapretMac reach it; removing it turns Transparent mode off.
- [self] The app reports the helper's state (not installed, needs approval, ready).
Status: done

### S-081 Bypass without any proxy setting
As the user, in Transparent mode every app's traffic to ports 80 and 443 goes through tpws without a proxy: the helper runs tpws as root with `--port … --user=root` and pf `rdr`/`route-to` rules, as zapret's macOS install does.
Depends: S-080
Acceptance:
- [manual] curl without any proxy opens a blocked site in Transparent mode.
- [self] Turning off removes ZapretMac's pf anchor and stops tpws.
Status: done

### S-082 Recover pf after a crash
As the user, if ZapretMac or the helper quits unexpectedly in Transparent mode, the pf rules are removed so my internet keeps working.
Depends: S-081
Acceptance:
- [manual] Killing ZapretMac while on leaves no ZapretMac pf rules after the next launch.
Status: done

## M9 What zapret still has for the Mac

The rest of zapret that runs on macOS, compared feature by feature with tpws's options (`Vendor/zapret/tpws/tpws.c`), blockcheck.sh, `ipset/`, and docs/bsd.en.md. Stories that depend on nothing come first.

### S-100 Let tpws build the site list by itself
As the user, I turn on "Add blocked sites automatically" under Sites; tpws notices sites whose connections the filter breaks (several failures in a short time) and adds them to an "Added automatically" list that the bypass then uses, so I do not have to know which sites are blocked.
Notes: tpws `--hostlist-auto=<file>`, `--hostlist-auto-fail-threshold` (default 3), `--hostlist-auto-fail-time` (default 60 s), `--hostlist-auto-debug=<log>`; zapret calls this MODE_FILTER=autohostlist. The app shows the file's sites as their own section, where I can move one to My list or Never Touch, delete it, or clear the list. Transparent mode: the helper refuses `--hostlist-auto` today because tpws would write the file as root; the helper owns the file (root-written under its own folder) and hands its contents to the app over XPC, or the mode is off there with a clear note — decide in the UX pass.
Acceptance:
- [unit] With the option on, the tpws arguments carry `--hostlist-auto=` with the threshold and time in every profile; off, they do not.
- [self] A local test server that resets connections for one host gets that host into the automatic list after the threshold, and the app shows it.
- [snap] The Sites page shows the automatic section with its count and the actions.
Status: todo

### S-101 Find out what kind of block it is
As the user, when a site does not open, Find a Strategy (and the site check) first tells me whether the block is something ZapretMac can get around: the provider changes DNS answers, the site's IP address is blocked, or the filter reads the site name (DPI). For DNS blocking it suggests turning on encrypted DNS; for an IP block it says no strategy will help.
Notes: blockcheck `check_dns`/`check_dns_spoof` (compares the system resolver with DNS-over-HTTPS answers from several public resolvers) and `check_dpi_ip_block` (connects to the blocked site's IP with an unblocked name, and to an unblocked site's IP with the blocked name). Use URLSession for DoH (`application/dns-message`, RFC 8484) or JSON DoH; never send the user's site list anywhere else.
Acceptance:
- [unit] The verdict logic maps (DNS differs, IP blocked, TLS reset with name) to the right message.
- [self] With a fake resolver result that differs from DoH, the finder shows the DNS verdict before trying strategies.
- [snap] The finder sheet shows a short verdict line with an icon above the results.
Status: todo

### S-102 Try TLS 1.2 and 1.3, and retry flaky results
As the user, Thorough scans try each strategy with TLS 1.2 and TLS 1.3 separately and can repeat each try, like blockcheck, so a DPI that treats the versions differently or answers unreliably does not give me a wrong winner.
Notes: blockcheck runs curl with `--tlsv1.2 --tls-max 1.2` and `--tlsv1.3`, and `REPEATS` attempts per try. URLSession: `tlsMinimumSupportedProtocolVersion`/`tlsMaximumSupportedProtocolVersion` on the session configuration. Default repeats 1; Thorough offers 3.
Acceptance:
- [unit] A try is "works" only if every repeat works; the result records the TLS version.
- [self] A scan of example.com reports both versions per row.
Status: todo

### S-103 Filter by IP address ranges
As the user, I can add IP addresses and ranges (one per line, CIDR, v4 and v6), or subscribe to an IP list, for apps that connect by address instead of by name; the bypass acts on those addresses (and never on an excluded range).
Notes: tpws `--ipset=<file>`, `--ipset-exclude=<file>`, `--ipset-ip=`, gzip supported; zapret's `ipset/get_antifilter_*.sh`, `get_refilter_ipsum.sh`, `get_ipban.sh` produce such lists. Reuse the subscription machinery from S-070 with a "domains / IP addresses" kind. The helper's validator must accept the ipset file paths under the data folder (it already allows `--ipset=` there).
Acceptance:
- [unit] IP lines are parsed and normalized (CIDR, v4, v6, comments); bad lines are skipped.
- [self] An IP list reaches tpws as `--ipset=` in every profile and passes the helper's validator.
- [snap] Sites shows an "IP addresses" section.
Depends: S-070
Status: todo

### S-104 Share the bypass with my other devices
As the user, I turn on "Share with devices on this network" and my phone or TV can use the Mac as a SOCKS5 proxy at the address the app shows (with a QR code); it is off by default and only listens on the local network interface.
Notes: tpws `--bind-iface4=<en0>` (plus 127.0.0.1) or `--bind-addr=<LAN address>`; macOS asks the user to allow incoming connections. Show the LAN address and port, and warn that anyone on the network can use it while it is on. Transparent passthrough for Internet Sharing (rdr on the shared interface, docs/bsd.en.md) is a later step.
Acceptance:
- [unit] With sharing on, the arguments add a LAN bind; off, only 127.0.0.1.
- [manual] An iPhone on the same Wi-Fi opens a blocked site through the shown proxy address.
- [snap] Settings shows the toggle, address, QR code, and the warning.
Status: todo

### S-105 Transparent mode for IPv6 too
As the user on an IPv6 network, Transparent mode also sends IPv6 web traffic through tpws, so no connection skips the bypass.
Notes: zapret's rules `rdr pass on lo0 inet6 proto tcp from !::1 to any port {80,443} -> fe80::1 port <P>` and `pass out route-to (lo0 fe80::1) inet6 … user { >root }`; tpws `--bind-iface6=lo0 --bind-linklocal=force`. Add to PFRules and the helper's fixed arguments; keep the validator strict.
Acceptance:
- [unit] PFRules produces both IPv4 and IPv6 lines; the helper's fixed arguments include the link-local bind.
- [manual] On an IPv6 network, `curl -6` to a blocked site opens with Transparent mode on.
Depends: S-081
Status: todo

### S-106 One-click suggested site lists
As the user, Add Subscription offers a short list of known community lists (for example zapret's antizapret and refilter sources) with one line on what each contains, so I do not have to find addresses myself.
Notes: URLs from zapret's `ipset/get_antizapret_domains.sh` and `get_refilter_domains.sh`; keep the list in one Kit file with names and descriptions; link to the source page. Country-specific lists say which country they are for.
Acceptance:
- [unit] Every suggested entry has a name, description, URL, and kind (domains / IPs).
- [snap] The Add Subscription sheet shows the suggestions; choosing one fills the address.
Depends: S-070
Status: todo

### S-107 The editor covers the remaining tpws options
As the user, the strategy editor has controls for the tpws desync options it still lacks: the OOB byte value (`--oob-data`), disorder or OOB only for TLS or only for HTTP (`--disorder=tls`, `--oob=http`), protocol filter (`--filter-l7=http,tls`), and where tampering starts and stops (`--tamper-start`, `--tamper-cutoff`).
Acceptance:
- [unit] StrategyOptions round-trips each option; existing strategies are unchanged.
- [self] tpws accepts a strategy using all of them (dry run), and the helper's validator accepts them.
- [snap] The editor shows them in its Advanced section.
Status: todo

## Dropped
- Accounts, sync, telemetry: a local tool for one person.
- nfqws / UDP / QUIC: zapret does not support it on macOS.
- nfqws strategies from blockcheck (fake, fakedsplit, syndata, seqovl, ipfrag): they need packet interception that zapret does not support on macOS.
- `--mss`, `--fix-seg`, and `--oob` together with `--disorder`: blockcheck itself skips them outside Linux.
