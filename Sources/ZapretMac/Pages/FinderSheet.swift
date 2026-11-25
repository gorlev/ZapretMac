import SwiftUI
import ZapretMacKit

/// "Find a Strategy": tries every strategy against one or more sites and
/// shows which ones open all of them, fastest first.
struct FinderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var finder: StrategyFinder { model.finder }

    var body: some View {
        @Bindable var prefs = model.prefs
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Find a Strategy").font(.title2.weight(.semibold))
                    Text("ZapretMac opens the site once with each strategy. Your bypass keeps running while it tests.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.lg) {
                        Picker("Scan", selection: $model.finderDepth) {
                            Text("Quick").tag(ScanDepth.quick)
                            Text("Thorough").tag(ScanDepth.thorough)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        if model.finderDepth == .thorough {
                            Picker("Repeat each try", selection: $model.finderRepeats) {
                                Text("Once").tag(1)
                                Text("3 times").tag(3)
                            }
                            .fixedSize()
                            .help("A try works only if it opens the site every time. Three times catches filters that answer unreliably.")
                        }
                        Spacer(minLength: 0)
                    }
                    .disabled(finder.isRunning)
                    Text(depthHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: Space.sm) {
                    TextField("Blocked sites", text: $prefs.finderSites, prompt: Text(verbatim: "discord.com youtube.com"),
                              axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .onSubmit(start)
                        .disabled(finder.isRunning)
                        .help("One site, or several separated by spaces, commas, or new lines. A strategy works only if every site opens.")
                    if finder.isRunning {
                        Button("Stop") { finder.stop() }
                    } else {
                        Button(finder.trials.isEmpty ? String(localized: "Start Test") : String(localized: "Test Again"), action: start)
                            .buttonStyle(.borderedProminent)
                            .disabled(SiteCheck.urls(from: prefs.finderSites).isEmpty || model.prefs.transparentMode)
                    }
                }
                if model.prefs.transparentMode {
                    // pf would send the test connections through the running
                    // tpws too, so every result would be wrong.
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Scans need Transparent mode off: it sends the test connections through the running bypass too.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Turn Off Transparent Mode") { _ = model.setTransparentMode(false) }
                            .controlSize(.small)
                    }
                }
                if finder.direct.count == 1, let direct = finder.direct.first {
                    HStack(spacing: Space.sm) {
                        Text("Without ZapretMac")
                        Spacer()
                        OutcomeLabel(outcome: direct.outcome)
                    }
                    .font(.callout)
                } else if !finder.direct.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Without ZapretMac")
                        ForEach(finder.direct) { direct in
                            HStack(spacing: Space.sm) {
                                Text(verbatim: direct.site)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                OutcomeLabel(outcome: direct.outcome)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                        }
                    }
                    .font(.callout)
                }
                if finder.isDiagnosing && finder.isRunning {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Finding out what kind of block it is…")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                } else {
                    ForEach(verdicts, id: \.kind) { verdict in
                        BlockVerdictLine(kind: verdict.kind, sites: finder.sites.count > 1 ? verdict.sites : [])
                    }
                }
            }
            .padding(Space.xl)

            if !finder.trials.isEmpty {
                Divider()
                List(finder.ranked) { trial in
                    TrialRow(trial: trial) {
                        if trial.isScan {
                            // Short label so it never truncates; the full name is in the
                            // context menu and the tooltip.
                            Button("Save") { model.saveScanRow(trial) }
                                .controlSize(.small)
                                .help("Save as Strategy…")
                        } else {
                            UseButton(inUse: model.prefs.strategyID == trial.id) { model.choose(strategy: trial.id) }
                        }
                    }
                    .contextMenu {
                        if trial.isScan && trial.works {
                            Button("Save as Strategy…") { model.saveScanRow(trial) }
                        }
                    }
                }
                .listStyle(.inset)
                .animation(.default, value: finder.ranked.map(\.id))
                .frame(height: listHeight)
            }

            Divider()
            HStack {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.canAlsoScanHTTP {
                    Button("Also scan HTTP") { model.alsoScanHTTP() }
                        .help("Run the HTTP tries on http:// and the same site")
                }
                if model.joinedScanStrategy != nil && !finder.isRunning {
                    Button("Save HTTP + HTTPS Strategy…") { model.saveJoinedScan() }
                        .help("One strategy: the fastest HTTP try for port 80 and the fastest HTTPS try for port 443")
                }
                Button("Done") {
                    finder.stop()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(Space.lg)
        }
        .frame(width: 520)
        .noInitialFocus()
        // The editor opens on top of this sheet, so the results stay put.
        .sheet(item: $model.finderDraft) { draft in
            StrategyEditor(draft: draft)
                .environment(model)
                .themed()
        }
    }

    /// Rows with flags under the name are taller; past eight rows the list scrolls.
    private var listHeight: CGFloat {
        let row: CGFloat = finder.trials.contains(where: \.isScan) ? 48 : 40
        return min(CGFloat(finder.trials.count) * row, 8 * row)
    }

    private var depthHelp: String {
        switch model.finderDepth {
        case .quick: String(localized: "Tries the built-in strategies and yours.")
        case .thorough: String(localized: "Tries every split and TLS-record combination zapret's blockcheck tests, with TLS 1.3 and TLS 1.2 separately. Takes a few minutes.")
        }
    }

    /// One line per kind of block, worst first, with the sites that have it.
    private var verdicts: [(kind: BlockKind, sites: [String])] {
        BlockKind.allCases.compactMap { kind in
            let sites = finder.diagnoses.filter { $0.kind == kind }.map(\.site)
            return sites.isEmpty ? nil : (kind, sites)
        }
    }

    private var summary: String {
        let done = finder.finishedCount
        let total = finder.trials.count
        if finder.isRunning {
            // Up to three tries run at once, so count the finished ones.
            return String(localized: "\(done) of \(total) tried…")
        }
        if finder.isStopped { return String(localized: "Stopped after \(done) of \(total).") }
        guard finder.isDone else { return "" }
        if finder.sites.count > 1 {
            if finder.workingCount == 0 { return String(localized: "No strategy opened every site.") }
            return String(localized: "\(finder.workingCount) strategies open every site.")
        }
        if finder.workingCount == 0 { return String(localized: "No strategy opened \(finder.site).") }
        return String(localized: "\(finder.workingCount) strategies open \(finder.site).")
    }

    private func start() {
        let urls = SiteCheck.urls(from: model.prefs.finderSites)
        guard !urls.isEmpty, !finder.isRunning else { return }
        model.startFinder(urls: urls)
    }
}

