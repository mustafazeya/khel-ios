import SwiftUI

enum LudoEngine: TurnEngine {
    enum Action: Codable, Sendable, Equatable { case roll, move(Int) }

    struct State: Codable, Sendable, Equatable {
        var players: Int
        /// Per seat, 4 tokens. -1 in the yard, 0...50 on the ring (relative to the seat's start), 51...55 home column, 56 home.
        var tokens: [[Int]]
        var turn = 0
        /// The dice value waiting for a token to be moved, 0 when the player must roll.
        var roll = 0
        var rng: SplitMix64
        var sixes = 0
        var finished: [Int] = []
        var lastSeat = 0, lastToken = 0, lastFrom = 0, lastTo = 0, lastRoll = 0
        var captured: [[Int]] = []
        var moves = 0
        /// 0 none, 1 three sixes, 2 no legal move
        var note = 0
    }

    static let info = GameInfo(
        id: "ludo", title: "Ludo", tagline: "Race your four tokens home", symbol: "dice.fill",
        origin: .indian, mode: .turnBased, minPlayers: 2, maxPlayers: 4, palette: [0xFF5F6D, 0xFFC371], supportsAI: true,
        rules: "Roll a six to bring a token onto the board, then move tokens round the track and up your coloured column to the centre. Landing on an opponent's token sends it back to its yard unless it stands on a star or a start square. A six, a capture or reaching home gives another roll; three sixes in a row lose the move. You need the exact number to enter the centre. Get all four tokens home first.")

    // MARK: Geometry

    /// The 52 track cells as (col, row) in a 15x15 grid, clockwise, starting on the first cell of the top-left arm.
    static let ring: [(Int, Int)] = {
        var p: [(Int, Int)] = []
        for c in 1 ... 5 { p.append((c, 6)) }
        for r in stride(from: 5, through: 0, by: -1) { p.append((6, r)) }
        p.append((7, 0)); p.append((8, 0))
        for r in 1 ... 5 { p.append((8, r)) }
        for c in 9 ... 14 { p.append((c, 6)) }
        p.append((14, 7)); p.append((14, 8))
        for c in stride(from: 13, through: 9, by: -1) { p.append((c, 8)) }
        for r in 9 ... 14 { p.append((8, r)) }
        p.append((7, 14)); p.append((6, 14))
        for r in stride(from: 13, through: 9, by: -1) { p.append((6, r)) }
        for c in stride(from: 5, through: 0, by: -1) { p.append((c, 8)) }
        p.append((0, 7)); p.append((0, 6))
        return p
    }()

    /// Seat colours follow `Theme.seatColors` (blue, red, green, yellow). Colour slots: 0 red (top-left), 1 green (top-right), 2 yellow (bottom-right), 3 blue (bottom-left).
    static let starts = [0, 13, 26, 39]
    static let safeCells: Set<Int> = [0, 13, 26, 39, 8, 21, 34, 47]
    static let homeColumns: [[(Int, Int)]] = [
        (1 ... 5).map { ($0, 7) }, (1 ... 5).map { (7, $0) },
        (0 ..< 5).map { (13 - $0, 7) }, (0 ..< 5).map { (7, 13 - $0) },
    ]
    static let yards: [[(Double, Double)]] = [
        [(1.75, 1.75), (4.25, 1.75), (1.75, 4.25), (4.25, 4.25)],
        [(10.75, 1.75), (13.25, 1.75), (10.75, 4.25), (13.25, 4.25)],
        [(10.75, 10.75), (13.25, 10.75), (10.75, 13.25), (13.25, 13.25)],
        [(1.75, 10.75), (4.25, 10.75), (1.75, 13.25), (4.25, 13.25)],
    ]
    static let centreSpots: [(Double, Double)] = [(6.8, 7.5), (7.5, 6.8), (8.2, 7.5), (7.5, 8.2)]

    static func slots(_ players: Int) -> [Int] {
        switch players { case 2: [3, 0]; case 3: [3, 0, 1]; default: [3, 0, 1, 2] }
    }

    static func ringIndex(slot: Int, progress p: Int) -> Int? { (0 ... 50).contains(p) ? (starts[slot] + p) % 52 : nil }

    // MARK: Rules

    static func newGame(players: Int, seed: UInt64) -> State {
        State(players: players, tokens: [[Int]](repeating: [-1, -1, -1, -1], count: players), rng: SplitMix64(seed: seed))
    }

