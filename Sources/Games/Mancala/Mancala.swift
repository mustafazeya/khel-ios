import SwiftUI

/// Kalah-style Mancala (Pallanguzhi-like seed sowing).
/// Indices: seat 0 pits 0...5, seat 0 store 6, seat 1 pits 7...12, seat 1 store 13. Sowing runs 0 → 13 and wraps, skipping the other store.
enum MancalaEngine: TurnEngine {
    typealias Action = Int

    struct State: Codable, Sendable, Equatable {
        var pits: [Int] = [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0]
        var turn = 0
        var over = false
        var lastPit = -1
        /// Pits that received a seed during the last move, in order.
        var lastPath: [Int] = []
        var captured = 0
        var extraTurn = false
        var moves = 0
    }

    static let info = GameInfo(
        id: "mancala", title: "Mancala", tagline: "Pallanguzhi-style seed sowing", symbol: "circle.grid.2x2.fill",
        origin: .indian, mode: .turnBased, minPlayers: 2, maxPlayers: 2, palette: [0x7F5539, 0xDDA15E], supportsAI: true,
        rules: "Pick one of your pits and sow its seeds one by one round the board, counter-clockwise, including your store but skipping your opponent's. If the last seed lands in your store you move again. If it lands in an empty pit of yours, you capture that seed and everything in the pit opposite. When one side is empty the other player keeps their remaining seeds. Most seeds in the store wins.")

    static func store(_ seat: Int) -> Int { seat == 0 ? 6 : 13 }
    static func pits(_ seat: Int) -> ClosedRange<Int> { seat == 0 ? 0 ... 5 : 7 ... 12 }

    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func legal(_ s: State, seat: Int) -> [Int] { pits(seat).filter { s.pits[$0] > 0 } }
    static func activeSeat(_ s: State) -> Int? { s.over ? nil : s.turn }

    static func apply(_ pit: Int, by seat: Int, to s: inout State) throws {
        guard !s.over else { throw ActionError("The game is over.") }
        guard seat == s.turn else { throw ActionError("Not your turn.") }
        guard pits(seat).contains(pit), s.pits[pit] > 0 else { throw ActionError("Pick one of your pits that has seeds.") }
        let skip = store(1 - seat)
        var seeds = s.pits[pit]
        s.pits[pit] = 0
        var i = pit
        s.lastPit = pit; s.lastPath = []; s.captured = 0; s.moves += 1
        while seeds > 0 {
            i = (i + 1) % 14
            if i == skip { continue }
            s.pits[i] += 1
            s.lastPath.append(i)
            seeds -= 1
        }
        s.extraTurn = false
        if i == store(seat) {
            s.extraTurn = true
        } else if pits(seat).contains(i), s.pits[i] == 1, s.pits[12 - i] > 0 {
            s.captured = s.pits[12 - i] + 1
            s.pits[store(seat)] += s.captured
            s.pits[i] = 0; s.pits[12 - i] = 0
        }
        if legal(s, seat: 0).isEmpty || legal(s, seat: 1).isEmpty {
            for seat in 0 ... 1 { for p in pits(seat) { s.pits[store(seat)] += s.pits[p]; s.pits[p] = 0 } }
            s.over = true
        } else if !s.extraTurn {
            s.turn = 1 - seat
        }
    }

