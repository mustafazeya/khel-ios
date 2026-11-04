import Foundation

enum ChessEngine: TurnEngine {
    /// A move, or a resignation when `from` is -1.
    typealias Action = ChessMove

    static let resign = ChessMove(from: -1, to: -1)

    struct State: Codable, Sendable, Equatable {
        var pos = ChessPosition.start
        var hist: [UInt64] = [ChessPosition.start.repetitionKey()]
        /// 0 playing, 1 checkmate, 2 stalemate, 3 insufficient material, 4 fifty moves, 5 repetition, 6 resignation
        var result = 0
        var winner: Int?
        var lastFrom = -1, lastTo = -1, lastPromo = 0
        var inCheck = false
    }

    static let info = GameInfo(
        id: "chess", title: "Chess", tagline: "The game of kings", symbol: "crown.fill",
        origin: .board, mode: .turnBased, minPlayers: 2, maxPlayers: 2, palette: [0x232526, 0x5C5C6E], supportsAI: true,
        rules: "Full chess rules: castling, en passant, promotion, check and checkmate. The game is drawn by stalemate, insufficient material, the fifty-move rule or threefold repetition. Tap or drag a piece, then its destination. White moves first.")

    static func newGame(players: Int, seed: UInt64) -> State { State() }

    static func activeSeat(_ s: State) -> Int? { s.result == 0 ? (s.pos.side == 1 ? 0 : 1) : nil }

    static func apply(_ a: Action, by seat: Int, to s: inout State) throws {
        guard s.result == 0 else { throw ActionError("The game is over.") }
        guard seat == (s.pos.side == 1 ? 0 : 1) else { throw ActionError("Not your turn.") }
        if a.from < 0 { s.result = 6; s.winner = 1 - seat; return }
        let legal = s.pos.legalMoves()
        guard let m = legal.first(where: { $0 == a }) else {
            if legal.contains(where: { $0.from == a.from && $0.to == a.to }) { throw ActionError("Choose a piece to promote to.") }
            throw ActionError("Illegal move.")
        }
        var p = s.pos
        p.make(m)
        s.pos = p
        s.lastFrom = m.from; s.lastTo = m.to; s.lastPromo = m.promo
        s.hist.append(p.repetitionKey())
        s.inCheck = p.inCheck
        if p.legalMoves().isEmpty {
            if s.inCheck { s.result = 1; s.winner = seat } else { s.result = 2 }
        } else if p.insufficientMaterial {
            s.result = 3
        } else if p.half >= 100 {
            s.result = 4
        } else if s.hist.filter({ $0 == s.hist.last! }).count >= 3 {
            s.result = 5
        }
    }

    static func outcome(_ s: State) -> Outcome? {
        switch s.result {
        case 0: return nil
        case 1: return .win(s.winner!, others: [1 - s.winner!], summary: "Checkmate")
        case 6: return .win(s.winner!, others: [1 - s.winner!], summary: "Resignation")
        case 2: return .draw("Stalemate")
        case 3: return .draw("Insufficient material")
        case 4: return .draw("Fifty-move rule")
        default: return .draw("Threefold repetition")
        }
    }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        let name = seats[s.pos.side == 1 ? 0 : 1].name
        return s.inCheck ? "\(name) is in check" : "\(name)'s turn"
    }

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Action? {
        guard s.result == 0 else { return nil }
        var search = ChessSearch(pos: s.pos, history: Set(s.hist))
        return search.best(level: level)
    }
}

// MARK: - Search

struct ChessSearch {
    var pos: ChessPosition
    var history: Set<UInt64>
    private var deadline = Date.distantFuture
    private var nodes = 0
    private var stopped = false
    private var killers = [[Int]](repeating: [-1, -1], count: 64)
    private var hist = [Int](repeating: 0, count: 4096)
    private let mate = 100_000

    init(pos: ChessPosition, history: Set<UInt64>) { self.pos = pos; self.history = history }

    static let values: [Int] = [0, 100, 320, 330, 500, 900, 0]

