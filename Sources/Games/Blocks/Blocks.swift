import SwiftUI

/// Falling-block puzzle engine: 10x20 well, 7-bag randomiser, SRS rotation with wall kicks, hold, ghost, classic-style scoring.
struct BlocksEngine: Codable, Equatable, Sendable {
    static let cols = 10, rows = 20

    enum Kind: Int, Codable, CaseIterable, Sendable { case i = 1, o, t, s, z, j, l }

    var board = [Int8](repeating: 0, count: BlocksEngine.cols * BlocksEngine.rows)
    var kind: Kind = .t
    var rot = 0
    var px = 3, py = 0
    var hold: Kind?
    var canHold = true
    var queue: [Kind] = []
    var rng: SplitMix64
    var score = 0
    var lines = 0
    var combo = -1
    var backToBack = false
    var over = false

    var level: Int { lines / 10 + 1 }

    /// Seconds per row of gravity.
    var gravityInterval: Double { max(0.02, pow(0.8 - Double(level - 1) * 0.007, Double(level - 1))) }

    struct LockResult: Equatable, Sendable { var cleared: [Int] = []; var gained = 0 }

    init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
        refill()
        spawn()
    }

    // MARK: Shapes

    private static let base: [Kind: (size: Int, cells: [(Int, Int)])] = [
        .i: (4, [(1, 0), (1, 1), (1, 2), (1, 3)]),
        .o: (4, [(0, 1), (0, 2), (1, 1), (1, 2)]),
        .t: (3, [(0, 1), (1, 0), (1, 1), (1, 2)]),
        .s: (3, [(0, 1), (0, 2), (1, 0), (1, 1)]),
        .z: (3, [(0, 0), (0, 1), (1, 1), (1, 2)]),
        .j: (3, [(0, 0), (1, 0), (1, 1), (1, 2)]),
        .l: (3, [(0, 2), (1, 0), (1, 1), (1, 2)]),
    ]

    /// (row, col) offsets inside the piece's box for a rotation state 0...3.
    static func cells(_ k: Kind, _ rot: Int) -> [(Int, Int)] {
        let (n, c0) = base[k]!
        if k == .o { return c0 }
        var cells = c0
        for _ in 0 ..< ((rot % 4) + 4) % 4 { cells = cells.map { ($0.1, n - 1 - $0.0) } }
        return cells
    }

    private static let kicksJLSTZ: [Int: [(Int, Int)]] = [
        01: [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)], 10: [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
        12: [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)], 21: [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
        23: [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)], 32: [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
        30: [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)], 03: [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
    ]
    private static let kicksI: [Int: [(Int, Int)]] = [
        01: [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)], 10: [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
        12: [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)], 21: [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
        23: [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)], 32: [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
        30: [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)], 03: [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
    ]

    // MARK: Bag and spawning

    mutating func refill() {
        while queue.count < 8 {
            var bag = Kind.allCases
            for i in stride(from: bag.count - 1, to: 0, by: -1) { bag.swapAt(i, rng.int(in: 0 ... i)) }
            queue += bag
        }
    }

    var upcoming: [Kind] { Array(queue.prefix(3)) }

    mutating func spawn(_ k: Kind? = nil) {
        kind = k ?? queue.removeFirst()
        refill()
        rot = 0
        px = (BlocksEngine.cols - (kind == .i || kind == .o ? 4 : 3)) / 2
        py = kind == .i ? -1 : 0
        canHold = k == nil ? true : canHold
        if collides(kind, rot, px, py) { over = true }
    }

    // MARK: Movement

    func collides(_ k: Kind, _ r: Int, _ x: Int, _ y: Int) -> Bool {
        for (cr, cc) in Self.cells(k, r) {
            let row = y + cr, col = x + cc
            if col < 0 || col >= Self.cols || row >= Self.rows { return true }
            if row >= 0, board[row * Self.cols + col] != 0 { return true }
        }
        return false
    }

    var grounded: Bool { collides(kind, rot, px, py + 1) }

    @discardableResult
    mutating func move(_ dx: Int) -> Bool {
        guard !over, !collides(kind, rot, px + dx, py) else { return false }
        px += dx
        return true
    }

    @discardableResult
    mutating func stepDown() -> Bool {
        guard !over, !collides(kind, rot, px, py + 1) else { return false }
        py += 1
        return true
    }

    @discardableResult
    mutating func rotate(clockwise: Bool) -> Bool {
        guard !over, kind != .o else { return false }
        let to = (rot + (clockwise ? 1 : 3)) % 4
        let table = kind == .i ? Self.kicksI : Self.kicksJLSTZ
        for (dx, dy) in table[rot * 10 + to] ?? [(0, 0)] where !collides(kind, to, px + dx, py - dy) {
            px += dx; py -= dy; rot = to
            return true
        }
        return false
    }

    var ghostY: Int {
        var y = py
        while !collides(kind, rot, px, y + 1) { y += 1 }
        return y
    }

    /// Drops the piece, locks it and returns what happened.
    mutating func hardDrop() -> LockResult {
        let dist = ghostY - py
        py += dist
        score += dist * 2
        return lock()
    }

    mutating func lock() -> LockResult {
        for (cr, cc) in Self.cells(kind, rot) {
            let row = py + cr, col = px + cc
            if row < 0 { over = true; return LockResult() }
            board[row * Self.cols + col] = Int8(kind.rawValue)
        }
        var cleared: [Int] = []
        for r in 0 ..< Self.rows where (0 ..< Self.cols).allSatisfy({ board[r * Self.cols + $0] != 0 }) { cleared.append(r) }
        var gained = 0
        if !cleared.isEmpty {
            var kept: [Int8] = []
            for r in 0 ..< Self.rows where !cleared.contains(r) { kept += board[r * Self.cols ..< (r + 1) * Self.cols] }
            board = [Int8](repeating: 0, count: cleared.count * Self.cols) + kept
            let table = [0, 100, 300, 500, 800]
            gained = table[min(cleared.count, 4)] * level
            if cleared.count == 4 && backToBack { gained += gained / 2 }
            backToBack = cleared.count == 4
            combo += 1
            gained += combo * 50 * level
            lines += cleared.count
        } else {
            combo = -1
        }
        score += gained
        spawn()
        return LockResult(cleared: cleared, gained: gained)
    }

    mutating func holdPiece() -> Bool {
        guard canHold, !over else { return false }
        let current = kind
        if let h = hold { hold = current; spawn(h) } else { hold = current; spawn() }
        canHold = false
        return true
    }
}

