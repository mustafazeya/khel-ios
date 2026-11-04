import Foundation

/// A deterministic, value-type game.
///
/// Engines are pure: `apply` is the only way state changes, randomness comes from a generator that lives
/// inside `State`, and nothing touches UI or the network. That makes every engine unit-testable, lets the host
/// broadcast plain state, and lets AI run off the main thread.
protocol TurnEngine: Sendable {
    associatedtype State: Codable & Sendable & Equatable
    associatedtype Action: Codable & Sendable & Equatable

    static var info: GameInfo { get }

    /// Fresh game for `players` seats. Use `seed` for every random decision (shuffles, dice, first player).
    static func newGame(players: Int, seed: UInt64) -> State

    /// Validate and apply `action` from `seat`. Throw `ActionError` for illegal moves; state must be untouched then.
    static func apply(_ action: Action, by seat: Int, to state: inout State) throws

    /// The seat that must act now, or nil when the game is over.
    static func activeSeat(_ state: State) -> Int?

    /// Non-nil once the game has finished.
    static func outcome(_ state: State) -> Outcome?

    /// Choose a move for an AI seat. Called off the main thread. Return nil if there is nothing to do.
    static func aiAction(for state: State, seat: Int, level: AILevel) -> Action?

    /// Short text for the status line ("Your turn", "Roll the dice"...). Optional.
    static func status(_ state: State, seats: [SeatConfig]) -> String
}

extension TurnEngine {
    static func status(_ state: State, seats: [SeatConfig]) -> String {
        if let o = outcome(state) { return o.summary }
        guard let s = activeSeat(state), seats.indices.contains(s) else { return "" }
        return "\(seats[s].name)'s turn"
    }
}
