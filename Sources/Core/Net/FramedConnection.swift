import Foundation
import Network

/// A TCP connection that speaks `Packet`s. Callbacks run on the connection's private queue; hop to the main actor yourself.
final class FramedConnection: @unchecked Sendable {
    enum Status: Sendable { case ready, failed(String), closed }

    let connection: NWConnection
    private let queue: DispatchQueue
    private var codec = FrameCodec()
    private var closed = false

    var onPacket: (@Sendable (Packet) -> Void)?
    var onStatus: (@Sendable (Status) -> Void)?

    init(connection: NWConnection, label: String = "khel.conn") {
        self.connection = connection
        self.queue = DispatchQueue(label: label, qos: .userInteractive)
    }

    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.connectionTimeout = 6
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true
        return params
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.onStatus?(.ready)
            case .failed(let e): self.finish(.failed(e.localizedDescription))
            case .waiting(let e): self.onStatus?(.failed(e.localizedDescription))
            case .cancelled: self.finish(.closed)
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    private func finish(_ status: Status) {
        guard !closed else { return }
        closed = true
        onStatus?(status)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for packet in try self.codec.feed(data) { self.onPacket?(packet) }
                } catch {
                    self.finish(.failed("Protocol error"))
                    self.connection.cancel()
                    return
                }
            }
            if error != nil || isComplete {
                self.finish(.closed)
                self.connection.cancel()
                return
            }
            self.receive()
        }
    }

    func send(_ packet: Packet) {
        guard let frame = try? FrameCodec.encode(packet) else { return }
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    /// Send a last packet and close once it has been written (a plain `cancel()` can drop it).
    func sendAndClose(_ packet: Packet) {
        guard let frame = try? FrameCodec.encode(packet) else { cancel(); return }
        connection.send(content: frame, completion: .contentProcessed { [weak self] _ in self?.cancel() })
    }

    func cancel() {
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}
