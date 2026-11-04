import SwiftUI

// STUB: replace with the real implementation.
enum ReversiEngine: TurnEngine {
    struct State: Codable, Sendable, Equatable { var done = false }
    typealias Action = Int
    static let info = GameInfo(id: "reversi", title: "Reversi", tagline: "Flip the board to your colour", symbol: "circle.lefthalf.filled", origin: .board, mode: .turnBased,
                              minPlayers: 2, maxPlayers: 2, palette: [0x134E5E, 0x71B280], supportsAI: true,
                              rules: "TODO")
    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func apply(_ action: Int, by seat: Int, to state: inout State) throws { state.done = true }
    static func activeSeat(_ state: State) -> Int? { state.done ? nil : 0 }
    static func outcome(_ state: State) -> Outcome? { state.done ? .win(0) : nil }
    static func aiAction(for state: State, seat: Int, level: AILevel) -> Int? { 0 }
}

struct ReversiBoardView: View {
    let session: TurnSession<ReversiEngine>
    var body: some View { Button("Reversi (stub)") { session.submit(0) }.foregroundStyle(.white) }
}
