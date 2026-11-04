import SwiftUI

/// A single step or jump. Multi-jumps are a series of jumps by the same piece: the engine keeps the turn until the chain ends.
struct CheckersMove: Codable, Equatable, Sendable, Hashable {
    var from: Int
    var to: Int
}

/// Board for English draughts. Squares 0...63 (row * 8 + col); only squares where row + col is odd are used.
/// Pieces: +1 / +2 man / king for side 1 (seat 0, moves up the screen), -1 / -2 for side -1 (seat 1, moves down).
struct CheckersPosition: Codable, Equatable, Sendable {
    var b: [Int8]
    var side = 1
    /// The square of a piece that must keep jumping, or -1.
    var chain = -1

    static var start: CheckersPosition {
        var b = [Int8](repeating: 0, count: 64)
        for r in 0 ..< 8 { for c in 0 ..< 8 where (r + c) % 2 == 1 {
            if r < 3 { b[r * 8 + c] = -1 } else if r > 4 { b[r * 8 + c] = 1 }
        } }
        return CheckersPosition(b: b)
    }

    struct Option: Equatable { var from: Int; var to: Int; var captured: Int }   // captured = -1 for steps

    private func directions(_ piece: Int8) -> [(Int, Int)] {
        if abs(piece) == 2 { return [(-1, -1), (-1, 1), (1, -1), (1, 1)] }
        let dr = piece > 0 ? -1 : 1
        return [(dr, -1), (dr, 1)]
    }

    private func jumps(from sq: Int) -> [Option] {
        let piece = b[sq]
        var out: [Option] = []
        let r = sq / 8, c = sq % 8
        for (dr, dc) in directions(piece) {
            let mr = r + dr, mc = c + dc, lr = r + 2 * dr, lc = c + 2 * dc
            guard (0 ..< 8).contains(lr), (0 ..< 8).contains(lc) else { continue }
            let mid = b[mr * 8 + mc]
            if mid != 0, (mid > 0) != (piece > 0), b[lr * 8 + lc] == 0 { out.append(Option(from: sq, to: lr * 8 + lc, captured: mr * 8 + mc)) }
        }
        return out
    }

    func options() -> [Option] {
        if chain >= 0 { return jumps(from: chain) }
        var jumpList: [Option] = []
        for sq in 0 ..< 64 where b[sq] != 0 && (b[sq] > 0) == (side == 1) { jumpList += jumps(from: sq) }
        if !jumpList.isEmpty { return jumpList }
        var steps: [Option] = []
        for sq in 0 ..< 64 where b[sq] != 0 && (b[sq] > 0) == (side == 1) {
            let r = sq / 8, c = sq % 8
            for (dr, dc) in directions(b[sq]) {
                let nr = r + dr, nc = c + dc
                if (0 ..< 8).contains(nr), (0 ..< 8).contains(nc), b[nr * 8 + nc] == 0 { steps.append(Option(from: sq, to: nr * 8 + nc, captured: -1)) }
            }
        }
        return steps
    }

    /// Applies an option and returns whether a man was crowned.
    @discardableResult
    mutating func make(_ o: Option) -> Bool {
        let piece = b[o.from]
        b[o.from] = 0
        b[o.to] = piece
        var crowned = false
        if abs(piece) == 1, (piece > 0 && o.to / 8 == 0) || (piece < 0 && o.to / 8 == 7) { b[o.to] = piece * 2; crowned = true }
        if o.captured >= 0 {
            b[o.captured] = 0
            if !crowned, !jumps(from: o.to).isEmpty { chain = o.to; return crowned }
        }
        chain = -1
        side = -side
        return crowned
    }

    func key() -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for v in b { h = (h ^ UInt64(UInt8(bitPattern: v))) &* 1099511628211 }
        return (h ^ UInt64(side + 1)) &* 1099511628211
    }
}

enum CheckersEngine: TurnEngine {
    typealias Action = CheckersMove

    struct State: Codable, Sendable, Equatable {
        var pos = CheckersPosition.start
        var half = 0
        var hist: [UInt64] = [CheckersPosition.start.key()]
        /// 0 playing, 1 win, 2 draw by the 40-move rule, 3 draw by repetition
        var result = 0
        var winner: Int?
        var lastFrom = -1, lastTo = -1, lastCaptured = -1
        var lastCrowned = false
    }

