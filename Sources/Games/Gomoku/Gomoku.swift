import SwiftUI

// STUB: replace with the real implementation.
enum GomokuEngine: TurnEngine {
    struct State: Codable, Sendable, Equatable { var done = false }
    typealias Action = Int
    static let info = GameInfo(id: "gomoku", title: "Gomoku", tagline: "Five in a row wins", symbol: "circle.grid.cross.fill", origin: .board, mode: .turnBased,
                              minPlayers: 2, maxPlayers: 2, palette: [0x606C88, 0x3F4C6B], supportsAI: true,
                              rules: "TODO")
    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func apply(_ action: Int, by seat: Int, to state: inout State) throws { state.done = true }
    static func activeSeat(_ state: State) -> Int? { state.done ? nil : 0 }
    static func outcome(_ state: State) -> Outcome? { state.done ? .win(0) : nil }
    static func aiAction(for state: State, seat: Int, level: AILevel) -> Int? { 0 }
}

struct GomokuBoardView: View {
    let session: TurnSession<GomokuEngine>
    var body: some View { Button("Gomoku (stub)") { session.submit(0) }.foregroundStyle(.white) }
}