    static func legalMoves(_ s: State, seat: Int) -> [Int] {
        guard s.roll > 0 else { return [] }
        return (0 ..< 4).filter { t in
            let p = s.tokens[seat][t]
            if p == -1 { return s.roll == 6 }
            return p < 56 && p + s.roll <= 56
        }
    }

    /// Tokens that lead to genuinely different positions (all yard tokens count as one).
    static func distinctMoves(_ s: State, seat: Int) -> [Int] {
        var seenYard = false
        return legalMoves(s, seat: seat).filter { t in
            guard s.tokens[seat][t] == -1 else { return true }
            defer { seenYard = true }
            return !seenYard
        }
    }

    static func apply(_ action: Action, by seat: Int, to s: inout State) throws {
        guard outcome(s) == nil else { throw ActionError("The game is over.") }
        guard seat == s.turn else { throw ActionError("Not your turn.") }
        switch action {
        case .roll:
            guard s.roll == 0 else { throw ActionError("Move a token first.") }
            let r = s.rng.int(in: 1 ... 6)
            s.lastSeat = seat; s.lastRoll = r; s.note = 0; s.captured = []
            s.sixes = r == 6 ? s.sixes + 1 : 0
            if s.sixes == 3 { s.note = 1; nextTurn(&s); return }
            s.roll = r
            if legalMoves(s, seat: seat).isEmpty { s.roll = 0; s.note = 2; nextTurn(&s) }
        case .move(let t):
            guard s.roll > 0 else { throw ActionError("Roll the dice first.") }
            guard legalMoves(s, seat: seat).contains(t) else { throw ActionError("That token cannot move.") }
            let slot = slots(s.players)[seat]
            let from = s.tokens[seat][t]
            let to = from == -1 ? 0 : from + s.roll
            s.tokens[seat][t] = to
            s.lastSeat = seat; s.lastToken = t; s.lastFrom = from; s.lastTo = to; s.lastRoll = s.roll
            s.moves += 1; s.note = 0; s.captured = []
            if let idx = ringIndex(slot: slot, progress: to), !safeCells.contains(idx) {
                for o in 0 ..< s.players where o != seat {
                    for k in 0 ..< 4 where ringIndex(slot: slots(s.players)[o], progress: s.tokens[o][k]) == idx {
                        s.tokens[o][k] = -1
                        s.captured.append([o, k])
                    }
                }
            }
            let rolled = s.roll
            s.roll = 0
            if to == 56, s.tokens[seat].allSatisfy({ $0 == 56 }) { s.finished.append(seat) }
            let extra = (rolled == 6 || !s.captured.isEmpty || to == 56) && !s.finished.contains(seat)
            if !extra || outcome(s) != nil { nextTurn(&s) }
        }
    }

    private static func nextTurn(_ s: inout State) {
        s.sixes = 0
        s.roll = 0
        guard outcome(s) == nil else { return }
        var n = (s.turn + 1) % s.players
        while s.finished.contains(n) { n = (n + 1) % s.players }
        s.turn = n
    }

    static func activeSeat(_ s: State) -> Int? { outcome(s) == nil ? s.turn : nil }

