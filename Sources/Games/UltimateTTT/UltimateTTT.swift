import SwiftUI

/// Ultimate Tic-Tac-Toe. Cell index = board * 9 + square (both 0...8, row-major). Seat 0 plays X, seat 1 plays O.
enum UltimateTTTEngine: TurnEngine {
    typealias Action = Int

    struct State: Codable, Sendable, Equatable {
        var cells = [Int8](repeating: 0, count: 81)
        /// Per small board: 0 undecided, 1 or -1 the winner, 2 drawn.
        var won = [Int8](repeating: 0, count: 9)
        /// The board the next player must play in, or -1 for any.
        var next = -1
        var side = 1
        var moves = 0
        var last = -1
        var winner: Int?
        var drawn = false
    }

    static let info = GameInfo(
        id: "ultimate", title: "Ultimate Tic-Tac-Toe", tagline: "Nine boards, one winner", symbol: "number.square.fill",
        origin: .board, mode: .turnBased, minPlayers: 2, maxPlayers: 2, palette: [0x8E2DE2, 0x4A00E0], supportsAI: true,
        rules: "Each square of the big board holds a small tic-tac-toe board. Where you play in a small board decides which small board your opponent must play in next. Win a small board by making three in a row there, and win the game by taking three small boards in a row. If you are sent to a board that is already decided, you may play anywhere.")

