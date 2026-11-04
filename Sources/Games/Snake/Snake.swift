import SwiftUI

struct SnakeEngine: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable { case classic = "Classic", wrap = "Wrap", speed = "Speed"
        var detail: String { switch self { case .classic: "Walls are deadly"; case .wrap: "Edges wrap around"; case .speed: "Speeds up quickly" } }
    }
    enum Dir: Sendable { case up, down, left, right
        var delta: (Int, Int) { switch self { case .up: (0, -1); case .down: (0, 1); case .left: (-1, 0); case .right: (1, 0) } }
        var opposite: Dir { switch self { case .up: .down; case .down: .up; case .left: .right; case .right: .left } }
    }
    struct Point: Codable, Equatable, Hashable, Sendable { var x: Int; var y: Int }
    enum Event: Sendable { case none, ate, died }

    let cols: Int
    let rows: Int
    var mode: Mode
    var body: [Point]            // head first
    var dir: Dir = .right
    var queued: [Dir] = []
    var food: Point
    var score = 0
    var alive = true
    var rng: SplitMix64

    // Codable support for Dir (not stored by default).
    enum CodingKeys: String, CodingKey { case cols, rows, mode, body, food, score, alive, rng }

    init(cols: Int = 15, rows: Int = 20, mode: Mode = .classic, seed: UInt64) {
        self.cols = cols; self.rows = rows; self.mode = mode
        body = (0 ..< 3).map { Point(x: cols / 2 - $0, y: rows / 2) }
        rng = SplitMix64(seed: seed)
        food = Point(x: 0, y: 0)
        placeFood()
    }

    var interval: Double {
        let base: Double = mode == .speed ? 0.16 : 0.2
        let step: Double = mode == .speed ? 0.006 : 0.0025
        return max(mode == .speed ? 0.055 : 0.085, base - Double(score / 10) * step)
    }

    mutating func placeFood() {
        let taken = Set(body)
        let free = (0 ..< cols * rows).map { Point(x: $0 % cols, y: $0 / cols) }.filter { !taken.contains($0) }
        if let f = free.isEmpty ? nil : free[rng.int(in: 0 ... free.count - 1)] { food = f }
    }

    /// Queue a turn; reversing into yourself and duplicates are ignored. At most two turns are buffered.
    mutating func turn(_ d: Dir) {
        let reference = queued.last ?? dir
        guard d != reference, d != reference.opposite, queued.count < 2 else { return }
        queued.append(d)
    }

    @discardableResult
    mutating func tick() -> Event {
        guard alive else { return .died }
        if !queued.isEmpty { dir = queued.removeFirst() }
        var head = Point(x: body[0].x + dir.delta.0, y: body[0].y + dir.delta.1)
        if mode == .wrap {
            head.x = (head.x + cols) % cols; head.y = (head.y + rows) % rows
        } else if !(0 ..< cols).contains(head.x) || !(0 ..< rows).contains(head.y) {
            alive = false; return .died
        }
        let willEat = head == food
        let tail = body.last!
        if body.contains(head), !(head == tail && !willEat) { alive = false; return .died }
        body.insert(head, at: 0)
        if willEat {
            score += 10
            placeFood()
            return .ate
        }
        body.removeLast()
        return .none
    }
}

// MARK: - Model

@MainActor @Observable
private final class SnakeModel {
    enum Phase { case ready, playing, paused, over }
    var engine = SnakeEngine(seed: 1)
    var previous: [SnakeEngine.Point] = []
    var phase = Phase.ready
    var lastTick = Date()
    var mode: SnakeEngine.Mode
    var best: Int
    var shake = 0.0
    var particles: [(pos: SnakeEngine.Point, born: Date)] = []
    private var loop: Task<Void, Never>?

    init() {
        let m = SnakeEngine.Mode(rawValue: UserDefaults.standard.string(forKey: "khel.snake.mode") ?? "") ?? .classic
        mode = m
        best = UserDefaults.standard.integer(forKey: "khel.snake.best.\(m.rawValue)")
    }