    static func outcome(_ s: State) -> Outcome? {
        guard s.finished.count >= s.players - 1 else { return nil }
        let rest = (0 ..< s.players).filter { !s.finished.contains($0) }.sorted { s.tokens[$0].reduce(0, +) > s.tokens[$1].reduce(0, +) }
        return Outcome(ranking: s.finished + rest, summary: "All tokens home")
    }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        let name = seats.indices.contains(s.turn) ? seats[s.turn].name : ""
        let who = seats.indices.contains(s.lastSeat) ? seats[s.lastSeat].name : ""
        if s.roll > 0 { return "\(name) rolled \(s.roll): pick a token" }
        if s.moves == 0 && s.lastRoll == 0 { return "\(name) rolls first" }
        if s.note == 1 { return "\(who) rolled three sixes: turn lost" }
        if s.note == 2 { return "\(who) rolled \(s.lastRoll): no move possible" }
        if !s.captured.isEmpty { return "\(who) captured a token! Roll again" }
        return "\(name) to roll"
    }

    // MARK: AI

    static func aiAction(for s: State, seat: Int, level: AILevel) -> Action? {
        guard outcome(s) == nil else { return nil }
        if s.roll == 0 { return .roll }
        let legal = legalMoves(s, seat: seat)
        guard !legal.isEmpty else { return nil }
        var rng = SplitMix64(seed: s.rng.state ^ UInt64(s.moves) &* 31)
        if level == .easy { return .move(legal[rng.int(in: 0 ... legal.count - 1)]) }
        var best = legal[0], bestScore = -Double.infinity
        for t in legal {
            let sc = score(s, seat: seat, token: t, careful: level == .hard) + Double(rng.int(in: 0 ... 10)) / 10
            if sc > bestScore { bestScore = sc; best = t }
        }
        return .move(best)
    }

    /// How many opponent tokens could land on `cell` with one roll.
    private static func threats(_ s: State, seat: Int, cell: Int) -> Double {
        var n = 0.0
        for o in 0 ..< s.players where o != seat {
            let slot = slots(s.players)[o]
            for k in 0 ..< 4 {
                let po = s.tokens[o][k]
                guard let oi = ringIndex(slot: slot, progress: po) else { continue }
                let d = (cell - oi + 52) % 52
                if (1 ... 6).contains(d), po + d <= 50 { n += 1 }
            }
        }
        return n
    }

    private static func score(_ s: State, seat: Int, token t: Int, careful: Bool) -> Double {
        let slot = slots(s.players)[seat]
        let p = s.tokens[seat][t]
        let np = p == -1 ? 0 : p + s.roll
        var sc = Double(np)
        if np == 56 { sc += 1000 }
        if p == -1 { sc += 450 }
        if np >= 51 && p < 51 { sc += 120 }
        let weight = careful ? 1.0 : 0.5
        if let idx = ringIndex(slot: slot, progress: np) {
            if safeCells.contains(idx) {
                sc += 180
            } else {
                for o in 0 ..< s.players where o != seat {
                    for k in 0 ..< 4 where ringIndex(slot: slots(s.players)[o], progress: s.tokens[o][k]) == idx {
                        sc += 600 + Double(s.tokens[o][k]) * 3
                    }
                }
                sc -= threats(s, seat: seat, cell: idx) * (80 + Double(np) * 1.5) * weight
            }
        }
        if p >= 0, let cur = ringIndex(slot: slot, progress: p), !safeCells.contains(cur) {
            sc += threats(s, seat: seat, cell: cur) * (60 + Double(p)) * weight
        }
        return sc
    }
}

// MARK: - Board

struct LudoBoardView: View {
    let session: TurnSession<LudoEngine>
    @State private var shown: [[Int]] = []
    @State private var queue: [LudoEngine.State] = []
    @State private var running = false
    @State private var diceSpin = 0.0
    @State private var pulse = false

    private typealias E = LudoEngine
    private static let colors: [Color] = [
        Color(red: 0.93, green: 0.27, blue: 0.27), Color(red: 0.18, green: 0.72, blue: 0.40),
        Color(red: 0.98, green: 0.78, blue: 0.15), Color(red: 0.22, green: 0.50, blue: 0.95),
    ]

    private var slots: [Int] { E.slots(session.state.players) }
    private var state: E.State { session.state }
    private var busy: Bool { running || !queue.isEmpty }

