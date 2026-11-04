import SwiftUI

/// Gomoku, free-style: 15x15 board, five or more in a row wins. Seat 0 plays black and moves first.
enum GomokuEngine: TurnEngine {
    typealias Action = Int
    static let size = 15

    struct State: Codable, Sendable, Equatable {
        var cells = [Int8](repeating: 0, count: 225)
        var side = 1
        var moves = 0
        var last = -1
        var winLine: [Int] = []
        var winner: Int?
        var drawn = false
    }

    static let info = GameInfo(
        id: "gomoku", title: "Gomoku", tagline: "Five in a row wins", symbol: "circle.grid.cross.fill",
        origin: .board, mode: .turnBased, minPlayers: 2, maxPlayers: 2, palette: [0x606C88, 0x3F4C6B], supportsAI: true,
        rules: "Take turns placing a stone on an intersection. The first player to make an unbroken line of five or more stones, horizontally, vertically or diagonally, wins. Black plays first. Tap or drag to choose a point (the stone shows above your finger), then press Place stone.")

    static func newGame(players: Int, seed: UInt64) -> State { State() }
    static func activeSeat(_ s: State) -> Int? { s.winner == nil && !s.drawn ? (s.side == 1 ? 0 : 1) : nil }

    static let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]

    static func line(_ cells: [Int8], at idx: Int, player: Int8) -> [Int]? {
        let r0 = idx / size, c0 = idx % size
        for (dr, dc) in dirs {
            var run = [idx]
            for sign in [1, -1] {
                var r = r0 + dr * sign, c = c0 + dc * sign
                while (0 ..< size).contains(r), (0 ..< size).contains(c), cells[r * size + c] == player { run.append(r * size + c); r += dr * sign; c += dc * sign }
            }
            if run.count >= 5 { return run.sorted() }
        }
        return nil
    }

    static func apply(_ idx: Int, by seat: Int, to s: inout State) throws {
        guard s.winner == nil, !s.drawn else { throw ActionError("The game is over.") }
        guard seat == (s.side == 1 ? 0 : 1) else { throw ActionError("Not your turn.") }
        guard (0 ..< 225).contains(idx), s.cells[idx] == 0 else { throw ActionError("That point is taken.") }
        s.cells[idx] = Int8(s.side)
        s.last = idx; s.moves += 1
        if let l = line(s.cells, at: idx, player: Int8(s.side)) { s.winner = seat; s.winLine = l }
        else if s.moves == 225 { s.drawn = true }
        else { s.side = -s.side }
    }

    static func outcome(_ s: State) -> Outcome? {
        if let w = s.winner { return .win(w, others: [1 - w], summary: "Five in a row") }
        return s.drawn ? .draw("The board is full") : nil
    }

    // MARK: AI

    /// Value of a run of `count` stones with `open` free ends.
    private static func runValue(_ count: Int, _ open: Int) -> Int {
        if count >= 5 { return 100_000 }
        switch (count, open) {
        case (4, 2): return 10_000
        case (4, 1): return 1_500
        case (3, 2): return 1_200
        case (3, 1): return 120
        case (2, 2): return 100
        case (2, 1): return 10
        case (1, 2): return 8
        default: return 0
        }
    }

    /// How good it would be for `player` to own point `idx` (sum over the four lines through it).
    static func pointScore(_ cells: [Int8], _ idx: Int, player: Int8) -> Int {
        let r0 = idx / size, c0 = idx % size
        var total = 0
        for (dr, dc) in dirs {
            var count = 1, open = 0
            for sign in [1, -1] {
                var r = r0 + dr * sign, c = c0 + dc * sign
                while (0 ..< size).contains(r), (0 ..< size).contains(c), cells[r * size + c] == player { count += 1; r += dr * sign; c += dc * sign }
                if (0 ..< size).contains(r), (0 ..< size).contains(c), cells[r * size + c] == 0 { open += 1 }
            }
            total += runValue(count, open)
        }
        return total
    }

    static func candidates(_ cells: [Int8], moves: Int) -> [Int] {
        if moves == 0 { return [7 * size + 7] }
        var near = Set<Int>()
        for i in 0 ..< 225 where cells[i] != 0 {
            let r = i / size, c = i % size
            for dr in -2 ... 2 { for dc in -2 ... 2 {
                let rr = r + dr, cc = c + dc
                if (0 ..< size).contains(rr), (0 ..< size).contains(cc), cells[rr * size + cc] == 0 { near.insert(rr * size + cc) }
            } }
        }
        return Array(near)
    }

    private static func ranked(_ cells: [Int8], player: Int8, moves: Int, limit: Int) -> [(Int, Int)] {
        candidates(cells, moves: moves)
            .map { ($0, pointScore(cells, $0, player: player) + Int(Double(pointScore(cells, $0, player: -player)) * 0.92)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit).map { $0 }
    }

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Action? {
        guard s.winner == nil, !s.drawn else { return nil }
        let me = Int8(s.side)
        var rng = SplitMix64(seed: UInt64(s.moves) &* 2246822519)
        let list = ranked(s.cells, player: me, moves: s.moves, limit: 14)
        guard !list.isEmpty else { return nil }
        // Always win now, and block an opponent's win, except on easy where it sometimes misses.
        if level != .easy || rng.int(in: 0 ... 3) != 0 {
            let cands = candidates(s.cells, moves: s.moves)
            if let w = cands.first(where: { pointScore(s.cells, $0, player: me) >= 100_000 }) { return w }
            if let b = cands.first(where: { pointScore(s.cells, $0, player: -me) >= 100_000 }) { return b }
        }
        switch level {
        case .easy: return list[min(rng.int(in: 0 ... 5), list.count - 1)].0
        case .medium: return list[0].0
        case .hard:
            var search = Search(deadline: Date().addingTimeInterval(1.1))
            return search.best(s.cells, me: me, moves: s.moves, list: list)
        }
    }

    private struct Search {
        let deadline: Date
        var stopped = false
        var nodes = 0

        mutating func best(_ cells: [Int8], me: Int8, moves: Int, list: [(Int, Int)]) -> Int {
            var best = list[0].0
            for depth in 1 ... 4 {
                var alpha = Int.min / 2, iter = list[0].0
                for (m, _) in list.prefix(10) {
                    var b = cells
                    b[m] = me
                    let v = -negamax(b, -me, depth - 1, Int.min / 2, -alpha, moves + 1, last: m)
                    if stopped { break }
                    if v > alpha { alpha = v; iter = m }
                }
                if stopped { break }
                best = iter
            }
            return best
        }

        mutating func negamax(_ cells: [Int8], _ player: Int8, _ depth: Int, _ alphaIn: Int, _ beta: Int, _ moves: Int, last: Int) -> Int {
            nodes += 1
            if nodes & 255 == 0, Date() > deadline { stopped = true }
            if stopped { return 0 }
            if GomokuEngine.line(cells, at: last, player: -player) != nil { return -1_000_000 - depth }
            if depth == 0 { return evaluate(cells, player, moves) }
            var alpha = alphaIn, best = Int.min / 2
            for (m, _) in GomokuEngine.ranked(cells, player: player, moves: moves, limit: 8) {
                var b = cells
                b[m] = player
                let v = -negamax(b, -player, depth - 1, -beta, -alpha, moves + 1, last: m)
                if stopped { return 0 }
                best = max(best, v); alpha = max(alpha, v)
                if alpha >= beta { break }
            }
            return best == Int.min / 2 ? 0 : best
        }

        /// Static score for the side to move: own potential minus the opponent's, scanning the best points.
        func evaluate(_ cells: [Int8], _ player: Int8, _ moves: Int) -> Int {
            var mine = 0, theirs = 0
            for i in GomokuEngine.candidates(cells, moves: moves) {
                mine = max(mine, GomokuEngine.pointScore(cells, i, player: player))
                theirs = max(theirs, GomokuEngine.pointScore(cells, i, player: -player))
            }
            return mine - theirs / 2
        }
    }
}