// MARK: - Model

@MainActor @Observable
private final class BlocksModel {
    enum Phase { case ready, playing, paused, over }
    var engine = BlocksEngine(seed: 1)
    var phase = Phase.ready
    var best = UserDefaults.standard.integer(forKey: "khel.blocks.best")
    var flashRows: [Int] = []
    var flashUntil = Date.distantPast
    var softDrop = false
    private var accumulator = 0.0
    private var lockTimer = 0.0
    private var lockResets = 0
    private var loop: Task<Void, Never>?
    private var reported = false

    func start() {
        engine = BlocksEngine(seed: UInt64.random(in: .min ... .max))
        phase = .playing
        accumulator = 0; lockTimer = 0; lockResets = 0; reported = false
        run()
    }

    func pause() { if phase == .playing { phase = .paused; loop?.cancel() } }
    func resume() { if phase == .paused { phase = .playing; run() } }
    func stop() { loop?.cancel() }

    private func run() {
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            var last = Date()
            while let self, !Task.isCancelled, self.phase == .playing {
                try? await Task.sleep(for: .milliseconds(16))
                let now = Date(); let dt = now.timeIntervalSince(last); last = now
                self.advance(dt)
            }
        }
    }

    private func advance(_ dt: Double) {
        guard phase == .playing else { return }
        if engine.grounded {
            lockTimer += dt
            if lockTimer >= 0.5 || (softDrop && lockTimer >= 0.12) { finishPiece(engine.lock()) }
            return
        }
        lockTimer = 0
        accumulator += dt * (softDrop ? 20 : 1)
        while accumulator >= engine.gravityInterval {
            accumulator -= engine.gravityInterval
            if engine.stepDown() { if softDrop { engine.score += 1 } } else { break }
        }
    }

    private func finishPiece(_ r: BlocksEngine.LockResult) {
        lockTimer = 0; lockResets = 0; accumulator = 0
        if !r.cleared.isEmpty {
            flashRows = r.cleared; flashUntil = Date().addingTimeInterval(0.25)
            r.cleared.count >= 4 ? Feedback.shared.success() : Feedback.shared.thud()
            Feedback.shared.play(.capture)
        } else { Feedback.shared.play(.place) }
        if engine.over { gameOver() }
    }

    private func gameOver() {
        phase = .over
        loop?.cancel()
        Feedback.shared.failure()
        if engine.score > best { best = engine.score; UserDefaults.standard.set(best, forKey: "khel.blocks.best") }
        if !reported { reported = true; StatsStore.shared.submitScore(gameID: "blocks", score: engine.score) }
    }

    private func touched() { if engine.grounded, lockResets < 15 { lockTimer = 0; lockResets += 1 } }

    func left() { if phase == .playing, engine.move(-1) { touched(); Feedback.shared.tap() } }
    func right() { if phase == .playing, engine.move(1) { touched(); Feedback.shared.tap() } }
    func rotate(_ cw: Bool = true) { if phase == .playing, engine.rotate(clockwise: cw) { touched(); Feedback.shared.tap() } }
    func hardDrop() { if phase == .playing { finishPiece(engine.hardDrop()) } }
    func hold() { if phase == .playing, engine.holdPiece() { lockTimer = 0; Feedback.shared.thud() } }
}

