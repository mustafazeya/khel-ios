import SwiftUI

enum SnakesLaddersEngine: TurnEngine {
    enum Action: Codable, Sendable, Equatable { case roll }

    static let ladders: [Int: Int] = [2: 38, 7: 14, 8: 31, 15: 26, 21: 42, 28: 84, 36: 44, 51: 67, 71: 91, 78: 98]
    static let snakes: [Int: Int] = [16: 6, 46: 25, 49: 11, 62: 19, 64: 60, 74: 53, 89: 68, 92: 72, 95: 75, 99: 80]

    struct State: Codable, Sendable, Equatable {
        var players: Int
        var positions: [Int]
        var turn = 0
        var rng: SplitMix64
        var sixes = 0
        var finished: [Int] = []
        var lastSeat = 0
        var lastRoll = 0
        /// Squares visited by the last mover: each step, then the snake or ladder destination.
        var lastPath: [Int] = []
        var lastKind = 0          // 0 none, 1 ladder, 2 snake, 3 bounced (overshoot), 4 three sixes
        var rolls = 0
    }

    static let info = GameInfo(
        id: "snakes", title: "Snakes & Ladders", tagline: "Climb the ladders, dodge the snakes", symbol: "figure.stairs",
        origin: .indian, mode: .turnBased, minPlayers: 2, maxPlayers: 4, palette: [0x11998E, 0x38EF7D], supportsAI: true,
        rules: "Roll the dice and move that many squares. Land at the bottom of a ladder to climb it, land on a snake's head and you slide down. You must roll the exact number to reach square 100. A six gives another turn, but three sixes in a row lose the move. The first to reach 100 wins.")

    static func newGame(players: Int, seed: UInt64) -> State {
        State(players: players, positions: [Int](repeating: 0, count: players), rng: SplitMix64(seed: seed))
    }

    static func apply(_ action: Action, by seat: Int, to s: inout State) throws {
        guard outcome(s) == nil else { throw ActionError("The game is over.") }
        guard seat == s.turn else { throw ActionError("Not your turn.") }
        let roll = s.rng.int(in: 1 ... 6)
        s.rolls += 1
        s.lastSeat = seat
        s.lastRoll = roll
        s.lastPath = []
        s.lastKind = 0
        let sixes = roll == 6 ? s.sixes + 1 : 0

        if sixes == 3 {
            s.lastKind = 4
            advanceTurn(&s, extra: false)
            return
        }

        let from = s.positions[seat]
        var pos = from
        if from + roll <= 100 {
            for step in 1 ... roll { pos = from + step; s.lastPath.append(pos) }
            if let up = ladders[pos] { pos = up; s.lastPath.append(pos); s.lastKind = 1 }
            else if let down = snakes[pos] { pos = down; s.lastPath.append(pos); s.lastKind = 2 }
        } else {
            s.lastKind = 3
        }
        s.positions[seat] = pos
        s.sixes = sixes
        if pos == 100 {
            s.finished.append(seat)
            advanceTurn(&s, extra: false)
        } else {
            advanceTurn(&s, extra: roll == 6)
        }
    }

    private static func advanceTurn(_ s: inout State, extra: Bool) {
        if extra { return }
        s.sixes = 0
        guard outcome(s) == nil else { return }
        var next = (s.turn + 1) % s.players
        while s.finished.contains(next) { next = (next + 1) % s.players }
        s.turn = next
    }

    static func activeSeat(_ s: State) -> Int? { outcome(s) == nil ? s.turn : nil }

    static func outcome(_ s: State) -> Outcome? {
        guard s.finished.count >= s.players - 1 else { return nil }
        let rest = (0 ..< s.players).filter { !s.finished.contains($0) }.sorted { s.positions[$0] > s.positions[$1] }
        return Outcome(ranking: s.finished + rest, summary: "Reached square 100")
    }

    static func aiAction(for state: State, seat: Int, level: AILevel) -> Action? { .roll }

