import SwiftUI

/// Dots & Boxes on a 5x5 grid of boxes (6x6 dots), 2 to 4 players.
/// Edges 0..<30 are horizontal (row 0...5, col 0...4 → row * 5 + col); edges 30..<60 are vertical (row 0...4, col 0...5 → 30 + row * 6 + col).
enum DotsBoxesEngine: TurnEngine {
    typealias Action = Int
    static let n = 5

    struct State: Codable, Sendable, Equatable {
        var players: Int
        var edges = [Int8](repeating: 0, count: 60)    // 0 free, else owner + 1
        var boxes = [Int8](repeating: 0, count: 25)    // 0 free, else owner + 1
        var turn = 0
        var scores: [Int]
        var lastEdge = -1
        var lastBoxes: [Int] = []
    }

    static let info = GameInfo(
        id: "dots", title: "Dots & Boxes", tagline: "Close the boxes, steal the turns", symbol: "square.grid.3x3.topleft.filled",
        origin: .board, mode: .turnBased, minPlayers: 2, maxPlayers: 4, palette: [0xF7971E, 0xFFD200], supportsAI: true,
        rules: "Take turns drawing one line between two neighbouring dots. Whoever draws the fourth side of a box claims it and must go again. When all 25 boxes are claimed, the player with the most boxes wins. Avoid drawing the third side of a box: it hands the box to your opponent.")

    static func newGame(players: Int, seed: UInt64) -> State { State(players: players, scores: [Int](repeating: 0, count: players)) }

    /// The four edges around box (r, c).
    static func edges(ofBox b: Int) -> [Int] {
        let r = b / 5, c = b % 5
        return [r * 5 + c, (r + 1) * 5 + c, 30 + r * 6 + c, 30 + r * 6 + c + 1]
    }

    /// Boxes touching an edge.
    static func boxes(ofEdge e: Int) -> [Int] {
        if e < 30 { let r = e / 5, c = e % 5; return [r > 0 ? (r - 1) * 5 + c : -1, r < 5 ? r * 5 + c : -1].filter { $0 >= 0 } }
        let r = (e - 30) / 6, c = (e - 30) % 6
        return [c > 0 ? r * 5 + c - 1 : -1, c < 5 ? r * 5 + c : -1].filter { $0 >= 0 }
    }

    static func sides(_ edges: [Int8], box: Int) -> Int { Self.edges(ofBox: box).filter { edges[$0] != 0 }.count }

    static func apply(_ e: Int, by seat: Int, to s: inout State) throws {
        guard outcome(s) == nil else { throw ActionError("The game is over.") }
        guard seat == s.turn else { throw ActionError("Not your turn.") }
        guard (0 ..< 60).contains(e), s.edges[e] == 0 else { throw ActionError("That line is already drawn.") }
        s.edges[e] = Int8(seat + 1)
        s.lastEdge = e
        s.lastBoxes = []
        for b in boxes(ofEdge: e) where s.boxes[b] == 0 && sides(s.edges, box: b) == 4 {
            s.boxes[b] = Int8(seat + 1); s.scores[seat] += 1; s.lastBoxes.append(b)
        }
        if s.lastBoxes.isEmpty, outcome(s) == nil { s.turn = (seat + 1) % s.players }
    }

    static func activeSeat(_ s: State) -> Int? { outcome(s) == nil ? s.turn : nil }

