# Architecture check-in, end of M3 (2026-11-25)

Signals: end of milestone only. Largest file OverviewPage.swift (469 lines), largest type AppModel (~340 lines). One fix-log entry. No file over 600 lines.

## Proposals

1. **Split AppModel by job** (Medium). It holds strategies, site lists, on/off, system proxy, site check, and the finder. A `SiteLists` module (fetch, add, remove, write hostlist files) would give the hostlist files one owner and make their tests independent of the engine. Do it before adding hostlist downloads (Later).
2. **A seam for running tpws** (Medium). Engine, StrategyFinder, and the dry run each start `Process` with the bundled binary. One `TPWSRunner` interface (start, stop, output stream) would remove three copies and let the self-test use a fake runner for the crash and restart paths without killing real processes.
3. **Split OverviewPage.swift** (Weak). Move StatsRow, SetupCard, CheckCard, and FlowLayout into their own files when it passes 600 lines.

None is Strong, so nothing was changed. Pick one to do it in its own commit.
