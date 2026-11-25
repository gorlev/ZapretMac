import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import ZapretMacKit

/// The two site lists: sites to unblock, and sites never to touch.
struct DomainsPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \DomainEntry.domain) private var all: [DomainEntry]
    @Query(sort: \ListSubscription.createdAt) private var allSubscriptions: [ListSubscription]
    @State private var showExcluded = false
    @State private var input = ""
    @State private var selection = Set<PersistentIdentifier>()
    @State private var importing = false
    @State private var note: String?
    @FocusState private var inputFocused: Bool

    private var entries: [DomainEntry] { all.filter { $0.isExcluded == showExcluded } }
    private var subscriptions: [ListSubscription] { allSubscriptions.filter { $0.isExcluded == showExcluded } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(selection: $selection) {
                if !subscriptions.isEmpty {
                    Section("Subscriptions") {
                        ForEach(subscriptions) { subscription in
                            SubscriptionRow(subscription: subscription)
                                .tag(subscription.id)
                                .contextMenu { subscriptionMenu(subscription) }
                        }
                    }
                }
                Section {
                    sites
                } header: {
                    if !subscriptions.isEmpty { Text("My List") }
                }
            }
            .onDeleteCommand(perform: deleteSelection)
            .overlay {
                if entries.isEmpty && subscriptions.isEmpty {
                    ContentUnavailableView {
                        Label(showExcluded ? String(localized: "Nothing Excluded") : String(localized: "No Sites Yet"), systemImage: showExcluded ? "hand.raised" : "globe")
                    } description: {
                        Text(showExcluded
                             ? String(localized: "Sites here are never changed, even with All sites on. Add banks or sites the strategy breaks.")
                             : String(localized: "Add the sites that do not open, like youtube.com or discord.com. Paste many at once."))
                    } actions: {
                        Button("Add Subscription…") { model.requestAddSubscription(excluded: showExcluded) }
                    }
                }
            }
        }
        .navigationTitle("Sites")
        .toolbar { toolbar }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            var added = 0
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    added += model.addDomains(from: text, excluded: showExcluded)
                }
            }
            note = String(localized: "Added \(added) sites.")
        }
        .onChange(of: showExcluded) { selection.removeAll(); note = nil; model.addSubscriptionExcluded = showExcluded }
        .onChange(of: model.addSitesRequest) { inputFocused = true }
        .onAppear {
            model.addSubscriptionExcluded = showExcluded
            if model.addSitesRequest > 0 { inputFocused = true }
        }
    }

    @ViewBuilder private var sites: some View {
        ForEach(entries) { entry in
            DomainRow(entry: entry)
                .tag(entry.id)
                .contextMenu {
                    Button(entry.isEnabled ? String(localized: "Turn Off") : String(localized: "Turn On")) {
                        entry.isEnabled.toggle()
                        model.listsChanged()
                    }
                    Button(showExcluded ? String(localized: "Move to Sites to Unblock") : String(localized: "Move to Never Touch")) {
                        entry.isExcluded.toggle()
                        model.listsChanged()
                    }
                    Divider()
                    Button("Delete", role: .destructive) { delete(contextFor: entry) }
                }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("List", selection: $showExcluded) {
                Text("Sites to Unblock").tag(false)
                Text("Never Touch").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        ToolbarItem {
            Button("Import", systemImage: "square.and.arrow.down") { importing = true }
                .help("Add every domain in a text file, one per line")
        }
        ToolbarItem {
            Button("Add Subscription", systemImage: "link.badge.plus") { model.requestAddSubscription(excluded: showExcluded) }
                .help("Subscribe to a site list on the web; it updates every day (Option-Command-N)")
        }
        ToolbarItem {
            Button("Add Sites", systemImage: "plus") { inputFocused = true }
                .help("Type or paste sites to add (Shift-Command-N)")
        }
        ToolbarItem {
            Button("Delete", systemImage: "trash", action: deleteSelection)
                .disabled(selection.isEmpty)
                .help("Delete the selected sites. Undo with Command-Z (Delete)")
        }
    }

    @ViewBuilder private func subscriptionMenu(_ subscription: ListSubscription) -> some View {
        Button("Update Now") { Task { await model.updateSubscription(subscription) } }
            .disabled(model.updatingSubscriptions.contains(subscription.uuid))
        Button(subscription.isEnabled ? String(localized: "Turn Off") : String(localized: "Turn On")) {
            model.setEnabled(subscription, !subscription.isEnabled)
        }
        Button("Copy Address") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(subscription.url, forType: .string)
        }
        Divider()
        Button("Delete", role: .destructive) {
            if selection.contains(subscription.id) { deleteSelection() } else { model.remove([subscription]) }
        }
    }

    private func deleteSelection() {
        let subs = subscriptions.filter { selection.contains($0.id) }
        let sites = entries.filter { selection.contains($0.id) }
        if !subs.isEmpty { model.remove(subs) }
        if !sites.isEmpty { model.remove(sites) }
        selection.removeAll()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                TextField("Add sites", text: $input,
                          prompt: Text(showExcluded ? String(localized: "Add a site never to touch, like mybank.com") : String(localized: "Add sites, like youtube.com discord.com")))
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(Domains.parseList(input).isEmpty)
            }
            HStack(spacing: Space.xs) {
                if let note {
                    Text(note).foregroundStyle(Palette.accentText)
                } else if showExcluded {
                    Text("Sites here always go straight through, whatever the strategy.")
                        .foregroundStyle(.secondary)
                } else if model.prefs.scope == .allSites {
                    Text("The bypass is on for all sites now. This list is used when Sites is set to My list.")
                        .foregroundStyle(.secondary)
                    Button("Use My List") { model.prefs.scope = .listOnly; model.restartIfRunning() }
                        .buttonStyle(.link)
                } else {
                    Text("Only these sites go through the bypass. Subdomains are included.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entries.count) sites")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.md)
        .gridArea("domains-header", inset: Space.md)
    }

    private func add() {
        let count = model.addDomains(from: input, excluded: showExcluded)
        let parsed = Domains.parseList(input).count
        if parsed == 0 { note = String(localized: "That does not look like a site address."); return }
        note = count == 0 ? String(localized: "Already in the list.") : String(localized: "Added \(count) sites.")
        input = ""
    }

    private func delete(contextFor entry: DomainEntry) {
        if selection.contains(entry.id) {
            deleteSelection()
        } else {
            model.remove([entry])
        }
    }
}

