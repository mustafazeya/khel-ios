import SwiftUI

enum ReversiEngine: TurnEngine {
    typealias Action = Int

    struct State: Codable, Sendable, Equatable {
        /// +1 seat 0 (black), -1 seat 1 (white), 0 empty. Square = row * 8 + col.
        var b: [Int8] = {
            var b = [Int8](repeating: 0, count: 64)
            b[27] = -1; b[36] = -1; b[28] = 1; b[35] = 1
            return b
        }()
        var side = 1
        var over = false
        var last = -1
        var flipped: [Int] = []
        /// The seat that had to pass on the previous turn, or -1.
        var passed = -1
        var moves = 0
    }

    static let info = GameInfo(
        id: "reversi", title: "Reversi", tagline: "Flip the board to your colour", symbol: "circle.lefthalf.filled",
        origin: .board, mode: .turnBased, minPlayers: 2, maxPlayers: 2, palette: [0x134E5E, 0x71B280], supportsAI: true,
        rules: "Place a disc so that it traps a line of your opponent's discs between your new disc and another of yours: they all flip to your colour. You must flip at least one disc, and you pass only when you have no move. When neither player can move, whoever has more discs wins.")

    private static let dirs = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

    static func newGame(players: Int, seed: UInt64) -> State { State() }

    /// Squares that would be flipped by `side` playing at `sq` (empty when the move is illegal).
    static func flips(_ b: [Int8], _ sq: Int, side: Int) -> [Int] {
        guard b[sq] == 0 else { return [] }
        var out: [Int] = []
        let r0 = sq / 8, c0 = sq % 8
        for (dr, dc) in dirs {
            var line: [Int] = []
            var r = r0 + dr, c = c0 + dc
            while (0 ..< 8).contains(r), (0 ..< 8).contains(c), b[r * 8 + c] == Int8(-side) { line.append(r * 8 + c); r += dr; c += dc }
            if !line.isEmpty, (0 ..< 8).contains(r), (0 ..< 8).contains(c), b[r * 8 + c] == Int8(side) { out += line }
        }
        return out
    }

    static func legalMoves(_ b: [Int8], side: Int) -> [Int] { (0 ..< 64).filter { !flips(b, $0, side: side).isEmpty } }

    static func counts(_ s: State) -> (black: Int, white: Int) { (s.b.filter { $0 == 1 }.count, s.b.filter { $0 == -1 }.count) }

    static func apply(_ sq: Int, by seat: Int, to s: inout State) throws {
        guard !s.over else { throw ActionError("The game is over.") }
        guard seat == (s.side == 1 ? 0 : 1) else { throw ActionError("Not your turn.") }
        guard (0 ..< 64).contains(sq) else { throw ActionError("Off the board.") }
        let f = flips(s.b, sq, side: s.side)
        guard !f.isEmpty else { throw ActionError("That move flips nothing.") }
        s.b[sq] = Int8(s.side)
        for i in f { s.b[i] = Int8(s.side) }
        s.last = sq; s.flipped = f; s.moves += 1; s.passed = -1
        let opponent = -s.side
        if !legalMoves(s.b, side: opponent).isEmpty { s.side = opponent }
        else if !legalMoves(s.b, side: s.side).isEmpty { s.passed = opponent == 1 ? 0 : 1 }
        else { s.over = true }
    }

    static func activeSeat(_ s: State) -> Int? { s.over ? nil : (s.side == 1 ? 0 : 1) }

