import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import ZapretMacKit

/// The two site lists: sites to unblock, and sites never to touch.
struct DomainsPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \DomainEntry.domain) private var all: [DomainEntry]
    @State private var showExcluded = false
    @State private var input = ""
    @State private var selection = Set<PersistentIdentifier>()
    @State private var importing = false
    @State private var note: String?
    @FocusState private var inputFocused: Bool

    private var entries: [DomainEntry] { all.filter { $0.isExcluded == showExcluded } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(selection: $selection) {
                ForEach(entries) { entry in
                    DomainRow(entry: entry)
                        .tag(entry.id)
                        .contextMenu {
                            Button(entry.isEnabled ? "Turn Off" : "Turn On") {
                                entry.isEnabled.toggle()
                                model.listsChanged()
                            }
                            Button(showExcluded ? "Move to Sites to Unblock" : "Move to Never Touch") {
                                entry.isExcluded.toggle()
                                model.listsChanged()
                            }
                            Divider()
                            Button("Delete", role: .destructive) { delete(contextFor: entry) }
                        }
                }
            }
            .onDeleteCommand { model.remove(entries.filter { selection.contains($0.id) }) }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label(showExcluded ? "Nothing Excluded" : "No Sites Yet", systemImage: showExcluded ? "hand.raised" : "globe")
                    } description: {
                        Text(showExcluded
                             ? "Sites here are never changed, even with All sites on. Add banks or sites the strategy breaks."
                             : "Add the sites that do not open, like youtube.com or discord.com. Paste many at once.")
                    }
                }
            }
        }
        .navigationTitle("Sites")
        .toolbar {
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
                Button("Add Sites", systemImage: "plus") { inputFocused = true }
                    .help("Type or paste sites to add (Shift-Command-N)")
            }
            ToolbarItem {
                Button("Delete", systemImage: "trash") {
                    model.remove(entries.filter { selection.contains($0.id) })
                }
                .disabled(selection.isEmpty)
                .help("Delete the selected sites. Undo with Command-Z (Delete)")
            }
        }
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
            note = added == 1 ? "Added 1 site." : "Added \(added) sites."
        }
        .onChange(of: showExcluded) { selection.removeAll(); note = nil }
        .onChange(of: model.addSitesRequest) { inputFocused = true }
        .onAppear { if model.addSitesRequest > 0 { inputFocused = true } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                TextField("Add sites", text: $input,
                          prompt: Text(showExcluded ? "Add a site never to touch, like mybank.com" : "Add sites, like youtube.com discord.com"))
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
                Text(entries.count == 1 ? "1 site" : "\(entries.count) sites")
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
        if parsed == 0 { note = "That does not look like a site address."; return }
        note = count == 0 ? "Already in the list." : (count == 1 ? "Added 1 site." : "Added \(count) sites.")
        input = ""
    }

    private func delete(contextFor entry: DomainEntry) {
        if selection.contains(entry.id) {
            model.remove(entries.filter { selection.contains($0.id) })
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
                .help(entry.isEnabled ? "On: tpws uses this site" : "Off: kept in the list but not used")
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
