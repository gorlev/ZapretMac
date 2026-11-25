import Foundation
import Network
import Observation
import ZapretMacKit

/// S-104: watches the network and keeps the Mac's current LAN IPv4 address,
/// the one other devices use to reach the shared proxy.
@Observable
final class ShareMonitor {
    /// Nil when the Mac has no shareable network address.
    private(set) var address: NetworkShare.Address?
    /// Called when the address or interface changes.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var preferred: String?

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // The interface macOS routes through, when it is Wi-Fi or Ethernet.
            let name = path.availableInterfaces.first { [.wifi, .wiredEthernet].contains($0.type) }?.name
            Task { @MainActor in
                guard let self else { return }
                self.preferred = name
                self.refresh()
                // An address can arrive a moment after the path changes: look again.
                try? await Task.sleep(for: .seconds(2))
                self.refresh()
            }
        }
        monitor.start(queue: .main)
        self.monitor = monitor
        refresh()
    }

    /// Reads the interfaces again and reports a changed address.
    func refresh() {
        let next = NetworkShare.choose(from: NetworkShare.currentAddresses(), preferred: preferred)
        guard next != address else { return }
        address = next
        onChange?()
    }
}

extension AppModel {
    /// The address tpws shares: nil when sharing is off, in Transparent mode
    /// (tpws runs in the helper on 127.0.0.1 only), or with no network.
    var sharedAddress: NetworkShare.Address? {
        guard prefs.shareOnNetwork, !prefs.transparentMode else { return nil }
        return shareMonitor.address
    }

    /// "192.168.1.20:1088", the proxy address other devices type in.
    var sharedProxyText: String? {
        sharedAddress.map { "\($0.ip):\(String(prefs.port))" }
    }

    /// Turns sharing on or off and restarts a running tpws with the new binds.
    func setShareOnNetwork(_ on: Bool) {
        guard prefs.shareOnNetwork != on else { return }
        prefs.shareOnNetwork = on
        shareMonitor.refresh()
        restartIfRunning()
    }

    func startShareMonitor() {
        shareMonitor.onChange = { [weak self] in self?.shareAddressChanged() }
        shareMonitor.start()
    }

    /// A new network or address: tpws listens on the old one, so restart it.
    private func shareAddressChanged() {
        guard prefs.shareOnNetwork, !prefs.transparentMode, engine.isOn else { return }
        restartIfRunning()
    }
}
