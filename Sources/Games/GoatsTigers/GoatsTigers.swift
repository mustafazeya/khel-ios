import SwiftUI

// STUB: replace with the real implementation.
enum GoatsTigersEngine: TurnEngine {
    struct State: Codable, Sendable, Equatable { var done = false }
    typealias Action = Int
    static let info = GameInfo(id: "goats", title: "Goats & Tigers", tagline: "Bagh-Chal: trap the tigers", symbol: "pawprint.fill", origin: .indian, mode: .turnBased,
                              minPlayers: 2, maxPlayers: 2, palette: [0x42275A, 0x734B6D], supportsAI: true,
                              rules: "TODO")
    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func apply(_ action: Int, by seat: Int, to state: inout State) throws { state.done = true }
    static func activeSeat(_ state: State) -> Int? { state.done ? nil : 0 }
    static func outcome(_ state: State) -> Outcome? { state.done ? .win(0) : nil }
    static func aiAction(for state: State, seat: Int, level: AILevel) -> Int? { 0 }
}

struct GoatsTigersBoardView: View {
    let session: TurnSession<GoatsTigersEngine>
    var body: some View { Button("Goats & Tigers (stub)") { session.submit(0) }.foregroundStyle(.white) }
}