    static func outcome(_ s: State) -> Outcome? {
        guard s.over else { return nil }
        let a = s.pits[6], b = s.pits[13]
        if a == b { return .draw("\(a) – \(b)") }
        return a > b ? .win(0, others: [1], summary: "\(a) – \(b)") : .win(1, others: [0], summary: "\(b) – \(a)")
    }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        let name = seats[s.turn].name
        if s.captured > 0 { return "Captured \(s.captured) seeds! \(name)'s turn" }
        if s.extraTurn { return "\(name) plays again" }
        return "\(name)'s turn"
    }

    // MARK: AI

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Int? {
        let moves = legal(s, seat: seat)
        guard !moves.isEmpty else { return nil }
        var rng = SplitMix64(seed: UInt64(s.moves) &* 6151)
        if level == .easy {
            if rng.int(in: 0 ... 1) == 0 {
                return moves.max { gain(s, $0, seat) < gain(s, $1, seat) }
            }
            return moves[rng.int(in: 0 ... moves.count - 1)]
        }
        let seconds = level == .hard ? 1.0 : 0.3
        let maxDepth = level == .hard ? 14 : 6
        var search = Search(deadline: Date().addingTimeInterval(seconds))
        var best = moves[0]
        for depth in 1 ... maxDepth {
            var alpha = -1000, iter = moves[0], bestScore = -1000
            for m in moves {
                var t = s
                try? apply(m, by: seat, to: &t)
                let v = t.turn == seat || t.over ? search.negamaxSame(t, seat, depth - 1, alpha, 1000) : -search.negamaxSame(t, 1 - seat, depth - 1, -1000, -alpha)
                if search.stopped { break }
                if v > bestScore { bestScore = v; iter = m; alpha = max(alpha, v) }
            }
            if search.stopped { break }
            best = iter
        }
        return best
    }

    private static func gain(_ s: State, _ m: Int, _ seat: Int) -> Int {
        var t = s
        try? apply(m, by: seat, to: &t)
        return t.pits[store(seat)] - s.pits[store(seat)] + (t.extraTurn ? 2 : 0)
    }

    private struct Search {
        let deadline: Date
        var nodes = 0
        var stopped = false

        /// Value for `seat`, who is to move in `s` (or the game is over).
        mutating func negamaxSame(_ s: State, _ seat: Int, _ depth: Int, _ alphaIn: Int, _ beta: Int) -> Int {
            nodes += 1
            if nodes & 1023 == 0, Date() > deadline { stopped = true }
            if stopped { return 0 }
            if s.over { return (s.pits[store(seat)] - s.pits[store(1 - seat)]) * 10 }
            if s.turn != seat { return -negamaxSame(s, s.turn, depth, -beta, -alphaIn) }
            if depth <= 0 { return (s.pits[store(seat)] - s.pits[store(1 - seat)]) * 10 + seeds(s, seat) - seeds(s, 1 - seat) }
            var alpha = alphaIn, best = -100_000
            let moves = legal(s, seat: seat).sorted { $0 > $1 }
            for m in moves {
                var t = s
                try? apply(m, by: seat, to: &t)
                let v = t.over ? (t.pits[store(seat)] - t.pits[store(1 - seat)]) * 10 : (t.turn == seat ? negamaxSame(t, seat, depth - 1, alpha, beta) : -negamaxSame(t, t.turn, depth - 1, -beta, -alpha))
                if stopped { return 0 }
                best = max(best, v); alpha = max(alpha, v)
                if alpha >= beta { break }
            }
            return best
        }

        func seeds(_ s: State, _ seat: Int) -> Int { pits(seat).reduce(0) { $0 + s.pits[$1] } }
    }
}

// MARK: - Board

struct MancalaBoardView: View {
    let session: TurnSession<MancalaEngine>
    @State private var shown: [Int] = MancalaEngine.State().pits
    @State private var animating = false
    @State private var hot = -1

