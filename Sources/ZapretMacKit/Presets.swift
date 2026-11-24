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
        Preset(id: "tlsrec-split", name: "TLS Record + Split", symbol: "square.split.2x1",
               blurb: "Cuts the TLS hello into two records, then splits the packet at the domain. Works on most providers.",
               commandLine: "--tlsrec=sniext+1 --split-pos=1,midsld"),
        Preset(id: "split-sni", name: "Split at Domain", symbol: "scissors",
               blurb: "Splits the first packet in the middle of the site name, so the filter never sees it whole.",
               commandLine: "--split-pos=1,midsld"),
        Preset(id: "split-disorder", name: "Split + Disorder", symbol: "arrow.left.arrow.right",
               blurb: "Splits the packet and sends the pieces out of order.",
               commandLine: "--split-pos=1,midsld --disorder"),
        Preset(id: "oob", name: "Out-of-Band Byte", symbol: "exclamationmark.bubble",
               blurb: "Adds an urgent byte between the pieces that the server drops but the filter reads.",
               commandLine: "--split-pos=1 --oob"),
        Preset(id: "http-tricks", name: "HTTP Header Tricks", symbol: "textformat",
               blurb: "Changes how the Host header is written, for sites that still use plain HTTP.",
               commandLine: "--hostcase --hostdot --methodeol --split-pos=method+2"),
        Preset(id: "aggressive", name: "Everything at Once", symbol: "bolt.shield",
               blurb: "TLS records, split, disorder, and header tricks together. Try it when the others fail.",
               commandLine: "--tlsrec=sniext+1 --split-pos=1,midsld --disorder --hostcase --domcase"),
    ]

    public static let defaultID = "tlsrec-split"

    public static func with(id: String) -> Preset? { all.first { $0.id == id } }
}
