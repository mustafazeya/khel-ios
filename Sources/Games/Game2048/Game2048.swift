import SwiftUI

/// Pure 2048 engine with stable tile identities so the view can animate slides and merges.
struct Game2048Engine: Codable, Equatable, Sendable {
    enum Direction: CaseIterable, Sendable { case left, right, up, down }

    struct Tile: Codable, Equatable, Identifiable, Sendable {
        var id: Int
        var value: Int
        var row: Int
        var col: Int
        var isNew = false
        var merged = false
    }

    struct MoveResult: Sendable {
        var moved = false
        /// Tiles that were absorbed by a merge, positioned where they ended up (for the slide-in animation).
        var absorbed: [Tile] = []
        var gained = 0
        var reached2048 = false
    }

    var size: Int
    var tiles: [Tile] = []
    var score = 0
    var nextID = 1
    var rng: SplitMix64
    var won = false
    var keepGoing = false
    var over = false

    init(size: Int = 4, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        spawn(); spawn()
    }

    var hasMoves: Bool {
        if tiles.count < size * size { return true }
        for t in tiles { for o in tiles where (abs(t.row - o.row) + abs(t.col - o.col) == 1) && t.value == o.value { return true } }
        return false
    }

    var highest: Int { tiles.map(\.value).max() ?? 0 }

    mutating func spawn() {
        var free: [(Int, Int)] = []
        for r in 0 ..< size { for c in 0 ..< size where !tiles.contains(where: { $0.row == r && $0.col == c }) { free.append((r, c)) } }
        guard !free.isEmpty else { return }
        let (r, c) = free[rng.int(in: 0 ... free.count - 1)]
        tiles.append(Tile(id: nextID, value: rng.int(in: 0 ... 9) == 0 ? 4 : 2, row: r, col: c, isNew: true))
        nextID += 1
    }

    @discardableResult
    mutating func move(_ d: Direction) -> MoveResult {
        var result = MoveResult()
        guard !over else { return result }
        for i in tiles.indices { tiles[i].isNew = false; tiles[i].merged = false }
        var next: [Tile] = []
        for line in 0 ..< size {
            // Tiles in this line ordered from the wall they move towards.
            var inLine = tiles.filter { d == .left || d == .right ? $0.row == line : $0.col == line }
            inLine.sort { a, b in
                switch d {
                case .left: a.col < b.col
                case .right: a.col > b.col
                case .up: a.row < b.row
                case .down: a.row > b.row
                }
            }
            var placed: [Tile] = []
            for var t in inLine {
                if var last = placed.last, last.value == t.value, !last.merged {
                    placed.removeLast()
                    last.value *= 2; last.merged = true
                    result.gained += last.value
                    if last.value == 2048 { result.reached2048 = true }
                    t.row = last.row; t.col = last.col
                    result.absorbed.append(t)
                    placed.append(last)
                    continue
                }
                let slot = placed.count
                switch d {
                case .left: t.col = slot
                case .right: t.col = size - 1 - slot
                case .up: t.row = slot
                case .down: t.row = size - 1 - slot
                }
                placed.append(t)
            }
            next += placed
        }
        let before = Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, ($0.row, $0.col, $0.value)) })
        let changed = !result.absorbed.isEmpty || next.contains { t in before[t.id].map { $0.0 != t.row || $0.1 != t.col } ?? true }
        guard changed else { return result }
        tiles = next
        score += result.gained
        result.moved = true
        spawn()
        if result.reached2048, !won { won = true }
        over = !hasMoves
        return result
    }
}

// MARK: - View

@MainActor @Observable
private final class Game2048Model {
    var engine: Game2048Engine
    var absorbed: [Game2048Engine.Tile] = []
    var popped: Set<Int> = []
    var history: [Game2048Engine] = []
    var best: Int
    var size: Int { engine.size }
    private var reported = false

