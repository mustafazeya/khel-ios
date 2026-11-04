import SwiftUI

// STUB: replace with the real implementation.
struct MinesweeperView: View {
    static let info = GameInfo(id: "minesweeper", title: "Minesweeper", tagline: "Clear the field, flag the mines", symbol: "flag.fill", origin: .arcade, mode: .solo,
                              minPlayers: 1, maxPlayers: 1, palette: [0x485563, 0x29323C], supportsAI: false,
                              rules: "TODO")
    var body: some View { Text("Minesweeper (stub)").foregroundStyle(.white) }
}
