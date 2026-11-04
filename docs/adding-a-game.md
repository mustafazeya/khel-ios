# Adding or changing a game

Khel is SwiftUI, Swift 6 language mode, iOS 26, generated with XcodeGen (`project.yml`). Everything lives in one module.
Default actor isolation is **nonisolated**: engines are plain nonisolated Swift, views and observable sessions are `@MainActor`.

Each game lives in `Sources/Games/<Folder>/` and is registered in `Sources/Core/Engine/GameCatalog.swift`.
There are three kinds of game.

## 1. Turn-based (`TurnEngine`): Ludo, Chess, Connect Four...

```swift
enum ChessEngine: TurnEngine {
    struct State: Codable, Sendable, Equatable { ... }   // everything, including the RNG state
    enum Action: Codable, Sendable, Equatable { ... }
    static let info = GameInfo(...)
    static func newGame(players: Int, seed: UInt64) -> State
    static func apply(_ a: Action, by seat: Int, to s: inout State) throws   // throw ActionError when illegal, leave s untouched
    static func activeSeat(_ s: State) -> Int?       // nil when finished
    static func outcome(_ s: State) -> Outcome?
    static func aiAction(for s: State, seat: Int, level: AILevel) -> Action?   // runs OFF the main thread
    static func status(_ s: State, seats: [SeatConfig]) -> String               // optional banner text
}
struct ChessBoardView: View { let session: TurnSession<ChessEngine> }
```

Rules of the road:

- **Pure and deterministic.** No `Date`, no `Bool.random()`, no UI. Randomness comes from a `SplitMix64` stored inside `State`
  (seeded from `newGame(seed:)`), so the host, every client and every test replay the same game.
- `State` is JSON-encoded and broadcast by the host after every action. Keep it compact (no caches that can be recomputed cheaply,
  no huge arrays of structs if a `[UInt8]` will do) and make sure `Codable` round-trips.
- Automatic follow-ups (an opponent with no legal move, a mismatched memory pair being hidden, dice with no legal move)
  are either handled inside `apply` or modelled as an explicit action that `aiAction` / the UI sends. The state must never get stuck:
  `activeSeat` must always be able to make progress.
- AI levels: `.easy` should be beatable and a little random, `.medium` decent, `.hard` strong. `aiAction` must finish within
  about 1.5 s on an iPhone even on `.hard` (use iterative deepening with a node/time budget).
- The board view receives a `TurnSession`. Read `session.state`, `session.seats`, `session.activeSeat`, `session.isMyTurn`,
  `session.lastMove` (for animating the latest action on every device) and call `session.submit(action)`.
  It only fills the space under the shared header; the shell already draws seats, whose turn it is, status, reactions,
  the result screen, rematch and reconnect handling.
- In pass-and-play several seats are "mine" on one device: `session.submit` always acts for the currently active seat when it is yours.
  Do not assume `mySeats.count == 1`; for a two-player board game you may want to flip or rotate the board per player.

## 2. Real-time (`RealtimeSession`): Carrom, Air Hockey

```swift
struct AirHockeyView: View {
    static let info = GameInfo(... mode: .realtime ...)
    let session: RealtimeSession
}
```

The game owns its simulation. `session.isAuthority` is true for the host or a purely local game; clients render what the host sends.
`session.send(data)` goes client → host, or host → all clients (`relay: true` also forwards a client's message to the other clients).
`session.onMessage` receives `(Data, senderSeat)`. Call `session.finish(outcome)` on the authority when the game ends;
`session.rematch()` + `session.onReset` handle another round. `session.aiSeats` lists computer-controlled seats (simulate them on the authority only).
`session.onPeerRejoined(seat)` is the cue to send a full snapshot to a player who dropped and came back.
When `session.launch.role == .local` there is no network: either one human against AI, or several humans on one device (`mySeats.count > 1`).

## 3. Solo

```swift
struct SnakeView: View { static let info = GameInfo(... mode: .solo ...); init() }
```

Draws its own full-screen UI below a small title bar. Persist progress in `UserDefaults` and report
`StatsStore.shared.submitScore(gameID:score:)` when a run ends. Use `@Environment(\.exitGame)` if you need to close the game.

## Shared building blocks

- `Theme` (colours, `seatColors`, gradients, button styles, `Card`), `AvatarView(spec:size:ring:)` for player faces.
- `Feedback.shared` — `.tap()`, `.thud()`, `.success()`, `.failure()`, `.play(.place / .capture / .roll / .win / .lose / .error)`.
  Call it from the view layer (never from an engine).
- `SplitMix64` for seeded randomness.

## Quality bar

- Smooth: 60 fps (120 on ProMotion) while animating. Avoid re-creating large view trees per frame; use `Canvas`/`TimelineView`,
  `drawingGroup()`, `matchedGeometryEffect`, SpriteKit for physics. No work on the main thread that can take > 4 ms per frame.
- Beautiful: use the shared `Theme`, rich gradients, soft shadows, spring animations, haptics. Large touch targets (≥ 44 pt).
- Works in portrait and landscape and on all iPhone sizes (use `GeometryReader`; never hard-code a screen size).
- Accessibility: labels on interactive controls, Dynamic Type where text is content, colour is never the only signal.
- Every engine has unit tests in `Tests/<Game>Tests.swift`: legal-move generation, win/draw detection, JSON round-trip of
  `State` and `Action`, determinism for a fixed seed, and a "self-play" test where AIs play complete games to the end without
  ever throwing or getting stuck.
- Type names are global to the module: prefix every helper type with the game's name (`LudoDiceView`, not `DiceView`).

## Trying a game quickly

```
-khelGame <id> [-khelPlayers n] [-khelLevel easy|medium|hard] [-khelPass] [-khelSeed n]
```

launches straight into a local game (vs AI, or pass-and-play with `-khelPass`). Example:
`xcrun simctl launch booted <bundle-id> -khelGame chess -khelLevel hard`.
