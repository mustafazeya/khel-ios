import SwiftUI

enum ConnectFourEngine: TurnEngine {
    static let cols = 7, rows = 6

    struct State: Codable, Sendable, Equatable {
        /// Row-major, row 0 is the top. 0 empty, 1 seat 0, 2 seat 1.
        var cells = [UInt8](repeating: 0, count: ConnectFourEngine.cols * ConnectFourEngine.rows)
        var turn = 0
        var moves = 0
        var winLine: [Int] = []
        var winner: Int?
        var drawn = false
    }
    typealias Action = Int

    static let info = GameInfo(
        id: "connect4", title: "Connect Four", tagline: "Drop discs, line up four", symbol: "circle.grid.3x3.fill",
        origin: .board, mode: .turnBased, minPlayers: 2, maxPlayers: 2, palette: [0x2193B0, 0x6DD5ED], supportsAI: true,
        rules: "Take turns dropping a disc into one of the seven columns. Discs fall to the lowest free slot. The first player to line up four of their discs horizontally, vertically or diagonally wins. If the board fills up it is a draw.")

    static func newGame(players: Int, seed: UInt64) -> State { State() }

    static func landingRow(_ s: State, col: Int) -> Int? {
        for r in stride(from: rows - 1, through: 0, by: -1) where s.cells[r * cols + col] == 0 { return r }
        return nil
    }

    static func apply(_ col: Int, by seat: Int, to s: inout State) throws {
        guard s.winner == nil, !s.drawn else { throw ActionError("The game is over.") }
        guard seat == s.turn else { throw ActionError("Not your turn.") }
        guard (0 ..< cols).contains(col), let row = landingRow(s, col: col) else { throw ActionError("That column is full.") }
        let piece = UInt8(seat + 1)
        s.cells[row * cols + col] = piece
        s.moves += 1
        if let line = fourInRow(s.cells, row: row, col: col, piece: piece) {
            s.winner = seat
            s.winLine = line
        } else if s.moves == cols * rows {
            s.drawn = true
        } else {
            s.turn = 1 - seat
        }
    }

