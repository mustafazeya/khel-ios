import SwiftUI

// STUB: replace with the real implementation.
enum MemoryEngine: TurnEngine {
    struct State: Codable, Sendable, Equatable { var done = false }
    typealias Action = Int
    static let info = GameInfo(id: "memory", title: "Memory Match", tagline: "Find the pairs before they do", symbol: "rectangle.on.rectangle.angled", origin: .arcade, mode: .turnBased,
                              minPlayers: 1, maxPlayers: 4, palette: [0xEE0979, 0xFF6A00], supportsAI: true,
                              rules: "TODO")
    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func apply(_ action: Int, by seat: Int, to state: inout State) throws { state.done = true }
    static func activeSeat(_ state: State) -> Int? { state.done ? nil : 0 }
    static func outcome(_ state: State) -> Outcome? { state.done ? .win(0) : nil }
    static func aiAction(for state: State, seat: Int, level: AILevel) -> Int? { 0 }
}

struct MemoryBoardView: View {
    let session: TurnSession<MemoryEngine>
    var body: some View { Button("Memory Match (stub)") { session.submit(0) }.foregroundStyle(.white) }
}
