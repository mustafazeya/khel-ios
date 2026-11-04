import SwiftUI

struct MinesweeperEngine: Codable, Equatable, Sendable {
    enum Level: String, Codable, CaseIterable, Sendable {
        case beginner = "Beginner", intermediate = "Intermediate", expert = "Expert"
        var size: (cols: Int, rows: Int, mines: Int) {
            switch self { case .beginner: (9, 9, 10); case .intermediate: (10, 14, 24); case .expert: (12, 20, 50) }
        }
        var weight: Int { switch self { case .beginner: 1; case .intermediate: 2; case .expert: 3 } }
    }
    enum Status: String, Codable, Sendable { case ready, playing, won, lost }

    struct Cell: Codable, Equatable, Sendable {
        var mine = false
        var revealed = false
        var flagged = false
        var adjacent = 0
    }

    let level: Level
    let cols: Int
    let rows: Int
    let mineCount: Int
    var cells: [Cell]
    var status = Status.ready
    var exploded = -1
    var rng: SplitMix64

    init(level: Level, seed: UInt64) {
        self.level = level
        (cols, rows, mineCount) = (level.size.cols, level.size.rows, level.size.mines)
        cells = [Cell](repeating: Cell(), count: level.size.cols * level.size.rows)
        rng = SplitMix64(seed: seed)
    }

    var flags: Int { cells.filter(\.flagged).count }
    var revealedCount: Int { cells.filter(\.revealed).count }

    func neighbours(_ i: Int) -> [Int] {
        let r = i / cols, c = i % cols
        var out: [Int] = []
        for dr in -1 ... 1 { for dc in -1 ... 1 where (dr != 0 || dc != 0) {
            let rr = r + dr, cc = c + dc
            if (0 ..< rows).contains(rr), (0 ..< cols).contains(cc) { out.append(rr * cols + cc) }
        } }
        return out
    }

    /// Mines are placed on the first reveal, never on or next to the tapped cell.
    private mutating func placeMines(avoiding first: Int) {
        let banned = Set([first] + neighbours(first))
        var candidates = (0 ..< cells.count).filter { !banned.contains($0) }
        for i in stride(from: candidates.count - 1, to: 0, by: -1) { candidates.swapAt(i, rng.int(in: 0 ... i)) }
        for i in candidates.prefix(mineCount) { cells[i].mine = true }
        for i in cells.indices { cells[i].adjacent = neighbours(i).filter { cells[$0].mine }.count }
    }

    /// Reveals a cell (flood-filling zeros). Returns the cells that were newly revealed, in order.
    @discardableResult
    mutating func reveal(_ i: Int) -> [Int] {
        guard status == .ready || status == .playing, cells.indices.contains(i), !cells[i].revealed, !cells[i].flagged else { return [] }
        if status == .ready { placeMines(avoiding: i); status = .playing }
        if cells[i].mine { cells[i].revealed = true; exploded = i; status = .lost; return [i] }
        var opened: [Int] = []
        var queue = [i]
        while let cur = queue.popLast() {
            guard !cells[cur].revealed, !cells[cur].flagged else { continue }
            cells[cur].revealed = true
            opened.append(cur)
            if cells[cur].adjacent == 0 { queue += neighbours(cur) }
        }
        checkWin()
        return opened
    }

    mutating func toggleFlag(_ i: Int) {
        guard status == .playing || status == .ready, cells.indices.contains(i), !cells[i].revealed else { return }
        cells[i].flagged.toggle()
    }

    /// Tapping a number whose flags match it reveals all remaining neighbours (a wrong flag can explode).
    @discardableResult
    mutating func chord(_ i: Int) -> [Int] {
        guard status == .playing, cells[i].revealed, cells[i].adjacent > 0 else { return [] }
        let around = neighbours(i)
        guard around.filter({ cells[$0].flagged }).count == cells[i].adjacent else { return [] }
        var opened: [Int] = []
        for n in around where !cells[n].flagged && !cells[n].revealed {
            opened += reveal(n)
            if status == .lost { break }
        }
        return opened
    }

    private mutating func checkWin() {
        if revealedCount == cells.count - mineCount {
            status = .won
            for i in cells.indices where cells[i].mine { cells[i].flagged = true }
        }
    }
}

// MARK: - Model

@MainActor @Observable
private final class MinesweeperModel {
    var engine: MinesweeperEngine
    var level: MinesweeperEngine.Level
    var flagMode = false
    var seconds = 0
    var boomProgress = 0
    var boomOrder: [Int] = []
    private var timer: Task<Void, Never>?
    private var reported = false

