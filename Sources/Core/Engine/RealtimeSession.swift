import Foundation
import Observation

/// Session for real-time (physics / action) games. The game owns its simulation and message format;
/// this class only gets bytes between devices, tracks seats and shares the final result.
///
/// Typical pattern: the host simulates and sends snapshots with `send`, clients send inputs to the host with `send`.
@MainActor @Observable
final class RealtimeSession {
    let launch: GameLaunch
    private(set) var seats: [SeatConfig]
    private(set) var outcome: Outcome?
    var status: String = ""

    /// Delivers a payload from another device. `seat` is the sender's seat (the host's seat when a client receives).
    @ObservationIgnored var onMessage: ((Data, Int) -> Void)?
    /// Called on every device when a rematch starts: rebuild the simulation from scratch.
    @ObservationIgnored var onReset: (() -> Void)?
    /// Host only: a remote player came back and needs a full snapshot.
    @ObservationIgnored var onPeerRejoined: ((Int) -> Void)?

    @ObservationIgnored private let room: RoomSession?
    @ObservationIgnored private var recorded = false

    var role: GameLaunch.Role { launch.role }
    /// The device that runs the authoritative simulation (host or a purely local game).
    var isAuthority: Bool { role != .client }
    var mySeats: Set<Int> { launch.mySeats }
    var isNetworked: Bool { room != nil }
    /// Lowest seat controlled by this device.
    var mySeat: Int { mySeats.min() ?? 0 }
    /// Seats driven by AI (only the authority should simulate them).
    var aiSeats: [Int] { seats.filter { $0.kind.isAI }.map(\.index) }

    init(launch: GameLaunch, room: RoomSession?) {
        self.launch = launch
        self.seats = launch.seats
        self.room = room
        room?.onGamePacket = { [weak self] packet, from in self?.receive(packet, from: from) }
        room?.onPeerRejoined = { [weak self] id in
            guard let self, let seat = self.seats.firstIndex(where: { $0.kind == .remote(id) }) else { return }
            self.onPeerRejoined?(seat)
        }
        if role == .client { room?.sendToHost(Packet(.sync)) }
    }

    func close() {
        room?.onGamePacket = nil
        room?.onPeerRejoined = nil
    }

    /// Send a payload. A client sends to the host; the host sends to every client.
    /// With `relay`, the host also forwards a client's payload to all the *other* clients.
    func send(_ data: Data, relay: Bool = false) {
        guard let room else { return }
        let packet = Packet(.rt, seat: mySeat, payload: data, text: relay ? "r" : nil)
        if room.role == .host { room.broadcast(packet) } else { room.sendToHost(packet) }
    }

    func send<T: Encodable>(_ value: T, relay: Bool = false) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        send(data, relay: relay)
    }

    /// Authority only: end the game and tell everyone.
    func finish(_ outcome: Outcome) {
        guard isAuthority, self.outcome == nil else { return }
        self.outcome = outcome
        if let data = try? JSONEncoder().encode(outcome), let room, room.role == .host {
            room.broadcast(Packet(.rt, seat: mySeat, payload: data, text: "o"))
        }
        record(outcome)
    }

    /// Authority only: clear the result and ask every device to reset via `onReset`.
    func rematch() {
        guard isAuthority else { return }
        reset()
        if let room, room.role == .host { room.broadcast(Packet(.rt, seat: mySeat, text: "m")) }
    }

    private func reset() {
        outcome = nil
        recorded = false
        onReset?()
    }

    private func record(_ outcome: Outcome) {
        guard !recorded else { return }
        recorded = true
        StatsStore.shared.record(gameID: launch.gameID, outcome: outcome, mySeats: mySeats, seatCount: seats.count)
    }

    private func receive(_ packet: Packet, from playerID: UUID?) {
        switch packet.kind {
        case .rt:
            if packet.text == "o", let o: Outcome = packet.decode() {
                outcome = o
                record(o)
                return
            }
            if packet.text == "m" { reset(); return }
            guard let data = packet.payload, let seat = packet.seat else { return }
            if let room, room.role == .host, packet.text == "r", let playerID {
                for s in seats where s.kind.isRemote && s.kind != .remote(playerID) {
                    if case .remote(let other) = s.kind { room.send(packet, to: other) }
                }
            }
            onMessage?(data, seat)
        case .sync:
            if let playerID, let seat = seats.firstIndex(where: { $0.kind == .remote(playerID) }) { onPeerRejoined?(seat) }
        case .seats:
            if let s: [SeatConfig] = packet.decode() { seats = s }
        default:
            break
        }
    }
}