    /// The run of four or more through (row, col), if the piece there completes one.
    static func fourInRow(_ cells: [UInt8], row: Int, col: Int, piece: UInt8) -> [Int]? {
        for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            var line = [row * cols + col]
            for sign in [1, -1] {
                var r = row + dr * sign, c = col + dc * sign
                while (0 ..< rows).contains(r), (0 ..< cols).contains(c), cells[r * cols + c] == piece {
                    line.append(r * cols + c)
                    r += dr * sign; c += dc * sign
                }
            }
            if line.count >= 4 { return line.sorted() }
        }
        return nil
    }

    static func activeSeat(_ s: State) -> Int? { s.winner == nil && !s.drawn ? s.turn : nil }

    static func outcome(_ s: State) -> Outcome? {
        if let w = s.winner { return .win(w, others: [1 - w], summary: "Four in a row") }
        return s.drawn ? .draw("The board is full") : nil
    }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        return "\(seats[s.turn].name)'s turn"
    }

    // MARK: AI

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Int? {
        let legal = (0 ..< cols).filter { landingRow(s, col: $0) != nil }
        guard !legal.isEmpty else { return nil }
        var rng = SplitMix64(seed: UInt64(s.moves) &* 0x9E37 &+ UInt64(seat))
        let me = UInt8(seat + 1)

        func immediate(_ piece: UInt8) -> Int? {
            for c in legal {
                var t = s; t.turn = Int(piece) - 1
                if (try? apply(c, by: Int(piece) - 1, to: &t)) != nil, t.winner != nil { return c }
            }
            return nil
        }

        switch level {
        case .easy:
            if rng.int(in: 0 ... 1) == 0 {
                if let w = immediate(me) { return w }
                if let b = immediate(3 - me) { return b }
            }
            return legal[rng.int(in: 0 ... legal.count - 1)]
        case .medium, .hard:
            if let w = immediate(me) { return w }
            if let b = immediate(3 - me) { return b }
            let budget: Double = level == .hard ? 1.0 : 0.25
            let maxDepth = level == .hard ? 12 : 5
            var search = Search(cells: s.cells, deadline: Date().addingTimeInterval(budget))
            var best = legal.sorted { abs($0 - 3) < abs($1 - 3) }[0]
            for depth in 1 ... maxDepth {
                guard let result = search.root(me: me, depth: depth), !search.timedOut else { break }
                best = result
            }
            return best
        }
    }

    private struct Search {
        var cells: [UInt8]
        let deadline: Date
        var nodes = 0
        var timedOut = false

        init(cells: [UInt8], deadline: Date) { self.cells = cells; self.deadline = deadline }

        private let order = [3, 2, 4, 1, 5, 0, 6]
        private let win = 100_000

        mutating func root(me: UInt8, depth: Int) -> Int? {
            var best: (col: Int, score: Int)?
            var alpha = -win * 2
            for c in order {
                guard let r = drop(c, me) else { continue }
                let score = won(r, c, me) ? win + depth : -negamax(3 - me, depth - 1, -win * 2, -alpha)
                undo(r, c)
                if timedOut { return best?.col }
                if best == nil || score > best!.score { best = (c, score) }
                alpha = max(alpha, score)
            }
            return best?.col
        }

        private mutating func negamax(_ player: UInt8, _ depth: Int, _ alphaIn: Int, _ beta: Int) -> Int {
            nodes += 1
            if nodes & 1023 == 0, Date() > deadline { timedOut = true }
            if timedOut { return 0 }
            if depth == 0 { return evaluate(player) }
            var alpha = alphaIn
            var any = false
            var best = -win * 2
            for c in order {
                guard let r = drop(c, player) else { continue }
                any = true
                let score = won(r, c, player) ? win + depth : -negamax(3 - player, depth - 1, -beta, -alpha)
                undo(r, c)
                if score > best { best = score }
                alpha = max(alpha, score)
                if alpha >= beta { break }
            }
            return any ? best : 0
        }

        private mutating func drop(_ c: Int, _ p: UInt8) -> Int? {
            for r in stride(from: ConnectFourEngine.rows - 1, through: 0, by: -1) where cells[r * ConnectFourEngine.cols + c] == 0 {
                cells[r * ConnectFourEngine.cols + c] = p
                return r
            }
            return nil
        }

        private mutating func undo(_ r: Int, _ c: Int) { cells[r * ConnectFourEngine.cols + c] = 0 }

        private func won(_ r: Int, _ c: Int, _ p: UInt8) -> Bool { ConnectFourEngine.fourInRow(cells, row: r, col: c, piece: p) != nil }

        /// Score from the point of view of `player` (who is to move).
        private func evaluate(_ player: UInt8) -> Int {
            let cols = ConnectFourEngine.cols, rows = ConnectFourEngine.rows
            var score = 0
            for r in 0 ..< rows { if cells[r * cols + 3] == player { score += 3 } else if cells[r * cols + 3] != 0 { score -= 3 } }
            for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
                for r in 0 ..< rows { for c in 0 ..< cols {
                    let er = r + dr * 3, ec = c + dc * 3
                    guard (0 ..< rows).contains(er), (0 ..< cols).contains(ec) else { continue }
                    var mine = 0, theirs = 0
                    for k in 0 ..< 4 {
                        let v = cells[(r + dr * k) * cols + c + dc * k]
                        if v == player { mine += 1 } else if v != 0 { theirs += 1 }
                    }
                    if mine > 0 && theirs > 0 { continue }
                    if mine == 3 { score += 6 } else if mine == 2 { score += 2 }
                    if theirs == 3 { score -= 7 } else if theirs == 2 { score -= 2 }
                } }
            }
            return score
        }
    }
}