    private typealias E = MancalaEngine
    private static let seedColors: [Color] = [
        Color(red: 0.98, green: 0.93, blue: 0.80), Color(red: 0.25, green: 0.78, blue: 0.72), Color(red: 0.95, green: 0.45, blue: 0.40),
        Color(red: 0.98, green: 0.72, blue: 0.25), Color(red: 0.45, green: 0.45, blue: 0.9),
    ]
    private var state: E.State { session.state }
    private var flipped: Bool { session.mySeats == [1] }
    private var canMove: Bool { session.isMyTurn && session.outcome == nil && !animating }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = min(geo.size.height, w * 0.62)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.33, blue: 0.18), Color(red: 0.38, green: 0.21, blue: 0.11)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color(red: 0.25, green: 0.13, blue: 0.07), lineWidth: 4))
                    ForEach(0 ..< 14, id: \.self) { i in pit(i, w: w, h: h) }
                }
                .frame(width: w, height: h)
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                .frame(maxHeight: .infinity)
            }
            .aspectRatio(1 / 0.62, contentMode: .fit)
            Text(canMove ? "Tap one of your pits" : (animating ? "Sowing…" : " ")).font(.footnote).foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .onAppear { shown = state.pits }
        .onChange(of: session.version) { _, _ in Task { await animate() } }
    }

    /// Unit-square centre of each pit (x, y in 0...1), seat 0 at the bottom, rotated when `flipped`.
    private func center(_ i: Int) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var x: CGFloat, y: CGFloat, pw: CGFloat = 0.115, ph: CGFloat = 0.3
        switch i {
        case 0 ... 5: x = 0.19 + CGFloat(i) * 0.125; y = 0.72
        case 6: x = 0.925; y = 0.5; pw = 0.12; ph = 0.7
        case 7 ... 12: x = 0.19 + CGFloat(12 - i) * 0.125; y = 0.28
        default: x = 0.075; y = 0.5; pw = 0.12; ph = 0.7
        }
        return flipped ? (1 - x, 1 - y, pw, ph) : (x, y, pw, ph)
    }

    private func pit(_ i: Int, w: CGFloat, h: CGFloat) -> some View {
        let (x, y, pw, ph) = center(i)
        let isStore = i == 6 || i == 13
        let size = CGSize(width: pw * w, height: ph * h)
        let n = shown[i]
        let mine = !isStore && E.pits(state.turn).contains(i) && state.pits[i] > 0 && canMove
        return ZStack {
            RoundedRectangle(cornerRadius: isStore ? size.width / 2 : size.width / 2, style: .continuous)
                .fill(RadialGradient(colors: [Color(red: 0.16, green: 0.08, blue: 0.04), Color(red: 0.30, green: 0.17, blue: 0.09)], center: .center, startRadius: 2, endRadius: size.height * 0.7))
                .overlay(RoundedRectangle(cornerRadius: size.width / 2, style: .continuous).strokeBorder(mine ? Theme.accent : Color.black.opacity(0.35), lineWidth: mine ? 3 : 1.5))
                .shadow(color: hot == i ? Theme.accent : .clear, radius: 10)
            Canvas { ctx, sz in
                let count = min(n, 40)
                for k in 0 ..< count {
                    let a = Double(k) * 2.399963, rr = sqrt((Double(k) + 0.5) / Double(max(count, 6)))
                    let rx = Double(sz.width) * 0.36 * rr, ry = Double(sz.height) * (isStore ? 0.4 : 0.34) * rr
                    let p = CGPoint(x: sz.width / 2 + CGFloat(cos(a) * rx), y: sz.height / 2 + CGFloat(sin(a) * ry))
                    let d = min(sz.width, 34) * 0.26
                    let c = Self.seedColors[(k * 7 + i) % 5]
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2 + 1, width: d, height: d)), with: .color(.black.opacity(0.35)))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                             with: .radialGradient(Gradient(colors: [.white.opacity(0.9), c]), center: CGPoint(x: p.x - d * 0.15, y: p.y - d * 0.2), startRadius: 0, endRadius: d))
                }
            }
            Text("\(n)").font(.system(size: isStore ? 20 : 12, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                .offset(y: isStore ? 0 : (i < 6) != flipped ? size.height * 0.42 : -size.height * 0.42)
        }
        .frame(width: size.width, height: size.height)
        .position(x: x * w, y: y * h)
        .contentShape(Rectangle())
        .onTapGesture {
            guard mine else { return }
            Feedback.shared.thud()
            session.submit(i)
        }
        .accessibilityLabel(isStore ? "Store, \(n) seeds" : "Pit, \(n) seeds")
    }

    @MainActor private func animate() async {
        let s = state
        guard s.lastPit >= 0, !s.lastPath.isEmpty else { shown = s.pits; return }
        animating = true
        // Walk back to the board before this move: the previous pits equal the new ones minus the sown seeds (captures are applied at the end).
        shown[s.lastPit] = 0
        for i in s.lastPath {
            shown[i] += 1
            hot = i
            Feedback.shared.play(.tap)
            try? await Task.sleep(for: .milliseconds(170))
        }
        hot = -1
        if s.captured > 0 { Feedback.shared.play(.capture); try? await Task.sleep(for: .milliseconds(250)) }
        shown = s.pits
        animating = false
    }
}
