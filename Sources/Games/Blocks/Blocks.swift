import SwiftUI

// STUB: replace with the real implementation.
struct BlocksView: View {
    static let info = GameInfo(id: "blocks", title: "Blocks", tagline: "Stack, clear, chase the high score", symbol: "square.stack.3d.up.fill", origin: .arcade, mode: .solo,
                              minPlayers: 1, maxPlayers: 1, palette: [0x654EA3, 0xEAAFC8], supportsAI: false,
                              rules: "TODO")
    var body: some View { Text("Blocks (stub)").foregroundStyle(.white) }
}