// MARK: - View

struct BlocksView: View {
    static let info = GameInfo(
        id: "blocks", title: "Blocks", tagline: "Stack, clear, chase the high score", symbol: "square.stack.3d.up.fill", origin: .arcade, mode: .solo,
        minPlayers: 1, maxPlayers: 1, palette: [0x654EA3, 0xEAAFC8], supportsAI: false,
        rules: "Guide the falling pieces and complete horizontal lines to clear them. Drag sideways to move, tap to rotate, drag down for a soft drop, flick down to hard drop and swipe up to hold a piece. Or use the buttons below. Clearing four lines at once scores big, and the game speeds up every ten lines.")

    @State private var model = BlocksModel()
    @State private var startPoint: CGPoint?
    @State private var movedCells = 0
    @State private var didAct = false

    private static let colors: [Color] = [
        .clear, Color(red: 0.2, green: 0.85, blue: 0.95), Color(red: 0.98, green: 0.85, blue: 0.2), Color(red: 0.7, green: 0.35, blue: 0.9),
        Color(red: 0.3, green: 0.85, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.3), Color(red: 0.25, green: 0.4, blue: 0.95), Color(red: 0.98, green: 0.6, blue: 0.2),
    ]

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let cell = max(8, min((geo.size.width - 150) / 10, geo.size.height / 20))
                HStack(alignment: .top, spacing: 10) {
                    sidePanel(left: true, cell: cell)
                    boardView(cell: cell)
                    sidePanel(left: false, cell: cell)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            controls
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
        .onDisappear { model.stop() }
    }

    private func sidePanel(left: Bool, cell: CGFloat) -> some View {
        VStack(spacing: 10) {
            if left {
                panel("HOLD") { if let h = model.engine.hold { PieceMini(kind: h, cell: cell * 0.5, dim: !model.engine.canHold) } }
                stat("SCORE", model.engine.score)
                stat("LINES", model.engine.lines)
                stat("LEVEL", model.engine.level)
                stat("BEST", model.best)
            } else {
                panel("NEXT") { VStack(spacing: 6) { ForEach(Array(model.engine.upcoming.enumerated()), id: \.offset) { _, k in PieceMini(kind: k, cell: cell * 0.5, dim: false) } } }
                Button { model.phase == .playing ? model.pause() : model.resume() } label: {
                    Image(systemName: model.phase == .paused ? "play.fill" : "pause.fill").frame(width: 44, height: 44).background(Theme.surface2, in: Circle())
                }.disabled(model.phase == .ready || model.phase == .over)
            }
        }
        .frame(width: 66)
    }