    private static let lines = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]

    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func activeSeat(_ s: State) -> Int? { s.winner == nil && !s.drawn ? (s.side == 1 ? 0 : 1) : nil }

    static func legal(_ s: State) -> [Int] {
        var out: [Int] = []
        for big in 0 ..< 9 where s.won[big] == 0 && (s.next == -1 || s.next == big) {
            for sq in 0 ..< 9 where s.cells[big * 9 + sq] == 0 { out.append(big * 9 + sq) }
        }
        return out
    }

    private static func winner(of v: [Int8], _ base: Int, stride: Int = 1) -> Int8 {
        for l in lines {
            let a = v[base + l[0] * stride]
            if a == 1 || a == -1, a == v[base + l[1] * stride], a == v[base + l[2] * stride] { return a }
        }
        return 0
    }

    static func apply(_ idx: Int, by seat: Int, to s: inout State) throws {
        guard s.winner == nil, !s.drawn else { throw ActionError("The game is over.") }
        guard seat == (s.side == 1 ? 0 : 1) else { throw ActionError("Not your turn.") }
        guard legal(s).contains(idx) else {
            throw ActionError(s.next >= 0 && s.won[s.next] == 0 ? "You must play in the highlighted board." : "That square is not available.")
        }
        let big = idx / 9, sq = idx % 9
        s.cells[idx] = Int8(s.side)
        s.last = idx; s.moves += 1
        let w = winner(of: s.cells, big * 9)
        if w != 0 { s.won[big] = w } else if (0 ..< 9).allSatisfy({ s.cells[big * 9 + $0] != 0 }) { s.won[big] = 2 }
        let overall = winner(of: s.won, 0)
        if overall != 0 { s.winner = seat }
        s.next = s.won[sq] == 0 ? sq : -1
        s.side = -s.side
        if s.winner == nil, legal(s).isEmpty {
            let x = s.won.filter { $0 == 1 }.count, o = s.won.filter { $0 == -1 }.count
            if x == o { s.drawn = true } else { s.winner = x > o ? 0 : 1 }
        }
    }

    static func outcome(_ s: State) -> Outcome? {
        if let w = s.winner { return .win(w, others: [1 - w], summary: "Won three boards in a row") }
        return s.drawn ? .draw("Boards are level") : nil
    }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        let name = seats[s.side == 1 ? 0 : 1].name
        return s.next >= 0 ? "\(name) plays in the highlighted board" : "\(name) can play anywhere"
    }

    // MARK: AI

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Action? {
        let moves = legal(s)
        guard !moves.isEmpty else { return nil }
        var rng = SplitMix64(seed: UInt64(s.moves) &* 69069 &+ 11)
        switch level {
        case .easy:
            if rng.int(in: 0 ... 1) == 0, let m = moves.first(where: { winsBoard(s, $0) }) { return m }
            return moves[rng.int(in: 0 ... moves.count - 1)]
        case .medium: return search(s, seconds: 0.35, maxDepth: 5)
        case .hard: return search(s, seconds: 1.1, maxDepth: 10)
        }
    }

    private static func winsBoard(_ s: State, _ m: Int) -> Bool {
        var cells = s.cells
        cells[m] = Int8(s.side)
        return winner(of: cells, m / 9 * 9) != 0
    }

    private static func search(_ s: State, seconds: Double, maxDepth: Int) -> Action {
        var ctx = Search(deadline: Date().addingTimeInterval(seconds))
        var ordered = order(s, legal(s))
        var best = ordered[0]
        for depth in 1 ... maxDepth {
            var alpha = -1_000_000, iter = ordered[0]
            var scored: [(Int, Int)] = []
            for m in ordered {
                var t = s
                try? apply(m, by: t.side == 1 ? 0 : 1, to: &t)
                let v = -ctx.negamax(t, depth - 1, -1_000_000, -alpha)
                if ctx.stopped { break }
                scored.append((m, v))
                if v > alpha { alpha = v; iter = m }
            }
            if ctx.stopped { break }
            best = iter
            ordered = scored.sorted { $0.1 > $1.1 }.map(\.0)
            if abs(alpha) > 90_000 { break }
        }
        return best
    }

    private static func order(_ s: State, _ moves: [Int]) -> [Int] {
        moves.sorted { a, b in
            let ka = (winsBoard(s, a) ? 100 : 0) + (a % 9 == 4 ? 3 : 0) + ([0, 2, 6, 8].contains(a % 9) ? 2 : 0)
            let kb = (winsBoard(s, b) ? 100 : 0) + (b % 9 == 4 ? 3 : 0) + ([0, 2, 6, 8].contains(b % 9) ? 2 : 0)
            return ka > kb
        }
    }

    private struct Search {
        let deadline: Date
        var nodes = 0
        var stopped = false

        mutating func negamax(_ s: State, _ depth: Int, _ alphaIn: Int, _ beta: Int) -> Int {
            nodes += 1
            if nodes & 511 == 0, Date() > deadline { stopped = true }
            if stopped { return 0 }
            if s.winner != nil { return -100_000 - depth }     // the previous mover won
            if s.drawn { return 0 }
            if depth <= 0 { return evaluate(s) }
            var alpha = alphaIn, best = -1_000_000
            for m in UltimateTTTEngine.order(s, UltimateTTTEngine.legal(s)) {
                var t = s
                try? UltimateTTTEngine.apply(m, by: t.side == 1 ? 0 : 1, to: &t)
                let v = -negamax(t, depth - 1, -beta, -alpha)
                if stopped { return 0 }
                best = max(best, v); alpha = max(alpha, v)
                if alpha >= beta { break }
            }
            return best
        }

        /// Score for the side to move.
        func evaluate(_ s: State) -> Int {
            var score = 0
            let me = Int8(s.side)
            for big in 0 ..< 9 {
                let weight = big == 4 ? 3 : ([0, 2, 6, 8].contains(big) ? 2 : 1)
                if s.won[big] == me { score += 60 * weight } else if s.won[big] == -me { score -= 60 * weight }
                else if s.won[big] == 0 {
                    for l in UltimateTTTEngine.lines {
                        let v = l.map { s.cells[big * 9 + $0] }
                        let m = v.filter { $0 == me }.count, o = v.filter { $0 == -me }.count
                        if o == 0 { score += m == 2 ? 6 : (m == 1 ? 1 : 0) }
                        if m == 0 { score -= o == 2 ? 6 : (o == 1 ? 1 : 0) }
                    }
                }
            }
            for l in UltimateTTTEngine.lines {
                let v = l.map { s.won[$0] }
                let m = v.filter { $0 == me }.count, o = v.filter { $0 == -me }.count
                if o == 0 && !v.contains(2) { score += m == 2 ? 70 : (m == 1 ? 8 : 0) }
                if m == 0 && !v.contains(2) { score -= o == 2 ? 70 : (o == 1 ? 8 : 0) }
            }
            return score
        }
    }
}

// MARK: - Board

struct UltimateTTTBoardView: View {
    let session: TurnSession<UltimateTTTEngine>
    private typealias E = UltimateTTTEngine
    private var state: E.State { session.state }
    private var canMove: Bool { session.isMyTurn && session.outcome == nil }