    private struct TokenID: Identifiable { let seat: Int, token: Int; var id: Int { seat * 4 + token } }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let u = side / 15
                ZStack(alignment: .topLeading) {
                    boardCanvas
                    ForEach((0 ..< state.players).flatMap { s in (0 ..< 4).map { TokenID(seat: s, token: $0) } }) { id in
                        tokenView(id, u: u)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            dicePanel
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .onAppear {
            shown = state.tokens
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: session.version) { _, _ in
            queue.append(state)
            if !running { Task { await drain() } }
        }
        .onChange(of: busy) { _, _ in autoMoveIfSingle() }
        .onChange(of: session.version) { _, _ in autoMoveIfSingle() }
    }

    // MARK: Positions

    private func cellPoint(seat: Int, token: Int, progress p: Int) -> CGPoint {
        let slot = slots[seat]
        if p < 0 { let y = E.yards[slot][token]; return CGPoint(x: y.0, y: y.1) }
        if p <= 50 { let c = E.ring[(E.starts[slot] + p) % 52]; return CGPoint(x: Double(c.0) + 0.5, y: Double(c.1) + 0.5) }
        if p <= 55 { let c = E.homeColumns[slot][p - 51]; return CGPoint(x: Double(c.0) + 0.5, y: Double(c.1) + 0.5) }
        let b = E.centreSpots[slot]
        let off = (Double(token) - 1.5) * 0.14
        return slot % 2 == 0 ? CGPoint(x: b.0, y: b.1 + off) : CGPoint(x: b.0 + off, y: b.1)
    }

    private func tokenView(_ id: TokenID, u: CGFloat) -> some View {
        let p = shown.indices.contains(id.seat) ? shown[id.seat][id.token] : -1
        let base = cellPoint(seat: id.seat, token: id.token, progress: p)
        var sharing = 0, index = 0
        if p >= 0 && p < 56 {
            for s in shown.indices { for t in 0 ..< 4 where shown[s][t] >= 0 && shown[s][t] < 56 {
                let q = cellPoint(seat: s, token: t, progress: shown[s][t])
                if abs(q.x - base.x) < 0.01 && abs(q.y - base.y) < 0.01 {
                    if s * 4 + t < id.id { index += 1 }
                    sharing += 1
                }
            } }
        }
        let spread = sharing > 1 ? (CGFloat(index) - CGFloat(sharing - 1) / 2) * 0.3 : 0
        let slot = slots[id.seat]
        let movable = !busy && session.isMyTurn && state.turn == id.seat && E.legalMoves(state, seat: id.seat).contains(id.token)
        let size = u * (sharing > 1 ? 0.62 : 0.8)
        return ZStack {
            Circle().fill(.black.opacity(0.3)).offset(y: 2)
            Circle().fill(RadialGradient(colors: [Self.colors[slot].opacity(0.8), Self.colors[slot]], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: size))
            Circle().strokeBorder(.white, lineWidth: max(2, size * 0.08))
            AvatarView(spec: session.seats[id.seat].avatar, size: size * 0.5)
            if movable { Circle().strokeBorder(.white, lineWidth: 3).scaleEffect(pulse ? 1.25 : 1.0).opacity(pulse ? 0.2 : 1) }
        }
        .frame(width: size, height: size)
        .scaleEffect(movable && pulse ? 1.08 : 1)
        .position(x: (base.x + spread) * u, y: base.y * u)
        .animation(.snappy(duration: 0.14), value: p)
        .zIndex(movable ? 2 : (p >= 0 ? 1 : 0))
        .onTapGesture {
            guard movable else { return }
            Feedback.shared.thud()
            session.submit(.move(id.token))
        }
        .accessibilityLabel("Token \(id.token + 1) of \(session.seats[id.seat].name)")
    }

    // MARK: Dice

    private var dicePanel: some View {
        HStack(spacing: 18) {
            DiceFace(value: state.lastRoll == 0 ? 1 : state.lastRoll, size: 64)
                .rotation3DEffect(.degrees(diceSpin), axis: (x: 1, y: 1, z: 0))
                .opacity(state.lastRoll == 0 ? 0.4 : 1)
            Button {
                guard canRoll else { return }
                Feedback.shared.play(.roll)
                withAnimation(.easeOut(duration: 0.5)) { diceSpin += 540 }
                session.submit(.roll)
            } label: {
                Label(buttonTitle, systemImage: canRoll ? "dice.fill" : "hourglass")
            }
            .buttonStyle(PrimaryButtonStyle(tint: canRoll ? Theme.accent : Theme.surface2))
            .disabled(!canRoll)
        }
        .padding(.horizontal, 8)
    }

    private var canRoll: Bool { session.isMyTurn && state.roll == 0 && !busy && session.outcome == nil }
    private var buttonTitle: String {
        if canRoll { return "Roll dice" }
        if session.isMyTurn && state.roll > 0 { return "Tap a glowing token" }
        return "Waiting…"
    }

    // MARK: Animation

    @MainActor private func drain() async {
        running = true
        while !queue.isEmpty {
            let st = queue.removeFirst()
            if st.moves > 0, shown.indices.contains(st.lastSeat), st.lastFrom != st.lastTo, st.lastSeat < shown.count,
               shown[st.lastSeat][st.lastToken] == st.lastFrom || st.lastFrom == -1 {
                let steps = st.lastFrom == -1 ? [0] : Array((st.lastFrom + 1) ... st.lastTo)
                for p in steps {
                    shown[st.lastSeat][st.lastToken] = p
                    Feedback.shared.play(.tap)
                    try? await Task.sleep(for: .milliseconds(110))
                }
                if !st.captured.isEmpty {
                    Feedback.shared.play(.capture); Feedback.shared.thud()
                    for c in st.captured { shown[c[0]][c[1]] = -1 }
                    try? await Task.sleep(for: .milliseconds(350))
                }
                if st.lastTo == 56 { Feedback.shared.success() }
            }
            shown = st.tokens
        }
        running = false
        autoMoveIfSingle()
    }

    /// When only one move is possible the game plays it, as a person would.
    private func autoMoveIfSingle() {
        guard !busy, session.isMyTurn, state.roll > 0, E.distinctMoves(state, seat: state.turn).count == 1,
              let only = E.distinctMoves(state, seat: state.turn).first else { return }
        let expected = session.version
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard session.version == expected, !busy, session.isMyTurn, state.roll > 0 else { return }
            session.submit(.move(only))
        }
    }