    init(size: Int) {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "khel.2048.state.\(size)"), let e = try? JSONDecoder().decode(Game2048Engine.self, from: data), !e.over {
            engine = e
        } else {
            engine = Game2048Engine(size: size, seed: UInt64.random(in: .min ... .max))
        }
        best = d.integer(forKey: "khel.2048.best.\(size)")
    }

    func newGame() {
        reported = false
        history = []
        engine = Game2048Engine(size: engine.size, seed: UInt64.random(in: .min ... .max))
        absorbed = []; popped = []
        save()
    }

    func move(_ d: Game2048Engine.Direction) {
        let snapshot = engine
        let r = engine.move(d)
        guard r.moved else { Feedback.shared.failure(); return }
        history.append(snapshot)
        if history.count > 30 { history.removeFirst() }
        absorbed = r.absorbed
        popped = Set(engine.tiles.filter(\.merged).map(\.id))
        r.gained > 0 ? Feedback.shared.thud() : Feedback.shared.play(.tap)
        if engine.score > best { best = engine.score; UserDefaults.standard.set(best, forKey: "khel.2048.best.\(size)") }
        if engine.over, !reported { reported = true; StatsStore.shared.submitScore(gameID: "g2048", score: engine.score); Feedback.shared.play(.lose) }
        save()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            absorbed = []; popped = []
        }
    }

    func undo() {
        guard let prev = history.popLast() else { return }
        engine = prev
        absorbed = []
        save()
    }

    func resize(_ n: Int) { self.engine = Game2048Model(size: n).engine; history = []; best = UserDefaults.standard.integer(forKey: "khel.2048.best.\(n)"); absorbed = [] }

    private func save() {
        if let data = try? JSONEncoder().encode(engine) { UserDefaults.standard.set(data, forKey: "khel.2048.state.\(engine.size)") }
    }
}

struct Game2048View: View {
    static let info = GameInfo(
        id: "g2048", title: "2048", tagline: "Slide, merge, reach 2048", symbol: "square.grid.2x2.fill", origin: .arcade, mode: .solo,
        minPlayers: 1, maxPlayers: 1, palette: [0xF2994A, 0xF2C94C], supportsAI: false,
        rules: "Swipe to slide every tile. Two tiles with the same number merge into one with the sum. Reach the 2048 tile to win, then keep going for a higher score. The game ends when the board is full and nothing can merge. Undo steps back up to 30 moves. Choose 4×4, 5×5 or 6×6.")

