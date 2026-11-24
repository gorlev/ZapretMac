import Foundation

/// A built-in strategy that ships with the app. People duplicate one to make
/// their own.
public struct Preset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let symbol: String
    public let blurb: String
    public let commandLine: String

    public var options: StrategyOptions { StrategyOptions(commandLine: commandLine) }

    public static let all: [Preset] = [
        Preset(id: "tlsrec-split", name: String(localized: "TLS Record + Split", bundle: .main), symbol: "square.split.2x1",
               blurb: String(localized: "Cuts the TLS hello into two records, then splits the packet at the domain. Works on most providers.", bundle: .main),
               commandLine: "--tlsrec=sniext+1 --split-pos=1,midsld"),
        Preset(id: "split-sni", name: String(localized: "Split at Domain", bundle: .main), symbol: "scissors",
               blurb: String(localized: "Splits the first packet in the middle of the site name, so the filter never sees it whole.", bundle: .main),
               commandLine: "--split-pos=1,midsld"),
        Preset(id: "split-disorder", name: String(localized: "Split + Disorder", bundle: .main), symbol: "arrow.left.arrow.right",
               blurb: String(localized: "Splits the packet and sends the pieces out of order.", bundle: .main),
               commandLine: "--split-pos=1,midsld --disorder"),
        Preset(id: "oob", name: String(localized: "Out-of-Band Byte", bundle: .main), symbol: "exclamationmark.bubble",
               blurb: String(localized: "Adds an urgent byte between the pieces that the server drops but the filter reads.", bundle: .main),
               commandLine: "--split-pos=1 --oob"),
        Preset(id: "http-tricks", name: String(localized: "HTTP Header Tricks", bundle: .main), symbol: "textformat",
               blurb: String(localized: "Changes how the Host header is written, for sites that still use plain HTTP.", bundle: .main),
               commandLine: "--hostcase --hostdot --methodeol --split-pos=method+2"),
        Preset(id: "aggressive", name: String(localized: "Everything at Once", bundle: .main), symbol: "bolt.shield",
               blurb: String(localized: "TLS records, split, disorder, and header tricks together. Try it when the others fail.", bundle: .main),
               commandLine: "--tlsrec=sniext+1 --split-pos=1,midsld --disorder --hostcase --domcase"),
    ]

    public static let defaultID = "tlsrec-split"

    public static func with(id: String) -> Preset? { all.first { $0.id == id } }
}
