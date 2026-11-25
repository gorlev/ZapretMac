import SwiftUI

/// A small "?" next to a term people may not know. Hovering shows the
/// explanation as a tooltip; clicking shows it in a popover.
struct InfoButton: View {
    let title: String
    let text: String
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .help(text)
        .accessibilityLabel(title)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(title).font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.lg)
            .frame(width: 320, alignment: .leading)
        }
    }
}

extension InfoButton {
    /// Transparent mode, in words for people who do not know proxies.
    static var transparentMode: InfoButton {
        InfoButton(
            title: String(localized: "What is Transparent mode?"),
            text: String(localized: "Normally ZapretMac works as a proxy: apps reach it only if they follow the Mac's proxy setting, and some apps don't. In Transparent mode, macOS itself sends every app's web traffic through ZapretMac, so there is nothing to set up and no app is left out. It needs a small helper that runs with administrator rights; turning the mode off removes its rules.")
        )
    }
}