    @State private var model = Game2048Model(size: UserDefaults.standard.integer(forKey: "khel.2048.size").nonZero(4))
    @State private var anchor: CGPoint?

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                stat("SCORE", model.engine.score)
                stat("BEST", model.best)
                Spacer()
                Menu {
                    ForEach([4, 5, 6], id: \.self) { n in Button("\(n)×\(n)") { UserDefaults.standard.set(n, forKey: "khel.2048.size"); model.resize(n) } }
                } label: { Label("\(model.size)×\(model.size)", systemImage: "square.grid.3x3").font(.system(.subheadline, design: .rounded, weight: .bold)) }
                .buttonStyle(.bordered).tint(.orange)
            }
            .padding(.horizontal, 16)

            GeometryReader { geo in
                let side = min(geo.size.width - 32, geo.size.height)
                board(side: side).frame(width: side, height: side).frame(maxWidth: .infinity)
            }
            HStack(spacing: 14) {
                Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(SecondaryButtonStyle()).disabled(model.history.isEmpty)
                Button { model.newGame() } label: { Label("New game", systemImage: "arrow.clockwise") }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    private func stat(_ title: String, _ v: Int) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.text2)
            Text("\(v)").font(.system(size: 20, weight: .heavy, design: .rounded)).contentTransition(.numericText())
        }
        .frame(minWidth: 74).padding(.vertical, 6).padding(.horizontal, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func color(_ v: Int) -> (Color, Color) {
        switch v {
        case 2: (Color(red: 0.93, green: 0.89, blue: 0.85), Color(red: 0.4, green: 0.36, blue: 0.32))
        case 4: (Color(red: 0.93, green: 0.88, blue: 0.78), Color(red: 0.4, green: 0.36, blue: 0.32))
        case 8: (Color(red: 0.96, green: 0.69, blue: 0.47), .white)
        case 16: (Color(red: 0.96, green: 0.58, blue: 0.39), .white)
        case 32: (Color(red: 0.96, green: 0.48, blue: 0.37), .white)
        case 64: (Color(red: 0.96, green: 0.37, blue: 0.23), .white)
        case 128: (Color(red: 0.93, green: 0.81, blue: 0.45), .white)
        case 256: (Color(red: 0.93, green: 0.80, blue: 0.38), .white)
        case 512: (Color(red: 0.93, green: 0.78, blue: 0.31), .white)
        case 1024: (Color(red: 0.93, green: 0.77, blue: 0.25), .white)
        case 2048: (Color(red: 0.93, green: 0.76, blue: 0.18), .white)
        default: (Color(red: 0.24, green: 0.23, blue: 0.2), .white)
        }
    }

    private func board(side: CGFloat) -> some View {
        let n = model.size
        let gap = side * 0.025
        let cell = (side - gap * CGFloat(n + 1)) / CGFloat(n)
        func pos(_ r: Int, _ c: Int) -> CGPoint { CGPoint(x: gap + CGFloat(c) * (cell + gap) + cell / 2, y: gap + CGFloat(r) * (cell + gap) + cell / 2) }
        func tile(_ t: Game2048Engine.Tile, ghost: Bool) -> some View {
            let (bg, fg) = color(t.value)
            let digits = String(t.value).count
            return Text("\(t.value)")
                .font(.system(size: cell * (digits <= 2 ? 0.46 : (digits == 3 ? 0.38 : 0.3)), weight: .heavy, design: .rounded))
                .foregroundStyle(fg).minimumScaleFactor(0.5)
                .frame(width: cell, height: cell)
                .background(bg, in: RoundedRectangle(cornerRadius: cell * 0.12, style: .continuous))
                .shadow(color: t.value >= 128 ? bg.opacity(0.7) : .clear, radius: 8)
                .scaleEffect(model.popped.contains(t.id) ? 1.16 : 1)
                .position(pos(t.row, t.col))
                .opacity(ghost ? 0 : 1)
                .animation(.easeOut(duration: 0.14), value: t.row)
                .animation(.easeOut(duration: 0.14), value: t.col)
                .animation(.spring(duration: 0.25, bounce: 0.5), value: model.popped)
        }
        return ZStack {
            RoundedRectangle(cornerRadius: side * 0.035, style: .continuous).fill(Color(red: 0.28, green: 0.25, blue: 0.22))
            ForEach(0 ..< n * n, id: \.self) { i in
                RoundedRectangle(cornerRadius: cell * 0.12, style: .continuous).fill(Color.white.opacity(0.08)).frame(width: cell, height: cell).position(pos(i / n, i % n))
            }
            ForEach(model.engine.tiles + model.absorbed) { t in
                tile(t, ghost: false).zIndex(model.absorbed.contains { $0.id == t.id } ? 0 : 1)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
            if model.engine.over { overlay("Game over") }
            else if model.engine.won && !model.engine.keepGoing {
                VStack(spacing: 10) {
                    Text("You made 2048!").font(.system(size: 26, weight: .heavy, design: .rounded))
                    Button("Keep going") { model.engine.keepGoing = true }.buttonStyle(PrimaryButtonStyle()).frame(width: 180)
                }
                .padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .animation(.spring(duration: 0.25), value: model.engine.tiles.count)
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { v in
                let a = anchor ?? v.startLocation
                anchor = a
                let dx = v.location.x - a.x, dy = v.location.y - a.y
                guard max(abs(dx), abs(dy)) > 24 else { return }
                anchor = v.location
                model.move(abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up))
            }
            .onEnded { _ in anchor = nil })
    }

    private func overlay(_ text: String) -> some View {
        VStack(spacing: 12) {
            Text(text).font(.system(size: 30, weight: .heavy, design: .rounded))
            Text("Score \(model.engine.score)").foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }
}

private extension Int { func nonZero(_ fallback: Int) -> Int { self == 0 ? fallback : self } }
