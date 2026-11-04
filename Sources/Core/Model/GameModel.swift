import Foundation

/// How hard an AI seat plays.
enum AILevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case easy, medium, hard
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Where a game comes from, used to group the catalog.
enum GameOrigin: String, Codable, Sendable {
    case indian = "Indian classics"
    case board = "Board & strategy"
    case arcade = "Arcade"
}

/// How a game is synchronised between devices.
enum GameMode: String, Codable, Sendable {
    /// Deterministic reducer; the host is authoritative and broadcasts full state after each action.
    case turnBased
    /// Physics / real-time; the game drives `RealtimeSession` itself.
    case realtime
    /// One player only.
    case solo
}

/// Static metadata shown in the catalog.
struct GameInfo: Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let tagline: String
    let symbol: String
    let origin: GameOrigin
    let mode: GameMode
    let minPlayers: Int
    let maxPlayers: Int
    /// Two hex colours (top, bottom) for the card gradient.
    let palette: [UInt32]
    /// Whether a single human can play against AI seats.
    let supportsAI: Bool
    let rules: String

    var isMultiplayer: Bool { maxPlayers > 1 && mode != .solo }
}

enum SeatKind: Codable, Sendable, Hashable {
    /// A person on this device (also used for pass-and-play).
    case local
    /// A person on another iPhone, identified by their player id.
    case remote(UUID)
    case ai(AILevel)

    var isAI: Bool { if case .ai = self { true } else { false } }
    var isRemote: Bool { if case .remote = self { true } else { false } }
}

/// A seat at the table.
struct SeatConfig: Codable, Sendable, Hashable, Identifiable {
    var index: Int
    var name: String
    var avatar: AvatarSpec
    var kind: SeatKind
    var connected: Bool = true
    var id: Int { index }
}

/// The result of a finished game.
struct Outcome: Codable, Sendable, Equatable {
    /// Seats from first place to last (may be partial for games with only winner / loser).
    var ranking: [Int]
    var isDraw: Bool = false
    var summary: String = ""

    var winners: [Int] { isDraw ? [] : Array(ranking.prefix(1)) }

    static func win(_ seat: Int, others: [Int] = [], summary: String = "") -> Outcome {
        Outcome(ranking: [seat] + others, summary: summary)
    }
    static func draw(_ summary: String = "It's a draw") -> Outcome {
        Outcome(ranking: [], isDraw: true, summary: summary)
    }
}

/// Everything a game needs to start.
struct GameLaunch: Codable, Sendable {
    enum Role: String, Codable, Sendable { case local, host, client }
    var gameID: String
    var seats: [SeatConfig]
    var seed: UInt64
    var role: Role
    /// Seats controlled by a human on this device.
    var mySeats: Set<Int>
    /// Free-form options chosen in the lobby (for example "variant": "fast").
    var options: [String: String] = [:]

    var humanSeatCount: Int { seats.filter { !$0.kind.isAI }.count }
}

struct ActionError: Error, Sendable, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Small deterministic generator. Codable so that it can live inside game state and keep replays
/// and network peers in lock-step.
struct SplitMix64: Codable, Sendable, Equatable, RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in `range`.
    mutating func int(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }
}