    static func outcome(_ s: State) -> Outcome? {
        guard s.over else { return nil }
        let (b, w) = counts(s)
        if b == w { return .draw("\(b) – \(w)") }
        return b > w ? .win(0, others: [1], summary: "\(b) – \(w)") : .win(1, others: [0], summary: "\(w) – \(b)")
    }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        let name = seats[s.side == 1 ? 0 : 1].name
        if s.passed >= 0 { return "\(seats[s.passed].name) has no move · \(name) plays again" }
        return "\(name)'s turn"
    }

    // MARK: AI

    private static let weights: [Int] = [
        100, -20, 10, 5, 5, 10, -20, 100, -20, -50, -2, -2, -2, -2, -50, -20, 10, -2, 1, 1, 1, 1, -2, 10, 5, -2, 1, 0, 0, 1, -2, 5,
        5, -2, 1, 0, 0, 1, -2, 5, 10, -2, 1, 1, 1, 1, -2, 10, -20, -50, -2, -2, -2, -2, -50, -20, 100, -20, 10, 5, 5, 10, -20, 100,
    ]

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Int? {
        let moves = legalMoves(s.b, side: s.side)
        guard !moves.isEmpty else { return nil }
        var rng = SplitMix64(seed: UInt64(s.moves) &* 104729)
        switch level {
        case .easy:
            if rng.int(in: 0 ... 2) == 0 { return moves.max { flips(s.b, $0, side: s.side).count < flips(s.b, $1, side: s.side).count } }
            return moves[rng.int(in: 0 ... moves.count - 1)]
        case .medium:
            var search = Search(deadline: Date().addingTimeInterval(0.4))
            return search.best(s.b, side: s.side, moves: moves, maxDepth: 4)
        case .hard:
            var search = Search(deadline: Date().addingTimeInterval(1.1))
            return search.best(s.b, side: s.side, moves: moves, maxDepth: 12)
        }
    }

    private struct Search {
        let deadline: Date
        var nodes = 0
        var stopped = false

        mutating func best(_ b: [Int8], side: Int, moves: [Int], maxDepth: Int) -> Int {
            var best = moves[0]
            var ordered = moves.sorted { weights[$0] > weights[$1] }
            for depth in 1 ... maxDepth {
                var alpha = -1_000_000, iterBest = ordered[0]
                var scored: [(Int, Int)] = []
                for m in ordered {
                    var nb = b
                    nb[m] = Int8(side)
                    for f in flips(b, m, side: side) { nb[f] = Int8(side) }
                    let score = -negamax(nb, -side, depth - 1, -1_000_000, -alpha, passed: false)
                    if stopped { break }
                    scored.append((m, score))
                    if score > alpha { alpha = score; iterBest = m }
                }
                if stopped { break }
                best = iterBest
                ordered = scored.sorted { $0.1 > $1.1 }.map(\.0)
            }
            return best
        }

        mutating func negamax(_ b: [Int8], _ side: Int, _ depth: Int, _ alphaIn: Int, _ beta: Int, passed: Bool) -> Int {
            nodes += 1
            if nodes & 511 == 0, Date() > deadline { stopped = true }
            if stopped { return 0 }
            let moves = legalMoves(b, side: side)
            if moves.isEmpty {
                if passed { return final(b, side) }
                return -negamax(b, -side, depth, -beta, -alphaIn, passed: true)
            }
            if depth <= 0 { return evaluate(b, side) }
            var alpha = alphaIn
            var best = -1_000_000
            for m in moves.sorted(by: { weights[$0] > weights[$1] }) {
                var nb = b
                nb[m] = Int8(side)
                for f in flips(b, m, side: side) { nb[f] = Int8(side) }
                let s = -negamax(nb, -side, depth - 1, -beta, -alpha, passed: false)
                if stopped { return 0 }
                best = max(best, s)
                alpha = max(alpha, s)
                if alpha >= beta { break }
            }
            return best
        }

        func final(_ b: [Int8], _ side: Int) -> Int {
            let diff = b.reduce(0) { $0 + Int($1) } * side
            return diff == 0 ? 0 : (diff > 0 ? 100_000 + diff : -100_000 + diff)
        }

        func evaluate(_ b: [Int8], _ side: Int) -> Int {
            var pos = 0, discs = 0
            for i in 0 ..< 64 where b[i] != 0 { pos += weights[i] * Int(b[i]) * side; discs += Int(b[i]) * side }
            let mine = legalMoves(b, side: side).count, theirs = legalMoves(b, side: -side).count
            let mobility = mine + theirs == 0 ? 0 : 100 * (mine - theirs) / (mine + theirs + 1)
            let empties = b.filter { $0 == 0 }.count
            return pos + mobility * 3 + (empties < 14 ? discs * 4 : 0)
        }
    }
}