    private func stat(_ t: String, _ v: Int) -> some View {
        VStack(spacing: 1) {
            Text(t).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Theme.text2)
            Text("\(v)").font(.system(size: 15, weight: .heavy, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 5).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func panel<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Theme.text2)
            content().frame(minHeight: 36)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func boardView(cell: CGFloat) -> some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 60)) { tl in
                Canvas { ctx, size in draw(&ctx, size: size, cell: cell, now: tl.date) }
            }
            if model.phase == .ready {
                VStack(spacing: 12) {
                    Text("BLOCKS").font(.system(size: 30, weight: .black, design: .rounded)).tracking(4)
                    Text("Best \(model.best)").foregroundStyle(Theme.text2)
                    Button("Play") { model.start() }.buttonStyle(PrimaryButtonStyle()).frame(width: 140)
                }
                .padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            if model.phase == .paused { Text("Paused").font(.title.bold()).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)) }
            if model.phase == .over {
                VStack(spacing: 10) {
                    Text("Game over").font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("Score \(model.engine.score)")
                    if model.engine.score >= model.best && model.engine.score > 0 { Label("New best!", systemImage: "star.fill").foregroundStyle(.yellow) }
                    Button("Play again") { model.start() }.buttonStyle(PrimaryButtonStyle()).frame(width: 160)
                }
                .padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .frame(width: cell * 10, height: cell * 20)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15), lineWidth: 2))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard model.phase == .playing else { return }
                if startPoint == nil { startPoint = v.startLocation; movedCells = 0; didAct = false }
                let cellsMoved = Int(v.translation.width / (cell * 0.9))
                while movedCells < cellsMoved { model.right(); movedCells += 1; didAct = true }
                while movedCells > cellsMoved { model.left(); movedCells -= 1; didAct = true }
                let down = v.translation.height > cell * 1.5 && abs(v.translation.height) > abs(v.translation.width)
                if down != model.softDrop { model.softDrop = down; if down { didAct = true } }
            }
            .onEnded { v in
                defer { startPoint = nil; model.softDrop = false }
                guard model.phase == .playing else { return }
                let dx = v.translation.width, dy = v.translation.height
                if !didAct, hypot(dx, dy) < 12 { model.rotate() }
                else if dy > cell * 2.5, v.predictedEndTranslation.height > cell * 8, abs(dy) > abs(dx) * 1.5 { model.hardDrop() }
                else if dy < -cell * 2, abs(dy) > abs(dx) { model.hold() }
            })
    }

    private var controls: some View {
        HStack(spacing: 10) {
            ctl("arrow.left") { model.left() }
            ctl("arrow.right") { model.right() }
            ctl("arrow.clockwise") { model.rotate() }
            ctl("arrow.down.to.line") { model.hardDrop() }
            ctl("tray.and.arrow.down.fill") { model.hold() }
        }
    }

    private func ctl(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).frame(maxWidth: .infinity).frame(height: 46)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Drawing

    static func drawBlock(_ ctx: inout GraphicsContext, _ rect: CGRect, kind: Int, alpha: Double = 1, ghost: Bool = false) {
        let c = colors[kind]
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        if ghost {
            ctx.stroke(Path(roundedRect: r.insetBy(dx: 2, dy: 2), cornerRadius: 3), with: .color(c.opacity(0.55)), lineWidth: 1.5)
            return
        }
        ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .linearGradient(Gradient(colors: [c.opacity(alpha), c.opacity(alpha * 0.7)]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        ctx.fill(Path(CGRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: r.height * 0.22)), with: .color(.white.opacity(0.35 * alpha)))
        ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(.black.opacity(0.35)), lineWidth: 1)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, cell: CGFloat, now: Date) {
        let e = model.engine
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.06, green: 0.05, blue: 0.12), Color(red: 0.03, green: 0.03, blue: 0.07)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        var grid = Path()
        for x in 1 ..< 10 { grid.move(to: CGPoint(x: CGFloat(x) * cell, y: 0)); grid.addLine(to: CGPoint(x: CGFloat(x) * cell, y: size.height)) }
        for y in 1 ..< 20 { grid.move(to: CGPoint(x: 0, y: CGFloat(y) * cell)); grid.addLine(to: CGPoint(x: size.width, y: CGFloat(y) * cell)) }
        ctx.stroke(grid, with: .color(.white.opacity(0.05)), lineWidth: 1)
        for i in 0 ..< e.board.count where e.board[i] != 0 {
            Self.drawBlock(&ctx, CGRect(x: CGFloat(i % 10) * cell, y: CGFloat(i / 10) * cell, width: cell, height: cell), kind: Int(e.board[i]))
        }
        if model.phase != .over && model.phase != .ready {
            let gy = e.ghostY
            for (r, c) in BlocksEngine.cells(e.kind, e.rot) {
                if gy != e.py { Self.drawBlock(&ctx, CGRect(x: CGFloat(e.px + c) * cell, y: CGFloat(gy + r) * cell, width: cell, height: cell), kind: e.kind.rawValue, ghost: true) }
            }
            for (r, c) in BlocksEngine.cells(e.kind, e.rot) where e.py + r >= 0 {
                Self.drawBlock(&ctx, CGRect(x: CGFloat(e.px + c) * cell, y: CGFloat(e.py + r) * cell, width: cell, height: cell), kind: e.kind.rawValue)
            }
        }
        if now < model.flashUntil {
            let k = model.flashUntil.timeIntervalSince(now) / 0.25
            for r in model.flashRows { ctx.fill(Path(CGRect(x: 0, y: CGFloat(r) * cell, width: size.width, height: cell)), with: .color(.white.opacity(0.85 * k))) }
        }
    }
}

private struct PieceMini: View {
    let kind: BlocksEngine.Kind
    let cell: CGFloat
    let dim: Bool
    var body: some View {
        let cells = BlocksEngine.cells(kind, 0)
        let minR = cells.map(\.0).min()!, maxR = cells.map(\.0).max()!, minC = cells.map(\.1).min()!, maxC = cells.map(\.1).max()!
        Canvas { ctx, _ in
            for (r, c) in cells {
                BlocksView.drawBlock(&ctx, CGRect(x: CGFloat(c - minC) * cell, y: CGFloat(r - minR) * cell, width: cell, height: cell), kind: kind.rawValue, alpha: dim ? 0.4 : 1)
            }
        }
        .frame(width: CGFloat(maxC - minC + 1) * cell, height: CGFloat(maxR - minR + 1) * cell)
    }
}
