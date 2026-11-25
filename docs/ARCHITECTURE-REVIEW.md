# Architecture check-in, end of M3 (2026-11-25)

Signals: end of milestone only. Largest file OverviewPage.swift (469 lines), largest type AppModel (~340 lines). One fix-log entry. No file over 600 lines.

## Proposals

1. **Split AppModel by job** (Medium). It holds strategies, site lists, on/off, system proxy, site check, and the finder. A `SiteLists` module (fetch, add, remove, write hostlist files) would give the hostlist files one owner and make their tests independent of the engine. Do it before adding hostlist downloads (Later).
2. **A seam for running tpws** (Medium). Engine, StrategyFinder, and the dry run each start `Process` with the bundled binary. One `TPWSRunner` interface (start, stop, output stream) would remove three copies and let the self-test use a fake runner for the crash and restart paths without killing real processes.
3. **Split OverviewPage.swift** (Weak). Move StatsRow, SetupCard, CheckCard, and FlowLayout into their own files when it passes 600 lines.

None is Strong, so nothing was changed. Pick one to do it in its own commit.

# Check-in, end of M6 (2026-11-25)

Signals: end of milestone; five stories changed the finder in parallel; FinderSheet.swift and Models.swift took most merge conflicts; three of four new fix-log entries are about running tpws processes (leftover process, unbounded exit wait, readiness).

1. **A seam for running tpws** (now Strong). Engine, StrategyFinder, the dry run, and the self-test's stray-process check each start `Process` with the bundled binary, each with its own stop/kill/wait rules. One `TPWSRunner` (start → handle with port, pid file, output stream; stop with a bounded wait) would own those rules once. Not done unattended because it touches the running bypass; do it as the first step of M8, which adds a root helper that also runs tpws.
2. **Split AppModel** (Medium, unchanged): the finder state (finderDraft, rememberScan, joined scans) now adds to it; a `FinderModel` beside `StrategyFinder` would take it out.
3. **Split FinderSheet.swift** (Medium): input, results list, row, and footer into separate views; it is the file every finder story edits.

# Check-in, end of M7 (2026-11-25)

Three stories merged with only test and snapshot conflicts. One real cross-story bug surfaced at merge: the PAC file read only My list, not subscriptions; fixed by giving both tpws and PAC one source, `mergedDomains(excluded:)`.
- Unchanged recommendation: the tpws runner seam (Strong) before M8.
- New (Medium): SelfTest.swift and Snapshot.swift take a conflict on every parallel wave; one file per story's checks (`SelfTest+S070.swift`, …) registered in a list would remove that.
