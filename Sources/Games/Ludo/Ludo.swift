import SwiftUI

// STUB: replace with the real implementation.
enum LudoEngine: TurnEngine {
    struct State: Codable, Sendable, Equatable { var done = false }
    typealias Action = Int
    static let info = GameInfo(id: "ludo", title: "Ludo", tagline: "Race your four tokens home", symbol: "dice.fill", origin: .indian, mode: .turnBased,
                              minPlayers: 2, maxPlayers: 4, palette: [0xFF5F6D, 0xFFC371], supportsAI: true,
                              rules: "TODO")
    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func apply(_ action: Int, by seat: Int, to state: inout State) throws { state.done = true }
    static func activeSeat(_ state: State) -> Int? { state.done ? nil : 0 }
    static func outcome(_ state: State) -> Outcome? { state.done ? .win(0) : nil }
    static func aiAction(for state: State, seat: Int, level: AILevel) -> Int? { 0 }
}

struct LudoBoardView: View {
    let session: TurnSession<LudoEngine>
    var body: some View { Button("Ludo (stub)") { session.submit(0) }.foregroundStyle(.white) }
}
