import XCTest
@testable import Khel

final class MinesweeperTests: XCTestCase {
    typealias E = MinesweeperEngine

    func testFirstRevealIsAlwaysSafeAndOpensArea() {
        for seed in 0 ..< 40 {
            var e = E(level: .beginner, seed: UInt64(seed))
            let opened = e.reveal(40)
            XCTAssertEqual(e.status, .playing, "seed \(seed)")
            XCTAssertFalse(e.cells[40].mine)
            XCTAssertEqual(e.cells[40].adjacent, 0, "the first tap and its neighbours are mine free")
            XCTAssertGreaterThan(opened.count, 1)
            XCTAssertEqual(e.cells.filter(\.mine).count, e.mineCount)
        }
    }

    func testAdjacencyCounts() {
        var e = E(level: .intermediate, seed: 3)
        e.reveal(0)
        for i in e.cells.indices { XCTAssertEqual(e.cells[i].adjacent, e.neighbours(i).filter { e.cells[$0].mine }.count) }
    }

    func testRevealingAMineLoses() {
        var e = E(level: .beginner, seed: 5)
        e.reveal(0)
        let mine = e.cells.firstIndex { $0.mine }!
        e.reveal(mine)
        XCTAssertEqual(e.status, .lost); XCTAssertEqual(e.exploded, mine)
        XCTAssertTrue(e.reveal(1).isEmpty, "no moves after the game ends")
    }

    func testFlagsBlockRevealAndToggle() {
        var e = E(level: .beginner, seed: 5)
        e.toggleFlag(10)
        XCTAssertTrue(e.cells[10].flagged); XCTAssertEqual(e.flags, 1)
        XCTAssertTrue(e.reveal(10).isEmpty)
        e.toggleFlag(10)
        XCTAssertFalse(e.cells[10].flagged)
    }

    func testWinningByRevealingEverySafeCell() {
        var e = E(level: .beginner, seed: 9)
        e.reveal(40)
        for i in e.cells.indices where !e.cells[i].mine { e.reveal(i) }
        XCTAssertEqual(e.status, .won)
        XCTAssertTrue(e.cells.filter(\.mine).allSatisfy(\.flagged))
    }

    func testChordRevealsNeighboursWhenFlagsMatch() {
        var e = E(level: .beginner, seed: 11)
        e.reveal(40)
        guard let numbered = e.cells.indices.first(where: { e.cells[$0].revealed && e.cells[$0].adjacent > 0 }) else { return XCTFail("no number revealed") }
        XCTAssertTrue(e.chord(numbered).isEmpty, "not enough flags yet")
        for n in e.neighbours(numbered) where e.cells[n].mine { e.toggleFlag(n) }
        e.chord(numbered)
        XCTAssertTrue(e.neighbours(numbered).allSatisfy { e.cells[$0].revealed || e.cells[$0].flagged })
        XCTAssertNotEqual(e.status, .lost)
    }

    func testWrongFlagChordCanExplode() {
        var e = E(level: .beginner, seed: 11)
        e.reveal(40)
        guard let numbered = e.cells.indices.first(where: { e.cells[$0].revealed && e.cells[$0].adjacent > 0 }) else { return XCTFail() }
        let hidden = e.neighbours(numbered).filter { !e.cells[$0].revealed }
        let safe = hidden.filter { !e.cells[$0].mine }
        for n in safe.prefix(e.cells[numbered].adjacent) { e.toggleFlag(n) }
        if e.flags == e.cells[numbered].adjacent { e.chord(numbered); XCTAssertEqual(e.status, .lost) }
    }

    func testCodableAndLevels() throws {
        var e = E(level: .expert, seed: 2)
        e.reveal(100)
        XCTAssertEqual(try JSONDecoder().decode(E.self, from: JSONEncoder().encode(e)), e)
        XCTAssertEqual(E(level: .expert, seed: 1).cells.count, 240)
        XCTAssertEqual(E.Level.allCases.map { $0.size.mines }, [10, 24, 50])
    }
}