// MARK: - Board

/// A disc that turns over with a 3D flip: angle 0 shows black, 180 shows white.
private struct ReversiDisc: View, Animatable {
    var angle: Double
    var size: CGFloat
    var animatableData: Double { get { angle } set { angle = newValue } }

    var body: some View {
        let black = angle < 90
        let face = black
            ? RadialGradient(colors: [Color(white: 0.34), Color(white: 0.06)], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.6)
            : RadialGradient(colors: [Color.white, Color(white: 0.78)], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.6)
        Circle().fill(face)
            .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
            .frame(width: size, height: size)
            .scaleEffect(x: 1, y: 1)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(black ? 0 : 180), axis: (x: 0, y: 1, z: 0))
    }
}

struct ReversiBoardView: View {
    let session: TurnSession<ReversiEngine>

    private typealias E = ReversiEngine
    private var state: E.State { session.state }
    private var canMove: Bool { session.isMyTurn && session.outcome == nil }
    private var legal: Set<Int> { canMove ? Set(E.legalMoves(state.b, side: state.side)) : [] }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let cell = side / 8
                ZStack(alignment: .topLeading) {
                    felt(cell: cell)
                    ForEach(0 ..< 64, id: \.self) { sq in
                        let v = state.b[sq]
                        let r = sq / 8, c = sq % 8
                        ZStack {
                            if v != 0 {
                                ReversiDisc(angle: v == 1 ? 0 : 180, size: cell * 0.8)
                                    .animation(.easeInOut(duration: 0.5).delay(flipDelay(sq)), value: v)
                                    .transition(.scale(scale: 0.2).combined(with: .opacity))
                            } else if legal.contains(sq) {
                                Circle().fill(Color.white.opacity(0.3)).frame(width: cell * 0.24, height: cell * 0.24)
                            }
                            if state.last == sq {
                                Circle().fill(Color.red.opacity(0.85)).frame(width: cell * 0.14, height: cell * 0.14)
                            }
                        }
                        .frame(width: cell, height: cell)
                        .contentShape(Rectangle())
                        .position(x: (CGFloat(c) + 0.5) * cell, y: (CGFloat(r) + 0.5) * cell)
                        .onTapGesture { tap(sq) }
                        .animation(.spring(duration: 0.3, bounce: 0.3), value: v)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            scores
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    private func flipDelay(_ sq: Int) -> Double {
        guard state.last >= 0, state.flipped.contains(sq) else { return 0 }
        let d = max(abs(sq / 8 - state.last / 8), abs(sq % 8 - state.last % 8))
        return Double(d) * 0.09
    }

    private func felt(cell: CGFloat) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.08, green: 0.45, blue: 0.30), Color(red: 0.05, green: 0.32, blue: 0.22)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            var grid = Path()
            for i in 0 ... 8 {
                grid.move(to: CGPoint(x: CGFloat(i) * cell, y: 0)); grid.addLine(to: CGPoint(x: CGFloat(i) * cell, y: size.height))
                grid.move(to: CGPoint(x: 0, y: CGFloat(i) * cell)); grid.addLine(to: CGPoint(x: size.width, y: CGFloat(i) * cell))
            }
            ctx.stroke(grid, with: .color(.black.opacity(0.35)), lineWidth: 1.2)
        }
    }

    private var scores: some View {
        let (b, w) = E.counts(state)
        return HStack(spacing: 28) {
            scoreChip(count: b, color: Color(white: 0.1), active: state.side == 1 && !state.over)
            scoreChip(count: w, color: .white, active: state.side == -1 && !state.over)
        }
    }

    private func scoreChip(count: Int, color: Color, active: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 22, height: 22).overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
            Text("\(count)").font(.system(size: 22, weight: .heavy, design: .rounded)).contentTransition(.numericText())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(active ? Theme.surface2 : Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(active ? Theme.accent : .clear, lineWidth: 2))
        .animation(.snappy, value: count)
    }

    private func tap(_ sq: Int) {
        guard canMove else { return }
        guard legal.contains(sq) else { Feedback.shared.failure(); return }
        Feedback.shared.thud()
        session.submit(sq)
    }
}
