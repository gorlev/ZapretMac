import SwiftUI
import ZapretMacKit

/// The sheet for making or changing a strategy, with every common tpws
/// option as a control and a live preview of the flags.
struct StrategyEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StrategyDraft
    @State private var extraText: String
    @State private var check: (ok: Bool, message: String)?
    @State private var checking = false

    init(draft: StrategyDraft) {
        _draft = State(initialValue: draft)
        _extraText = State(initialValue: draft.options.extra.joined(separator: " "))
    }

    private var options: StrategyOptions {
        var o = draft.options
        o.extra = CommandLineWords.split(extraText)
        return o
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("My Provider"))
                }
                Section {
                    TextField("Split at", text: $draft.options.splitPositions, prompt: Text("1,midsld"))
                        .help("Where to cut the first packet. A number is a byte offset; markers: method, host, endhost, sld, midsld, endsld, sniext. Add +N or -N.")
                    TextField("TLS record split", text: $draft.options.tlsRecord, prompt: Text("sniext+1"))
                        .help("Cut the TLS hello into two records at this position.")
                    Toggle("Send pieces out of order (disorder)", isOn: $draft.options.disorder)
                    Toggle("Add an out-of-band byte (oob)", isOn: $draft.options.oob)
                    Toggle("Split every protocol, not only HTTP and TLS", isOn: $draft.options.splitAnyProtocol)
                } header: {
                    Text("Splitting")
                } footer: {
                    Text("Markers: sld is the site name, midsld its middle, sniext the TLS server-name field.")
                        .foregroundStyle(.secondary)
                }
                Section("HTTP header tricks") {
                    Grid(alignment: .leading, horizontalSpacing: Space.xl, verticalSpacing: Space.sm) {
                        GridRow {
                            Toggle("host: lowercase", isOn: $draft.options.hostCase)
                            Toggle("MiXeD domain case", isOn: $draft.options.domainCase)
                        }
                        GridRow {
                            Toggle("Dot after host", isOn: $draft.options.hostDot)
                            Toggle("Tab after host", isOn: $draft.options.hostTab)
                        }
                        GridRow {
                            Toggle("No space after Host:", isOn: $draft.options.hostNoSpace)
                            Toggle("Line break before method", isOn: $draft.options.methodEOL)
                        }
                        GridRow {
                            Toggle("Extra space after method", isOn: $draft.options.methodSpace)
                            Toggle("Unix line endings", isOn: $draft.options.unixEOL)
                        }
                    }
                }
                Section {
                    TextField("Only these ports", text: $draft.options.tcpPorts, prompt: Text("80,443"))
                    LabeledContent("More tpws flags") {
                        TextField("More tpws flags", text: $extraText, prompt: Text("--mss=88"), axis: .vertical)
                            .labelsHidden()
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1...3)
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Any tpws desync flag works here. See zapret's documentation for the full list.")
                        .foregroundStyle(.secondary)
                }
                Section("Command") {
                    Text(options.commandLine.isEmpty ? "No flags: traffic is passed through unchanged." : options.commandLine)
                        .font(.callout.monospaced())
                        .foregroundStyle(options.commandLine.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Button("Check with tpws") { runCheck() }
                            .disabled(checking)
                        Button("Paste Flags") { pasteFlags() }
                            .help("Replace the options with tpws flags from the clipboard")
                        if checking { ProgressView().controlSize(.small) }
                        if let check {
                            Label(check.message, systemImage: check.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(check.ok ? .green : .red)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 520)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.editing == nil ? "Create" : "Save") {
                    var final = draft
                    final.options = options
                    model.save(final)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Space.lg)
        }
        .frame(width: 560)
        .noInitialFocus()
        .onChange(of: options) { check = nil }
    }

    private func pasteFlags() {
        guard let pasted = model.clipboardFlags else { NSSound.beep(); return }
        draft.options = pasted
        extraText = pasted.extra.joined(separator: " ")
    }

    private func runCheck() {
        checking = true
        let args = options.arguments
        Task {
            let result = await Engine.dryRun(args)
            let message = result.ok
                ? "tpws accepts these flags."
                : result.output.split(whereSeparator: \.isNewline).last(where: { !$0.isEmpty }).map(String.init) ?? "tpws refused these flags."
            check = (result.ok, message)
            checking = false
        }
    }
}