/// One strategy's result. Scan tries show their flags under the name. With
/// several sites, a row where some opened shows how many, and its help lists
/// every site's result.
/// `action` is shown after the time on rows that work (Use, or Save as Strategy… on scan rows).
private struct TrialRow<Action: View>: View {
    let trial: Trial
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: Space.sm) {
            icon.frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(trial.name)
                    .foregroundStyle(trial.status == .waiting ? .secondary : .primary)
                    .lineLimit(1)
                if trial.isScan {
                    Text(verbatim: trial.arguments.joined(separator: " "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if trial.worksOnlyWithTLS13 {
                    Text("Works in browsers; some older apps may not get through.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help("This strategy works with TLS 1.3, which browsers use, but not with TLS 1.2, which some older apps still use.")
                }
            }
            Spacer(minLength: Space.sm)
            if trial.versions.isEmpty {
                trailing
            } else {
                // TLS columns line up from row to row: the result after them has one width.
                TLSMarks(versions: trial.versions)
                HStack(spacing: Space.sm) { trailing }
                    .frame(width: 112, alignment: .trailing)
            }
        }
        .font(.callout)
        .frame(minHeight: 28)
        .help(siteDetails)
    }

    @ViewBuilder private var trailing: some View {
        switch trial.status {
        case .waiting: EmptyView()
        case .testing: Text("Testing…").foregroundStyle(.secondary)
        case .works(let ms):
            // The time and the button keep their size; the name truncates.
            Text("\(ms) ms").foregroundStyle(.secondary).monospacedDigit().fixedSize()
            action().fixedSize()
        case .fails(let reason):
            if trial.isPartial {
                Text("Opened \(trial.openCount) of \(trial.sites.count)").foregroundStyle(.secondary).monospacedDigit().fixedSize()
            } else {
                Text(reason).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    /// Every site's result, one per line, when there are several; the sites
    /// that did not open come first.
    private var siteDetails: String {
        if !trial.versions.isEmpty {
            // Every TLS version's result, with the site names when there are several.
            return trial.versions.flatMap { result in
                result.sites.map { attempt in
                    let label = trial.sites.count > 1 ? "\(result.version.name) · \(attempt.site)" : result.version.name
                    return switch attempt.result {
                    case .opens(let ms): String(localized: "\(label): opens in \(ms) ms")
                    case .fails(let reason): String(localized: "\(label): \(reason)")
                    }
                }
            }.joined(separator: "\n")
        }
        guard trial.sites.count > 1 else { return "" }
        let ordered = trial.failedSites + trial.sites.filter(\.opens)
        return ordered.map { attempt in
            switch attempt.result {
            case .opens(let ms): String(localized: "\(attempt.site): opens in \(ms) ms")
            case .fails(let reason): String(localized: "\(attempt.site): \(reason)")
            }
        }.joined(separator: "\n")
    }

    @ViewBuilder private var icon: some View {
        switch trial.status {
        case .waiting: Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        case .testing: ProgressView().controlSize(.small)
        case .works: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .fails: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

/// "TLS 1.3 ✓  TLS 1.2 ✗": which TLS versions a scan try worked with.
private struct TLSMarks: View {
    let versions: [VersionResult]

    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(versions, id: \.version) { result in
                HStack(spacing: Space.xs) {
                    Text(verbatim: result.version.name)
                    Image(systemName: result.opens ? "checkmark" : "xmark")
                        .foregroundStyle(result.opens ? .green : .red)
                        .accessibilityLabel(result.opens ? Text("works") : Text("fails"))
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

/// The diagnosis of a site (S-101): one line with an icon. With several
/// sites, the ones it applies to are listed under it.
struct BlockVerdictLine: View {
    let kind: BlockKind
    var sites: [String] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: kind.symbol)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(kind.message)
                    .fixedSize(horizontal: false, vertical: true)
                if !sites.isEmpty {
                    Text(verbatim: sites.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var color: AnyShapeStyle {
        switch kind {
        case .dns: AnyShapeStyle(.orange)
        case .ip: AnyShapeStyle(.red)
        case .dpi: AnyShapeStyle(.tint)
        case .none: AnyShapeStyle(.green)
        }
    }
}

private struct UseButton: View {
    let inUse: Bool
    let use: () -> Void

    var body: some View {
        if inUse {
            Label("In use", systemImage: "checkmark")
                .labelStyle(.titleOnly)
                .foregroundStyle(Palette.accentText)
                .frame(width: 56)
        } else {
            Button("Use", action: use)
                .controlSize(.small)
                .frame(width: 56)
        }
    }
}

struct OutcomeLabel: View {
    let outcome: SiteCheck.Outcome

    var body: some View {
        switch outcome {
        case .ok(let status, let ms):
            Label("Opens · \(status) · \(ms) ms", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .monospacedDigit()
        case .failed(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
