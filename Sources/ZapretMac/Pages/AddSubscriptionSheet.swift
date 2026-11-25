import SwiftUI
import ZapretMacKit

/// Takes the address of a site list, downloads it, and adds it under Sites.
/// Typing the address is its only job, so the address field starts focused.
struct AddSubscriptionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var name = ""
    @State private var excluded = false
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
                    Picker("Add to", selection: $excluded) {
                        Text("Sites to Unblock").tag(false)
                        Text("Never Touch").tag(true)
                    }
                } footer: {
                    Text("A text file with one domain per line, like zapret's lists. Lines starting with # are skipped, and gzip files work. ZapretMac downloads it again every day.")
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
            }
            .formStyle(.grouped)
            .fitsContent(max: 420)
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
        .frame(width: 480)
        .onAppear {
            excluded = model.addSubscriptionExcluded
            addressFocused = true
        }
        .onChange(of: address) { error = nil }
    }

    private func add() {
        guard let url, !downloading else { return }
        downloading = true
        error = nil
        Task {
            let failure = await model.addSubscription(url: url, name: name, excluded: excluded)
            downloading = false
            if let failure { error = failure } else { dismiss() }
        }
    }
}
