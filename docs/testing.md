# Testing

```bash
xcodegen generate
xcodebuild test -project Khel.xcodeproj -scheme Khel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -only-testing:KhelTests
```

- `Tests/CoreTests.swift`: framing, RNG, SVG parser/renderer, every avatar option, catalog consistency, stats.
- `Tests/NetworkTests.swift`: a real host and client over localhost sockets playing a game end to end.
- `Tests/<Game>Tests.swift`: rules, JSON round-trip, determinism, AI legality and full AI self-play for every game.
- `UITests/`: launch smoke test.

Jump into any game for a manual check without tapping through menus:

```bash
xcrun simctl launch booted <bundle-id> -khelGame chess -khelLevel hard
# options: -khelPlayers n  -khelPass (all seats human)  -khelSeed n
```
