import XCTest
@testable import Khel

/// A tiny engine for exercising sessions and sockets without depending on any real game.
enum ToyEngine: TurnEngine {
    struct State: Codable, Sendable, Equatable { var total = 0; var turn = 0; var players = 2; var winner: Int? }
    typealias Action = Int
    static let info = GameInfo(id: "toy", title: "Toy", tagline: "", symbol: "circle", origin: .arcade, mode: .turnBased, minPlayers: 2, maxPlayers: 2,
                               palette: [0, 0], supportsAI: true, rules: "Add 1–3. Reach 10 to win.")
    static func newGame(players: Int, seed: UInt64) -> State { State(players: players) }
    static func apply(_ a: Int, by seat: Int, to s: inout State) throws {
        guard s.winner == nil, seat == s.turn else { throw ActionError("not your turn") }
        guard (1 ... 3).contains(a) else { throw ActionError("1–3 only") }
        s.total += a
        if s.total >= 10 { s.winner = seat } else { s.turn = (s.turn + 1) % s.players }
    }
    static func activeSeat(_ s: State) -> Int? { s.winner == nil ? s.turn : nil }
    static func outcome(_ s: State) -> Outcome? { s.winner.map { .win($0, others: [1 - $0]) } }
    static func aiAction(for s: State, seat: Int, level: AILevel) -> Int? { (10 - s.total) <= 3 ? 10 - s.total : max(1, (s.total + 1) % 4) }
}

@MainActor
final class NetworkTests: XCTestCase {
    private func entry(_ name: String) -> RosterEntry { RosterEntry(playerID: UUID(), name: name, avatar: .random(seed: UInt64(name.hashValue.magnitude))) }

