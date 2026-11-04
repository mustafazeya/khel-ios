import Foundation
import Observation

/// The local player's identity. The id is stable so a dropped player can rejoin their seat.
@MainActor @Observable
final class Profile {
    let id: UUID
    var name: String { didSet { save() } }
    var avatar: AvatarSpec { didSet { save() } }

    private static let key = "khel.profile.v1"

    private struct Stored: Codable { var id: UUID; var name: String; var avatar: AvatarSpec }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let s = try? JSONDecoder().decode(Stored.self, from: data) {
            id = s.id; name = s.name; avatar = s.avatar
        } else {
            let id = UUID()
            self.id = id
            name = "Player"
            avatar = AvatarSpec.random(seed: UInt64(truncatingIfNeeded: id.uuidString.hashValue))
            save()
        }
    }

    private func save() {
        let stored = Stored(id: id, name: name, avatar: avatar)
        if let data = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func rosterEntry(isHost: Bool) -> RosterEntry {
        RosterEntry(playerID: id, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Player" : name, avatar: avatar, isHost: isHost)
    }

    /// Seat used for the person holding this device.
    func seat(index: Int) -> SeatConfig {
        SeatConfig(index: index, name: rosterEntry(isHost: false).name, avatar: avatar, kind: .local)
    }
}

struct GameRecord: Codable, Sendable, Equatable {
    var played = 0
    var wins = 0
    var draws = 0
    var streak = 0
    var bestStreak = 0
    var bestScore = 0
    var losses: Int { played - wins - draws }
}

/// Lifetime results per game, stored on device.
@MainActor @Observable
final class StatsStore {
    static let shared = StatsStore()
    private static let key = "khel.stats.v1"
    private(set) var records: [String: GameRecord]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let r = try? JSONDecoder().decode([String: GameRecord].self, from: data) { records = r } else { records = [:] }
    }

    func record(_ id: String) -> GameRecord { records[id] ?? GameRecord() }

    var totalPlayed: Int { records.values.reduce(0) { $0 + $1.played } }
    var totalWins: Int { records.values.reduce(0) { $0 + $1.wins } }

    /// Called once per finished game. A "win" means one of this device's seats came first.
    func record(gameID: String, outcome: Outcome, mySeats: Set<Int>, seatCount: Int) {
        var r = record(gameID)
        r.played += 1
        if outcome.isDraw {
            r.draws += 1
            r.streak = 0
        } else if let first = outcome.ranking.first, mySeats.contains(first) {
            r.wins += 1
            r.streak += 1
            r.bestStreak = max(r.bestStreak, r.streak)
        } else {
            r.streak = 0
        }
        records[gameID] = r
        save()
    }

    /// For score-based games (2048, Snake).
    func submitScore(gameID: String, score: Int) {
        var r = record(gameID)
        r.played += 1
        r.bestScore = max(r.bestScore, score)
        records[gameID] = r
        save()
    }

    func reset() { records = [:]; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

@MainActor @Observable
final class AppSettings {
    var sound: Bool { didSet { UserDefaults.standard.set(sound, forKey: "khel.sound") } }
    var haptics: Bool { didSet { UserDefaults.standard.set(haptics, forKey: "khel.haptics") } }
    var aiLevel: AILevel { didSet { UserDefaults.standard.set(aiLevel.rawValue, forKey: "khel.ai") } }

    init() {
        let d = UserDefaults.standard
        sound = d.object(forKey: "khel.sound") as? Bool ?? true
        haptics = d.object(forKey: "khel.haptics") as? Bool ?? true
        aiLevel = AILevel(rawValue: d.string(forKey: "khel.ai") ?? "") ?? .medium
        Feedback.shared.settings = self
    }
}