    func selectMode(_ m: SnakeEngine.Mode) {
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: "khel.snake.mode")
        best = UserDefaults.standard.integer(forKey: "khel.snake.best.\(m.rawValue)")
    }

    func start() {
        engine = SnakeEngine(mode: mode, seed: UInt64.random(in: .min ... .max))
        previous = engine.body
        phase = .playing
        lastTick = Date()
        run()
    }

    func pause() { if phase == .playing { phase = .paused; loop?.cancel() } }
    func resume() { if phase == .paused { phase = .playing; lastTick = Date(); run() } }
    func stop() { loop?.cancel() }

    private func run() {
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.phase == .playing {
                try? await Task.sleep(for: .seconds(self.engine.interval))
                guard !Task.isCancelled, self.phase == .playing else { return }
                self.previous = self.engine.body
                let e = self.engine.tick()
                self.lastTick = Date()
                switch e {
                case .ate:
                    Feedback.shared.play(.place); Feedback.shared.tap()
                    self.particles.append((self.engine.body[0], Date()))
                    if self.particles.count > 6 { self.particles.removeFirst() }
                case .died:
                    self.phase = .over
                    Feedback.shared.failure()
                    self.shake = 1
                    if self.engine.score > self.best {
                        self.best = self.engine.score
                        UserDefaults.standard.set(self.best, forKey: "khel.snake.best.\(self.mode.rawValue)")
                    }
                    StatsStore.shared.submitScore(gameID: "snake", score: self.engine.score)
                case .none: break
                }
            }
        }
    }
}

// MARK: - View

struct SnakeView: View {
    static let info = GameInfo(
        id: "snake", title: "Snake", tagline: "Eat, grow, don't crash", symbol: "scribble.variable", origin: .arcade, mode: .solo,
        minPlayers: 1, maxPlayers: 1, palette: [0x56AB2F, 0xA8E063], supportsAI: false,
        rules: "Swipe anywhere to steer. Eat the glowing food to grow and score. Classic: hitting a wall or yourself ends the run. Wrap: you pass through the edges but still can't touch yourself. Speed: the snake accelerates much faster. You can queue two quick turns.")

