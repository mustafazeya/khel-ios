import SwiftUI

/// Sudoku solver and generator (bitmask constraint propagation with most-constrained-cell search).
struct SudokuSolver {
    var cells: [Int]        // 0 empty
    private var rows = [UInt16](repeating: 0, count: 9)
    private var cols = [UInt16](repeating: 0, count: 9)
    private var boxes = [UInt16](repeating: 0, count: 9)
    private(set) var valid = true

    init(_ cells: [Int]) {
        self.cells = cells
        for i in 0 ..< 81 where cells[i] != 0 {
            let bit = UInt16(1) << UInt16(cells[i])
            let r = i / 9, c = i % 9, b = r / 3 * 3 + c / 3
            if rows[r] & bit != 0 || cols[c] & bit != 0 || boxes[b] & bit != 0 { valid = false }
            rows[r] |= bit; cols[c] |= bit; boxes[b] |= bit
        }
    }

    private func candidates(_ i: Int) -> UInt16 {
        let r = i / 9, c = i % 9
        return ~(rows[r] | cols[c] | boxes[r / 3 * 3 + c / 3]) & 0b11_1111_1110
    }

    private mutating func place(_ i: Int, _ v: Int) {
        let bit = UInt16(1) << UInt16(v), r = i / 9, c = i % 9
        cells[i] = v; rows[r] |= bit; cols[c] |= bit; boxes[r / 3 * 3 + c / 3] |= bit
    }

    private mutating func unplace(_ i: Int) {
        let bit = UInt16(1) << UInt16(cells[i]), r = i / 9, c = i % 9
        rows[r] &= ~bit; cols[c] &= ~bit; boxes[r / 3 * 3 + c / 3] &= ~bit
        cells[i] = 0
    }

    /// Counts solutions up to `limit`. With `rng`, candidate order is shuffled (used to build random grids).
    mutating func countSolutions(limit: Int, rng: UnsafeMutablePointer<SplitMix64>? = nil, keep: Bool = false, nodes: inout Int, maxNodes: Int) -> Int {
        guard valid else { return 0 }
        nodes += 1
        if nodes > maxNodes { return limit }       // treat as "too hard to prove": caller keeps the clue
        var best = -1, bestCount = 10, bestMask: UInt16 = 0
        for i in 0 ..< 81 where cells[i] == 0 {
            let m = candidates(i)
            let n = m.nonzeroBitCount
            if n == 0 { return 0 }
            if n < bestCount { best = i; bestCount = n; bestMask = m; if n == 1 { break } }
        }
        if best < 0 { return 1 }
        var values = (1 ... 9).filter { bestMask & (1 << UInt16($0)) != 0 }
        if let rng { for k in stride(from: values.count - 1, to: 0, by: -1) { values.swapAt(k, rng.pointee.int(in: 0 ... k)) } }
        var found = 0
        for v in values {
            place(best, v)
            found += countSolutions(limit: limit - found, rng: rng, keep: keep, nodes: &nodes, maxNodes: maxNodes)
            if found >= limit || (keep && found == 1) { if !(keep && found == 1) { unplace(best) }; return found }
            unplace(best)
        }
        return found
    }
}

struct SudokuPuzzle: Codable, Equatable, Sendable {
    var givens: [Int]
    var solution: [Int]

    enum Level: String, Codable, CaseIterable, Sendable {
        case easy = "Easy", medium = "Medium", hard = "Hard", expert = "Expert"
        var clues: Int { switch self { case .easy: 42; case .medium: 35; case .hard: 29; case .expert: 25 } }
    }

    /// A random puzzle with exactly one solution. Stops removing clues at `level.clues` or after a time budget.
    static func generate(level: Level, seed: UInt64, budget: Double = 1.5) -> SudokuPuzzle {
        var rng = SplitMix64(seed: seed)
        var full = SudokuSolver([Int](repeating: 0, count: 81))
        var nodes = 0
        _ = withUnsafeMutablePointer(to: &rng) { full.countSolutions(limit: 1, rng: $0, keep: true, nodes: &nodes, maxNodes: 1_000_000) }
        let solution = full.cells
        var puzzle = solution
        var order = Array(0 ..< 81)
        for k in stride(from: 80, to: 0, by: -1) { order.swapAt(k, rng.int(in: 0 ... k)) }
        let deadline = Date().addingTimeInterval(budget)
        var clues = 81
        for idx in order where clues > level.clues && Date() < deadline {
            let saved = puzzle[idx]
            puzzle[idx] = 0
            var solver = SudokuSolver(puzzle)
            var n = 0
            if solver.countSolutions(limit: 2, nodes: &n, maxNodes: 20_000) != 1 { puzzle[idx] = saved } else { clues -= 1 }
        }
        return SudokuPuzzle(givens: puzzle, solution: solution)
    }
}

