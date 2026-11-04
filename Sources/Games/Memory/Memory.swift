import SwiftUI

/// Memory Match for 1 to 4 players. Cards are flipped with explicit actions; a mismatch stays face up until `.resolve`.
enum MemoryEngine: TurnEngine {
    enum Action: Codable, Sendable, Equatable { case flip(Int), resolve }

    struct State: Codable, Sendable, Equatable {
        var players: Int
        var cols = 4
        var cards: [Int]
        var matchedBy: [Int]            // -1 not matched, else the seat that matched it
        var up: [Int] = []              // face-up unmatched cards
        var pending = false             // two different cards are showing
        var turn = 0
        var scores: [Int]
        var tries = 0
        /// Every card index that has ever been turned over, in order (public information, used by the AI's memory).
        var seen: [Int] = []
        var lastMatched = false
    }

    static let symbols = ["star.fill", "heart.fill", "moon.fill", "flame.fill", "bolt.fill", "leaf.fill", "drop.fill", "bell.fill",
                          "cloud.fill", "crown.fill", "camera.fill", "gift.fill"]

    static let info = GameInfo(
        id: "memory", title: "Memory Match", tagline: "Find the pairs before they do", symbol: "rectangle.on.rectangle.angled",
        origin: .arcade, mode: .turnBased, minPlayers: 1, maxPlayers: 4, palette: [0xEE0979, 0xFF6A00], supportsAI: true,
        rules: "Turn over two cards per turn. If they match you keep the pair and go again; if not, they flip back and the next player goes. Remember where the cards are! The player with the most pairs wins. Playing alone, try to finish in as few tries as you can.")

    static func newGame(players: Int, seed: UInt64) -> State {
        let pairs = players <= 2 ? 8 : 12
        var rng = SplitMix64(seed: seed)
        var cards = (0 ..< pairs).flatMap { [$0, $0] }
        for i in stride(from: cards.count - 1, to: 0, by: -1) { cards.swapAt(i, rng.int(in: 0 ... i)) }
        return State(players: players, cols: 4, cards: cards, matchedBy: [Int](repeating: -1, count: cards.count), scores: [Int](repeating: 0, count: players))
    }

    static func activeSeat(_ s: State) -> Int? { outcome(s) == nil ? s.turn : nil }

    static func apply(_ a: Action, by seat: Int, to s: inout State) throws {
        guard outcome(s) == nil else { throw ActionError("The game is over.") }
        guard seat == s.turn else { throw ActionError("Not your turn.") }
        switch a {
        case .flip(let i):
            guard !s.pending, s.up.count < 2 else { throw ActionError("Wait for the cards to flip back.") }
            guard s.cards.indices.contains(i), s.matchedBy[i] == -1, !s.up.contains(i) else { throw ActionError("That card is already showing.") }
            s.up.append(i)
            s.seen.append(i)
            s.lastMatched = false
            if s.up.count == 2 {
                s.tries += 1
                if s.cards[s.up[0]] == s.cards[s.up[1]] {
                    for k in s.up { s.matchedBy[k] = seat }
                    s.scores[seat] += 1
                    s.up = []
                    s.lastMatched = true
                } else {
                    s.pending = true
                }
            }
        case .resolve:
            guard s.pending else { throw ActionError("Nothing to flip back.") }
            s.up = []
            s.pending = false
            s.turn = (s.turn + 1) % s.players
        }
    }

    static func outcome(_ s: State) -> Outcome? {
        guard s.matchedBy.allSatisfy({ $0 >= 0 }) else { return nil }
        if s.players == 1 { return .win(0, summary: "All pairs in \(s.tries) tries") }
        let ranking = (0 ..< s.players).sorted { s.scores[$0] > s.scores[$1] }
        let top = s.scores[ranking[0]]
        if s.scores.filter({ $0 == top }).count > 1 { return Outcome(ranking: ranking, isDraw: true, summary: "Tied on \(top) pairs") }
        return Outcome(ranking: ranking, summary: "\(top) pairs")
    }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        let name = seats[s.turn].name
        if s.pending { return "No match" }
        if s.lastMatched { return "\(name) found a pair! Go again" }
        return s.players == 1 ? "\(s.tries) tries" : "\(name)'s turn"
    }

    // MARK: AI

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Action? {
        if s.pending { return .resolve }
        var rng = SplitMix64(seed: UInt64(s.seen.count) &* 99991 &+ UInt64(s.scores.reduce(0, +)))
        let window = level == .easy ? 6 : (level == .medium ? 16 : 1000)
        let remembered = Set(s.seen.suffix(window)).filter { s.matchedBy[$0] == -1 && !s.up.contains($0) }
        let unseen = s.cards.indices.filter { s.matchedBy[$0] == -1 && !s.up.contains($0) && !remembered.contains($0) }
        func pick(_ from: [Int]) -> Int? { from.isEmpty ? nil : from[rng.int(in: 0 ... from.count - 1)] }

        if let first = s.up.first {
            if let m = remembered.first(where: { $0 != first && s.cards[$0] == s.cards[first] }) { return .flip(m) }
            if let u = pick(unseen) { return .flip(u) }
            if let r = pick(Array(remembered).filter { $0 != first }) { return .flip(r) }
            return nil
        }
        let byValue = Dictionary(grouping: remembered, by: { s.cards[$0] })
        if let pair = byValue.values.first(where: { $0.count >= 2 }) { return .flip(pair.sorted()[0]) }
        if let u = pick(unseen) { return .flip(u) }
        return pick(Array(remembered)).map { .flip($0) }
    }
}

