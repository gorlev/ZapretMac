# ZapretMac design plan

## Archetype
Sidebar window plus a menu bar extra (the main entry point: the on/off switch and strategy without opening the window). Settings window with three tabs.

## Information architecture
- Overview: the switch, status, stats, setup (strategy, scope, system proxy), site check, recent sites
- Strategies: built-in and custom strategy cards; editor sheet
- Sites: Sites to Unblock / Never Touch lists
- Log: live tpws output

## Command map
| Action | Menu | Shortcut |
| --- | --- | --- |
| Turn On / Turn Off | Bypass, menu bar extra, Overview toolbar | Command-B |
| Check Site | Bypass | Command-T |
| Use as System Proxy | Bypass, menu bar extra | — |
| Copy tpws Command | Bypass, Log toolbar | — |
| New Strategy… | File | Command-N |
| Add Sites… | File, Sites toolbar | Shift-Command-N |
| Delete selected sites | Edit > Delete, Sites toolbar | Delete |
| Undo / Redo delete or add | Edit | Command-Z / Shift-Command-Z |
| Go to Overview, Strategies, Sites, Log | View | Command-1…4 |
| Settings | ZapretMac | Command-Comma |

## Empty states
- Sites: "No Sites Yet" with what to add; Never Touch: "Nothing Excluded" with why to add.
- Log: "No Output Yet: turn the bypass on".
- Overview off: grey switch, dashes in the stats, one line on what the switch does.
- Strategies: never empty (six built-in); "Yours" shows a New Strategy card.

## Feeling
Confident. One big switch, a clear on/off state in teal, plain words, and a site check that shows whether it works.

## Custom parts and why
- The round power switch on Overview: the app's one job, so it gets the most weight on the page.
- Strategy cards: each strategy needs a name, a sentence, and its flags side by side to compare.
