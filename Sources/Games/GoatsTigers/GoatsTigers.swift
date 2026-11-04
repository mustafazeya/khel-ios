import SwiftUI

/// Bagh-Chal: 4 tigers against 20 goats on a 5x5 point board. Seat 0 plays the goats, seat 1 the tigers.
enum GoatsTigersEngine: TurnEngine {
    /// `from` is -1 when placing a goat from the hand.
    struct Action: Codable, Sendable, Equatable, Hashable { var from: Int; var to: Int }

    struct State: Codable, Sendable, Equatable {
        /// 0 empty, 1 goat, 2 tiger. Point = row * 5 + col.
        var b: [Int8] = {
            var b = [Int8](repeating: 0, count: 25)
            for p in [0, 4, 20, 24] { b[p] = 2 }
            return b
        }()
        var inHand = 20
        var captured = 0
        var turn = 0
        /// 0 playing, 1 tigers win, 2 goats win, 3 draw
        var result = 0
        var lastFrom = -1, lastTo = -1, lastCaptured = -1
        var plies = 0
    }

    static let info = GameInfo(
        id: "goats", title: "Goats & Tigers", tagline: "Bagh-Chal: trap the tigers", symbol: "pawprint.fill",
        origin: .indian, mode: .turnBased, minPlayers: 2, maxPlayers: 2, palette: [0x42275A, 0x734B6D], supportsAI: true,
        rules: "Four tigers hunt twenty goats. The goat player first places one goat per turn on any empty point, then slides goats along the lines. Tigers slide one step, or jump over an adjacent goat along a line to capture it. Tigers win by capturing five goats; goats win by trapping all four tigers so they cannot move. The goats play first.")

    // MARK: Graph

    static func neighbours(_ p: Int) -> [Int] {
        let r = p / 5, c = p % 5
        var out: [Int] = []
        var dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if (r + c) % 2 == 0 { dirs += [(-1, -1), (-1, 1), (1, -1), (1, 1)] }
        for (dr, dc) in dirs {
            let nr = r + dr, nc = c + dc
            if (0 ..< 5).contains(nr), (0 ..< 5).contains(nc) { out.append(nr * 5 + nc) }
        }
        return out
    }

    /// (over, landing) pairs for a jump from `p`.
    static func jumps(_ p: Int) -> [(over: Int, to: Int)] {
        let r = p / 5, c = p % 5
        var dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if (r + c) % 2 == 0 { dirs += [(-1, -1), (-1, 1), (1, -1), (1, 1)] }
        return dirs.compactMap { dr, dc in
            let r2 = r + 2 * dr, c2 = c + 2 * dc
            guard (0 ..< 5).contains(r2), (0 ..< 5).contains(c2) else { return nil }
            return ((r + dr) * 5 + c + dc, r2 * 5 + c2)
        }
    }

    static func newGame(players: Int, seed: UInt64) -> State { State() }

    static func moves(_ s: State) -> [Action] {
        var out: [Action] = []
        if s.turn == 0 {
            if s.inHand > 0 { for p in 0 ..< 25 where s.b[p] == 0 { out.append(Action(from: -1, to: p)) } }
            else { for p in 0 ..< 25 where s.b[p] == 1 { for n in neighbours(p) where s.b[n] == 0 { out.append(Action(from: p, to: n)) } } }
        } else {
            for p in 0 ..< 25 where s.b[p] == 2 {
                for n in neighbours(p) where s.b[n] == 0 { out.append(Action(from: p, to: n)) }
                for j in jumps(p) where s.b[j.over] == 1 && s.b[j.to] == 0 { out.append(Action(from: p, to: j.to)) }
            }
        }
        return out
    }