// MARK: - Board

private struct MemoryCardFace: View, Animatable {
    var angle: Double
    let symbol: String
    let tint: Color
    let glow: Color?
    var animatableData: Double { get { angle } set { angle = newValue } }

    var body: some View {
        let front = angle >= 90
        ZStack {
            if front {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LinearGradient(colors: [.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                Image(systemName: symbol).font(.system(size: 30, weight: .bold)).foregroundStyle(tint).padding(8)
                    .minimumScaleFactor(0.5)
                if let glow { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(glow, lineWidth: 4) }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.2, blue: 0.5), Color(red: 1, green: 0.42, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 2).padding(7)
                Image(systemName: "questionmark").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        .scaleEffect(x: front ? -1 : 1, y: 1)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
    }
}

struct MemoryBoardView: View {
    let session: TurnSession<MemoryEngine>
    private typealias E = MemoryEngine
    private var state: E.State { session.state }
    private var canFlip: Bool { session.isMyTurn && session.outcome == nil && !state.pending && state.up.count < 2 }

    private static let tints: [Color] = [
        .yellow, .red, .indigo, .orange, .blue, .green, .cyan, .purple, .teal, Color(red: 0.9, green: 0.65, blue: 0.1), .pink, .mint,
    ]

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let cols = state.cols, rows = state.cards.count / cols
                let gap: CGFloat = 8
                let cw = min((geo.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols), (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows) / 1.1)
                let ch = cw * 1.1
                VStack(spacing: gap) {
                    ForEach(0 ..< rows, id: \.self) { r in
                        HStack(spacing: gap) {
                            ForEach(0 ..< cols, id: \.self) { c in card(r * cols + c).frame(width: cw, height: ch) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if state.players > 1 {
                HStack(spacing: 12) {
                    ForEach(session.seats) { seat in
                        HStack(spacing: 6) {
                            Circle().fill(Theme.seatColors[seat.index % 4]).frame(width: 12, height: 12)
                            Text("\(state.scores[seat.index])").font(.system(size: 20, weight: .heavy, design: .rounded)).contentTransition(.numericText())
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(state.turn == seat.index && session.outcome == nil ? Theme.surface2 : Theme.surface, in: Capsule())
                    }
                }
                .animation(.snappy, value: state.scores)
            } else {
                Text("Tries: \(state.tries)").font(.system(.title3, design: .rounded, weight: .bold))
            }
        }
        .padding(.bottom, 8)
        .onChange(of: state.pending) { _, pending in
            guard pending, session.isMyTurn else { return }
            let expected = session.version
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1000))
                if session.version == expected, session.isMyTurn { session.submit(.resolve) }
            }
        }
    }

    private func card(_ i: Int) -> some View {
        let matched = state.matchedBy[i] >= 0
        let faceUp = matched || state.up.contains(i)
        let value = state.cards[i]
        return MemoryCardFace(angle: faceUp ? 180 : 0, symbol: E.symbols[value % E.symbols.count], tint: Self.tints[value % Self.tints.count],
                              glow: matched && state.players > 1 ? Theme.seatColors[state.matchedBy[i] % 4] : nil)
            .opacity(matched ? 0.85 : 1)
            .animation(.easeInOut(duration: 0.35), value: faceUp)
            .contentShape(Rectangle())
            .onTapGesture {
                guard canFlip, !faceUp else { return }
                Feedback.shared.tap()
                session.submit(.flip(i))
            }
            .accessibilityLabel(faceUp ? "Card, \(E.symbols[value % E.symbols.count])" : "Hidden card")
    }
}