    private static let xColor = Color(red: 0.25, green: 0.88, blue: 1.0)
    private static let oColor = Color(red: 1.0, green: 0.38, blue: 0.62)

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let big = side / 3
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 0.07, green: 0.06, blue: 0.14))
                    // Active boards glow
                    ForEach(0 ..< 9, id: \.self) { b in
                        let active = session.outcome == nil && state.won[b] == 0 && (state.next == -1 || state.next == b)
                        RoundedRectangle(cornerRadius: 10).fill((state.side == 1 ? Self.xColor : Self.oColor).opacity(active ? 0.16 : 0))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder((state.side == 1 ? Self.xColor : Self.oColor).opacity(active ? 0.9 : 0), lineWidth: 2))
                            .frame(width: big - 8, height: big - 8)
                            .position(x: (CGFloat(b % 3) + 0.5) * big, y: (CGFloat(b / 3) + 0.5) * big)
                            .animation(.easeInOut(duration: 0.25), value: active)
                    }
                    marks(side: side, big: big)
                    grid(big: big)
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .onTapGesture { p in tap(p, big: big) }
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            HStack(spacing: 24) {
                Label("\(state.won.filter { $0 == 1 }.count)", systemImage: "xmark").foregroundStyle(Self.xColor)
                Label("\(state.won.filter { $0 == -1 }.count)", systemImage: "circle").foregroundStyle(Self.oColor)
            }
            .font(.system(.title3, design: .rounded, weight: .bold))
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    private func center(_ idx: Int, big: CGFloat) -> CGPoint {
        let b = idx / 9, s = idx % 9, small = big / 3
        return CGPoint(x: CGFloat(b % 3) * big + (CGFloat(s % 3) + 0.5) * small, y: CGFloat(b / 3) * big + (CGFloat(s / 3) + 0.5) * small)
    }

    private func grid(big: CGFloat) -> some View {
        Canvas { ctx, size in
            let small = big / 3
            var thin = Path(), thick = Path()
            for b in 0 ..< 9 {
                let ox = CGFloat(b % 3) * big, oy = CGFloat(b / 3) * big
                for i in 1 ... 2 {
                    let o = CGFloat(i) * small
                    thin.move(to: CGPoint(x: ox + o, y: oy + small * 0.25)); thin.addLine(to: CGPoint(x: ox + o, y: oy + big - small * 0.25))
                    thin.move(to: CGPoint(x: ox + small * 0.25, y: oy + o)); thin.addLine(to: CGPoint(x: ox + big - small * 0.25, y: oy + o))
                }
            }
            for i in 1 ... 2 {
                let o = CGFloat(i) * big
                thick.move(to: CGPoint(x: o, y: 6)); thick.addLine(to: CGPoint(x: o, y: size.height - 6))
                thick.move(to: CGPoint(x: 6, y: o)); thick.addLine(to: CGPoint(x: size.width - 6, y: o))
            }
            ctx.stroke(thin, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            ctx.stroke(thick, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        .allowsHitTesting(false)
    }

    private func marks(side: CGFloat, big: CGFloat) -> some View {
        let small = big / 3
        return ZStack(alignment: .topLeading) {
            ForEach(0 ..< 81, id: \.self) { i in
                if state.cells[i] != 0 {
                    UTTTMark(player: Int(state.cells[i]), size: small * 0.5, dim: state.won[i / 9] != 0, last: state.last == i)
                        .position(center(i, big: big))
                }
            }
            ForEach(0 ..< 9, id: \.self) { b in
                if state.won[b] == 1 || state.won[b] == -1 {
                    UTTTMark(player: Int(state.won[b]), size: big * 0.62, dim: false, last: false, bold: true)
                        .position(x: (CGFloat(b % 3) + 0.5) * big, y: (CGFloat(b / 3) + 0.5) * big)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.35), value: state.won)
        .allowsHitTesting(false)
    }

    private func tap(_ p: CGPoint, big: CGFloat) {
        guard canMove else { return }
        let small = big / 3
        let bc = Int(p.x / big), br = Int(p.y / big)
        guard (0 ..< 3).contains(bc), (0 ..< 3).contains(br) else { return }
        let sc = Int((p.x - CGFloat(bc) * big) / small), sr = Int((p.y - CGFloat(br) * big) / small)
        guard (0 ..< 3).contains(sc), (0 ..< 3).contains(sr) else { return }
        let idx = (br * 3 + bc) * 9 + sr * 3 + sc
        guard E.legal(state).contains(idx) else { Feedback.shared.failure(); return }
        Feedback.shared.thud()
        session.submit(idx)
    }
}

/// X or O, drawn with an animated stroke.
private struct UTTTMark: View {
    let player: Int
    let size: CGFloat
    let dim: Bool
    let last: Bool
    var bold = false
    @State private var progress: CGFloat = 0

    var body: some View {
        let color = player == 1 ? Color(red: 0.25, green: 0.88, blue: 1.0) : Color(red: 1.0, green: 0.38, blue: 0.62)
        ZStack {
            if player == 1 {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: size, y: size))
                    p.move(to: CGPoint(x: size, y: 0)); p.addLine(to: CGPoint(x: 0, y: size))
                }
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: bold ? size * 0.12 : size * 0.18, lineCap: .round))
                .frame(width: size, height: size)
            } else {
                Circle().trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: bold ? size * 0.12 : size * 0.18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)
            }
        }
        .shadow(color: color.opacity(last ? 0.95 : 0.45), radius: last ? 8 : 4)
        .opacity(dim ? 0.35 : 1)
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { progress = 1 } }
    }
}
