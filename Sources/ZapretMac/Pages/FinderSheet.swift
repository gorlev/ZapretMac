import SwiftUI
import ZapretMacKit

/// "Find a Strategy": tries every strategy against one site and shows which
/// ones open it, fastest first.
struct FinderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var finder: StrategyFinder { model.finder }

    var body: some View {
        @Bindable var prefs = model.prefs
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Find a Strategy").font(.title2.weight(.semibold))
                    Text("ZapretMac opens the site once with each strategy. Your bypass keeps running while it tests.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Space.sm) {
                    TextField("Blocked site", text: $prefs.testURL, prompt: Text("discord.com"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(start)
                        .disabled(finder.isRunning)
                    if finder.isRunning {
                        Button("Stop") { finder.stop() }
                    } else {
                        Button(finder.trials.isEmpty ? "Start Test" : "Test Again", action: start)
                            .buttonStyle(.borderedProminent)
                            .disabled(SiteCheck.url(from: prefs.testURL) == nil)
                    }
                }
                if let direct = finder.direct {
                    HStack(spacing: Space.sm) {
                        Text("Without ZapretMac")
                        Spacer()
                        OutcomeLabel(outcome: direct)
                    }
                    .font(.callout)
                }
            }
            .padding(Space.xl)

            if !finder.trials.isEmpty {
                Divider()
                List(finder.ranked) { trial in
                    TrialRow(trial: trial, inUse: model.prefs.strategyID == trial.id) {
                        model.choose(strategy: trial.id)
                    }
                }
                .listStyle(.inset)
                .animation(.default, value: finder.ranked.map(\.id))
                .frame(height: CGFloat(min(finder.trials.count, 8)) * 40)
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

    private var summary: String {
        if finder.isRunning {
            let done = finder.trials.filter { $0.status != .waiting && $0.status != .testing }.count
            return "Testing \(done + 1) of \(finder.trials.count)…"
        }
        guard finder.isDone else { return "" }
        switch finder.workingCount {
        case 0: return "No strategy opened \(finder.site)."
        case 1: return "1 strategy opens \(finder.site)."
        default: return "\(finder.workingCount) strategies open \(finder.site)."
        }
    }

    private func start() {
        guard let url = SiteCheck.url(from: model.prefs.testURL), !finder.isRunning else { return }
        model.startFinder(url: url)
    }
}

private struct TrialRow: View {
    let trial: Trial
    let inUse: Bool
    let use: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            icon.frame(width: 20)
            Text(trial.name)
                .foregroundStyle(trial.status == .waiting ? .secondary : .primary)
            Spacer()
            switch trial.status {
            case .waiting: EmptyView()
            case .testing: Text("Testing…").foregroundStyle(.secondary)
            case .works(let ms):
                Text("\(ms) ms").foregroundStyle(.secondary).monospacedDigit()
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
            case .fails(let reason): Text(reason).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(height: 28)
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
