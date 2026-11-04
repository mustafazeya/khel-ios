# Khel for iPhone

[![CI](https://github.com/mustafazeya/khel-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/mustafazeya/khel-ios/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

*Khel* (खेल) means "game". A native SwiftUI games app for iPhone: Indian classics, international board games and arcade games,
all offline. Play alone against the computer, pass the phone around, or connect several iPhones over the local network, where one
iPhone is the server. No ads, no accounts, no tracking, no internet needed.

It is built for sideloading on your own iPhones (yours and your family's) and stays fresh with the same hourly auto-install job as
[CineFlix](https://github.com/mustafazeya/cineflix-ios). It is not an App Store app.

## Games

| | Game | Players | Notes |
|---|---|---|---|
| 🇮🇳 | **Ludo** | 2–4 | Classic cross board, safe stars, captures, animated dice |
| 🇮🇳 | **Snakes & Ladders** | 2–4 | Vector snakes and ladders, hopping tokens |
| 🇮🇳 | **Carrom** | 2 | SpriteKit physics, flick-to-shoot, queen cover rule |
| 🇮🇳 | **Mancala** | 2 | Pallanguzhi-style sowing with animated seeds |
| 🇮🇳 | **Goats & Tigers** | 2 | Bagh-Chal hunt game |
| ♟ | **Chess** | 2 | Full FIDE rules, strong time-boxed AI, vector pieces |
| ♟ | **Checkers** | 2 | Forced captures and multi-jumps |
| ♟ | **Reversi** | 2 | Animated 3D disc flips |
| ♟ | **Connect Four** | 2 | Solid negamax AI |
| ♟ | **Gomoku** | 2 | 15×15, five in a row |
| ♟ | **Ultimate Tic-Tac-Toe** | 2 | Nine boards, one winner |
| ♟ | **Dots & Boxes** | 2–4 | Chain-aware AI |
| 🕹 | **Memory Match** | 1–4 | Co-op practice or versus |
| 🕹 | **Air Hockey** | 2 | 60 Hz authoritative host physics, interpolated client |
| 🕹 | **2048** | 1 | Animated tiles, undo, 4×4 to 6×6 |
| 🕹 | **Snake** | 1 | Interpolated motion, three modes |
| 🕹 | **Blocks** | 1 | 7-bag, SRS-style kicks, hold, ghost piece |
| 🕹 | **Minesweeper** | 1 | First tap is always safe, chording |
| 🕹 | **Sudoku** | 1 | Unique-solution puzzles at four levels, notes, hints |

## Features

- **Local multiplayer with no internet.** One iPhone hosts (Bonjour discovery, or type `ip:port`), others join. The host is authoritative,
  clients reconnect automatically and get their seat back. See [docs/multiplayer.md](docs/multiplayer.md).
- **Computer players at three levels** for every board game, plus pass-and-play on one phone.
- **Generated SVG avatars** with an editor (face, hair, headwear, pagdi, bindi, kurta...), shown at every seat and exportable as `.svg`.
- Reactions during online games, haptics and synthesised sound effects (no audio assets), stats and records per game.
- Every game's rules engine is deterministic and unit-tested, including full AI self-play.

## Requirements

- A Mac with **Xcode 27** and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iPhones on **iOS 26 or later**, and an Apple ID (a free personal team is enough)

## Quick start

```bash
git clone https://github.com/mustafazeya/khel-ios.git
cd khel-ios
cp Config/Signing.example.xcconfig Config/Signing.xcconfig     # your bundle id and team id
./install-iphone.sh                                             # builds and installs on every paired iPhone
scripts/install-launchagent.sh                                  # keeps them installed (free teams expire after 7 days)
```

Every game has a **How to play** screen with steps and a video link (tap **?** while playing), also written up in [how to play](docs/how-to-play.md).

Details: [build and install](docs/build-and-install.md) · [auto-install](docs/auto-install.md) · [architecture](docs/architecture.md) ·
[multiplayer](docs/multiplayer.md) · [adding a game](docs/adding-a-game.md) · [testing](docs/testing.md)

## Privacy

Everything stays on the device. The only network traffic is the local-network connection between your own iPhones while you play together.

## License

[MIT](LICENSE)