    private func wait(_ what: String, timeout: TimeInterval = 8, _ cond: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() > end { XCTFail("timed out waiting for \(what)"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func connectedPair() async throws -> (RoomSession, RoomSession, RosterEntry) {
        let hostEntry = entry("Zeya"), guestEntry = entry("Sadiqa")
        let host = RoomSession.host(entry: hostEntry)
        host.startHosting()
        try await wait("host port") { host.port != nil }
        let guest = RoomSession.client(entry: guestEntry)
        guest.connect(host: "127.0.0.1", port: host.port!)
        try await wait("roster") { host.roster.count == 2 && guest.roster.count == 2 && guest.phase == .lobby }
        return (host, guest, guestEntry)
    }

    func testLobbyAndGameStart() async throws {
        let (host, guest, _) = try await connectedPair()
        defer { guest.leave(); host.leave() }
        XCTAssertEqual(guest.roster.map(\.name), ["Zeya", "Sadiqa"])
        XCTAssertEqual(host.roster.first?.isHost, true)

        host.setOptions(RoomOptions(gameID: "connect4"))
        try await wait("options") { guest.options.gameID == "connect4" }

        let launch = try XCTUnwrap(host.startGame())
        XCTAssertEqual(launch.seats.count, 2)
        XCTAssertEqual(launch.mySeats, [0])
        try await wait("client launch") { guest.launch != nil && guest.phase == .playing }
        XCTAssertEqual(guest.launch?.mySeats, [1])
        XCTAssertEqual(guest.launch?.seed, launch.seed)
        XCTAssertEqual(guest.launch?.seats.map(\.name), ["Zeya", "Sadiqa"])
    }

    func testTurnGameOverTheWire() async throws {
        let (host, guest, _) = try await connectedPair()
        defer { guest.leave(); host.leave() }
        host.setOptions(RoomOptions(gameID: "connect4"))
        _ = host.startGame()
        try await wait("client launch") { guest.launch != nil }

        let hs = TurnSession<ToyEngine>(launch: host.launch!, room: host)
        let gs = TurnSession<ToyEngine>(launch: guest.launch!, room: guest)

        // Guest tries to move out of turn: nothing happens anywhere.
        gs.submit(2)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(hs.state.total, 0)
        XCTAssertEqual(gs.state.total, 0)

        hs.submit(3)
        try await wait("guest sees host move") { gs.version == 1 }
        XCTAssertEqual(gs.state, hs.state)
        XCTAssertEqual(gs.lastMove?.seat, 0)
        XCTAssertEqual(gs.lastMove?.action, 3)

        gs.submit(2)
        try await wait("host sees guest move") { hs.version == 2 }
        XCTAssertEqual(hs.state.total, 5)

        // Invalid action from the guest (4) is rejected by the host's engine.
        hs.submit(1)
        try await wait("v3") { gs.version == 3 }
        gs.submit(4)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(hs.version, 3)

        gs.submit(3); try await wait("v4") { hs.version == 4 }
        hs.submit(3); try await wait("v5") { gs.version == 5 }
        XCTAssertEqual(hs.state.total, 12)
        XCTAssertEqual(hs.outcome?.winners, [0])
        XCTAssertEqual(gs.outcome, hs.outcome)
        hs.close(); gs.close()
    }

    func testClientReconnectsAndGetsStateBack() async throws {
        let (host, guest, guestEntry) = try await connectedPair()
        defer { host.leave() }
        host.setOptions(RoomOptions(gameID: "connect4"))
        _ = host.startGame()
        try await wait("client launch") { guest.launch != nil }
        let hs = TurnSession<ToyEngine>(launch: host.launch!, room: host)
        hs.submit(2)

        guest.leave()
        try await wait("host marks away") { host.roster.last?.connected == false }
        XCTAssertEqual(hs.seats[1].connected, false)
        XCTAssertEqual(hs.waitingForPlayer?.index, 1)

        let back = RoomSession.client(entry: guestEntry)
        back.connect(host: "127.0.0.1", port: host.port!)
        try await wait("rejoined launch") { back.launch != nil && back.phase == .playing }
        XCTAssertEqual(back.launch?.mySeats, [1])
        let gs = TurnSession<ToyEngine>(launch: back.launch!, room: back)
        try await wait("state resync") { gs.version == hs.version }
        XCTAssertEqual(gs.state.total, 2)
        XCTAssertEqual(host.roster.last?.connected, true)
        gs.submit(1)
        try await wait("move after rejoin") { hs.version == 2 }
        hs.close(); gs.close(); back.leave()
    }

    func testRoomRefusesWhenFullAndWhenInGame() async throws {
        let (host, guest, _) = try await connectedPair()
        defer { guest.leave(); host.leave() }
        host.setOptions(RoomOptions(gameID: "connect4"))     // max 2 players

        let third = RoomSession.client(entry: entry("Third"))
        third.connect(host: "127.0.0.1", port: host.port!)
        try await wait("refusal") { if case .closed = third.phase { true } else { false } }
        XCTAssertEqual(host.roster.count, 2)
    }

    func testRealtimeRelayAndOutcome() async throws {
        let (host, guest, _) = try await connectedPair()
        defer { guest.leave(); host.leave() }
        host.setOptions(RoomOptions(gameID: "airhockey"))
        _ = host.startGame()
        try await wait("client launch") { guest.launch != nil }
        let hr = RealtimeSession(launch: host.launch!, room: host)
        let gr = RealtimeSession(launch: guest.launch!, room: guest)
        var hostGot: [(Data, Int)] = [], guestGot: [(Data, Int)] = []
        hr.onMessage = { hostGot.append(($0, $1)) }
        gr.onMessage = { guestGot.append(($0, $1)) }

        gr.send(Data([9, 9]))
        try await wait("host gets client data") { !hostGot.isEmpty }
        XCTAssertEqual(hostGot.first?.0, Data([9, 9]))
        XCTAssertEqual(hostGot.first?.1, 1)

        hr.send(Data([1]))
        try await wait("client gets host data") { !guestGot.isEmpty }
        XCTAssertEqual(guestGot.first?.1, 0)

        hr.finish(.win(1, others: [0]))
        try await wait("client outcome") { gr.outcome != nil }
        XCTAssertEqual(gr.outcome?.ranking, [1, 0])
        hr.close(); gr.close()
    }
}