private struct DomainRow: View {
    @Environment(AppModel.self) private var model
    @Bindable var entry: DomainEntry

    var body: some View {
        HStack(spacing: Space.sm) {
            Toggle("", isOn: Binding(get: { entry.isEnabled },
                                     set: { entry.isEnabled = $0; model.listsChanged() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(entry.isEnabled ? String(localized: "On: tpws uses this site") : String(localized: "Off: kept in the list but not used"))
            Image(systemName: entry.isExcluded ? "hand.raised.fill" : "globe")
                .foregroundStyle(entry.isEnabled ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.tertiary))
                .frame(width: 20)
            Text(entry.domain)
                .foregroundStyle(entry.isEnabled ? .primary : .secondary)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

/// A subscribed list: its name, how many sites it has, and when it was last
/// downloaded, or why the last download failed.
private struct SubscriptionRow: View {
    @Environment(AppModel.self) private var model
    @Bindable var subscription: ListSubscription

    private var isUpdating: Bool { model.updatingSubscriptions.contains(subscription.uuid) }

    var body: some View {
        HStack(spacing: Space.sm) {
            Toggle("", isOn: Binding(get: { subscription.isEnabled },
                                     set: { model.setEnabled(subscription, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(subscription.isEnabled ? String(localized: "On: tpws uses the sites in this list") : String(localized: "Off: kept but not used"))
            Image(systemName: "link")
                .foregroundStyle(subscription.isEnabled ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.tertiary))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(subscription.displayName)
                    .foregroundStyle(subscription.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                status
                    .font(.caption)
                    .lineLimit(1)
            }
            .help(subscription.url)
            Spacer(minLength: Space.sm)
            if isUpdating {
                ProgressView().controlSize(.small)
            } else {
                Button("Update Now", systemImage: "arrow.clockwise") {
                    Task { await model.updateSubscription(subscription) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Download this list again")
            }
            Text("\(subscription.domainCount) sites")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var status: some View {
        if isUpdating {
            Text("Downloading…").foregroundStyle(.secondary)
        } else if let error = subscription.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(error)
        } else if let date = subscription.lastUpdated {
            Text("Updated \(Text(date, format: .relative(presentation: .named)))")
                .foregroundStyle(.secondary)
        }
    }
}