    static func outcome(_ s: State) -> Outcome? {
        guard s.boxes.allSatisfy({ $0 != 0 }) else { return nil }
        let ranking = (0 ..< s.players).sorted { s.scores[$0] > s.scores[$1] }
        let top = s.scores[ranking[0]]
        if s.scores.filter({ $0 == top }).count > 1 { return Outcome(ranking: ranking, isDraw: true, summary: "Shared top score of \(top)") }
        return Outcome(ranking: ranking, summary: "\(top) of 25 boxes")
    }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        let name = seats[s.turn].name
        return s.lastBoxes.isEmpty || s.lastEdge < 0 ? "\(name)'s turn" : "\(name) scored! Go again"
    }

    // MARK: AI

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Action? {
        let free = (0 ..< 60).filter { s.edges[$0] == 0 }
        guard !free.isEmpty else { return nil }
        var rng = SplitMix64(seed: UInt64(free.count) &* 40503 &+ UInt64(s.scores.reduce(0, +)))
        let takes = free.filter { e in boxes(ofEdge: e).contains { sides(s.edges, box: $0) == 3 && s.boxes[$0] == 0 } }
        let safe = free.filter { e in !boxes(ofEdge: e).contains { sides(s.edges, box: $0) == 2 && s.boxes[$0] == 0 } }

        if level == .easy { return takes.randomElement(using: &rng) ?? free[rng.int(in: 0 ... free.count - 1)] }
        if level == .hard, s.players == 2, free.count <= 15 { return solve(s, seat: seat, free: free) }
        if let t = takes.first, level == .medium || safe.isEmpty || free.count > 15 { return t }
        if !safe.isEmpty { return safe[rng.int(in: 0 ... safe.count - 1)] }
        // Every move gives something away: give away the fewest boxes.
        return free.min { giveaway(s, $0) < giveaway(s, $1) } ?? free[0]
    }

    /// How many boxes the opponent could chain after this edge is drawn.
    private static func giveaway(_ s: State, _ e: Int) -> Int {
        var t = s
        t.edges[e] = 1
        var count = 0
        var progress = true
        while progress {
            progress = false
            for b in 0 ..< 25 where t.boxes[b] == 0 && sides(t.edges, box: b) == 3 {
                if let missing = edges(ofBox: b).first(where: { t.edges[$0] == 0 }) {
                    t.edges[missing] = 2; t.boxes[b] = 2; count += 1; progress = true
                    for nb in boxes(ofEdge: missing) where nb != b && t.boxes[nb] == 0 && sides(t.edges, box: nb) == 4 { t.boxes[nb] = 2; count += 1 }
                }
            }
        }
        return count
    }

    /// Exact endgame solution for two players by memoised search over the remaining edges.
    private static func solve(_ s: State, seat: Int, free: [Int]) -> Int {
        var memo: [UInt64: Int] = [:]
        func mask(_ e: [Int8]) -> UInt64 { var m: UInt64 = 0; for (i, v) in e.enumerated() where v != 0 { m |= 1 << UInt64(i) }; return m }
        // Value = (points for the mover) - (points for the other) obtainable from here on.
        func value(_ edges: [Int8]) -> Int {
            let key = mask(edges)
            if let v = memo[key] { return v }
            var best = Int.min
            for e in 0 ..< 60 where edges[e] == 0 {
                var t = edges
                t[e] = 1
                var gained = 0
                for b in boxes(ofEdge: e) where sides(t, box: b) == 4 { gained += 1 }
                let remaining = t.filter { $0 == 0 }.count
                let v: Int
                if remaining == 0 { v = gained }
                else if gained > 0 { v = gained + value(t) }
                else { v = -value(t) }
                best = max(best, v)
            }
            memo[key] = best
            return best
        }
        var bestEdge = free[0], bestValue = Int.min
        for e in free {
            var t = s.edges
            t[e] = 1
            var gained = 0
            for b in boxes(ofEdge: e) where sides(t, box: b) == 4 && s.boxes[b] == 0 { gained += 1 }
            let remaining = t.filter { $0 == 0 }.count
            let v = remaining == 0 ? gained : (gained > 0 ? gained + value(t) : -value(t))
            if v > bestValue { bestValue = v; bestEdge = e }
        }
        return bestEdge
    }
}

// MARK: - Board

struct DotsBoxesBoardView: View {
    let session: TurnSession<DotsBoxesEngine>
    @State private var hover: Int?

