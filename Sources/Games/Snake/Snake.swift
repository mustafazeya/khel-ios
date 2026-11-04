import SwiftUI

// STUB: replace with the real implementation.
struct SnakeView: View {
    static let info = GameInfo(id: "snake", title: "Snake", tagline: "Eat, grow, don't crash", symbol: "scribble.variable", origin: .arcade, mode: .solo,
                              minPlayers: 1, maxPlayers: 1, palette: [0x56AB2F, 0xA8E063], supportsAI: false,
                              rules: "TODO")
    var body: some View { Text("Snake (stub)").foregroundStyle(.white) }
}
