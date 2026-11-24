import AppKit
import SwiftUI
import ZapretMacKit

/// tpws's own output, live, with a filter.
struct LogPage: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var follow = true

    enum Filter: String, CaseIterable, Identifiable {
        case all, sites, errors
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .sites: "Sites"
            case .errors: "Errors"
            }
        }
    }

    private var visible: [LogLine] {
        model.engine.lines.filter { line in
            let kindOK = switch filter {
            case .all: true
            case .sites: line.kind == .target
            case .errors: line.kind == .error
            }
            return kindOK && (search.isEmpty || line.text.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visible) { line in
                            LogRow(line: line).id(line.id)
                        }
                    }
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .onChange(of: model.engine.lines.last?.id) {
                    if follow, let last = visible.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onAppear {
                    if let last = visible.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .background(.background)
            .overlay {
                if model.engine.lines.isEmpty {
                    ContentUnavailableView("No Output Yet", systemImage: "text.alignleft",
                                           description: Text("Turn the bypass on to see what tpws is doing."))
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            if !model.engine.commandLine.isEmpty { commandBar }
        }
        .navigationTitle("Log")
        .searchable(text: $search, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem {
                Toggle(isOn: $follow) {
                    Label("Follow", systemImage: "arrow.down.to.line")
                }
                .help("Keep the newest line in view")
            }
            ToolbarItem {
                Menu {
                    Button("Copy Lines") { copy(visible.map(\.text).joined(separator: "\n")) }
                        .disabled(visible.isEmpty)
                    Button("Copy tpws Command") { copy(model.engine.commandLine) }
                        .disabled(model.engine.commandLine.isEmpty)
                } label: {
                    Label("Copy", systemImage: "document.on.document")
                } primaryAction: {
                    copy(visible.map(\.text).joined(separator: "\n"))
                }
                .help("Copy the lines shown. Hold for the tpws command")
                .disabled(visible.isEmpty && model.engine.commandLine.isEmpty)
            }
            ToolbarItem {
                Button("Clear", systemImage: "trash") { model.engine.clearLog() }
                    .help("Clear the log")
                    .disabled(model.engine.lines.isEmpty)
            }
        }
    }

    private var commandBar: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(model.engine.commandLine)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Text(visible.count == 1 ? "1 line" : "\(visible.count) lines")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contextMenu {
            Button("Copy tpws Command") { copy(model.engine.commandLine) }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct LogRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text(line.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .foregroundStyle(.tertiary)
            Text(line.text)
                .foregroundStyle(color)
                .fontWeight(line.kind == .target ? .medium : .regular)
        }
        .font(.callout.monospaced())
    }

    private var color: Color {
        switch line.kind {
        case .error: .red
        case .target: .primary
        case .connection: .secondary
        case .info: .secondary
        }
    }
}
