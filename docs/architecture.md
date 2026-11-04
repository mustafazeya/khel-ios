# Architecture

```
Sources/
  App/          KhelApp (entry, Router, tabs), DebugLaunch (-khelGame ...)
  Core/
    Model/      GameInfo, SeatConfig, Outcome, GameLaunch, SplitMix64, Profile, StatsStore, AppSettings
    Engine/     TurnEngine (pure game rules), TurnSession (host-authoritative), RealtimeSession, GameCatalog
    Net/        Packet + FrameCodec, FramedConnection (NWConnection), RoomSession (host/client), RoomBrowser (Bonjour)
    Avatar/     AvatarSpec, AvatarSVG (generator), SVG (parser + renderer), AvatarView
    Audio/      Feedback (haptics + synthesised sounds, no audio assets)
  UI/           Theme and shared components
  Features/     Home (catalog + setup), Lobby (rooms), Profile (avatar editor, stats, settings), Game (shared game shell)
  Games/        one folder per game
Tests/          unit tests (core + one file per game)
```

## Games are pure, sessions do the plumbing

A turn-based game is a `TurnEngine`: value-type `State`, `Action`, a throwing `apply`, an `aiAction`. It never touches UI, time or
the network, and all randomness comes from a seeded generator stored in `State`. `TurnSession<E>` runs it in one of three roles:

| Role | Used for | Behaviour |
|---|---|---|
| `local` | solo vs computer, pass-and-play | applies actions itself, runs AI |
| `host` | hosting a room | same, and broadcasts every new state; accepts actions from clients |
| `client` | joined phone | sends actions to the host, renders broadcast state |

Because the engine is deterministic and value-typed, AI runs on a background task, games are trivially unit-testable (including full AI
self-play), and replays/rematches need nothing extra. Real-time games (Carrom, Air Hockey) use `RealtimeSession`, a thin
authority-aware byte channel, and keep their own simulation.

`GameChrome` (in `Features/Game`) is the shared shell: seats with avatars and a pulsing turn ring, status line, reactions, result screen with
confetti, rematch (host), leave confirmation and the "waiting for a player to reconnect" banner. A game only draws its board.

## SVG avatars

`AvatarSpec` is ~15 small integers (Codable, ~100 bytes on the wire). `AvatarSVG.document(_:)` turns it into a standalone SVG 1.1 document
(200×200 viewBox, gradients, clip paths, transforms). `SVGDocument` parses that with `XMLParser` and `SVGRenderer` draws it into a SwiftUI
`Canvas`, so the same vector art is crisp at every size and can be exported from **Me > Avatar > Export SVG**.
The renderer supports svg, g, rect, circle, ellipse, line, polyline, polygon, path (all commands including arcs), linear/radial gradients,
clipPath, transform, opacity and inline `style`. Games (chess pieces, animals) reuse it for their own vector art.

## Concurrency

Swift 6 language mode. Default isolation is nonisolated: engines are plain Swift; observable sessions, views and `Feedback` are `@MainActor`.
Network callbacks arrive on a private queue and hop to the main actor.
