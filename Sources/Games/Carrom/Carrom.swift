import SwiftUI

// STUB: replace with the real implementation.
struct CarromView: View {
    static let info = GameInfo(id: "carrom", title: "Carrom", tagline: "Flick, pocket, win the queen", symbol: "target", origin: .indian, mode: .realtime,
                              minPlayers: 2, maxPlayers: 2, palette: [0xB06A2C, 0xE8B46B], supportsAI: true,
                              rules: "TODO")
    let session: RealtimeSession
    var body: some View { Text("Carrom (stub)").foregroundStyle(.white) }
}