    static let info = GameInfo(
        id: "checkers", title: "Checkers", tagline: "Jump, crown, conquer", symbol: "circle.circle.fill",
        origin: .board, mode: .turnBased, minPlayers: 2, maxPlayers: 2, palette: [0xCB2D3E, 0xEF473A], supportsAI: true,
        rules: "Move diagonally forward. If you can jump an opponent's piece you must, and you must keep jumping while you can. Reach the far row to become a king, which moves and jumps both ways. You win when your opponent has no pieces or no moves. Forty moves without a capture or a man move is a draw.")

    static func newGame(players: Int, seed: UInt64) -> State { State() }

    static func activeSeat(_ s: State) -> Int? { s.result == 0 ? (s.pos.side == 1 ? 0 : 1) : nil }

    static func apply(_ a: Action, by seat: Int, to s: inout State) throws {
        guard s.result == 0 else { throw ActionError("The game is over.") }
        guard seat == (s.pos.side == 1 ? 0 : 1) else { throw ActionError("Not your turn.") }
        let opts = s.pos.options()
        guard let o = opts.first(where: { $0.from == a.from && $0.to == a.to }) else {
            if opts.contains(where: { $0.captured >= 0 }) { throw ActionError("You must jump.") }
            throw ActionError("Illegal move.")
        }
        let wasMan = abs(s.pos.b[o.from]) == 1
        let crowned = s.pos.make(o)
        s.lastFrom = o.from; s.lastTo = o.to; s.lastCaptured = o.captured; s.lastCrowned = crowned
        s.half = (o.captured >= 0 || wasMan) ? 0 : s.half + 1
        if s.pos.chain >= 0 { return }
        s.hist.append(s.pos.key())
        if s.pos.options().isEmpty { s.result = 1; s.winner = seat }
        else if s.half >= 80 { s.result = 2 }
        else if s.hist.filter({ $0 == s.hist.last! }).count >= 3 { s.result = 3 }
    }

    static func outcome(_ s: State) -> Outcome? {
        switch s.result {
        case 0: return nil
        case 1: return .win(s.winner!, others: [1 - s.winner!], summary: "No moves left")
        case 2: return .draw("Forty moves without progress")
        default: return .draw("Repetition")
        }
    }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        let name = seats[s.pos.side == 1 ? 0 : 1].name
        if s.pos.chain >= 0 { return "\(name) must keep jumping" }
        if s.pos.options().contains(where: { $0.captured >= 0 }) { return "\(name) must capture" }
        return "\(name)'s turn"
    }

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Action? {
        let opts = s.pos.options()
        guard !opts.isEmpty else { return nil }
        if opts.count == 1 { return CheckersMove(from: opts[0].from, to: opts[0].to) }
        var search = CheckersSearch()
        let o = search.best(s.pos, level: level, seed: UInt64(s.hist.count))
        return CheckersMove(from: o.from, to: o.to)
    }
}

// MARK: - Search

struct CheckersSearch {
    private var deadline = Date.distantFuture
    private var nodes = 0
    private var stopped = false

    mutating func best(_ pos: CheckersPosition, level: AILevel, seed: UInt64) -> CheckersPosition.Option {
        let opts = pos.options()
        var rng = SplitMix64(seed: seed &* 7919)
        let (maxDepth, seconds, noise): (Int, Double, Int) = switch level {
        case .easy: (2, 0.2, 60)
        case .medium: (6, 0.4, 6)
        case .hard: (14, 1.3, 0)
        }
        deadline = Date().addingTimeInterval(seconds)
        var best = opts[0]
        var ordered = opts
        for depth in 1 ... maxDepth {
            var alpha = -100_000, iterBest = ordered[0]
            var scored: [(CheckersPosition.Option, Int)] = []
            for o in ordered {
                var p = pos
                p.make(o)
                var s = p.side == pos.side ? search(p, depth, alpha, 100_000) : -search(p, depth - 1, -100_000, -alpha)
                if stopped { break }
                if noise > 0 { s += rng.int(in: -noise ... noise) }
                scored.append((o, s))
                if s > alpha { alpha = s; iterBest = o }
            }
            if stopped { break }
            best = iterBest
            ordered = scored.sorted { $0.1 > $1.1 }.map(\.0)
            if abs(alpha) > 50_000 { break }
        }
        return best
    }

