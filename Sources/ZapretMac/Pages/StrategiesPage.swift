import SwiftData
import SwiftUI
import ZapretMacKit

/// Every strategy as a card. Click one to use it.
struct StrategiesPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \CustomStrategy.createdAt) private var custom: [CustomStrategy]

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 400), spacing: Space.lg, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                section("Built-in", caption: "Ready-made strategies from zapret. Start with the first one; if a site still does not open, try the next.") {
                    ForEach(Preset.all) { preset in
                        let id = "preset:\(preset.id)"
                        StrategyCard(name: preset.name, symbol: preset.symbol, blurb: preset.blurb,
                                     commandLine: preset.commandLine, selected: model.prefs.strategyID == id) {
                            model.choose(strategy: id)
                        }
                        .contextMenu {
                            Button("Use") { model.choose(strategy: id) }
                            Button("Copy Flags") { model.copyFlags(preset.commandLine) }
                            Button("Duplicate and Edit…") {
                                model.newStrategy(from: preset.options, name: "\(preset.name) Copy")
                            }
                        }
                    }
                }
                section("Yours", caption: "Strategies you made from tpws options.") {
                    ForEach(custom) { strategy in
                        StrategyCard(name: strategy.name, symbol: "person.crop.circle",
                                     blurb: strategy.options.summary, commandLine: strategy.commandLine,
                                     selected: model.prefs.strategyID == strategy.selectionID) {
                            model.choose(strategy: strategy.selectionID)
                        }
                        .contextMenu {
                            Button("Use") { model.choose(strategy: strategy.selectionID) }
                            Button("Edit…") { model.edit(strategy) }
                            Button("Copy Flags") { model.copyFlags(strategy.commandLine) }
                            Button("Duplicate") {
                                model.newStrategy(from: strategy.options, name: "\(strategy.name) Copy")
                            }
                            Divider()
                            Button("Delete", role: .destructive) { model.delete(strategy) }
                        }
                    }
                    NewStrategyCard { model.newStrategy() }
                }
            }
            .padding(Space.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridArea("strategies")
        }
        .navigationTitle("Strategies")
        .toolbar {
            ToolbarItem {
                Button("Find a Strategy", systemImage: "wand.and.sparkles") { model.openFinder() }
                    .help("Try every strategy on a blocked site (Shift-Command-T)")
            }
            ToolbarItem {
                Button("New Strategy", systemImage: "plus") { model.newStrategy() }
                    .help("Make your own strategy (Command-N)")
            }
        }
    }

    private func section<Content: View>(_ title: String, caption: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(caption).font(.callout).foregroundStyle(.secondary)
            }
            .gridProbe("section-\(title)", area: "strategies")
            LazyVGrid(columns: columns, alignment: .leading, spacing: Space.lg) {
                content()
            }
        }
    }
}

private struct StrategyCard: View {
    let name: String
    let symbol: String
    let blurb: String
    let commandLine: String
    let selected: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(selected ? AnyShapeStyle(Palette.onAccent) : AnyShapeStyle(Palette.accentText))
                        .frame(width: 40, height: 40)
                        .background(selected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.accent.opacity(0.14)),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer()
                    if selected {
                        Label("In use", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accentText)
                    }
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(name).font(.headline)
                    Text(blurb)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3, reservesSpace: true)
                }
                Text(commandLine.isEmpty ? "no flags" : commandLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, minHeight: 204, alignment: .topLeading)
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: selected ? 2 : 0)
            )
            .shadow(color: .black.opacity(hovering ? 0.08 : 0), radius: 8, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(name)
        .accessibilityHint(blurb)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NewStrategyCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.sm) {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Palette.accentText)
                Text("New Strategy").font(.headline)
                Text("Pick tpws options in a form")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 204)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
