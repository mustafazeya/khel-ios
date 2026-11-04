import SwiftUI

// STUB: replace with the real implementation.
enum SnakesLaddersEngine: TurnEngine {
    struct State: Codable, Sendable, Equatable { var done = false }
    typealias Action = Int
    static let info = GameInfo(id: "snakes", title: "Snakes & Ladders", tagline: "Climb the ladders, dodge the snakes", symbol: "figure.stairs", origin: .indian, mode: .turnBased,
                              minPlayers: 2, maxPlayers: 4, palette: [0x11998E, 0x38EF7D], supportsAI: true,
                              rules: "TODO")
    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func apply(_ action: Int, by seat: Int, to state: inout State) throws { state.done = true }
    static func activeSeat(_ state: State) -> Int? { state.done ? nil : 0 }
    static func outcome(_ state: State) -> Outcome? { state.done ? .win(0) : nil }
    static func aiAction(for state: State, seat: Int, level: AILevel) -> Int? { 0 }
}

struct SnakesLaddersBoardView: View {
    let session: TurnSession<SnakesLaddersEngine>
    var body: some View { Button("Snakes & Ladders (stub)") { session.submit(0) }.foregroundStyle(.white) }
}
