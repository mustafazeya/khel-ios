# Multiplayer over the local network

No internet, no accounts, no relay server. One iPhone is the **host** and acts as the server; the others join it.

## How phones find each other

- The host listens with `NWListener` on a free TCP port and advertises a Bonjour service `_khel._tcp` carrying the room name,
  host name, selected game and player count (TXT record).
- A joining phone browses `_khel._tcp` with `NWBrowser` (Nearby tab) and connects to the chosen room.
- If Bonjour is blocked (some routers isolate Wi-Fi clients), the host's lobby shows `ip:port`; type it in **Nearby > Join by address**.
- Peer-to-peer Wi-Fi is enabled, so two iPhones can also play next to each other with a hotspot and no router.
- iOS asks for **Local Network** permission the first time (`NSLocalNetworkUsageDescription`, `NSBonjourServices`).

## Wire protocol

TCP with `TCP_NODELAY`. Every message is a 4-byte big-endian length followed by a JSON `Packet`
(`kind`, `seat`, `seq`, `payload`, `aux`, `text`). Frames above 1 MiB are rejected and the connection is dropped.

| Kind | Direction | Meaning |
|---|---|---|
| `hello` / `welcome` / `reject` | client ↔ host | join handshake with protocol version, player id, name and avatar |
| `roster`, `options` | host → clients | players in the room, selected game, AI fill and level |
| `start`, `end` | host → clients | begin a game with its `GameLaunch` (seats, seed, your seats), return to the lobby |
| `action` | client → host | a move for a turn-based game |
| `state` | host → clients | full game state after each action plus the action that caused it (for animation) |
| `seats` | host → clients | seat changes (player dropped, computer took over) |
| `rt` | both | opaque real-time game payload (physics snapshots, shots, inputs, outcome, rematch) |
| `emote`, `ping`, `pong`, `leave` | both | reactions, heartbeat (every 2 s, 9 s timeout), clean exit |

## Authority and fairness

The host owns the truth. For turn-based games a client only sends an *intent*; the host checks that the sender owns the active
seat, applies the action to the deterministic engine, then broadcasts the new state. Illegal or out-of-turn actions are ignored
and the sender is re-synced. Real-time games run their authoritative simulation on the host and clients interpolate.

## Dropped connections

- The client reconnects automatically (6 attempts with back-off) using its stable player id and gets its seat, the game and the
  latest state back.
- While a player is away the game pauses on their turn and the host can hand that seat to the computer.
- If the host closes the room or disappears, clients are told why and return to the home screen.