// MARK: - Game state

struct SudokuGame: Codable, Equatable, Sendable {
    var puzzle: SudokuPuzzle
    var level: SudokuPuzzle.Level
    var values: [Int]
    var notes: [UInt16]
    var hints = 0
    var mistakes = 0
    var undo: [Snapshot] = []
    var redo: [Snapshot] = []
    var seconds = 0

    struct Snapshot: Codable, Equatable, Sendable { var values: [Int]; var notes: [UInt16] }

    init(puzzle: SudokuPuzzle, level: SudokuPuzzle.Level) {
        self.puzzle = puzzle; self.level = level
        values = puzzle.givens
        notes = [UInt16](repeating: 0, count: 81)
    }

    func isGiven(_ i: Int) -> Bool { puzzle.givens[i] != 0 }
    var solved: Bool { values == puzzle.solution }

    func conflicts(_ i: Int) -> Bool {
        let v = values[i]
        guard v != 0 else { return false }
        let r = i / 9, c = i % 9
        for j in 0 ..< 81 where j != i && values[j] == v {
            if j / 9 == r || j % 9 == c || (j / 9 / 3 == r / 3 && j % 9 / 3 == c / 3) { return true }
        }
        return false
    }

    func remaining(_ v: Int) -> Int { 9 - values.filter { $0 == v }.count }

    private mutating func push() { undo.append(Snapshot(values: values, notes: notes)); if undo.count > 100 { undo.removeFirst() }; redo = [] }

    mutating func enter(_ v: Int, at i: Int, notesMode: Bool) {
        guard !isGiven(i) else { return }
        push()
        if notesMode {
            guard values[i] == 0 else { return }
            notes[i] ^= UInt16(1) << UInt16(v)
        } else {
            values[i] = values[i] == v ? 0 : v
            notes[i] = 0
            if values[i] != 0 {
                if values[i] != puzzle.solution[i] { mistakes += 1 }
                // Remove the placed number from the notes of peers.
                let r = i / 9, c = i % 9
                for j in 0 ..< 81 where j / 9 == r || j % 9 == c || (j / 9 / 3 == r / 3 && j % 9 / 3 == c / 3) { notes[j] &= ~(UInt16(1) << UInt16(v)) }
            }
        }
    }

    mutating func erase(_ i: Int) {
        guard !isGiven(i), values[i] != 0 || notes[i] != 0 else { return }
        push(); values[i] = 0; notes[i] = 0
    }

    mutating func hint(at i: Int?) -> Int? {
        let target = i.flatMap { values[$0] != puzzle.solution[$0] ? $0 : nil } ?? (0 ..< 81).first { values[$0] != puzzle.solution[$0] }
        guard let t = target else { return nil }
        push()
        values[t] = puzzle.solution[t]; notes[t] = 0; hints += 1
        return t
    }

    mutating func undoMove() {
        guard let s = undo.popLast() else { return }
        redo.append(Snapshot(values: values, notes: notes)); values = s.values; notes = s.notes
    }

    mutating func redoMove() {
        guard let s = redo.popLast() else { return }
        undo.append(Snapshot(values: values, notes: notes)); values = s.values; notes = s.notes
    }
}

// MARK: - Model

@MainActor @Observable
private final class SudokuModel {
    var game: SudokuGame?
    var selected: Int?
    var notesMode = false
    var generating = false
    var paused = false
    var celebrate = false
    var level: SudokuPuzzle.Level
    private var timer: Task<Void, Never>?
    private var reported = false

    init() {
        let d = UserDefaults.standard
        level = SudokuPuzzle.Level(rawValue: d.string(forKey: "khel.sudoku.level") ?? "") ?? .easy
        if let data = d.data(forKey: "khel.sudoku.game"), let g = try? JSONDecoder().decode(SudokuGame.self, from: data), !g.solved {
            game = g; level = g.level; startTimer()
        } else {
            newGame(level)
        }
    }

    func bestTime(_ l: SudokuPuzzle.Level) -> Int? { let v = UserDefaults.standard.integer(forKey: "khel.sudoku.best.\(l.rawValue)"); return v == 0 ? nil : v }

    func newGame(_ l: SudokuPuzzle.Level) {
        level = l
        UserDefaults.standard.set(l.rawValue, forKey: "khel.sudoku.level")
        timer?.cancel(); generating = true; celebrate = false; reported = false; selected = nil; paused = false
        let seed = UInt64.random(in: .min ... .max)
        Task { @MainActor in
            let puzzle = await Task.detached(priority: .userInitiated) { SudokuPuzzle.generate(level: l, seed: seed) }.value
            game = SudokuGame(puzzle: puzzle, level: l)
            generating = false
            save(); startTimer()
        }
    }