    static func status(_ s: State, seats: [SeatConfig]) -> String {
        if let o = outcome(s) { return o.summary }
        let name = seats.indices.contains(s.turn) ? seats[s.turn].name : ""
        if s.rolls == 0 { return "\(name) rolls first" }
        let who = seats.indices.contains(s.lastSeat) ? seats[s.lastSeat].name : ""
        switch s.lastKind {
        case 1: return "\(who) climbed a ladder!"
        case 2: return "\(who) was bitten by a snake!"
        case 3: return "\(who) rolled \(s.lastRoll): needs the exact number"
        case 4: return "\(who) rolled three sixes: move lost"
        default: return "\(who) rolled \(s.lastRoll) · \(name) to roll"
        }
    }

    /// Centre of a square (1...100) in a 10x10 grid, row 0 at the top. Square 0 is placed just below square 1.
    static func cell(_ n: Int) -> (col: Double, row: Double) {
        guard n > 0 else { return (0.5, 10.4) }
        let r = (n - 1) / 10, c = (n - 1) % 10
        return (Double(r % 2 == 0 ? c : 9 - c) + 0.5, Double(9 - r) + 0.5)
    }
}

// MARK: - Board

struct SnakesLaddersBoardView: View {
    let session: TurnSession<SnakesLaddersEngine>
    @State private var shown: [Int] = []
    @State private var animating = false
    @State private var diceSpin = 0.0

    private typealias E = SnakesLaddersEngine

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let unit = side / 10
                ZStack(alignment: .topLeading) {
                    boardCanvas
                    ForEach(session.seats) { seat in token(seat, unit: unit) }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            dicePanel
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .onAppear { shown = session.state.positions }
        .onChange(of: session.version) { _, _ in Task { await animateLastMove() } }
    }

    // MARK: Tokens

    @ViewBuilder private func token(_ seat: SeatConfig, unit: CGFloat) -> some View {
        let sq = shown.indices.contains(seat.index) ? shown[seat.index] : 0
        let c = E.cell(sq)
        let same = shown.enumerated().filter { $0.element == sq && sq > 0 }.map(\.offset)
        let slot = same.firstIndex(of: seat.index) ?? 0
        let spread = same.count > 1 ? CGFloat(slot) - CGFloat(same.count - 1) / 2 : 0
        // Tokens waiting to enter sit in a row below square 1.
        let waitingX = CGFloat(seat.index) * unit * 0.8 + unit * 0.5
        AvatarView(spec: seat.avatar, size: unit * 0.78, ring: Theme.seatColors[seat.index % 4])
            .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            .scaleEffect(session.activeSeat == seat.index ? 1.12 : 1)
            .position(x: sq == 0 ? waitingX : CGFloat(c.col) * unit + spread * unit * 0.24,
                      y: sq == 0 ? unit * 9.5 : CGFloat(c.row) * unit)
            .animation(.snappy(duration: 0.12), value: sq)
    }

    // MARK: Dice

