import AppKit
import JavaScriptCore
import SwiftData
import ZapretMacKit

/// Self-test: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/ZapretMac-self.store ~/Applications/ZapretMac.app/Contents/MacOS/ZapretMac --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
/// It never changes the system proxy.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            model.prefs.useSystemProxy = false

            check("tpws is inside the app", Engine.binaryExists, Engine.binaryURL.path)

            // The engine's restart-once and failure rules, on a fake tpws:
            // no real process is started or killed.
            await checkEngineWithFakeRunner()

            // The page is remembered in real runs only.
            let savedPage = UserDefaults.standard.string(forKey: "sidebar.page")
            model.sidebar = .log
            check("test runs do not change the remembered page", UserDefaults.standard.string(forKey: "sidebar.page") == savedPage)
            model.sidebar = .overview

            // Every built-in strategy is accepted by tpws.
            for preset in Preset.all {
                let result = await Engine.dryRun(preset.options.arguments)
                check("tpws accepts \(preset.name)", result.ok, result.output)
            }
            let bad = await Engine.dryRun(["--split-pos=nonsense"])
            check("tpws refuses bad flags", !bad.ok)

            // Sites
            let added = model.addDomains(from: "https://www.YouTube.com/x, discord.com\ndiscord.com", excluded: false)
            check("pasting sites adds each once", added == 2, "added \(added)")
            check("adding a known site adds nothing", model.addDomains(from: "youtube.com", excluded: false) == 0)
            model.addDomains(from: "apple.com", excluded: true)
            let hostlist = (try? String(contentsOf: Store.hostlistURL, encoding: .utf8)) ?? ""
            check("the hostlist file has the sites", hostlist == "discord.com\nyoutube.com\n", hostlist)
            let exclude = (try? String(contentsOf: Store.excludeURL, encoding: .utf8)) ?? ""
            check("the exclude file has the excluded site", exclude == "apple.com\n", exclude)

            // Strategies shared as text (the clipboard is put back after).
            let savedClipboard = NSPasteboard.general.string(forType: .string)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("--split-pos=3,midsld --oob --mss=88", forType: .string)
            let pasted = model.clipboardFlags
            check("flags on the clipboard become options", pasted?.splitPositions == "3,midsld" && pasted?.oob == true && pasted?.extra == ["--mss=88"])
            NSPasteboard.general.setString("hello", forType: .string)
            check("other clipboard text is not flags", model.clipboardFlags == nil)
            NSPasteboard.general.clearContents()
            if let savedClipboard { NSPasteboard.general.setString(savedClipboard, forType: .string) }

            // Strategies
            var draft = StrategyDraft(name: "Test", options: StrategyOptions(commandLine: "--split-pos=2 --disorder"))
            let saved = model.save(draft)
            check("saving a strategy selects it", model.prefs.strategyID == saved.selectionID)
            check("the active strategy uses its flags", model.activeStrategy.arguments == ["--split-pos=2", "--disorder"])
            draft.editing = saved.uuid
            draft.name = "Renamed"
            model.save(draft)
            check("editing keeps one strategy", model.customStrategies().count == 1)
            model.delete(saved)
            check("deleting the active strategy falls back to the default", model.prefs.strategyID == "preset:\(Preset.defaultID)")

            // A tpws left behind by a force-quit run holds the port: turning on
            // must stop it first.
            let strayCommand = TPWSCommand(port: model.prefs.port, strategy: [], scope: .allSites, debug: false,
                                           pidFile: Store.pidURL.path)
            let stray = try? LocalTPWSRunner().start(strayCommand, output: nil, exit: nil)
            try? await Task.sleep(for: .milliseconds(400))

            // On and off, with real traffic through tpws.
            model.prefs.scope = .allSites
            model.turnOn()
            for _ in 0..<30 where model.engine.state != .running { try? await Task.sleep(for: .milliseconds(100)) }
            check("turning on starts tpws", model.engine.state == .running, "\(model.engine.state)")
            check("a leftover tpws on the port is stopped first", stray?.isRunning == false)
            if let url = URL(string: "https://example.com") {
                let outcome = await SiteCheck.fetch(url, socksPort: model.prefs.port)
                check("a site opens through tpws", outcome.isOK, "\(outcome)")
            }
            try? await Task.sleep(for: .milliseconds(300))
            check("the log counts the connection", model.engine.connections > 0)
            check("the log names the site", model.engine.hostsSeen.contains("example.com"), "\(model.engine.hostsSeen)")
            model.prefs.scope = .listOnly
            model.restartIfRunning()
            try? await Task.sleep(for: .milliseconds(800))
            check("restarting with the site list keeps it running", model.engine.state == .running, "\(model.engine.state)")
            check("the list scope passes the hostlist", model.command.arguments.contains("--hostlist=\(Store.hostlistURL.path)"))
            // tpws quitting by itself is restarted once.
            if let pid = model.engine.pid {
                kill(pid, SIGKILL)
                for _ in 0..<30 where !(model.engine.state == .running && model.engine.pid != pid) {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                check("tpws quitting by itself is restarted", model.engine.state == .running && model.engine.autoRestarts == 1,
                      "\(model.engine.state), restarts \(model.engine.autoRestarts)")
                if let second = model.engine.pid {
                    kill(second, SIGKILL)
                    try? await Task.sleep(for: .milliseconds(800))
                    let failed = if case .failed = model.engine.state { true } else { false }
                    check("a second quit within a minute is a failure", failed, "\(model.engine.state)")
                    check("the menu bar shows a warning", model.engine.menuBarSymbol == "exclamationmark.shield")
                }
                model.turnOn()
                for _ in 0..<30 where model.engine.state != .running { try? await Task.sleep(for: .milliseconds(100)) }
            }

            // S-090
            // A thorough scan runs blockcheck's tpws matrix beside the bypass.
            let beforeScan = model.engine.commandLine
            if let url = URL(string: "https://example.com") {
                model.startFinder(url: url, depth: .thorough)
                check("a thorough scan of an https address has 39 tries", model.finder.trials.count == 39, "\(model.finder.trials.count)")
                // The full matrix is checked by ScanPlanTests; on a real network
                // a run takes minutes, so try the first few and stop.
                for _ in 0..<600 where model.finder.finishedCount < 4 && model.finder.isRunning {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            check("a thorough scan works through its tries", model.finder.finishedCount >= 4, "\(model.finder.finishedCount) done")
            check("at least one scan try opens example.com", model.finder.workingCount > 0)
            model.finder.stop()
            check("stopping a scan stops it", !model.finder.isRunning && model.finder.trials.allSatisfy { $0.status != .testing })
            check("the bypass keeps running through a thorough scan",
                  model.engine.state == .running && model.engine.commandLine == beforeScan)
            model.finderDepth = .quick

            // Find a strategy: runs beside the bypass without touching it.
            let before = model.engine.commandLine
            if let url = URL(string: "https://example.com") {
                model.startFinder(url: url)
                for _ in 0..<800 where model.finder.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
            }
            check("finding a strategy tests every one", model.finder.isDone, "\(model.finder.trials.map(\.status))")
            check("at least one strategy opens example.com", model.finder.workingCount > 0)
            check("the bypass keeps running while it tests", model.engine.state == .running && model.engine.commandLine == before)

            // S-092
            // A quick find on two sites tries every strategy on both, a few at a time.
            let beforeMulti = model.engine.commandLine
            let multi = SiteCheck.urls(from: "https://example.com https://www.wikipedia.org")
            check("two sites typed with a space are read as two", multi.map { $0.host ?? "" } == ["example.com", "www.wikipedia.org"],
                  "\(multi)")
            model.startFinder(urls: multi, depth: .quick)
            for _ in 0..<1200 where model.finder.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
            let rows = model.finder.trials
            check("a find on two sites finishes", model.finder.isDone, "\(rows.map(\.status))")
            check("every row has a result for both sites",
                  !rows.isEmpty && rows.allSatisfy { $0.sites.map(\.site) == ["example.com", "www.wikipedia.org"] },
                  "\(rows.map { $0.sites.map(\.site) })")
            check("the direct check covers both sites", model.finder.direct.map(\.site) == ["example.com", "www.wikipedia.org"])
            check("at least one strategy opens both sites", rows.contains { $0.works && $0.openCount == 2 },
                  "\(rows.map { "\($0.name): \($0.status)" })")
            check("the bypass keeps running through a find on two sites",
                  model.engine.state == .running && model.engine.commandLine == beforeMulti)

            // S-091 S-093
            // One strategy for HTTP and another for HTTPS, joined with --new.
            let joined = StrategyProfiles(http: StrategyOptions(arguments: ["--hostcase", "--split-pos=method+2"]),
                                          https: StrategyOptions(arguments: ["--tlsrec=sniext+1", "--split-pos=midsld"])).arguments
            let joinedRun = await Engine.dryRun(joined)
            check("tpws accepts an HTTP + HTTPS strategy", joinedRun.ok, joinedRun.output)
            // Saving a scan row: the editor opens with its flags; saving selects it.
            if let row = ScanPlan.https.first(where: { $0.arguments.contains("--oob") && $0.arguments.contains { $0.hasPrefix("--tlsrec") } }) {
                let trial = Trial(id: row.id, name: row.name, arguments: row.arguments, status: .works(milliseconds: 100))
                model.saveScanRow(trial)
                let scanDraft = model.finderDraft
                check("saving a scan row opens the editor with its flags and name",
                      scanDraft?.options.arguments == row.arguments && scanDraft?.name == row.name, "\(String(describing: scanDraft))")
                model.finderDraft = nil
                if let scanDraft {
                    let found = model.save(scanDraft)
                    check("a saved scan row is a custom strategy with exactly its flags, selected",
                          model.prefs.strategyID == found.selectionID && model.activeStrategy.arguments == row.arguments,
                          "\(model.activeStrategy.arguments)")
                }
            }
            // Turning on with the joined strategy and the site list: both parts get the list.
            model.prefs.scope = .listOnly
            model.save(StrategyDraft(name: "HTTP + HTTPS", options: StrategyOptions(arguments: joined)))
            check("a joined strategy round-trips through a saved strategy", model.activeStrategy.arguments == joined,
                  "\(model.activeStrategy.arguments)")
            try? await Task.sleep(for: .milliseconds(300))
            for _ in 0..<30 where model.engine.state != .running { try? await Task.sleep(for: .milliseconds(100)) }
            let line = model.engine.commandLine
            check("tpws runs with an HTTP + HTTPS strategy and the site list", model.engine.state == .running, "\(model.engine.state)")
            check("the command has two profiles, each with the hostlist",
                  line.contains(" --new ") && line.components(separatedBy: "--hostlist=").count - 1 == 2, line)

            // S-073
            // The global shortcut: saved, registered system-wide, and its handler flips the bypass.
            check("there is no global shortcut until one is recorded", model.prefs.globalShortcut == nil)
            let hotkey = GlobalShortcut(keyCode: 111, modifiers: [.control, .option, .shift]) // ⌃⌥⇧F12
            model.setGlobalShortcut(hotkey)
            check("the global shortcut is saved", Prefs.savedShortcut(in: model.prefs.defaults) == hotkey)
            check("the global shortcut registers", !model.globalShortcutFailed && GlobalHotKey.shared.registered == hotkey,
                  "\(String(describing: GlobalHotKey.shared.registered))")
            for _ in 0..<30 where model.engine.state != .running { try? await Task.sleep(for: .milliseconds(100)) }
            let wasRunning = model.engine.state == .running
            GlobalHotKey.shared.fire(GlobalHotKey.bypassID)
            check("the shortcut turns the bypass off", wasRunning && model.engine.state == .stopped, "\(model.engine.state)")
            check("the shortcut shows the HUD", BypassHUD.shared.window?.isVisible == true)
            GlobalHotKey.shared.fire(GlobalHotKey.bypassID)
            for _ in 0..<30 where model.engine.state != .running { try? await Task.sleep(for: .milliseconds(100)) }
            check("the shortcut turns the bypass back on", model.engine.state == .running, "\(model.engine.state)")
            model.setGlobalShortcut(nil)
            check("removing the shortcut unregisters it", GlobalHotKey.shared.registered == nil && model.prefs.globalShortcut == nil
                  && Prefs.savedShortcut(in: model.prefs.defaults) == nil)
            BypassHUD.shared.hide()

            // S-072
            // My list + system proxy uses a PAC file served on 127.0.0.1. The
            // system proxy itself is never applied here (useSystemProxy is off).
            model.prefs.scope = .listOnly
            check("my list uses PAC mode for the system proxy", model.proxyMode == .pac)
            model.prefs.scope = .allSites
            check("all sites uses SOCKS mode for the system proxy", model.proxyMode == .socks)
            model.prefs.scope = .listOnly
            check("the self-test never applies the system proxy", !model.proxy.isApplied)
            if let pacURL = await model.servePAC() {
                check("the PAC file is served on 127.0.0.1", pacURL.host == "127.0.0.1" && pacURL.path == PACFile.path, pacURL.absoluteString)
                let socks = PACFile.proxy(port: model.prefs.port)
                let first = await fetchPAC(pacURL)
                check("the PAC file has its content type", first.type == PACFile.contentType, first.type)
                check("the served PAC sends a listed site to SOCKS", route(first.body, "www.youtube.com") == socks,
                      route(first.body, "www.youtube.com"))
                check("the served PAC sends an unlisted site direct", route(first.body, "example.org") == "DIRECT")
                check("the served PAC sends an excluded site direct", route(first.body, "www.apple.com") == "DIRECT")
                var missing = pacURL
                missing.deletePathExtension()
                let notFound = await fetchPAC(missing.appendingPathExtension("txt"))
                check("other paths are not found", notFound.status == 404, "\(notFound.status)")
                model.addDomains(from: "example.org", excluded: false)
                let second = await fetchPAC(pacURL)
                check("a list change updates the served PAC", route(second.body, "example.org") == socks,
                      route(second.body, "example.org"))
                model.remove(model.domains(excluded: false).filter { $0.domain == "example.org" })
                model.pacServer.stop()
                let afterStop = await fetchPAC(pacURL)
                check("stopping the PAC server stops serving", !model.pacServer.isRunning && afterStop.status == 0, "\(afterStop.status)")
            } else {
                check("the PAC server starts", false)
            }

            // S-070 S-071
            // Subscribed lists, served from local files (never the internet),
            // feed the hostlist files tpws reads, next to My list.
            let listDir = Store.directory.appending(path: "selftest-lists", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: listDir, withIntermediateDirectories: true)
            let plainList = listDir.appending(path: "community.txt")
            try? "# community list\nblocked-one.example\nwww.Blocked-Two.example # mirror\n\nblocked-one.example\n"
                .write(to: plainList, atomically: true, encoding: .utf8)
            let neverText = listDir.appending(path: "never.txt")
            try? "# banks\nnever-one.example\n".write(to: neverText, atomically: true, encoding: .utf8)
            let gzip = Process()
            gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            gzip.arguments = ["-kf", neverText.path]
            try? gzip.run()
            gzip.waitUntilExit()
            let gzipList = listDir.appending(path: "never.txt.gz")
            @MainActor func waitRunning() async {
                for _ in 0..<30 where model.engine.state != .running { try? await Task.sleep(for: .milliseconds(100)) }
            }
            func file(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

            await waitRunning()
            let pidBeforeList = model.engine.pid
            let addError = await model.addSubscription(url: plainList, name: "", excluded: false)
            check("subscribing to a local list works", addError == nil, addError ?? "")
            let subscription = model.subscriptions(excluded: false).first { $0.url == plainList.absoluteString }
            check("the list has its name, domain count, and update time",
                  subscription?.displayName == "community.txt" && subscription?.domainCount == 2 && subscription?.lastUpdated != nil,
                  "\(String(describing: subscription?.displayName)) \(String(describing: subscription?.domainCount))")
            let withList = file(Store.hostlistURL)
            check("the hostlist file has My list and the list's sites",
                  withList == "discord.com\nyoutube.com\nblocked-one.example\nblocked-two.example\n", withList)
            check("the PAC file includes a subscribed list's sites", model.pacScript().contains("blocked-two.example"))
            await waitRunning()
            check("tpws restarts with the new sites", model.engine.state == .running && model.engine.pid != pidBeforeList)
            check("a list under Sites to Unblock keeps the same hostlist option in every profile",
                  model.command.arguments.filter { $0 == "--hostlist=\(Store.hostlistURL.path)" }.count == 2)

            let gzipError = await model.addSubscription(url: gzipList, name: "Banks", excluded: true)
            check("subscribing to a gzip list works", gzipError == nil, gzipError ?? "")
            let neverFile = file(Store.excludeURL)
            check("a gzip list under Never Touch reaches the exclude file", neverFile == "apple.com\nnever-one.example\n", neverFile)
            check("the gzip list keeps the name it was given",
                  model.subscriptions(excluded: true).first?.displayName == "Banks")

            if let subscription {
                await waitRunning()
                let steadyPid = model.engine.pid
                await model.updateSubscription(subscription)
                check("updating an unchanged list does not restart tpws", model.engine.pid == steadyPid && model.engine.state == .running)
                check("a good update clears the error and sets the time", subscription.lastError == nil && subscription.lastUpdated != nil)

                // S-071: a failed download keeps the last good list.
                let lastGood = subscription.lastUpdated
                subscription.url = listDir.appending(path: "missing.txt").absoluteString
                await model.updateSubscription(subscription)
                let afterFail = file(Store.hostlistURL)
                check("a failed update keeps the old domains", afterFail == withList && subscription.domainCount == 2, afterFail)
                check("a failed update shows the error on the row", !(subscription.lastError ?? "").isEmpty)
                check("a failed update keeps the last update time", subscription.lastUpdated == lastGood)
                check("a failed update does not restart tpws", model.engine.pid == steadyPid)

                // Turning a list off takes its sites out; deleting it too.
                model.setEnabled(subscription, false)
                check("a list turned off leaves the hostlist file", file(Store.hostlistURL) == "discord.com\nyoutube.com\n")
                model.remove(model.subscriptions())
                check("deleting lists leaves only My list",
                      file(Store.hostlistURL) == "discord.com\nyoutube.com\n" && file(Store.excludeURL) == "apple.com\n")
                await waitRunning()
            }

            model.turnOff()
            check("turning off stops tpws", model.engine.state == .stopped)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// Runs an engine on a `FakeTPWSRunner` through start, output, a crash and
    /// restart, a second crash, and stop.
    private static func checkEngineWithFakeRunner() async {
        let fake = FakeTPWSRunner()
        let engine = Engine(runner: fake)
        var failure: String?
        engine.onFailure = { failure = $0 }
        func settle(until done: () -> Bool) async {
            for _ in 0..<100 where !done() { try? await Task.sleep(for: .milliseconds(20)) }
        }
        let command = TPWSCommand(port: 1, strategy: ["--split-pos=2"], scope: .allSites)
        engine.start(command)
        await settle { engine.state == .running }
        check("a fake tpws that accepts connections is running", engine.state == .running && fake.handles.count == 1,
              "\(engine.state), \(fake.handles.count) starts")
        check("the engine passes its command to the runner", fake.latest?.command == command)
        check("the command line names the runner's tpws", engine.commandLine.hasPrefix("/fake/tpws --socks"), engine.commandLine)

        guard let first = fake.latest else { return }
        first.print(["127.0.0.1:50000 connected from 127.0.0.1:50001", "hostname='fake.example'"])
        await settle { engine.connections > 0 && engine.hostsSeen.contains("fake.example") }
        check("output lines from the runner reach the log", engine.connections == 1 && engine.hostsSeen.contains("fake.example"),
              "\(engine.connections) \(engine.hostsSeen)")

        first.quit(code: 1)
        await settle { fake.handles.count == 2 && engine.state == .running }
        check("a fake tpws quitting by itself is restarted once", engine.autoRestarts == 1 && fake.handles.count == 2
              && engine.state == .running, "\(engine.state), restarts \(engine.autoRestarts), starts \(fake.handles.count)")
        let linesBefore = engine.lines.count
        first.print(["late line from the old tpws"])
        try? await Task.sleep(for: .milliseconds(100))
        check("output from a replaced tpws is ignored", engine.lines.count == linesBefore)

        guard let second = fake.latest else { return }
        second.print(["bind: Address already in use"])
        second.quit(code: 2)
        await settle { failure != nil }
        check("a second quit within a minute fails with the last error", engine.state == .failed("bind: Address already in use")
              && failure == "bind: Address already in use" && fake.handles.count == 2, "\(engine.state)")

        engine.start(command)
        await settle { engine.state == .running }
        guard let third = fake.latest else { return }
        engine.stop()
        try? await Task.sleep(for: .milliseconds(100))
        check("stopping asks the runner to stop and does not restart", third.stopCount == 1 && !third.isRunning
              && engine.state == .stopped && fake.handles.count == 3, "\(engine.state), starts \(fake.handles.count)")

        // A tpws that quits before its port answers fails with its exit code.
        let silent = FakeTPWSRunner()
        silent.ready = false
        let quiet = Engine(runner: silent)
        quiet.start(TPWSCommand(port: 1, strategy: [], scope: .allSites, debug: false))
        check("a fake tpws whose port does not answer stays starting", quiet.state == .starting)
        silent.latest?.quit(code: 3)
        await settle { silent.handles.count == 2 }
        silent.latest?.quit(code: 3)
        await settle { quiet.state != .starting }
        check("quitting twice before ready fails with the exit code", quiet.state == .failed("tpws quit with code 3."),
              "\(quiet.state)")
    }

    /// Fetches a URL with no proxy. Status 0 when nothing answers.
    private static func fetchPAC(_ url: URL) async -> (status: Int, type: String, body: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(from: url), let http = response as? HTTPURLResponse else {
            return (0, "", "")
        }
        return (http.statusCode, http.value(forHTTPHeaderField: "Content-Type") ?? "", String(decoding: data, as: UTF8.self))
    }

    /// Runs a PAC script's FindProxyForURL for a host in JavaScriptCore.
    private static func route(_ script: String, _ host: String) -> String {
        let context = JSContext()
        context?.evaluateScript(script)
        return context?.objectForKeyedSubscript("FindProxyForURL")?
            .call(withArguments: ["https://\(host)/", host])?.toString() ?? "no result"
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
