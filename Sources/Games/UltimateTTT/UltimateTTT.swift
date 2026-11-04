import SwiftUI

// STUB: replace with the real implementation.
enum UltimateTTTEngine: TurnEngine {
    struct State: Codable, Sendable, Equatable { var done = false }
    typealias Action = Int
    static let info = GameInfo(id: "ultimate", title: "Ultimate Tic-Tac-Toe", tagline: "Nine boards, one winner", symbol: "number.square.fill", origin: .board, mode: .turnBased,
                              minPlayers: 2, maxPlayers: 2, palette: [0x8E2DE2, 0x4A00E0], supportsAI: true,
                              rules: "TODO")
    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func apply(_ action: Int, by seat: Int, to state: inout State) throws { state.done = true }
    static func activeSeat(_ state: State) -> Int? { state.done ? nil : 0 }
    static func outcome(_ state: State) -> Outcome? { state.done ? .win(0) : nil }
    static func aiAction(for state: State, seat: Int, level: AILevel) -> Int? { 0 }
}

struct UltimateTTTBoardView: View {
    let session: TurnSession<UltimateTTTEngine>
    var body: some View { Button("Ultimate Tic-Tac-Toe (stub)") { session.submit(0) }.foregroundStyle(.white) }
}