    init() {
        let d = UserDefaults.standard
        let saved = MinesweeperEngine.Level(rawValue: d.string(forKey: "khel.mines.level") ?? "") ?? .beginner
        level = saved
        if let data = d.data(forKey: "khel.mines.state"), let e = try? JSONDecoder().decode(MinesweeperEngine.self, from: data), e.status == .playing {
            engine = e; level = e.level; seconds = d.integer(forKey: "khel.mines.seconds")
        } else {
            engine = MinesweeperEngine(level: saved, seed: UInt64.random(in: .min ... .max))
        }
        if engine.status == .playing { startTimer() }
    }

    func bestTime(_ l: MinesweeperEngine.Level) -> Int? { let v = UserDefaults.standard.integer(forKey: "khel.mines.best.\(l.rawValue)"); return v == 0 ? nil : v }

    func newGame(_ l: MinesweeperEngine.Level? = nil) {
        timer?.cancel()
        if let l { level = l; UserDefaults.standard.set(l.rawValue, forKey: "khel.mines.level") }
        engine = MinesweeperEngine(level: level, seed: UInt64.random(in: .min ... .max))
        seconds = 0; boomProgress = 0; boomOrder = []; reported = false; flagMode = false
        save()
    }

    func tap(_ i: Int) {
        let before = engine.status
        if engine.cells[i].revealed { act(engine.chord(i)); return }
        if flagMode { flag(i); return }
        act(engine.reveal(i))
        if before == .ready, engine.status == .playing { startTimer() }
    }

    func flag(_ i: Int) {
        guard !engine.cells[i].revealed else { return }
        engine.toggleFlag(i)
        Feedback.shared.thud()
        save()
    }

    private func act(_ opened: [Int]) {
        if opened.isEmpty { Feedback.shared.failure(); return }
        Feedback.shared.tap()
        switch engine.status {
        case .lost: lose()
        case .won: win()
        default: break
        }
        save()
    }

    private func lose() {
        timer?.cancel()
        Feedback.shared.failure()
        let e = engine.exploded
        boomOrder = engine.cells.indices.filter { engine.cells[$0].mine && $0 != e }.sorted {
            hypot(Double($0 % engine.cols - e % engine.cols), Double($0 / engine.cols - e / engine.cols)) < hypot(Double($1 % engine.cols - e % engine.cols), Double($1 / engine.cols - e / engine.cols))
        }
        boomProgress = 0
        Task { @MainActor in
            for k in 1 ... boomOrder.count { try? await Task.sleep(for: .milliseconds(55)); boomProgress = k; Feedback.shared.play(.tap) }
        }
        UserDefaults.standard.removeObject(forKey: "khel.mines.state")
    }

    private func win() {
        timer?.cancel()
        Feedback.shared.success()
        if !reported {
            reported = true
            let key = "khel.mines.best.\(level.rawValue)"
            let old = UserDefaults.standard.integer(forKey: key)
            if old == 0 || seconds < old { UserDefaults.standard.set(max(1, seconds), forKey: key) }
            StatsStore.shared.submitScore(gameID: "minesweeper", score: max(1, (3000 - seconds * 5)) * level.weight)
        }
        UserDefaults.standard.removeObject(forKey: "khel.mines.state")
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.engine.status == .playing else { return }
                self.seconds += 1
                UserDefaults.standard.set(self.seconds, forKey: "khel.mines.seconds")
            }
        }
    }

    func stop() { timer?.cancel(); save() }

    private func save() {
        guard engine.status == .playing, let data = try? JSONEncoder().encode(engine) else { return }
        UserDefaults.standard.set(data, forKey: "khel.mines.state")
        UserDefaults.standard.set(seconds, forKey: "khel.mines.seconds")
    }
}

// MARK: - View

struct MinesweeperView: View {
    static let info = GameInfo(
        id: "minesweeper", title: "Minesweeper", tagline: "Clear the field, flag the mines", symbol: "flag.fill", origin: .arcade, mode: .solo,
        minPlayers: 1, maxPlayers: 1, palette: [0x485563, 0x29323C], supportsAI: false,
        rules: "Tap a square to reveal it. A number shows how many of the eight squares around it hold a mine. Long-press, or switch on the flag button, to mark a mine. Tap a number whose flags already match it to reveal the rest of its neighbours. Reveal every safe square to win. Your first tap is always safe, and a game in progress is saved.")

    @State private var model = MinesweeperModel()
    @State private var pressStart: Date?
    @State private var pressTask: Task<Void, Never>?
    @State private var longFired = false