// MARK: - Board

struct ConnectFourBoardView: View {
    let session: TurnSession<ConnectFourEngine>
    @State private var pulse = false

    private let cols = ConnectFourEngine.cols, rows = ConnectFourEngine.rows

    var body: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / CGFloat(cols), (geo.size.height - 56) / CGFloat(rows), 64)
            let w = cell * CGFloat(cols), h = cell * CGFloat(rows)
            VStack(spacing: 8) {
                preview(cell: cell).frame(width: w, height: 48)
                ZStack {
                    discs(cell: cell, height: h)
                    frame(cell: cell).allowsHitTesting(false)
                    columnTargets(cell: cell, height: h)
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
    }

    private func color(_ piece: UInt8) -> Color {
        piece == 1 ? Color(red: 1, green: 0.28, blue: 0.3) : Color(red: 1, green: 0.82, blue: 0.2)
    }

    private func discView(_ piece: UInt8, size: CGFloat, glow: Bool) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color(piece).opacity(0.75), color(piece)], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.7))
            .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 2).padding(size * 0.14))
            .overlay(Circle().strokeBorder(.white.opacity(glow ? (pulse ? 0.95 : 0.3) : 0), lineWidth: 4))
            .frame(width: size * 0.84, height: size * 0.84)
    }

    private func discs(cell: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.05, green: 0.09, blue: 0.22)
            ForEach(0 ..< session.state.cells.count, id: \.self) { i in
                let piece = session.state.cells[i]
                if piece != 0 {
                    discView(piece, size: cell, glow: session.state.winLine.contains(i))
                        .position(x: CGFloat(i % cols) * cell + cell / 2, y: CGFloat(i / cols) * cell + cell / 2)
                        .transition(.offset(y: -(height + cell)))
                }
            }
        }
        .animation(.interpolatingSpring(stiffness: 140, damping: 11), value: session.state.cells)
    }

    private func frame(cell: CGFloat) -> some View {
        Canvas { ctx, size in
            func hole(_ r: Int, _ c: Int) -> CGRect {
                CGRect(x: CGFloat(c) * cell + cell * 0.08, y: CGFloat(r) * cell + cell * 0.08, width: cell * 0.84, height: cell * 0.84)
            }
            var path = Path(CGRect(origin: .zero, size: size))
            for r in 0 ..< rows { for c in 0 ..< cols { path.addEllipse(in: hole(r, c)) } }
            ctx.fill(path, with: .linearGradient(Gradient(colors: [Color(red: 0.18, green: 0.45, blue: 0.95), Color(red: 0.08, green: 0.25, blue: 0.7)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), style: FillStyle(eoFill: true))
            for r in 0 ..< rows { for c in 0 ..< cols { ctx.stroke(Path(ellipseIn: hole(r, c)), with: .color(.black.opacity(0.25)), lineWidth: 2) } }
        }
    }

    private func columnTargets(cell: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0 ..< cols, id: \.self) { c in
                Color.clear.contentShape(Rectangle())
                    .frame(width: cell, height: height)
                    .onTapGesture { drop(c) }
                    .accessibilityLabel("Column \(c + 1)")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func preview(cell: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0 ..< cols, id: \.self) { c in
                let full = ConnectFourEngine.landingRow(session.state, col: c) == nil
                ZStack {
                    if session.isMyTurn, !full, session.outcome == nil {
                        discView(UInt8(session.state.turn + 1), size: cell * 0.7, glow: false).opacity(0.28)
                    }
                }
                .frame(width: cell, height: 48)
            }
        }
    }

    private func drop(_ col: Int) {
        guard session.isMyTurn, session.outcome == nil else { return }
        guard ConnectFourEngine.landingRow(session.state, col: col) != nil else { Feedback.shared.failure(); return }
        Feedback.shared.thud()
        session.submit(col)
    }
}
