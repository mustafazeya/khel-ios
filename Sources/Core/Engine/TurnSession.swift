import Foundation
import Observation

/// Authoritative-host session for a `TurnEngine` game.
///
/// - `.local`: everything runs on this device (solo vs AI, pass-and-play).
/// - `.host`: same, plus remote players send actions here and receive the resulting state.
/// - `.client`: sends actions to the host and renders whatever state the host broadcasts.
@MainActor @Observable
final class TurnSession<E: TurnEngine> {
    struct Move: Identifiable, Equatable {
        let id: UInt64
        let seat: Int
        let action: E.Action
    }

    let launch: GameLaunch
    private(set) var seats: [SeatConfig]
    private(set) var state: E.State
    private(set) var version: UInt64 = 0
    /// The most recent action, for animations. Changes on every move on every device.
    private(set) var lastMove: Move?
    private(set) var notice: String?

    @ObservationIgnored private let room: RoomSession?
    @ObservationIgnored private var aiTask: Task<Void, Never>?
    @ObservationIgnored private var recorded = false

    var role: GameLaunch.Role { launch.role }
    var mySeats: Set<Int> { launch.mySeats }
    var outcome: Outcome? { E.outcome(state) }
    var activeSeat: Int? { E.activeSeat(state) }
    var isMyTurn: Bool { activeSeat.map(mySeats.contains) ?? false }
    var status: String { E.status(state, seats: seats) }
    var isNetworked: Bool { room != nil }
    /// True when someone we are waiting for has dropped off the network.
    var waitingForPlayer: SeatConfig? {
        guard let s = activeSeat, seats.indices.contains(s), !seats[s].connected else { return nil }
        return seats[s]
    }

    init(launch: GameLaunch, room: RoomSession?) {
        self.launch = launch
        self.seats = launch.seats
        self.room = room
        self.state = E.newGame(players: launch.seats.count, seed: launch.seed)
        room?.onGamePacket = { [weak self] packet, from in self?.receive(packet, from: from) }
        room?.onPeerRejoined = { [weak self] id in self?.resync(playerID: id) }
        room?.onPeerPresence = { [weak self] id, online in self?.presence(playerID: id, online: online) }
        if role != .client { scheduleAI() } else { room?.sendToHost(Packet(.sync)) }
    }

    func close() {
        aiTask?.cancel()
        room?.onGamePacket = nil
        room?.onPeerRejoined = nil
        room?.onPeerPresence = nil
    }

    // MARK: Input

    /// Submit an action for the seat that is currently active (must be one of ours).
    func submit(_ action: E.Action) {
        guard let seat = activeSeat, mySeats.contains(seat) else { return }
        switch role {
        case .local, .host:
            perform(action, seat: seat)
        case .client:
            room?.sendToHost(.make(.action, seat: seat, value: action))
        }
    }

    /// Host-only: start the game again with a fresh seed.
    func rematch() {
        guard role != .client else { return }
        recorded = false
        var rng = SplitMix64(seed: launch.seed &+ version &+ 1)
        state = E.newGame(players: seats.count, seed: rng.next())
        version += 1
        lastMove = nil
        notice = nil
        broadcastState(action: nil, seat: nil)
        scheduleAI()
    }

    /// Host-only: hand a disconnected player's seat to the computer so the game can continue.
    func replaceWithAI(seat: Int, level: AILevel = .medium) {
        guard role == .host, seats.indices.contains(seat) else { return }
        seats[seat].kind = .ai(level)
        seats[seat].connected = true
        room?.broadcast(.make(.seats, value: seats))
        scheduleAI()
    }

    // MARK: Authority

    private func perform(_ action: E.Action, seat: Int) {
        var next = state
        do { try E.apply(action, by: seat, to: &next) } catch {
            notice = (error as? ActionError)?.description ?? "That move is not allowed."
            return
        }
        notice = nil
        state = next
        version += 1
        lastMove = Move(id: version, seat: seat, action: action)
        broadcastState(action: action, seat: seat)
        if let outcome { finish(outcome) }
        scheduleAI()
    }

    private func broadcastState(action: E.Action?, seat: Int?) {
        guard role == .host, let room else { return }
        room.broadcast(.make(.state, seat: seat, seq: version, value: state, aux: action))
    }

    private func finish(_ outcome: Outcome) {
        guard !recorded else { return }
        recorded = true
        StatsStore.shared.record(gameID: E.info.id, outcome: outcome, mySeats: mySeats, seatCount: seats.count)
    }

    private func scheduleAI() {
        aiTask?.cancel()
        guard role != .client, outcome == nil, let seat = activeSeat, seats.indices.contains(seat),
              case .ai(let level) = seats[seat].kind else { return }
        let snapshot = state
        let expected = version
        aiTask = Task { [weak self] in
            let pause = Double.random(in: 0.55 ... 1.0)
            let started = ContinuousClock.now
            let move = await Task.detached(priority: .userInitiated) { E.aiAction(for: snapshot, seat: seat, level: level) }.value
            let spent = ContinuousClock.now - started
            let remaining = Duration.seconds(pause) - spent
            if remaining > .zero { try? await Task.sleep(for: remaining) }
            guard !Task.isCancelled, let self, self.version == expected, let move else { return }
            self.perform(move, seat: seat)
        }
    }

    // MARK: Networking

    private func receive(_ packet: Packet, from playerID: UUID?) {
        switch (role, packet.kind) {
        case (.host, .action):
            guard let playerID, let seat = packet.seat, let action: E.Action = packet.decode(),
                  seats.indices.contains(seat), seats[seat].kind == .remote(playerID), activeSeat == seat else {
                if let playerID { resync(playerID: playerID) }
                return
            }
            perform(action, seat: seat)
        case (.client, .state):
            guard let seq = packet.seq, seq >= version, let s: E.State = packet.decode() else { return }
            let changed = seq != version
            state = s
            version = seq
            if changed, let seat = packet.seat, let aux = packet.aux,
               let action = try? JSONDecoder().decode(E.Action.self, from: aux) {
                lastMove = Move(id: seq, seat: seat, action: action)
            }
            if let outcome { finish(outcome) } else { recorded = false }
        case (.host, .sync):
            if let playerID { resync(playerID: playerID) }
        case (.client, .seats):
            if let s: [SeatConfig] = packet.decode() { seats = s }
        default:
            break
        }
    }

    private func resync(playerID: UUID) {
        guard role == .host, let room else { return }
        room.send(.make(.seats, value: seats), to: playerID)
        room.send(.make(.state, seq: version, value: state), to: playerID)
    }

    private func presence(playerID: UUID, online: Bool) {
        guard role == .host, let i = seats.firstIndex(where: { $0.kind == .remote(playerID) }) else { return }
        seats[i].connected = online
        room?.broadcast(.make(.seats, value: seats))
    }
}