    private static let numberColors: [Color] = [.clear, .cyan, .green, Color(red: 1, green: 0.4, blue: 0.4), .purple, .orange, .mint, .white, .gray]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                stat("flag.fill", "\(model.engine.mineCount - model.engine.flags)")
                stat("clock.fill", String(format: "%d:%02d", model.seconds / 60, model.seconds % 60))
                Spacer()
                Menu {
                    ForEach(MinesweeperEngine.Level.allCases, id: \.self) { l in
                        Button("\(l.rawValue)  \(model.bestTime(l).map { "· best \($0)s" } ?? "")") { model.newGame(l) }
                    }
                } label: { Label(model.level.rawValue, systemImage: "slider.horizontal.3").font(.system(.subheadline, design: .rounded, weight: .bold)) }
                    .buttonStyle(.bordered).tint(.gray)
            }
            .padding(.horizontal, 16)

            GeometryReader { geo in
                let cell = min(geo.size.width / CGFloat(model.engine.cols), geo.size.height / CGFloat(model.engine.rows))
                let w = cell * CGFloat(model.engine.cols), h = cell * CGFloat(model.engine.rows)
                ZStack {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: model.engine.status != .lost)) { _ in
                        Canvas { ctx, size in draw(&ctx, cell: cell) }
                    }
                    if model.engine.status == .won { banner("You cleared it!", "\(model.seconds)s") }
                    if model.engine.status == .lost, model.boomProgress >= model.boomOrder.count { banner("Boom!", "Try again") }
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard pressStart == nil else { return }
                        pressStart = Date(); longFired = false
                        let p = v.startLocation
                        pressTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            guard !Task.isCancelled, let i = index(p, cell: cell) else { return }
                            longFired = true
                            model.flag(i)
                        }
                    }
                    .onEnded { v in
                        pressTask?.cancel(); pressStart = nil
                        if !longFired, hypot(v.translation.width, v.translation.height) < 14, let i = index(v.startLocation, cell: cell) { model.tap(i) }
                    })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 8)

            HStack(spacing: 12) {
                if model.flagMode {
                    Button { model.flagMode.toggle() } label: { Label("Flag mode on", systemImage: "flag.fill") }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button { model.flagMode.toggle() } label: { Label("Flag mode", systemImage: "flag") }.buttonStyle(SecondaryButtonStyle())
                }
                Button { model.newGame() } label: { Label("New game", systemImage: "arrow.clockwise") }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .onDisappear { model.stop() }
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(.title3, design: .monospaced, weight: .bold))
            .padding(.horizontal, 12).padding(.vertical, 6).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func banner(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 4) { Text(title).font(.system(size: 28, weight: .heavy, design: .rounded)); Text(sub).foregroundStyle(Theme.text2) }
            .padding(22).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func index(_ p: CGPoint, cell: CGFloat) -> Int? {
        let c = Int(p.x / cell), r = Int(p.y / cell)
        return (0 ..< model.engine.cols).contains(c) && (0 ..< model.engine.rows).contains(r) ? r * model.engine.cols + c : nil
    }

    private func draw(_ ctx: inout GraphicsContext, cell: CGFloat) {
        let e = model.engine
        let boomed = Set(model.boomOrder.prefix(model.boomProgress))
        for i in e.cells.indices {
            let c = e.cells[i]
            let r = CGRect(x: CGFloat(i % e.cols) * cell, y: CGFloat(i / e.cols) * cell, width: cell, height: cell).insetBy(dx: 1, dy: 1)
            let showMine = e.status == .lost && c.mine && (i == e.exploded || boomed.contains(i)) && !c.flagged
            if c.revealed || showMine {
                ctx.fill(Path(roundedRect: r, cornerRadius: cell * 0.14), with: .color(i == e.exploded ? Color.red.opacity(0.85) : Color(white: 0.2)))
                if c.mine || showMine {
                    ctx.draw(Text("💣").font(.system(size: cell * 0.55)), at: CGPoint(x: r.midX, y: r.midY))
                } else if c.adjacent > 0 {
                    ctx.draw(Text("\(c.adjacent)").font(.system(size: cell * 0.55, weight: .heavy, design: .rounded)).foregroundStyle(Self.numberColors[c.adjacent].opacity(1)),
                             at: CGPoint(x: r.midX, y: r.midY))
                }
            } else {
                ctx.fill(Path(roundedRect: r, cornerRadius: cell * 0.14), with: .linearGradient(
                    Gradient(colors: [Color(white: 0.55), Color(white: 0.38)]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                ctx.fill(Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.3), cornerRadius: cell * 0.14), with: .color(.white.opacity(0.18)))
                if c.flagged { ctx.draw(Text("🚩").font(.system(size: cell * 0.5)), at: CGPoint(x: r.midX, y: r.midY)) }
            }
        }
    }
}