    private mutating func search(_ pos: CheckersPosition, _ depth: Int, _ alphaIn: Int, _ beta: Int) -> Int {
        nodes += 1
        if nodes & 1023 == 0, Date() > deadline { stopped = true }
        if stopped { return 0 }
        let opts = pos.options()
        if opts.isEmpty { return -50_000 - depth }
        if depth <= 0 && pos.chain < 0 { return evaluate(pos) }
        var alpha = alphaIn
        var best = -100_000
        for o in opts.sorted(by: { $0.captured > $1.captured }) {
            var p = pos
            p.make(o)
            let s = p.side == pos.side ? search(p, depth, alpha, beta) : -search(p, depth - 1, -beta, -alpha)
            if stopped { return 0 }
            best = max(best, s)
            alpha = max(alpha, s)
            if alpha >= beta { break }
        }
        return best
    }

    /// Score for the side to move.
    private func evaluate(_ pos: CheckersPosition) -> Int {
        var score = 0
        for sq in 0 ..< 64 {
            let p = pos.b[sq]
            if p == 0 { continue }
            let r = sq / 8, c = sq % 8
            let sign = p > 0 ? 1 : -1
            var v = abs(p) == 2 ? 175 : 100
            if abs(p) == 1 { v += (p > 0 ? 7 - r : r) * 4; if (p > 0 && r == 7) || (p < 0 && r == 0) { v += 8 } }
            if c == 0 || c == 7 { v += abs(p) == 1 ? 2 : -6 }
            if (2 ... 5).contains(r), (2 ... 5).contains(c) { v += 3 }
            score += sign * v
        }
        return pos.side == 1 ? score : -score
    }
}

// MARK: - Board

struct CheckersBoardView: View {
    let session: TurnSession<CheckersEngine>

    private struct Item: Identifiable, Equatable { let id: Int; var piece: Int8; var sq: Int }

    @State private var items: [Item] = []
    @State private var selected: Int?
    @State private var pulse = false

    private var state: CheckersEngine.State { session.state }
    private var canMove: Bool { session.isMyTurn && session.outcome == nil }
    private var options: [CheckersPosition.Option] { canMove ? state.pos.options() : [] }