// MARK: - Board

struct GomokuBoardView: View {
    let session: TurnSession<GomokuEngine>
    @State private var ghost: Int?
    @State private var pulse = false

    private typealias E = GomokuEngine
    private var state: E.State { session.state }
    private var canMove: Bool { session.isMyTurn && session.outcome == nil }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let cell = side / 15
                ZStack(alignment: .topLeading) {
                    grid(cell: cell)
                    ForEach(0 ..< 225, id: \.self) { i in
                        if state.cells[i] != 0 { stone(Int(state.cells[i]), cell: cell, win: state.winLine.contains(i), last: state.last == i).position(point(i, cell: cell)) }
                    }
                    if let ghost, canMove, state.cells[ghost] == 0 {
                        let p = point(ghost, cell: cell)
                        Path { path in
                            path.move(to: CGPoint(x: cell / 2, y: p.y)); path.addLine(to: CGPoint(x: side - cell / 2, y: p.y))
                            path.move(to: CGPoint(x: p.x, y: cell / 2)); path.addLine(to: CGPoint(x: p.x, y: side - cell / 2))
                        }.stroke(Theme.accent.opacity(0.55), lineWidth: 1.5)
                        stone(state.side == 1 ? 1 : -1, cell: cell, win: false, last: false).opacity(0.7).position(p)
                    }
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard canMove else { return }
                        let dragged = hypot(v.translation.width, v.translation.height) > 8
                        ghost = index(CGPoint(x: v.location.x, y: v.location.y - (dragged ? cell * 1.7 : 0)), cell: cell) ?? ghost
                    }
                    .onEnded { v in
                        guard canMove else { return }
                        let dragged = hypot(v.translation.width, v.translation.height) > 8
                        if !dragged, let i = index(v.location, cell: cell), i == ghost, state.cells[i] == 0 { place() }
                        else if !dragged { ghost = index(v.location, cell: cell) }
                    })
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            Button { place() } label: { Label("Place stone", systemImage: "circle.fill") }
                .buttonStyle(PrimaryButtonStyle(tint: ghost != nil && canMove ? Theme.accent : Theme.surface2))
                .disabled(ghost == nil || !canMove)
                .frame(maxWidth: 260)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
        .onChange(of: session.version) { _, _ in ghost = nil }
    }

    private func point(_ i: Int, cell: CGFloat) -> CGPoint { CGPoint(x: (CGFloat(i % 15) + 0.5) * cell, y: (CGFloat(i / 15) + 0.5) * cell) }

    private func index(_ p: CGPoint, cell: CGFloat) -> Int? {
        let c = Int(p.x / cell), r = Int(p.y / cell)
        return (0 ..< 15).contains(c) && (0 ..< 15).contains(r) ? r * 15 + c : nil
    }

    private func place() {
        guard canMove, let g = ghost, state.cells[g] == 0 else { return }
        ghost = nil
        Feedback.shared.thud()
        session.submit(g)
    }

    private func grid(cell: CGFloat) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.89, green: 0.72, blue: 0.45), Color(red: 0.80, green: 0.60, blue: 0.33)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            var p = Path()
            for i in 0 ..< 15 {
                let o = (CGFloat(i) + 0.5) * cell
                p.move(to: CGPoint(x: o, y: cell / 2)); p.addLine(to: CGPoint(x: o, y: size.height - cell / 2))
                p.move(to: CGPoint(x: cell / 2, y: o)); p.addLine(to: CGPoint(x: size.width - cell / 2, y: o))
            }
            ctx.stroke(p, with: .color(Color(red: 0.25, green: 0.15, blue: 0.07).opacity(0.85)), lineWidth: 1)
            for (r, c) in [(3, 3), (3, 11), (11, 3), (11, 11), (7, 7)] {
                ctx.fill(Path(ellipseIn: CGRect(x: (CGFloat(c) + 0.5) * cell - 3.5, y: (CGFloat(r) + 0.5) * cell - 3.5, width: 7, height: 7)), with: .color(Color(red: 0.25, green: 0.15, blue: 0.07)))
            }
        }
    }

    private func stone(_ v: Int, cell: CGFloat, win: Bool, last: Bool) -> some View {
        let d = cell * 0.88
        return ZStack {
            Circle().fill(.black.opacity(0.35)).offset(x: 1, y: 2)
            Circle().fill(v == 1
                ? RadialGradient(colors: [Color(white: 0.4), Color(white: 0.03)], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: d * 0.7)
                : RadialGradient(colors: [.white, Color(white: 0.8)], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: d * 0.7))
            if last { Circle().fill(Color.red).frame(width: d * 0.2, height: d * 0.2) }
            if win { Circle().strokeBorder(Color.yellow, lineWidth: 3).opacity(pulse ? 1 : 0.3) }
        }
        .frame(width: d, height: d)
        .transition(.scale(scale: 0.3).combined(with: .opacity))
    }
}