    func input(_ v: Int) {
        guard var g = game, let i = selected, !paused else { return }
        g.enter(v, at: i, notesMode: notesMode)
        apply(g, wasValue: !notesMode)
    }

    func erase() { guard var g = game, let i = selected else { return }; g.erase(i); apply(g, wasValue: false) }
    func undo() { guard var g = game else { return }; g.undoMove(); apply(g, wasValue: false) }
    func redo() { guard var g = game else { return }; g.redoMove(); apply(g, wasValue: false) }
    func hint() { guard var g = game else { return }; if let t = g.hint(at: selected) { selected = t; apply(g, wasValue: true) } }

    private func apply(_ g: SudokuGame, wasValue: Bool) {
        let mistakesBefore = game?.mistakes ?? 0
        game = g
        if g.mistakes > mistakesBefore { Feedback.shared.failure() } else { Feedback.shared.tap() }
        save()
        if g.solved { finish() }
    }

    private func finish() {
        timer?.cancel()
        celebrate = true
        Feedback.shared.success()
        guard let g = game, !reported else { return }
        reported = true
        let key = "khel.sudoku.best.\(g.level.rawValue)"
        let old = UserDefaults.standard.integer(forKey: key)
        if old == 0 || g.seconds < old { UserDefaults.standard.set(max(1, g.seconds), forKey: key) }
        let weight = [SudokuPuzzle.Level.easy: 1, .medium: 2, .hard: 3, .expert: 4][g.level] ?? 1
        StatsStore.shared.submitScore(gameID: "sudoku", score: max(100, 10_000 - g.seconds * 4 - g.hints * 300 - g.mistakes * 100) * weight / 4)
        UserDefaults.standard.removeObject(forKey: "khel.sudoku.game")
    }

    func togglePause() { paused.toggle() }

    private func startTimer() {
        timer?.cancel()
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.game?.solved == false, !self.paused else { continue }
                self.game?.seconds += 1
            }
        }
    }

    func stop() { timer?.cancel(); save() }

    private func save() {
        guard let g = game, !g.solved, let data = try? JSONEncoder().encode(g) else { return }
        UserDefaults.standard.set(data, forKey: "khel.sudoku.game")
    }
}

// MARK: - View

struct SudokuView: View {
    static let info = GameInfo(
        id: "sudoku", title: "Sudoku", tagline: "Fill the grid with logic", symbol: "number", origin: .arcade, mode: .solo,
        minPlayers: 1, maxPlayers: 1, palette: [0x1D976C, 0x93F9B9], supportsAI: false,
        rules: "Fill the grid so that every row, column and 3×3 box contains the digits 1 to 9 exactly once. Select a cell and tap a number. Turn on Notes to pencil in candidates. Conflicts are highlighted in red. Every puzzle has exactly one solution. Use Hint if you are stuck. Your game is saved automatically.")

    @State private var model = SudokuModel()