    static func apply(_ a: Action, by seat: Int, to s: inout State) throws {
        guard s.result == 0 else { throw ActionError("The game is over.") }
        guard seat == s.turn else { throw ActionError("Not your turn.") }
        guard moves(s).contains(a) else {
            throw ActionError(seat == 0 && s.inHand > 0 ? "Place a goat on an empty point." : "That move is not allowed.")
        }
        s.lastFrom = a.from; s.lastTo = a.to; s.lastCaptured = -1
        if seat == 0 {
            if a.from < 0 { s.inHand -= 1 } else { s.b[a.from] = 0 }
            s.b[a.to] = 1
        } else {
            s.b[a.from] = 0
            s.b[a.to] = 2
            if let j = jumps(a.from).first(where: { $0.to == a.to }), s.b[j.over] == 1 {
                s.b[j.over] = 0; s.captured += 1; s.lastCaptured = j.over
            }
        }
        s.plies += 1
        s.turn = 1 - seat
        if s.captured >= 5 { s.result = 1 }
        else if moves(s).isEmpty { s.result = s.turn == 1 ? 2 : 1 }
        else if s.plies >= 200 { s.result = 3 }
    }

    static func activeSeat(_ s: State) -> Int? { s.result == 0 ? s.turn : nil }

    static func outcome(_ s: State) -> Outcome? {
        switch s.result {
        case 0: return nil
        case 1: return .win(1, others: [0], summary: s.captured >= 5 ? "Five goats captured" : "The goats are stuck")
        case 2: return .win(0, others: [1], summary: "All tigers trapped")
        default: return .draw("Too many moves")
        }
    }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        let name = seats[s.turn].name
        if s.turn == 0 { return s.inHand > 0 ? "\(name): place a goat (\(s.inHand) left)" : "\(name): move a goat" }
        return "\(name): move a tiger"
    }

    // MARK: AI

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Action? {
        let all = moves(s)
        guard !all.isEmpty else { return nil }
        var rng = SplitMix64(seed: UInt64(s.plies) &* 2654435761)
        switch level {
        case .easy:
            if seat == 1, let cap = all.first(where: { abs($0.to - $0.from) > 6 || ($0.from >= 0 && !neighbours($0.from).contains($0.to)) }), rng.int(in: 0 ... 1) == 0 { return cap }
            return all[rng.int(in: 0 ... all.count - 1)]
        case .medium: return search(s, seat: seat, depth: 3, seconds: 0.4)
        case .hard: return search(s, seat: seat, depth: 8, seconds: 1.2)
        }
    }

    private static func search(_ s: State, seat: Int, depth: Int, seconds: Double) -> Action {
        var ctx = Search(deadline: Date().addingTimeInterval(seconds))
        var ordered = moves(s)
        var best = ordered[0]
        for d in 1 ... depth {
            var alpha = -1_000_000, iter = ordered[0]
            var scored: [(Action, Int)] = []
            for m in ordered {
                var t = s
                try? apply(m, by: seat, to: &t)
                let v = -ctx.negamax(t, d - 1, -1_000_000, -alpha)
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

    private struct Search {
        let deadline: Date
        var nodes = 0
        var stopped = false

        mutating func negamax(_ s: State, _ depth: Int, _ alphaIn: Int, _ beta: Int) -> Int {
            nodes += 1
            if nodes & 1023 == 0, Date() > deadline { stopped = true }
            if stopped { return 0 }
            if s.result != 0 { let t = terminal(s); return t > 0 ? t + depth : (t < 0 ? t - depth : 0) }
            if depth <= 0 { return evaluate(s) }
            var alpha = alphaIn, best = -1_000_000
            var list = moves(s)
            if s.turn == 1 { list.sort { (abs($0.to - $0.from) > 6 ? 1 : 0) > (abs($1.to - $1.from) > 6 ? 1 : 0) } }
            for m in list {
                var t = s
                try? apply(m, by: s.turn, to: &t)
                let v = -negamax(t, depth - 1, -beta, -alpha)
                if stopped { return 0 }
                best = max(best, v); alpha = max(alpha, v)
                if alpha >= beta { break }
            }
            return best
        }

        /// Score for the side to move at a finished game.
        func terminal(_ s: State) -> Int {
            switch s.result {
            case 1: return s.turn == 1 ? 100_000 : -100_000   // tigers won; side to move is the loser or winner
            case 2: return s.turn == 0 ? 100_000 : -100_000
            default: return 0
            }
        }

        /// Score for the side to move.
        func evaluate(_ s: State) -> Int {
            var tigerMobility = 0, trapped = 0, jumpsAvail = 0
            for p in 0 ..< 25 where s.b[p] == 2 {
                var m = 0
                for n in neighbours(p) where s.b[n] == 0 { m += 1 }
                for j in jumps(p) where s.b[j.over] == 1 && s.b[j.to] == 0 { m += 1; jumpsAvail += 1 }
                tigerMobility += m
                if m == 0 { trapped += 1 }
            }
            let tigerScore = s.captured * 260 + tigerMobility * 7 + jumpsAvail * 40 - trapped * 120
            return s.turn == 1 ? tigerScore : -tigerScore
        }
    }
}

// MARK: - Art

@MainActor
private enum GoatsTigersArt {
    static var cache: [Int: SVGDocument] = [:]
    static func document(_ piece: Int) -> SVGDocument? {
        if let d = cache[piece] { return d }
        let s = piece == 2 ? tiger : goat
        guard let d = SVGDocument(string: s) else { return nil }
        cache[piece] = d
        return d
    }

    static let tiger = ##"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><radialGradient id="t" cx="0.4" cy="0.35" r="0.8"><stop offset="0" stop-color="#FFB347"/><stop offset="1" stop-color="#E8590C"/></radialGradient></defs>
    <circle cx="50" cy="54" r="40" fill="#000" opacity="0.25"/>
    <circle cx="22" cy="24" r="12" fill="#E8590C" stroke="#3B1A06" stroke-width="3"/><circle cx="78" cy="24" r="12" fill="#E8590C" stroke="#3B1A06" stroke-width="3"/>
    <circle cx="22" cy="24" r="5" fill="#FFD9A8"/><circle cx="78" cy="24" r="5" fill="#FFD9A8"/>
    <circle cx="50" cy="52" r="38" fill="url(#t)" stroke="#3B1A06" stroke-width="3.5"/>
    <g fill="#2A1204"><path d="M50 16 L46 32 L54 32 Z"/><path d="M26 34 L38 40 L30 46 Z"/><path d="M74 34 L62 40 L70 46 Z"/><path d="M14 54 L28 52 L26 60 Z"/><path d="M86 54 L72 52 L74 60 Z"/></g>
    <ellipse cx="50" cy="66" rx="18" ry="14" fill="#FFE8C8"/>
    <ellipse cx="37" cy="48" rx="6" ry="5" fill="#FFF"/><ellipse cx="63" cy="48" rx="6" ry="5" fill="#FFF"/>
    <circle cx="38" cy="48" r="3" fill="#1A1A1A"/><circle cx="62" cy="48" r="3" fill="#1A1A1A"/>
    <path d="M44 60 L56 60 L50 67 Z" fill="#2A1204"/><path d="M50 67 V72 M50 72 Q43 77 38 72 M50 72 Q57 77 62 72" stroke="#2A1204" stroke-width="2.5" fill="none" stroke-linecap="round"/>
    </svg>
    """##

    static let goat = ##"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><radialGradient id="g" cx="0.4" cy="0.3" r="0.85"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#D8D2C2"/></radialGradient></defs>
    <circle cx="50" cy="56" r="38" fill="#000" opacity="0.22"/>
    <path d="M30 34 C14 30 8 14 20 8 C16 18 24 24 36 26 Z" fill="#8B6B3E" stroke="#3A2A10" stroke-width="3" stroke-linejoin="round"/>
    <path d="M70 34 C86 30 92 14 80 8 C84 18 76 24 64 26 Z" fill="#8B6B3E" stroke="#3A2A10" stroke-width="3" stroke-linejoin="round"/>
    <ellipse cx="22" cy="46" rx="13" ry="7" fill="#F1ECDF" stroke="#3A2A10" stroke-width="3" transform="rotate(-20 22 46)"/><ellipse cx="78" cy="46" rx="13" ry="7" fill="#F1ECDF" stroke="#3A2A10" stroke-width="3" transform="rotate(20 78 46)"/>
    <path d="M50 24 C72 24 78 44 72 66 C68 80 60 86 50 86 C40 86 32 80 28 66 C22 44 28 24 50 24 Z" fill="url(#g)" stroke="#3A2A10" stroke-width="3.5" stroke-linejoin="round"/>
    <ellipse cx="38" cy="48" rx="5" ry="4.5" fill="#FFF"/><ellipse cx="62" cy="48" rx="5" ry="4.5" fill="#FFF"/>
    <rect x="35" y="46" width="6" height="4" rx="2" fill="#222"/><rect x="59" y="46" width="6" height="4" rx="2" fill="#222"/>
    <ellipse cx="50" cy="70" rx="12" ry="9" fill="#F2C9C0"/><circle cx="45" cy="69" r="2" fill="#7A3B35"/><circle cx="55" cy="69" r="2" fill="#7A3B35"/>
    <path d="M44 86 Q50 98 56 86 Z" fill="#F1ECDF" stroke="#3A2A10" stroke-width="3" stroke-linejoin="round"/>
    </svg>
    """##
}

private struct GoatsTigersPieceView: View {
    let piece: Int
    let size: CGFloat
    var body: some View {
        let doc = GoatsTigersArt.document(piece)
        Canvas { ctx, sz in if let doc { SVGRenderer.draw(doc, in: &ctx, size: sz) } }.frame(width: size, height: size)
    }
}

// MARK: - Board

struct GoatsTigersBoardView: View {
    let session: TurnSession<GoatsTigersEngine>

    private struct Item: Identifiable, Equatable { let id: Int; var piece: Int; var pt: Int }
    @State private var items: [Item] = []
    @State private var nextID = 1000
    @State private var selected: Int?

    private typealias E = GoatsTigersEngine
    private var state: E.State { session.state }
    private var canMove: Bool { session.isMyTurn && session.outcome == nil }
    private var options: [E.Action] { canMove ? E.moves(state) : [] }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let step = side / 5.4
                let origin = (side - step * 4) / 2
                ZStack(alignment: .topLeading) {
                    boardArt(side: side, step: step, origin: origin)
                    targets(step: step, origin: origin)
                    ForEach(items) { it in
                        GoatsTigersPieceView(piece: it.piece, size: step * 0.86)
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                            .position(pos(it.pt, step: step, origin: origin))
                            .scaleEffect(selected == it.pt ? 1.15 : 1)
                            .animation(.snappy(duration: 0.25), value: it.pt)
                            .transition(.scale.combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            HStack(spacing: 22) {
                Label("\(state.inHand) in hand", systemImage: "hand.raised.fill")
                Label("\(state.captured)/5 captured", systemImage: "xmark.circle.fill").foregroundStyle(state.captured >= 4 ? Theme.bad : Theme.text2)
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .onAppear { rebuild() }
        .onChange(of: session.version) { _, _ in sync() }
        .onChange(of: session.isMyTurn) { _, _ in selected = nil }
    }

    private func pos(_ p: Int, step: CGFloat, origin: CGFloat) -> CGPoint {
        CGPoint(x: origin + CGFloat(p % 5) * step, y: origin + CGFloat(p / 5) * step)
    }

    private func boardArt(side: CGFloat, step: CGFloat, origin: CGFloat) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.93, green: 0.84, blue: 0.64), Color(red: 0.84, green: 0.70, blue: 0.46)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            var lines = Path()
            func pt(_ r: Int, _ c: Int) -> CGPoint { CGPoint(x: origin + CGFloat(c) * step, y: origin + CGFloat(r) * step) }
            for i in 0 ..< 5 {
                lines.move(to: pt(i, 0)); lines.addLine(to: pt(i, 4))
                lines.move(to: pt(0, i)); lines.addLine(to: pt(4, i))
            }
            lines.move(to: pt(0, 0)); lines.addLine(to: pt(4, 4))
            lines.move(to: pt(0, 4)); lines.addLine(to: pt(4, 0))
            lines.move(to: pt(0, 2)); lines.addLine(to: pt(2, 0)); lines.addLine(to: pt(4, 2)); lines.addLine(to: pt(2, 4)); lines.closeSubpath()
            ctx.stroke(lines, with: .color(Color(red: 0.25, green: 0.14, blue: 0.07)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            for p in 0 ..< 25 {
                let c = pt(p / 5, p % 5)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(Color(red: 0.25, green: 0.14, blue: 0.07)))
            }
            if state.lastFrom >= 0 { let c = pt(state.lastFrom / 5, state.lastFrom % 5); ctx.stroke(Path(ellipseIn: CGRect(x: c.x - step * 0.4, y: c.y - step * 0.4, width: step * 0.8, height: step * 0.8)), with: .color(.yellow.opacity(0.6)), lineWidth: 3) }
        }
    }

    private func targets(step: CGFloat, origin: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0 ..< 25, id: \.self) { p in
                let isTarget = selected.map { s in options.contains { $0.from == s && $0.to == p } } ?? options.contains { $0.from == -1 && $0.to == p }
                let movable = options.contains { $0.from == p }
                Circle().fill(isTarget ? Color.green.opacity(0.55) : (movable && selected == nil ? Color.white.opacity(0.22) : .clear))
                    .frame(width: step * 0.8, height: step * 0.8)
                    .overlay(Circle().strokeBorder(movable && selected == nil ? Color.white.opacity(0.6) : .clear, lineWidth: 2))
                    .position(pos(p, step: step, origin: origin))
                    .contentShape(Rectangle().size(width: step, height: step).offset(x: -step / 2, y: -step / 2))
                    .onTapGesture { tap(p) }
            }
        }
    }

    private func tap(_ p: Int) {
        guard canMove else { return }
        if let sel = selected, let m = options.first(where: { $0.from == sel && $0.to == p }) {
            selected = nil; Feedback.shared.thud(); session.submit(m); return
        }
        if let m = options.first(where: { $0.from == -1 && $0.to == p }) { Feedback.shared.thud(); session.submit(m); return }
        if options.contains(where: { $0.from == p }) { selected = selected == p ? nil : p; Feedback.shared.tap() } else { selected = nil }
    }

    private func rebuild() {
        var id = 0
        items = state.b.enumerated().compactMap { p, v in v == 0 ? nil : { id += 1; return Item(id: id, piece: Int(v), pt: p) }() }
        selected = nil
    }

    private func sync() {
        selected = nil
        let s = state
        if s.lastTo < 0 { rebuild(); return }
        var next = items
        if s.lastFrom < 0 {
            nextID += 1
            next.append(Item(id: nextID, piece: 1, pt: s.lastTo))
        } else if let i = next.firstIndex(where: { $0.pt == s.lastFrom }) {
            next[i].pt = s.lastTo
        } else { rebuild(); return }
        if s.lastCaptured >= 0 { next.removeAll { $0.pt == s.lastCaptured }; Feedback.shared.play(.capture) }
        var board = [Int8](repeating: 0, count: 25)
        for it in next { board[it.pt] = Int8(it.piece) }
        guard board == s.b else { rebuild(); return }
        withAnimation(.snappy(duration: 0.25)) { items = next }
    }
}
