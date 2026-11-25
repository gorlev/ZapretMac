import AppKit
import Foundation
import SwiftData
import ZapretMacKit

/// A site list someone else keeps, downloaded from an address and used
/// together with My list (S-070). Its cleaned domains live in
/// `Store.subscriptionURL(uuid)`; the row keeps what the list shows.
@Model
final class ListSubscription {
    var url: String = ""
    /// Empty: the name comes from the address.
    var name: String = ""
    /// false: feeds "Sites to unblock". true: feeds "Never touch".
    var isExcluded: Bool = false
    var isEnabled: Bool = true
    var domainCount: Int = 0
    var lastUpdated: Date?
    /// Why the last download failed, or nil after a good one.
    var lastError: String?
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()

    init(url: String, name: String = "", isExcluded: Bool = false) {
        self.url = url
        self.name = name
        self.isExcluded = isExcluded
    }

    var displayName: String {
        if !name.isEmpty { return name }
        return URL(string: url).map(SiteListSubscription.defaultName) ?? url
    }
}

extension AppModel {
    private var context: ModelContext { container.mainContext }

    func subscriptions(excluded: Bool? = nil) -> [ListSubscription] {
        let all = (try? context.fetch(FetchDescriptor<ListSubscription>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        guard let excluded else { return all }
        return all.filter { $0.isExcluded == excluded }
    }

    /// The last good download of a list, or nothing before the first one.
    func subscriptionDomains(_ subscription: ListSubscription) -> [String] {
        let text = (try? String(contentsOf: Store.subscriptionURL(subscription.uuid), encoding: .utf8)) ?? ""
        return SiteListSubscription.readFile(text)
    }

    func requestAddSubscription(excluded: Bool? = nil) {
        sidebar = .domains
        if let excluded { addSubscriptionExcluded = excluded }
        showAddSubscription = true
    }

    /// Downloads a list and adds it when the download works. Returns why it
    /// did not, for the sheet to show; a list that never downloaded is not added.
    func addSubscription(url: URL, name: String, excluded: Bool) async -> String? {
        if subscriptions(excluded: excluded).contains(where: { $0.url == url.absoluteString }) {
            return String(localized: "This list is already in your subscriptions.")
        }
        do {
            let domains = try await Self.download(url)
            let subscription = ListSubscription(url: url.absoluteString,
                                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                isExcluded: excluded)
            try Domains.fileContents(domains).write(to: Store.subscriptionURL(subscription.uuid), atomically: true, encoding: .utf8)
            subscription.domainCount = domains.count
            subscription.lastUpdated = .now
            context.insert(subscription)
            try? context.save()
            context.undoManager?.setActionName(String(localized: "Add Subscription"))
            subscriptionsChanged()
            return nil
        } catch {
            return Self.message(for: error)
        }
    }

    /// Downloads a list again. A failed download keeps the last good file
    /// and puts the error on the row; tpws restarts only if domains changed.
    func updateSubscription(_ subscription: ListSubscription) async {
        let id = subscription.uuid
        guard !updatingSubscriptions.contains(id), let url = URL(string: subscription.url) else { return }
        updatingSubscriptions.insert(id)
        defer { updatingSubscriptions.remove(id) }
        let result: Result<[String], Error>
        do { result = .success(try await Self.download(url)) } catch { result = .failure(error) }
        // Deleted while it downloaded: nothing to update.
        guard !subscription.isDeleted, subscription.modelContext != nil else { return }
        // A background refresh is not something to undo.
        context.undoManager?.disableUndoRegistration()
        defer { context.undoManager?.enableUndoRegistration() }
        switch result {
        case .success(let domains):
            do {
                try Domains.fileContents(domains).write(to: Store.subscriptionURL(id), atomically: true, encoding: .utf8)
                subscription.domainCount = domains.count
                subscription.lastUpdated = .now
                subscription.lastError = nil
            } catch {
                subscription.lastError = error.localizedDescription
            }
        case .failure(let error):
            subscription.lastError = Self.message(for: error)
        }
        try? context.save()
        subscriptionsChanged()
    }

    func updateAllSubscriptions() {
        for subscription in subscriptions() { Task { await updateSubscription(subscription) } }
    }

    /// The turned-on lists whose last download is a day old.
    func updateDueSubscriptions() {
        for subscription in subscriptions() where subscription.isEnabled
            && SiteListSubscription.isDue(lastUpdated: subscription.lastUpdated) {
            Task { await updateSubscription(subscription) }
        }
    }

    func setEnabled(_ subscription: ListSubscription, _ on: Bool) {
        subscription.isEnabled = on
        try? context.save()
        subscriptionsChanged()
    }

    /// Deletes rows; Edit > Undo brings them back with their downloaded file.
    func remove(_ subscriptions: [ListSubscription]) {
        guard !subscriptions.isEmpty else { return }
        for subscription in subscriptions { context.delete(subscription) }
        try? context.save()
        context.undoManager?.setActionName(subscriptions.count == 1
            ? String(localized: "Delete Subscription") : String(localized: "Delete \(subscriptions.count) Subscriptions"))
        subscriptionsChanged()
    }

    /// Rewrites the hostlist files and restarts tpws only when they changed.
    func subscriptionsChanged() {
        if writeLists() { restartIfRunning() }
    }

    /// Daily refresh while the app runs: checked at launch, every hour, and
    /// after the Mac wakes. Test and snapshot runs refresh only on request.
    func startSubscriptionSchedule() {
        guard !Store.isOverridden, subscriptionTimer == nil else { return }
        removeOrphanSubscriptionFiles()
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDueSubscriptions() }
        }
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        subscriptionTimer = timer
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // The network comes back a little after the Mac wakes.
                _ = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    self?.updateDueSubscriptions()
                }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.updateDueSubscriptions()
        }
    }

    /// Files of lists deleted in an earlier run (Undo cannot bring them back now).
    private func removeOrphanSubscriptionFiles() {
        let dir = Store.subscriptionURL(UUID()).deletingLastPathComponent()
        let known = Set(subscriptions().map { "\($0.uuid.uuidString).txt" })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for file in files where !known.contains(file) {
            try? FileManager.default.removeItem(at: dir.appending(path: file))
        }
    }

    // MARK: - Download

    private enum DownloadError: Error { case status(Int) }

    /// Reads a list from the web or a local file and cleans it, off the main thread.
    private static func download(_ url: URL) async throws -> [String] {
        let data: Data
        if url.isFileURL {
            data = try await Task.detached { try Data(contentsOf: url) }.value
        } else {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            let (body, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw DownloadError.status(http.statusCode)
            }
            data = body
        }
        return try await Task.detached { try SiteListSubscription.domains(from: data) }.value
    }

    private static func message(for error: Error) -> String {
        switch error {
        case DownloadError.status(let code): String(localized: "The server answered with error \(code).")
        case SiteListSubscription.Failure.notText: String(localized: "This address is not a site list.")
        case SiteListSubscription.Failure.empty: String(localized: "The list has no sites in it.")
        case SiteListSubscription.Failure.tooLarge: String(localized: "The list is too large.")
        case is Gzip.Failure: String(localized: "The gzip file is damaged.")
        default: error.localizedDescription
        }
    }
}
