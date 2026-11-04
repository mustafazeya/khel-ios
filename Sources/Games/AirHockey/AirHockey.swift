import SwiftUI

// STUB: replace with the real implementation.
struct AirHockeyView: View {
    static let info = GameInfo(id: "airhockey", title: "Air Hockey", tagline: "Fast, smooth, head-to-head", symbol: "sportscourt.fill", origin: .arcade, mode: .realtime,
                              minPlayers: 2, maxPlayers: 2, palette: [0x00C6FF, 0x0072FF], supportsAI: true,
                              rules: "TODO")
    let session: RealtimeSession
    var body: some View { Text("Air Hockey (stub)").foregroundStyle(.white) }
}
