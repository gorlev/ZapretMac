import SwiftUI
import ZapretMacKit

/// Takes the address of a site list, downloads it, and adds it under Sites.
/// Typing the address is its main job, so the address field starts focused.
/// Below it, known community lists fill the form in one click (S-106).
struct AddSubscriptionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var name = ""
    @State private var excluded = false
    @State private var kind: ListKind = .domains
    @State private var downloading = false
    @State private var error: String?
    @FocusState private var addressFocused: Bool

    private var url: URL? { SiteListSubscription.url(from: address) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Address", text: $address, prompt: Text(verbatim: "https://example.com/list.txt"))
                        .focused($addressFocused)
                        .onSubmit(add)
                    TextField("Name", text: $name,
                              prompt: Text(url.map(SiteListSubscription.defaultName) ?? String(localized: "From the address")))
                    Picker("Kind", selection: $kind) {
                        Text("Sites").tag(ListKind.domains)
                        Text("IP Addresses").tag(ListKind.addresses)
                    }
                    Picker("Add to", selection: $excluded) {
                        Text("Sites to Unblock").tag(false)
                        Text("Never Touch").tag(true)
                    }
                } footer: {
                    Group {
                        if kind == .domains {
                            Text("A text file with one domain per line, like zapret's lists. Lines starting with # are skipped, and gzip files work. ZapretMac downloads it again every day.")
                        } else {
                            Text("A text file with one IP address or range per line, like 203.0.113.0/24 or 2001:db8::/32. Lines starting with # are skipped, and gzip files work. ZapretMac downloads it again every day.")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if !address.isEmpty && url == nil {
                    Label("Enter an address that starts with https://", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    ForEach(SuggestedLists.all) { list in
                        SuggestionRow(list: list, isChosen: url == list.url) { choose(list) }
                    }
                } header: {
                    Text("Suggested Lists")
                } footer: {
                    Text("Lists that zapret's own scripts download. Choose one to fill in the form.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 640)
            Divider()
            HStack {
                if downloading {
                    ProgressView().controlSize(.small)
                    Text("Downloading…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Subscribe", action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(url == nil || downloading)
            }
            .padding(Space.lg)
        }
        .frame(width: 520)
        .onAppear {
            excluded = model.addSubscriptionExcluded
            if let suggestion = model.addSubscriptionSuggestion {
                choose(suggestion)
                model.addSubscriptionSuggestion = nil
            }
            addressFocused = true
        }
        .onChange(of: address) { error = nil }
        .onChange(of: kind) { error = nil }
    }

    /// Fills the form with a suggested list; Subscribe still downloads it.
    private func choose(_ list: SuggestedList) {
        address = list.url.absoluteString
        name = list.name
        kind = list.kind
        excluded = false
        error = nil
    }

    private func add() {
        guard let url, !downloading else { return }
        downloading = true
        error = nil
        Task {
            let failure = await model.addSubscription(url: url, name: name, excluded: excluded, kind: kind)
            downloading = false
            if let failure { error = failure } else { dismiss() }
        }
    }
}

/// One suggested list: what it holds, and the country it is for. Clicking
/// the row fills the form; the arrow opens the list's page.
private struct SuggestionRow: View {
    let list: SuggestedList
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: choose) {
                HStack(spacing: Space.sm) {
                    Image(systemName: list.kind == .domains ? "globe" : "number")
                        .foregroundStyle(Palette.accentText)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: list.name)
                            .foregroundStyle(.primary)
                        Text(list.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.sm)
                    if isChosen {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Palette.accentText)
                            .accessibilityLabel(Text("Chosen"))
                    }
                    if let country = list.countryName {
                        Text(country)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(list.summary)
            .accessibilityHint(list.kind == .domains ? Text("A list of sites") : Text("A list of IP addresses"))
            Link(destination: list.source) {
                Label("Open the List's Page", systemImage: "arrow.up.right.square")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(list.source.absoluteString)
        }
    }
}