    private var dicePanel: some View {
        HStack(spacing: 18) {
            DiceFace(value: session.state.lastRoll == 0 ? 1 : session.state.lastRoll, size: 64)
                .rotation3DEffect(.degrees(diceSpin), axis: (x: 1, y: 1, z: 0))
                .opacity(session.state.lastRoll == 0 ? 0.35 : 1)
            Button {
                guard session.isMyTurn, !animating else { return }
                Feedback.shared.play(.roll)
                withAnimation(.easeOut(duration: 0.5)) { diceSpin += 540 }
                session.submit(.roll)
            } label: {
                Label(session.isMyTurn ? "Roll dice" : "Waiting…", systemImage: "dice.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: session.isMyTurn && !animating ? Theme.accent : Theme.surface2))
            .disabled(!session.isMyTurn || animating || session.outcome != nil)
        }
        .padding(.horizontal, 8)
    }

    // MARK: Animation

    private func animateLastMove() async {
        let s = session.state
        guard s.rolls > 0, !s.lastPath.isEmpty, shown.indices.contains(s.lastSeat) else {
            shown = s.positions
            return
        }
        animating = true
        for i in s.positions.indices where i != s.lastSeat { shown[i] = s.positions[i] }
        let jump = s.lastKind == 1 || s.lastKind == 2
        let steps = jump ? Array(s.lastPath.dropLast()) : s.lastPath
        for sq in steps {
            shown[s.lastSeat] = sq
            Feedback.shared.play(.tap)
            try? await Task.sleep(for: .milliseconds(130))
        }
        if jump, let dest = s.lastPath.last {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeInOut(duration: 0.55)) { shown[s.lastSeat] = dest }
            if s.lastKind == 2 { Feedback.shared.failure() } else { Feedback.shared.success() }
            try? await Task.sleep(for: .milliseconds(600))
        }
        shown = session.state.positions
        animating = false
    }

    // MARK: Drawing

    private var boardCanvas: some View {
        Canvas { ctx, size in
            let u = size.width / 10
            for n in 1 ... 100 {
                let c = E.cell(n)
                let rect = CGRect(x: (c.col - 0.5) * u, y: (c.row - 0.5) * u, width: u, height: u)
                let parity = (n - 1) / 10 + (n - 1) % 10
                ctx.fill(Path(rect), with: .color(parity % 2 == 0 ? Color(red: 0.98, green: 0.90, blue: 0.70) : Color(red: 0.95, green: 0.78, blue: 0.52)))
                ctx.draw(Text("\(n)").font(.system(size: u * 0.24, weight: .bold, design: .rounded)).foregroundStyle(Color.black.opacity(0.5)),
                         at: CGPoint(x: rect.minX + u * 0.07, y: rect.minY + u * 0.05), anchor: .topLeading)
            }
            ctx.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.45, green: 0.28, blue: 0.12)), lineWidth: 4)
            for (from, to) in E.ladders.sorted(by: { $0.key < $1.key }) { drawLadder(&ctx, from: from, to: to, u: u) }
            for (from, to) in E.snakes.sorted(by: { $0.key < $1.key }) { drawSnake(&ctx, head: from, tail: to, u: u) }
            let f = E.cell(100)
            ctx.draw(Text("🏆").font(.system(size: u * 0.5)), at: CGPoint(x: f.col * u, y: f.row * u + u * 0.12))
        }
    }

    private func point(_ n: Int, _ u: CGFloat) -> CGPoint { let c = E.cell(n); return CGPoint(x: c.col * u, y: c.row * u) }

    private func drawLadder(_ ctx: inout GraphicsContext, from: Int, to: Int, u: CGFloat) {
        let a = point(from, u), b = point(to, u)
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        let nx = -dy / len, ny = dx / len
        let half = u * 0.14
        let rails = [(CGPoint(x: a.x + nx * half, y: a.y + ny * half), CGPoint(x: b.x + nx * half, y: b.y + ny * half)),
                     (CGPoint(x: a.x - nx * half, y: a.y - ny * half), CGPoint(x: b.x - nx * half, y: b.y - ny * half))]
        var rungs = Path()
        let count = max(3, Int(len / (u * 0.42)))
        for i in 1 ..< count {
            let t = CGFloat(i) / CGFloat(count)
            rungs.move(to: CGPoint(x: rails[0].0.x + (rails[0].1.x - rails[0].0.x) * t, y: rails[0].0.y + (rails[0].1.y - rails[0].0.y) * t))
            rungs.addLine(to: CGPoint(x: rails[1].0.x + (rails[1].1.x - rails[1].0.x) * t, y: rails[1].0.y + (rails[1].1.y - rails[1].0.y) * t))
        }
        for r in rails {
            var p = Path(); p.move(to: r.0); p.addLine(to: r.1)
            ctx.stroke(p, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: u * 0.1, lineCap: .round))
            ctx.stroke(p, with: .color(Color(red: 0.55, green: 0.33, blue: 0.14)), style: StrokeStyle(lineWidth: u * 0.08, lineCap: .round))
        }
        ctx.stroke(rungs, with: .color(Color(red: 0.72, green: 0.46, blue: 0.2)), style: StrokeStyle(lineWidth: u * 0.06, lineCap: .round))
    }

    private func drawSnake(_ ctx: inout GraphicsContext, head: Int, tail: Int, u: CGFloat) {
        let h = point(head, u), t = point(tail, u)
        let dx = t.x - h.x, dy = t.y - h.y
        let len = hypot(dx, dy)
        let nx = -dy / len, ny = dx / len
        let wave = min(u * 0.6, len * 0.14)
        var path = Path()
        path.move(to: h)
        let segs = max(3, Int(len / (u * 1.6)))
        for i in 0 ..< segs {
            let t0 = CGFloat(i) / CGFloat(segs), t1 = CGFloat(i + 1) / CGFloat(segs), mid = (t0 + t1) / 2
            let sign: CGFloat = i % 2 == 0 ? 1 : -1
            let ctrl = CGPoint(x: h.x + dx * mid + nx * wave * sign, y: h.y + dy * mid + ny * wave * sign)
            path.addQuadCurve(to: CGPoint(x: h.x + dx * t1, y: h.y + dy * t1), control: ctrl)
        }
        let hue = Double((head * 37) % 100) / 100
        let body = Color(hue: 0.25 + hue * 0.25, saturation: 0.65, brightness: 0.75)
        ctx.stroke(path, with: .color(.black.opacity(0.28)), style: StrokeStyle(lineWidth: u * 0.26, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(body.opacity(0.92)), style: StrokeStyle(lineWidth: u * 0.2, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: u * 0.06, lineCap: .round, lineJoin: .round, dash: [u * 0.1, u * 0.18]))
        ctx.fill(Path(ellipseIn: CGRect(x: h.x - u * 0.2, y: h.y - u * 0.2, width: u * 0.4, height: u * 0.4)), with: .color(body))
        for side: CGFloat in [-1, 1] {
            let e = CGPoint(x: h.x + nx * u * 0.09 * side, y: h.y + ny * u * 0.09 * side - u * 0.04)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - u * 0.06, y: e.y - u * 0.06, width: u * 0.12, height: u * 0.12)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - u * 0.03, y: e.y - u * 0.03, width: u * 0.06, height: u * 0.06)), with: .color(.black))
        }
        var tongue = Path()
        let dir = CGPoint(x: -dx / len, y: -dy / len)
        tongue.move(to: CGPoint(x: h.x + dir.x * u * 0.18, y: h.y + dir.y * u * 0.18))
        tongue.addLine(to: CGPoint(x: h.x + dir.x * u * 0.36, y: h.y + dir.y * u * 0.36))
        ctx.stroke(tongue, with: .color(.red), style: StrokeStyle(lineWidth: u * 0.04, lineCap: .round))
    }
}

/// A die face with pips, shared by the dice games.
struct DiceFace: View {
    let value: Int
    var size: CGFloat = 60
    var tint: Color = .white

    private static let layout: [Int: [(Double, Double)]] = [
        1: [(0.5, 0.5)], 2: [(0.27, 0.27), (0.73, 0.73)], 3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
        4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
        5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
        6: [(0.27, 0.25), (0.73, 0.25), (0.27, 0.5), (0.73, 0.5), (0.27, 0.75), (0.73, 0.75)],
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
            ForEach(Array((Self.layout[min(max(value, 1), 6)] ?? []).enumerated()), id: \.offset) { _, p in
                Circle().fill(Color(red: 0.15, green: 0.1, blue: 0.25)).frame(width: size * 0.17, height: size * 0.17)
                    .position(x: size * p.0, y: size * p.1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Dice showing \(value)")
    }
}