    private typealias E = DotsBoxesEngine
    private var state: E.State { session.state }
    private var canMove: Bool { session.isMyTurn && session.outcome == nil }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let pad = side * 0.07
                let step = (side - 2 * pad) / 5
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface)
                    ForEach(0 ..< 25, id: \.self) { b in box(b, step: step, pad: pad) }
                    ForEach(0 ..< 60, id: \.self) { e in edgeView(e, step: step, pad: pad) }
                    dots(step: step, pad: pad)
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in hover = canMove ? nearestEdge(v.location, step: step, pad: pad) : nil }
                    .onEnded { v in
                        defer { hover = nil }
                        guard canMove, let e = nearestEdge(v.location, step: step, pad: pad) else { return }
                        Feedback.shared.thud()
                        session.submit(e)
                    })
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            HStack(spacing: 14) {
                ForEach(session.seats) { seat in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.seatColors[seat.index % 4]).frame(width: 12, height: 12)
                        Text("\(state.scores[seat.index])").font(.system(size: 22, weight: .heavy, design: .rounded)).contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(state.turn == seat.index && session.outcome == nil ? Theme.surface2 : Theme.surface, in: Capsule())
                }
            }
            .animation(.snappy, value: state.scores)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    private func dotPoint(_ r: Int, _ c: Int, step: CGFloat, pad: CGFloat) -> CGPoint { CGPoint(x: pad + CGFloat(c) * step, y: pad + CGFloat(r) * step) }

    private func endpoints(_ e: Int, step: CGFloat, pad: CGFloat) -> (CGPoint, CGPoint) {
        if e < 30 { let r = e / 5, c = e % 5; return (dotPoint(r, c, step: step, pad: pad), dotPoint(r, c + 1, step: step, pad: pad)) }
        let r = (e - 30) / 6, c = (e - 30) % 6
        return (dotPoint(r, c, step: step, pad: pad), dotPoint(r + 1, c, step: step, pad: pad))
    }

    private func nearestEdge(_ p: CGPoint, step: CGFloat, pad: CGFloat) -> Int? {
        var best: (Int, CGFloat)?
        for e in 0 ..< 60 where state.edges[e] == 0 {
            let (a, b) = endpoints(e, step: step, pad: pad)
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let d = hypot(p.x - mid.x, p.y - mid.y)
            if best == nil || d < best!.1 { best = (e, d) }
        }
        if let best, best.1 < step * 0.62 { return best.0 }
        return nil
    }

    private func edgeView(_ e: Int, step: CGFloat, pad: CGFloat) -> some View {
        let (a, b) = endpoints(e, step: step, pad: pad)
        let owner = Int(state.edges[e]) - 1
        let preview = hover == e
        return Path { p in p.move(to: a); p.addLine(to: b) }
            .stroke(owner >= 0 ? Theme.seatColors[owner % 4] : (preview ? Theme.seatColors[state.turn % 4].opacity(0.6) : Color.white.opacity(0.08)),
                    style: StrokeStyle(lineWidth: owner >= 0 ? step * 0.12 : (preview ? step * 0.12 : step * 0.05), lineCap: .round))
            .animation(.easeOut(duration: 0.2), value: owner)
            .allowsHitTesting(false)
    }

    private func box(_ b: Int, step: CGFloat, pad: CGFloat) -> some View {
        let owner = Int(state.boxes[b]) - 1
        let r = b / 5, c = b % 5
        return ZStack {
            if owner >= 0 {
                RoundedRectangle(cornerRadius: 8).fill(Theme.seatColors[owner % 4].opacity(0.35))
                AvatarView(spec: session.seats[owner].avatar, size: step * 0.5)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .frame(width: step * 0.86, height: step * 0.86)
        .position(x: pad + (CGFloat(c) + 0.5) * step, y: pad + (CGFloat(r) + 0.5) * step)
        .animation(.spring(duration: 0.4, bounce: 0.4), value: owner)
        .allowsHitTesting(false)
    }

    private func dots(step: CGFloat, pad: CGFloat) -> some View {
        Canvas { ctx, _ in
            for r in 0 ..< 6 { for c in 0 ..< 6 {
                let p = dotPoint(r, c, step: step, pad: pad)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - step * 0.08, y: p.y - step * 0.08, width: step * 0.16, height: step * 0.16)), with: .color(.white.opacity(0.9)))
            } }
        }
        .allowsHitTesting(false)
    }
}