    var body: some View {
        VStack(spacing: 10) {
            header
            if model.generating || model.game == nil {
                VStack(spacing: 12) { ProgressView(); Text("Creating a puzzle…").foregroundStyle(Theme.text2) }.frame(maxHeight: .infinity)
            } else if let g = model.game {
                GeometryReader { geo in
                    let side = min(geo.size.width - 16, geo.size.height)
                    grid(g, side: side).frame(width: side, height: side).frame(maxWidth: .infinity)
                        .overlay {
                            if model.paused { Text("Paused").font(.title.bold()).frame(width: side, height: side).background(Theme.bg, in: RoundedRectangle(cornerRadius: 10)).onTapGesture { model.togglePause() } }
                        }
                }
                toolbar(g)
                pad(g)
            }
        }
        .padding(.bottom, 8)
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(SudokuPuzzle.Level.allCases, id: \.self) { l in Button("\(l.rawValue)\(model.bestTime(l).map { "  · best \($0 / 60):\(String(format: "%02d", $0 % 60))" } ?? "")") { model.newGame(l) } }
            } label: { Label("New · \(model.level.rawValue)", systemImage: "plus.circle.fill").font(.system(.subheadline, design: .rounded, weight: .bold)) }
                .buttonStyle(.bordered).tint(.green)
            Spacer()
            if let g = model.game {
                Label("\(g.mistakes)", systemImage: "xmark.circle").foregroundStyle(g.mistakes > 0 ? Theme.bad : Theme.text2)
                Button { model.togglePause() } label: {
                    Label(String(format: "%d:%02d", g.seconds / 60, g.seconds % 60), systemImage: model.paused ? "play.fill" : "pause.fill").font(.system(.body, design: .monospaced, weight: .semibold))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func grid(_ g: SudokuGame, side: CGFloat) -> some View {
        let cell = side / 9
        let selValue = model.selected.map { g.values[$0] } ?? 0
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.1))
            ForEach(0 ..< 81, id: \.self) { i in
                let r = i / 9, c = i % 9
                let isSel = model.selected == i
                let peer = model.selected.map { s in s / 9 == r || s % 9 == c || (s / 9 / 3 == r / 3 && s % 9 / 3 == c / 3) } ?? false
                let same = selValue != 0 && g.values[i] == selValue
                let bad = g.conflicts(i)
                ZStack {
                    Rectangle().fill(isSel ? Color.green.opacity(0.5) : (same ? Color.green.opacity(0.28) : (peer ? Color.white.opacity(0.07) : Color.clear)))
                    if g.values[i] != 0 {
                        Text("\(g.values[i])").font(.system(size: cell * 0.56, weight: g.isGiven(i) ? .bold : .medium, design: .rounded))
                            .foregroundStyle(bad ? Theme.bad : (g.isGiven(i) ? .white : Color(red: 0.5, green: 0.9, blue: 1)))
                    } else if g.notes[i] != 0 {
                        notesGrid(g.notes[i], cell: cell)
                    }
                }
                .frame(width: cell, height: cell)
                .scaleEffect(model.celebrate ? 1.12 : 1)
                .animation(.spring(duration: 0.35, bounce: 0.5).delay(Double(r + c) * 0.05), value: model.celebrate)
                .position(x: (CGFloat(c) + 0.5) * cell, y: (CGFloat(r) + 0.5) * cell)
                .onTapGesture { model.selected = i; Feedback.shared.tap() }
            }
            Canvas { ctx, size in
                var thin = Path(), thick = Path()
                for i in 1 ..< 9 {
                    let o = CGFloat(i) * cell
                    if i % 3 == 0 { thick.move(to: CGPoint(x: o, y: 0)); thick.addLine(to: CGPoint(x: o, y: size.height)); thick.move(to: CGPoint(x: 0, y: o)); thick.addLine(to: CGPoint(x: size.width, y: o)) }
                    else { thin.move(to: CGPoint(x: o, y: 0)); thin.addLine(to: CGPoint(x: o, y: size.height)); thin.move(to: CGPoint(x: 0, y: o)); thin.addLine(to: CGPoint(x: size.width, y: o)) }
                }
                ctx.stroke(thin, with: .color(.white.opacity(0.18)), lineWidth: 1)
                ctx.stroke(thick, with: .color(.white.opacity(0.8)), lineWidth: 2.5)
                ctx.stroke(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8), with: .color(.white.opacity(0.8)), lineWidth: 3)
            }
            .allowsHitTesting(false)
        }
    }

    private func notesGrid(_ mask: UInt16, cell: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 3, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0 ..< 3, id: \.self) { c in
                        let n = r * 3 + c + 1
                        Text(mask & (1 << UInt16(n)) != 0 ? "\(n)" : " ").font(.system(size: cell * 0.24, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text2).frame(width: cell / 3.4, height: cell / 3.4)
                    }
                }
            }
        }
    }

    private func toolbar(_ g: SudokuGame) -> some View {
        HStack(spacing: 8) {
            tool("arrow.uturn.backward", "Undo", disabled: g.undo.isEmpty) { model.undo() }
            tool("arrow.uturn.forward", "Redo", disabled: g.redo.isEmpty) { model.redo() }
            tool("eraser", "Erase", disabled: model.selected == nil) { model.erase() }
            tool(model.notesMode ? "pencil.circle.fill" : "pencil", "Notes", active: model.notesMode) { model.notesMode.toggle() }
            tool("lightbulb", "Hint (\(g.hints))") { model.hint() }
        }
        .padding(.horizontal, 12)
    }

    private func tool(_ symbol: String, _ title: String, active: Bool = false, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(active ? Color.green.opacity(0.45) : Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain).disabled(disabled)
    }

    private func pad(_ g: SudokuGame) -> some View {
        HStack(spacing: 6) {
            ForEach(1 ... 9, id: \.self) { n in
                Button { model.input(n) } label: {
                    VStack(spacing: 0) {
                        Text("\(n)").font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("\(g.remaining(n))").font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    .opacity(g.remaining(n) == 0 ? 0.3 : 1)
                }
                .buttonStyle(.plain).disabled(g.remaining(n) == 0)
            }
        }
        .padding(.horizontal, 8)
    }
}
