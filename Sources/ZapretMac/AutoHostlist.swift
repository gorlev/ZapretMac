import Foundation
import SwiftData
import ZapretMacKit

/// S-100: tpws builds part of the site list by itself. With the option on and
/// Sites set to My list, tpws gets `--hostlist-auto` and appends a site to
/// `Store.autoHostlistURL` after it fails a few times in a short while; the
/// bypass then acts on it. The app reads that file and lets people move,
/// delete, or clear its sites.
extension AppModel {
    /// tpws runs as root in Transparent mode and would write the file as root.
    var autoHostlistAvailable: Bool { !prefs.transparentMode }

    func setAutoHostlist(_ on: Bool) {
        guard prefs.autoHostlist != on else { return }
        prefs.autoHostlist = on
        restartIfRunning()
    }

    /// The section shows while the option is on or the file still has sites.
    var showsAutoSites: Bool { prefs.autoHostlist || !autoSites.isEmpty }

    private func autoFileText() -> String {
        (try? String(contentsOf: Store.autoHostlistURL, encoding: .utf8)) ?? ""
    }

    /// Reads the file again; the Sites page calls this while it is open.
    func reloadAutoSites() {
        let sites = AutoHostlistFile.sites(in: autoFileText())
        if sites != autoSites { autoSites = sites }
    }

    /// Moves sites from the automatic list to My list (excluded false) or Never Touch.
    func moveAutoSites(_ sites: [String], excluded: Bool) {
        guard !sites.isEmpty else { return }
        removeFromAutoFile(Set(sites))
        // New rows rewrite the lists and restart tpws; sites already in the
        // list only left the automatic file, which tpws must read again.
        if addDomains(from: sites.joined(separator: "\n"), excluded: excluded) == 0 { restartIfRunning() }
        context.undoManager?.setActionName(excluded
            ? String(localized: "Move \(sites.count) Sites to Never Touch")
            : String(localized: "Move \(sites.count) Sites to My List"))
    }

    func deleteAutoSites(_ sites: [String]) {
        guard !sites.isEmpty else { return }
        removeFromAutoFile(Set(sites))
        context.undoManager?.setActionName(String(localized: "Delete \(sites.count) Sites"))
        restartIfRunning()
    }

    func clearAutoSites() {
        guard !autoSites.isEmpty else { return }
        removeFromAutoFile(Set(autoSites))
        context.undoManager?.setActionName(String(localized: "Clear Automatically Added Sites"))
        restartIfRunning()
    }

    private var context: ModelContext { container.mainContext }

    private func removeFromAutoFile(_ removed: Set<String>) {
        let old = autoFileText()
        writeAutoFile(AutoHostlistFile.contents(of: old, removing: removed), undoText: old)
    }

    /// Writes the file and lets Edit > Undo put the old text back.
    private func writeAutoFile(_ text: String, undoText: String) {
        context.undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.writeAutoFile(undoText, undoText: model.autoFileText())
            }
        }
        try? text.write(to: Store.autoHostlistURL, atomically: true, encoding: .utf8)
        reloadAutoSites()
    }
}
