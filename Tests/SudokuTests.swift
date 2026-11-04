import XCTest
@testable import Khel

final class SudokuTests: XCTestCase {
    private func parse(_ s: String) -> [Int] { s.compactMap { $0 == "." ? 0 : $0.wholeNumberValue } }

    func testSolverSolvesAKnownPuzzle() {
        let puzzle = parse("53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79")
        var solver = SudokuSolver(puzzle)
        var nodes = 0
        XCTAssertEqual(solver.countSolutions(limit: 2, keep: false, nodes: &nodes, maxNodes: 100_000), 1)
        var s2 = SudokuSolver(puzzle); nodes = 0
        XCTAssertEqual(s2.countSolutions(limit: 1, keep: true, nodes: &nodes, maxNodes: 100_000), 1)
        XCTAssertEqual(s2.cells, parse("534678912672195348198342567859761423426853791713924856961537284287419635345286179"))
    }

    func testSolverDetectsMultipleAndNoSolutions() {
        var empty = SudokuSolver([Int](repeating: 0, count: 81)); var n = 0
        XCTAssertEqual(empty.countSolutions(limit: 2, keep: false, nodes: &n, maxNodes: 100_000), 2)
        var clash = SudokuSolver(parse("55" + String(repeating: ".", count: 79))); n = 0
        XCTAssertEqual(clash.countSolutions(limit: 2, keep: false, nodes: &n, maxNodes: 100_000), 0)
    }

    func testGeneratedPuzzlesAreValidAndUniqueAtEveryLevel() {
        for level in SudokuPuzzle.Level.allCases {
            let p = SudokuPuzzle.generate(level: level, seed: UInt64(level.clues), budget: 4)
            XCTAssertEqual(p.givens.count, 81)
            let clues = p.givens.filter { $0 != 0 }.count
            XCTAssertLessThanOrEqual(clues, level == .easy ? 50 : 40, "\(level) has too many clues: \(clues)")
            XCTAssertGreaterThanOrEqual(clues, 17)
            for i in 0 ..< 81 where p.givens[i] != 0 { XCTAssertEqual(p.givens[i], p.solution[i]) }
            var solver = SudokuSolver(p.givens); var n = 0
            XCTAssertEqual(solver.countSolutions(limit: 2, keep: false, nodes: &n, maxNodes: 1_000_000), 1, "\(level) puzzle is not unique")
            // The solution is a valid grid.
            for g in 0 ..< 9 {
                XCTAssertEqual(Set((0 ..< 9).map { p.solution[g * 9 + $0] }), Set(1 ... 9))
                XCTAssertEqual(Set((0 ..< 9).map { p.solution[$0 * 9 + g] }), Set(1 ... 9))
                XCTAssertEqual(Set((0 ..< 9).map { p.solution[(g / 3 * 3 + $0 / 3) * 9 + g % 3 * 3 + $0 % 3] }), Set(1 ... 9))
            }
        }
    }

    func testGenerationIsDeterministic() {
        XCTAssertEqual(SudokuPuzzle.generate(level: .easy, seed: 5, budget: 5), SudokuPuzzle.generate(level: .easy, seed: 5, budget: 5))
    }

    func testGameplay() {
        let p = SudokuPuzzle.generate(level: .easy, seed: 1, budget: 3)
        var g = SudokuGame(puzzle: p, level: .easy)
        let empty = (0 ..< 81).first { g.values[$0] == 0 }!
        let right = p.solution[empty], wrong = right == 9 ? 1 : right + 1
        g.enter(wrong, at: empty, notesMode: false)
        XCTAssertEqual(g.mistakes, 1)
        g.enter(wrong, at: empty, notesMode: false)
        XCTAssertEqual(g.values[empty], 0, "tapping the same number clears it")
        g.enter(3, at: empty, notesMode: true); g.enter(5, at: empty, notesMode: true)
        XCTAssertEqual(g.notes[empty], (1 << 3) | (1 << 5))
        g.enter(right, at: empty, notesMode: false)
        XCTAssertEqual(g.values[empty], right); XCTAssertEqual(g.notes[empty], 0)
        g.undoMove(); XCTAssertEqual(g.values[empty], 0)
        g.redoMove(); XCTAssertEqual(g.values[empty], right)
        let given = (0 ..< 81).first { g.isGiven($0) }!
        let before = g.values
        g.enter(1, at: given, notesMode: false); g.erase(given)
        XCTAssertEqual(g.values, before)
    }

    func testHintsAndCompletion() {
        let p = SudokuPuzzle.generate(level: .easy, seed: 2, budget: 3)
        var g = SudokuGame(puzzle: p, level: .easy)
        XCTAssertFalse(g.solved)
        while let _ = g.hint(at: nil) {}
        XCTAssertTrue(g.solved)
        XCTAssertGreaterThan(g.hints, 0)
        XCTAssertTrue((0 ..< 81).allSatisfy { !g.conflicts($0) })
    }

    func testConflictDetectionAndRemainingCounts() {
        let p = SudokuPuzzle.generate(level: .easy, seed: 3, budget: 3)
        var g = SudokuGame(puzzle: p, level: .easy)
        let given = (0 ..< 81).first { g.isGiven($0) }!
        let peer = (0 ..< 81).first { $0 != given && !g.isGiven($0) && $0 / 9 == given / 9 }!
        g.values[peer] = g.values[given]
        XCTAssertTrue(g.conflicts(given)); XCTAssertTrue(g.conflicts(peer))
        XCTAssertEqual(g.remaining(g.values[given]), 9 - g.values.filter { $0 == g.values[given] }.count)
    }

    func testCodable() throws {
        var g = SudokuGame(puzzle: SudokuPuzzle.generate(level: .easy, seed: 4, budget: 2), level: .easy)
        _ = g.hint(at: nil)
        XCTAssertEqual(try JSONDecoder().decode(SudokuGame.self, from: JSONEncoder().encode(g)), g)
    }
}
