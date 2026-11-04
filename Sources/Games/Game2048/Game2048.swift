import SwiftUI

// STUB: replace with the real implementation.
struct Game2048View: View {
    static let info = GameInfo(id: "g2048", title: "2048", tagline: "Slide, merge, reach 2048", symbol: "square.grid.2x2.fill", origin: .arcade, mode: .solo,
                              minPlayers: 1, maxPlayers: 1, palette: [0xF2994A, 0xF2C94C], supportsAI: false,
                              rules: "TODO")
    var body: some View { Text("2048 (stub)").foregroundStyle(.white) }
}
