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
                    Picker("Scan", selection: $model.finderDepth) {
                        Text("Quick").tag(ScanDepth.quick)
                        Text("Thorough").tag(ScanDepth.thorough)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
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
                            .disabled(SiteCheck.urls(from: prefs.finderSites).isEmpty)
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
            }
            .padding(Space.xl)

            if !finder.trials.isEmpty {
                Divider()
                List(finder.ranked) { trial in
                    TrialRow(trial: trial) {
                        if !trial.isScan {
                            UseButton(inUse: model.prefs.strategyID == trial.id) { model.choose(strategy: trial.id) }
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
    }

    /// Rows with flags under the name are taller; past eight rows the list scrolls.
    private var listHeight: CGFloat {
        let row: CGFloat = finder.trials.contains(where: \.isScan) ? 48 : 40
        return min(CGFloat(finder.trials.count) * row, 8 * row)
    }

    private var depthHelp: String {
        switch model.finderDepth {
        case .quick: String(localized: "Tries the built-in strategies and yours.")
        case .thorough: String(localized: "Tries every split and TLS-record combination zapret's blockcheck tests. Takes a few minutes.")
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
/// `action` is shown after the time on rows that work (Use, and later Save).
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
            }
            .layoutPriority(1)
            Spacer(minLength: Space.sm)
            switch trial.status {
            case .waiting: EmptyView()
            case .testing: Text("Testing…").foregroundStyle(.secondary)
            case .works(let ms):
                Text("\(ms) ms").foregroundStyle(.secondary).monospacedDigit()
                action()
            case .fails(let reason):
                if trial.isPartial {
                    Text("\(trial.openCount) of \(trial.sites.count) sites").foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text(reason).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .font(.callout)
        .frame(minHeight: 28)
        .help(siteDetails)
    }

    /// Every site's result, one per line, when there are several; the sites
    /// that did not open come first.
    private var siteDetails: String {
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
