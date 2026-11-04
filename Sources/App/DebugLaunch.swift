import Foundation

/// `-khelGame <id> [-khelPlayers <n>] [-khelLevel easy|medium|hard] [-khelPass]` jumps straight into a local game,
/// so screenshots, UI tests and manual checks do not need to tap through the menus.
@MainActor
enum DebugLaunch {
    static func make(profile: Profile) -> GameLaunch? {
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? { args.firstIndex(of: key).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        guard let id = value("-khelGame"), let info = GameCatalog.info(id) else { return nil }
        let total = min(max(Int(value("-khelPlayers") ?? "") ?? max(info.minPlayers, 2), info.minPlayers), info.maxPlayers)
        let level = AILevel(rawValue: value("-khelLevel") ?? "") ?? .medium
        let pass = args.contains("-khelPass")
        var rng = SplitMix64(seed: UInt64(value("-khelSeed") ?? "") ?? 42)
        var seats = [profile.seat(index: 0)]
        while seats.count < total && info.mode != .solo {
            let bot = BotIdentity.make(index: seats.count, using: &rng, avoiding: seats.map(\.name))
            seats.append(SeatConfig(index: seats.count, name: bot.name, avatar: bot.avatar, kind: pass ? .local : .ai(level)))
        }
        return GameLaunch(gameID: id, seats: seats, seed: rng.next(), role: .local,
                          mySeats: Set(seats.filter { $0.kind == .local }.map(\.index)))
    }
}