    // MARK: Drawing

    private var boardCanvas: some View {
        Canvas { ctx, size in
            let u = size.width / 15
            func rect(_ c: Int, _ r: Int) -> CGRect { CGRect(x: CGFloat(c) * u, y: CGFloat(r) * u, width: u, height: u) }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.98, green: 0.96, blue: 0.9)))

            let yardOrigins = [(0, 0), (9, 0), (9, 9), (0, 9)]
            for slot in 0 ..< 4 {
                let o = yardOrigins[slot], col = Self.colors[slot]
                ctx.fill(Path(CGRect(x: CGFloat(o.0) * u, y: CGFloat(o.1) * u, width: 6 * u, height: 6 * u)), with: .color(col))
                ctx.fill(Path(roundedRect: CGRect(x: CGFloat(o.0 + 1) * u, y: CGFloat(o.1 + 1) * u, width: 4 * u, height: 4 * u), cornerRadius: u * 0.6),
                         with: .color(.white.opacity(0.92)))
                for spot in E.yards[slot] {
                    let r = u * 0.5
                    ctx.fill(Path(ellipseIn: CGRect(x: spot.0 * u - r, y: spot.1 * u - r, width: 2 * r, height: 2 * r)), with: .color(col.opacity(0.28)))
                }
            }
            for (i, c) in E.ring.enumerated() {
                var fill = Color.white
                if let slot = E.starts.firstIndex(of: i) { fill = Self.colors[slot] }
                ctx.fill(Path(rect(c.0, c.1)), with: .color(fill))
                ctx.stroke(Path(rect(c.0, c.1)), with: .color(.black.opacity(0.22)), lineWidth: 1)
                if E.safeCells.contains(i), !E.starts.contains(i) {
                    ctx.draw(Text("★").font(.system(size: u * 0.7)).foregroundStyle(Color.black.opacity(0.35)), at: CGPoint(x: (CGFloat(c.0) + 0.5) * u, y: (CGFloat(c.1) + 0.52) * u))
                }
            }
            for slot in 0 ..< 4 {
                for c in E.homeColumns[slot] {
                    ctx.fill(Path(rect(c.0, c.1)), with: .color(Self.colors[slot]))
                    ctx.stroke(Path(rect(c.0, c.1)), with: .color(.black.opacity(0.22)), lineWidth: 1)
                }
            }
            func tri(_ a: CGPoint, _ b: CGPoint, _ col: Color) {
                var p = Path(); p.move(to: CGPoint(x: a.x * u, y: a.y * u)); p.addLine(to: CGPoint(x: b.x * u, y: b.y * u)); p.addLine(to: CGPoint(x: 7.5 * u, y: 7.5 * u)); p.closeSubpath()
                ctx.fill(p, with: .color(col)); ctx.stroke(p, with: .color(.white.opacity(0.7)), lineWidth: 1.5)
            }
            tri(CGPoint(x: 6, y: 6), CGPoint(x: 6, y: 9), Self.colors[0])
            tri(CGPoint(x: 6, y: 6), CGPoint(x: 9, y: 6), Self.colors[1])
            tri(CGPoint(x: 9, y: 6), CGPoint(x: 9, y: 9), Self.colors[2])
            tri(CGPoint(x: 6, y: 9), CGPoint(x: 9, y: 9), Self.colors[3])
        }
    }
}
