import SwiftUI

// STUB: replace with the real implementation.
enum DotsBoxesEngine: TurnEngine {
    struct State: Codable, Sendable, Equatable { var done = false }
    typealias Action = Int
    static let info = GameInfo(id: "dots", title: "Dots & Boxes", tagline: "Close the boxes, steal the turns", symbol: "square.grid.3x3.topleft.filled", origin: .board, mode: .turnBased,
                              minPlayers: 2, maxPlayers: 4, palette: [0xF7971E, 0xFFD200], supportsAI: true,
                              rules: "TODO")
    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func apply(_ action: Int, by seat: Int, to state: inout State) throws { state.done = true }
    static func activeSeat(_ state: State) -> Int? { state.done ? nil : 0 }
    static func outcome(_ state: State) -> Outcome? { state.done ? .win(0) : nil }
    static func aiAction(for state: State, seat: Int, level: AILevel) -> Int? { 0 }
}

struct DotsBoxesBoardView: View {
    let session: TurnSession<DotsBoxesEngine>
    var body: some View { Button("Dots & Boxes (stub)") { session.submit(0) }.foregroundStyle(.white) }
}
