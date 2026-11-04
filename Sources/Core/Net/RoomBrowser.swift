import Foundation
import Network
import Observation

struct DiscoveredRoom: Identifiable, Hashable, @unchecked Sendable {
    let id: String
    let name: String
    let hostName: String
    let gameID: String
    let players: Int
    let maxPlayers: Int
    let endpoint: NWEndpoint
}

/// Finds Khel rooms on the local network with Bonjour.
@MainActor @Observable
final class RoomBrowser {
    private(set) var rooms: [DiscoveredRoom] = []
    private(set) var failure: String?
    private var browser: NWBrowser?

    func start() {
        stop()
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Wire.serviceType, domain: nil), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let e) = state { Task { @MainActor in self?.failure = e.localizedDescription } }
            if case .waiting(let e) = state { Task { @MainActor in self?.failure = e.localizedDescription } }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found: [DiscoveredRoom] = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                var txt: [String: String] = [:]
                if case let .bonjour(record) = result.metadata {
                    for key in ["host", "game", "players", "max", "v"] { if let v = record[key] { txt[key] = v } }
                }
                guard txt["v"] == String(Wire.version) else { return nil }
                return DiscoveredRoom(id: name, name: name, hostName: txt["host"] ?? name, gameID: txt["game"] ?? "",
                                      players: Int(txt["players"] ?? "") ?? 1, maxPlayers: Int(txt["max"] ?? "") ?? 4,
                                      endpoint: result.endpoint)
            }.sorted { $0.name < $1.name }
            Task { @MainActor in self?.rooms = found; self?.failure = nil }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

enum NetworkInfo {
    /// IPv4 addresses of this device on Wi-Fi / hotspot / Ethernet, for manual joining.
    static func localAddresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        return result
    }
}
