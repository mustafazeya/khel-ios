import SwiftUI

// STUB: replace with the real implementation.
struct SudokuView: View {
    static let info = GameInfo(id: "sudoku", title: "Sudoku", tagline: "Fill the grid with logic", symbol: "number", origin: .arcade, mode: .solo,
                              minPlayers: 1, maxPlayers: 1, palette: [0x1D976C, 0x93F9B9], supportsAI: false,
                              rules: "TODO")
    var body: some View { Text("Sudoku (stub)").foregroundStyle(.white) }
}