    private var flipped: Bool {
        if session.mySeats.count > 1 { return state.pos.side == -1 }
        return session.mySeats == [1]
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let cell = side / 8
                ZStack(alignment: .topLeading) {
                    boardCanvas(cell: cell)
                    hints(cell: cell)
                    ForEach(items) { item in
                        discView(item, cell: cell)
                    }
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .onTapGesture { loc in tapped(at: loc, cell: cell) }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            counts
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .onAppear {
            rebuild()
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: session.version) { _, _ in sync() }
        .onChange(of: session.isMyTurn) { _, _ in selected = nil }
    }

    private func point(_ sq: Int, cell: CGFloat) -> CGPoint {
        let r = sq / 8, c = sq % 8
        let col = flipped ? 7 - c : c, row = flipped ? 7 - r : r
        return CGPoint(x: (CGFloat(col) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
    }

    private func boardCanvas(cell: CGFloat) -> some View {
        Canvas { ctx, _ in
            for r in 0 ..< 8 { for c in 0 ..< 8 {
                let dark = (r + c) % 2 == 1
                ctx.fill(Path(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)),
                         with: .color(dark ? Color(red: 0.36, green: 0.22, blue: 0.16) : Color(red: 0.93, green: 0.85, blue: 0.70)))
            } }
        }
    }

    private func hints(cell: CGFloat) -> some View {
        let movable = Set(options.map(\.from))
        let forced = options.contains { $0.captured >= 0 }
        return ZStack(alignment: .topLeading) {
            if state.lastFrom >= 0 {
                ForEach([state.lastFrom, state.lastTo], id: \.self) { sq in
                    Rectangle().fill(Color.yellow.opacity(0.28)).frame(width: cell, height: cell).position(point(sq, cell: cell))
                }
            }
            ForEach(Array(movable), id: \.self) { sq in
                RoundedRectangle(cornerRadius: 6).strokeBorder(forced ? Color.orange : Color.white.opacity(0.4), lineWidth: forced ? 3 : 2)
                    .frame(width: cell * 0.96, height: cell * 0.96).position(point(sq, cell: cell))
                    .opacity(forced ? (pulse ? 1 : 0.35) : 0.7)
            }
            if let selected {
                Rectangle().fill(Color.green.opacity(0.4)).frame(width: cell, height: cell).position(point(selected, cell: cell))
                ForEach(options.filter { $0.from == selected }, id: \.to) { o in
                    Circle().fill(Color.green.opacity(0.8)).frame(width: cell * 0.3, height: cell * 0.3).position(point(o.to, cell: cell))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func discView(_ item: Item, cell: CGFloat) -> some View {
        let red = item.piece > 0
        let base = red ? Color(red: 0.88, green: 0.22, blue: 0.24) : Color(red: 0.16, green: 0.16, blue: 0.2)
        let rim = red ? Color(red: 0.62, green: 0.1, blue: 0.14) : Color.black
        return ZStack {
            Circle().fill(.black.opacity(0.35)).offset(y: cell * 0.05)
            Circle().fill(rim)
            Circle().fill(RadialGradient(colors: [base.opacity(0.75), base], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: cell * 0.5)).padding(cell * 0.04)
            Circle().strokeBorder(.white.opacity(0.22), lineWidth: 2).padding(cell * 0.16)
            Circle().strokeBorder(.white.opacity(0.14), lineWidth: 2).padding(cell * 0.26)
            if abs(item.piece) == 2 {
                Image(systemName: "crown.fill").font(.system(size: cell * 0.34, weight: .bold)).foregroundStyle(Color(red: 1, green: 0.84, blue: 0.3))
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
            }
        }
        .frame(width: cell * 0.82, height: cell * 0.82)
        .position(point(item.sq, cell: cell))
        .animation(.snappy(duration: 0.24), value: item.sq)
        .animation(.snappy(duration: 0.24), value: flipped)
        .transition(.scale.combined(with: .opacity))
        .allowsHitTesting(false)
    }

    private var counts: some View {
        let red = state.pos.b.filter { $0 > 0 }.count, black = state.pos.b.filter { $0 < 0 }.count
        return HStack(spacing: 24) {
            Label("\(red)", systemImage: "circle.fill").foregroundStyle(Color(red: 0.88, green: 0.22, blue: 0.24))
            Label("\(black)", systemImage: "circle.fill").foregroundStyle(Color(white: 0.7))
        }
        .font(.system(.headline, design: .rounded))
    }

    // MARK: Input

    private func tapped(at p: CGPoint, cell: CGFloat) {
        guard canMove else { return }
        let col = Int(p.x / cell), row = Int(p.y / cell)
        guard (0 ..< 8).contains(col), (0 ..< 8).contains(row) else { return }
        let sq = flipped ? (7 - row) * 8 + (7 - col) : row * 8 + col
        if let selected, let o = options.first(where: { $0.from == selected && $0.to == sq }) {
            self.selected = nil
            Feedback.shared.thud()
            session.submit(CheckersMove(from: o.from, to: o.to))
        } else if options.contains(where: { $0.from == sq }) {
            selected = selected == sq ? nil : sq
            Feedback.shared.tap()
        } else {
            if selected != nil { Feedback.shared.failure() }
            selected = nil
        }
    }

    // MARK: Piece identity (for animation)

    private func rebuild() {
        var id = 0
        items = state.pos.b.enumerated().compactMap { sq, p in p == 0 ? nil : { id += 1; return Item(id: id, piece: p, sq: sq) }() }
        selected = nil
    }

    private func sync() {
        let s = state
        guard s.lastFrom >= 0, let i = items.firstIndex(where: { $0.sq == s.lastFrom }) else { rebuild(); return }
        var next = items
        let id = next[i].id
        if s.lastCaptured >= 0 { next.removeAll { $0.sq == s.lastCaptured }; Feedback.shared.play(.capture) }
        guard let j = next.firstIndex(where: { $0.id == id }) else { rebuild(); return }
        next[j].sq = s.lastTo
        if s.lastCrowned { next[j].piece *= 2 }
        var board = [Int8](repeating: 0, count: 64)
        for it in next { board[it.sq] = it.piece }
        guard board == s.pos.b else { rebuild(); return }
        selected = s.pos.chain >= 0 && session.isMyTurn ? s.pos.chain : nil
        withAnimation(.snappy(duration: 0.24)) { items = next }
    }
}