    mutating func best(level: AILevel) -> ChessMove? {
        let legal = pos.legalMoves()
        guard !legal.isEmpty else { return nil }
        if legal.count == 1 { return legal[0] }
        var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: pos.repetitionKey()))
        switch level {
        case .easy:
            deadline = Date().addingTimeInterval(0.3)
            var bestMove = legal[0], bestScore = Int.min
            for m in legal {
                let u = pos.make(m)
                let s = -quiesce(-mate, mate, ply: 0) + rng.int(in: -180 ... 180)
                pos.unmake(u)
                if s > bestScore { bestScore = s; bestMove = m }
            }
            return bestMove
        case .medium: return iterate(legal, maxDepth: 4, seconds: 0.5)
        case .hard: return iterate(legal, maxDepth: 9, seconds: 1.4)
        }
    }

    private mutating func iterate(_ legal: [ChessMove], maxDepth: Int, seconds: Double) -> ChessMove {
        deadline = Date().addingTimeInterval(seconds)
        var ordered = order(legal, ply: 0, first: nil)
        var best = ordered[0]
        for depth in 1 ... maxDepth {
            var alpha = -mate - 1
            var iterationBest = ordered[0]
            var scores: [(ChessMove, Int)] = []
            for m in ordered {
                let u = pos.make(m)
                let score = -negamax(depth - 1, -mate - 1, -alpha, ply: 1)
                pos.unmake(u)
                if stopped { break }
                scores.append((m, score))
                if score > alpha { alpha = score; iterationBest = m }
            }
            if stopped { break }
            best = iterationBest
            ordered = scores.sorted { $0.1 > $1.1 }.map(\.0)
            if alpha > mate - 100 { break }
        }
        return best
    }

    private mutating func negamax(_ depthIn: Int, _ alphaIn: Int, _ beta: Int, ply: Int) -> Int {
        nodes += 1
        if nodes & 2047 == 0, Date() > deadline { stopped = true }
        if stopped { return 0 }
        if pos.half >= 100 || (ply > 0 && history.contains(pos.repetitionKey())) { return 0 }
        let check = pos.inCheck
        var depth = depthIn
        if check, ply < 30 { depth += 1 }
        if depth <= 0 { return quiesce(alphaIn, beta, ply: ply) }
        var alpha = alphaIn
        var legal = 0
        let side = pos.side
        var bestScore = -mate - 1
        for m in order(pos.pseudoMoves(), ply: ply, first: nil) {
            let u = pos.make(m)
            if pos.isAttacked(pos.kings[side == 1 ? 0 : 1], by: -side) { pos.unmake(u); continue }
            legal += 1
            let score = -negamax(depth - 1, -beta, -alpha, ply: ply + 1)
            pos.unmake(u)
            if stopped { return 0 }
            if score > bestScore { bestScore = score }
            if score > alpha { alpha = score }
            if alpha >= beta {
                if pos.b[m.to] == 0, ply < 64 { killers[ply][1] = killers[ply][0]; killers[ply][0] = m.from * 64 + m.to; hist[m.from * 64 + m.to] += depth * depth }
                break
            }
        }
        if legal == 0 { return check ? -mate + ply : 0 }
        return bestScore
    }

    private mutating func quiesce(_ alphaIn: Int, _ beta: Int, ply: Int) -> Int {
        nodes += 1
        if nodes & 2047 == 0, Date() > deadline { stopped = true }
        if stopped { return 0 }
        let stand = evaluate()
        if stand >= beta { return beta }
        var alpha = max(alphaIn, stand)
        if ply > 40 { return alpha }
        let side = pos.side
        for m in order(pos.pseudoMoves(capturesOnly: true), ply: 64, first: nil) {
            let u = pos.make(m)
            if pos.isAttacked(pos.kings[side == 1 ? 0 : 1], by: -side) { pos.unmake(u); continue }
            let score = -quiesce(-beta, -alpha, ply: ply + 1)
            pos.unmake(u)
            if stopped { return 0 }
            if score >= beta { return beta }
            if score > alpha { alpha = score }
        }
        return alpha
    }

    private func order(_ moves: [ChessMove], ply: Int, first: ChessMove?) -> [ChessMove] {
        func score(_ m: ChessMove) -> Int {
            let victim = Int(abs(pos.b[m.to])), attacker = Int(abs(pos.b[m.from]))
            var s = 0
            if victim > 0 { s = 10_000 + victim * 10 - attacker }
            else if abs(pos.b[m.from]) == 1, m.to == pos.ep { s = 10_000 + 10 - 1 }
            if m.promo != 0 { s += 9_000 + m.promo }
            if ply < 64 {
                let key = m.from * 64 + m.to
                if killers[ply][0] == key { s += 8_000 } else if killers[ply][1] == key { s += 7_000 }
            }
            return s == 0 ? hist[m.from * 64 + m.to] : s
        }
        return moves.sorted { score($0) > score($1) }
    }

    // MARK: Evaluation (simplified evaluation function)

    private static let pst: [[Int]] = [
        [],
        [0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, 10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5,
         0, 0, 0, 20, 20, 0, 0, 0, 5, -5, -10, 0, 0, -10, -5, 5, 5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0],
        [-50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30, -30, 5, 15, 20, 20, 15, 5, -30,
         -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30, -40, -20, 0, 5, 5, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50],
        [-20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 10, 10, 5, 0, -10, -10, 5, 5, 10, 10, 5, 5, -10,
         -10, 0, 10, 10, 10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10, -10, 5, 0, 0, 0, 0, 5, -10, -20, -10, -10, -10, -10, -10, -10, -20],
        [0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5,
         -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0],
        [-20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10, -5, 0, 5, 5, 5, 5, 0, -5,
         0, 0, 5, 5, 5, 5, 0, -5, -10, 5, 5, 5, 5, 5, 0, -10, -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20],
        [-30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30,
         -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20, -20, -10, 20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10, 30, 20],
    ]
    private static let kingEnd: [Int] = [
        -50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -30, 0, 0, 0, 0, -30, -30, -50, -30, -30, -30, -30, -30, -30, -50,
    ]

    func evaluate() -> Int {
        var white = 0, black = 0, material = 0
        for p in pos.b where p != 0 && abs(p) != 1 && abs(p) != 6 { material += Self.values[Int(abs(p))] }
        let endgame = material <= 2600
        for sq in 0 ..< 64 {
            let p = pos.b[sq]
            if p == 0 { continue }
            let t = Int(abs(p))
            let table = t == 6 && endgame ? Self.kingEnd : Self.pst[t]
            if p > 0 { white += Self.values[t] + table[sq] } else { black += Self.values[t] + table[sq ^ 56] }
        }
        let s = white - black
        return pos.side == 1 ? s : -s
    }
}