    @State private var model = SnakeModel()
    @State private var anchor: CGPoint?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("\(model.engine.score)", systemImage: "leaf.fill").font(.system(.title2, design: .rounded, weight: .heavy)).contentTransition(.numericText())
                Spacer()
                Label("Best \(model.best)", systemImage: "trophy.fill").font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Theme.text2)
                Button { model.phase == .playing ? model.pause() : model.resume() } label: {
                    Image(systemName: model.phase == .paused ? "play.fill" : "pause.fill").frame(width: 36, height: 36).background(Theme.surface2, in: Circle())
                }.disabled(model.phase == .ready || model.phase == .over)
            }
            .padding(.horizontal, 16)

            GeometryReader { geo in
                let cell = min(geo.size.width / CGFloat(model.engine.cols), geo.size.height / CGFloat(model.engine.rows))
                let w = cell * CGFloat(model.engine.cols), h = cell * CGFloat(model.engine.rows)
                ZStack {
                    TimelineView(.animation(minimumInterval: 1 / 120)) { tl in
                        Canvas { ctx, size in draw(&ctx, size: size, cell: cell, now: tl.date) }
                    }
                    if model.phase == .ready { startPanel }
                    if model.phase == .paused { Text("Paused").font(.system(size: 30, weight: .heavy, design: .rounded)).padding(30).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)) }
                    if model.phase == .over { gameOver }
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 2))
                .offset(x: model.shake > 0 ? CGFloat(sin(model.shake * 40)) * 6 * model.shake : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 6)
                    .onChanged { v in
                        guard model.phase == .playing else { return }
                        let a = anchor ?? v.startLocation
                        anchor = a
                        let dx = v.location.x - a.x, dy = v.location.y - a.y
                        guard max(abs(dx), abs(dy)) > 18 else { return }
                        anchor = v.location
                        model.engine.turn(abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up))
                    }
                    .onEnded { _ in anchor = nil })
            }
            .padding(.horizontal, 8)
        }
        .padding(.bottom, 8)
        .onDisappear { model.stop() }
        .onChange(of: model.shake) { _, v in
            guard v > 0 else { return }
            withAnimation(.easeOut(duration: 0.5)) { model.shake = 0 }
        }
    }

    private var startPanel: some View {
        VStack(spacing: 14) {
            Text("SNAKE").font(.system(size: 38, weight: .black, design: .rounded)).tracking(6)
            Picker("Mode", selection: Binding(get: { model.mode }, set: { model.selectMode($0) })) {
                ForEach(SnakeEngine.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Text(model.mode.detail).font(.footnote).foregroundStyle(Theme.text2)
            Text("Best \(model.best)").font(.system(.headline, design: .rounded))
            Button("Play") { model.start() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(24).frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var gameOver: some View {
        VStack(spacing: 12) {
            Text("Game over").font(.system(size: 30, weight: .heavy, design: .rounded))
            Text("Score \(model.engine.score)").font(.title3)
            if model.engine.score >= model.best && model.engine.score > 0 { Label("New best!", systemImage: "star.fill").foregroundStyle(.yellow) }
            Button("Play again") { model.start() }.buttonStyle(PrimaryButtonStyle())
            Button("Change mode") { model.phase = .ready }.buttonStyle(SecondaryButtonStyle())
        }
        .padding(24).frame(maxWidth: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, cell: CGFloat, now: Date) {
        let e = model.engine
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [Color(red: 0.05, green: 0.10, blue: 0.09), Color(red: 0.03, green: 0.05, blue: 0.07)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        var grid = Path()
        for x in 0 ... e.cols { grid.move(to: CGPoint(x: CGFloat(x) * cell, y: 0)); grid.addLine(to: CGPoint(x: CGFloat(x) * cell, y: size.height)) }
        for y in 0 ... e.rows { grid.move(to: CGPoint(x: 0, y: CGFloat(y) * cell)); grid.addLine(to: CGPoint(x: size.width, y: CGFloat(y) * cell)) }
        ctx.stroke(grid, with: .color(.white.opacity(0.04)), lineWidth: 1)

        // Food with a gentle bounce.
        let t = now.timeIntervalSinceReferenceDate
        let bounce = 1 + 0.12 * sin(t * 6)
        let fc = CGPoint(x: (CGFloat(e.food.x) + 0.5) * cell, y: (CGFloat(e.food.y) + 0.5) * cell)
        let fr = cell * 0.34 * bounce
        ctx.fill(Path(ellipseIn: CGRect(x: fc.x - fr * 2, y: fc.y - fr * 2, width: fr * 4, height: fr * 4)), with: .radialGradient(Gradient(colors: [.red.opacity(0.45), .clear]), center: fc, startRadius: 0, endRadius: fr * 2))
        ctx.fill(Path(ellipseIn: CGRect(x: fc.x - fr, y: fc.y - fr, width: fr * 2, height: fr * 2)), with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.2, blue: 0.25)]), center: CGPoint(x: fc.x - fr * 0.3, y: fc.y - fr * 0.3), startRadius: 0, endRadius: fr * 1.2))

        // Snake: interpolate every segment from its previous cell to its current one.
        let progress = model.phase == .playing ? min(1, now.timeIntervalSince(model.lastTick) / e.interval) : 1
        func pt(_ p: SnakeEngine.Point) -> CGPoint { CGPoint(x: (CGFloat(p.x) + 0.5) * cell, y: (CGFloat(p.y) + 0.5) * cell) }
        var pts: [CGPoint] = []
        for (i, cur) in e.body.enumerated() {
            let prev = i < model.previous.count && !model.previous.isEmpty ? model.previous[min(i, model.previous.count - 1)] : cur
            let a = pt(prev), b = pt(cur)
            pts.append(hypot(a.x - b.x, a.y - b.y) > cell * 1.5 ? b : CGPoint(x: a.x + (b.x - a.x) * CGFloat(progress), y: a.y + (b.y - a.y) * CGFloat(progress)))
        }
        // A newly grown snake keeps its old tail in place until the next tick.
        if pts.count >= 2 {
            var path = Path()
            path.move(to: pts[0])
            for p in pts.dropFirst() where hypot(p.x - path.currentPoint!.x, p.y - path.currentPoint!.y) < cell * 1.6 { path.addLine(to: p) }
            ctx.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: cell * 0.86, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.95, blue: 0.3), Color(red: 0.1, green: 0.65, blue: 0.4)]), startPoint: pts[0], endPoint: pts[pts.count - 1]),
                       style: StrokeStyle(lineWidth: cell * 0.78, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: cell * 0.12, lineCap: .round, lineJoin: .round, dash: [cell * 0.2, cell * 0.5]))
        }
        if let head = pts.first {
            let d = e.dir.delta
            let fwd = CGPoint(x: CGFloat(d.0), y: CGFloat(d.1)), side = CGPoint(x: -fwd.y, y: fwd.x)
            for s: CGFloat in [-1, 1] {
                let c = CGPoint(x: head.x + fwd.x * cell * 0.14 + side.x * cell * 0.2 * s, y: head.y + fwd.y * cell * 0.14 + side.y * cell * 0.2 * s)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - cell * 0.12, y: c.y - cell * 0.12, width: cell * 0.24, height: cell * 0.24)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - cell * 0.06 + fwd.x * 2, y: c.y - cell * 0.06 + fwd.y * 2, width: cell * 0.12, height: cell * 0.12)), with: .color(.black))
            }
        }
        // Eat particles.
        for p in model.particles where now.timeIntervalSince(p.born) < 0.5 {
            let k = now.timeIntervalSince(p.born) / 0.5
            let c = pt(p.pos)
            for i in 0 ..< 8 {
                let a = Double(i) / 8 * .pi * 2
                let r = cell * (0.3 + 0.8 * k)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x + CGFloat(cos(a)) * r - 3, y: c.y + CGFloat(sin(a)) * r - 3, width: 6, height: 6)), with: .color(.yellow.opacity(1 - k)))
            }
        }
    }
}
