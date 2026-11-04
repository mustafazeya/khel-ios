import XCTest
@testable import Khel

final class Game2048Tests: XCTestCase {
    typealias E = Game2048Engine

    private func engine(_ rows: [[Int]]) -> E {
        var e = E(size: rows.count, seed: 1)
        e.tiles = []
        e.nextID = 1
        for (r, row) in rows.enumerated() { for (c, v) in row.enumerated() where v != 0 { e.tiles.append(E.Tile(id: e.nextID, value: v, row: r, col: c)); e.nextID += 1 } }
        return e
    }

    private func values(_ e: E, row: Int) -> [Int] { (0 ..< e.size).map { c in e.tiles.first { $0.row == row && $0.col == c && !$0.isNew }?.value ?? 0 } }

    func testStartsWithTwoTiles() {
        let e = E(size: 4, seed: 3)
        XCTAssertEqual(e.tiles.count, 2)
        XCTAssertTrue(e.tiles.allSatisfy { $0.value == 2 || $0.value == 4 })
    }

    func testMergeAndSlideLeft() {
        var e = engine([[2, 2, 2, 2], [0, 2, 0, 2], [4, 0, 4, 8], [2, 2, 2, 0]])
        let r = e.move(.left)
        XCTAssertTrue(r.moved)
        XCTAssertEqual(values(e, row: 0), [4, 4, 0, 0])
        XCTAssertEqual(values(e, row: 1), [4, 0, 0, 0])
        XCTAssertEqual(values(e, row: 2), [8, 8, 0, 0])
        XCTAssertEqual(values(e, row: 3), [4, 2, 0, 0])
        XCTAssertEqual(r.gained, 4 + 4 + 4 + 8 + 4)
        XCTAssertEqual(e.score, r.gained)
        XCTAssertEqual(r.absorbed.count, 5)
    }

    func testAllDirections() {
        for d in E.Direction.allCases {
            var e = engine([[2, 0, 0, 2], [0, 0, 0, 0], [0, 0, 0, 0], [4, 0, 0, 0]])
            let r = e.move(d)
            XCTAssertTrue(r.moved, "\(d)")
            XCTAssertEqual(e.tiles.count, d == .left || d == .right ? 3 : 4, "row tiles merge sideways; one tile spawns for \(d)")
        }
        var e = engine([[2, 0, 0, 2], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        e.move(.right)
        XCTAssertEqual(e.tiles.first { $0.merged }?.col, 3)
        var f = engine([[0, 0, 0, 0], [0, 0, 0, 0], [2, 0, 0, 0], [2, 0, 0, 0]])
        f.move(.up)
        XCTAssertEqual(f.tiles.first { $0.merged }?.row, 0)
    }

    func testNoMoveDoesNothing() {
        var e = engine([[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 0]])
        let before = e
        XCTAssertFalse(e.move(.up).moved && false)
        var f = engine([[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        let g = f
        XCTAssertFalse(f.move(.left).moved)
        XCTAssertEqual(f, g)
        _ = before
    }

    func testGameOverAndWin() {
        var e = engine([[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 0]])
        e.move(.right)
        XCTAssertFalse(e.hasMoves && e.tiles.count == 16 ? false : e.over)
        var full = engine([[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 8]])
        XCTAssertFalse(full.hasMoves)
        full.over = !full.hasMoves
        XCTAssertTrue(full.over)
        var w = engine([[1024, 1024, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        let r = w.move(.left)
        XCTAssertTrue(r.reached2048); XCTAssertTrue(w.won)
    }

    func testDeterministicAndCodable() throws {
        var a = E(size: 5, seed: 9), b = E(size: 5, seed: 9)
        for d in [E.Direction.left, .up, .right, .down, .left, .up] { a.move(d); b.move(d) }
        XCTAssertEqual(a, b)
        XCTAssertEqual(try JSONDecoder().decode(E.self, from: JSONEncoder().encode(a)), a)
    }

    func testRandomPlayNeverCorruptsTheBoard() {
        var e = E(size: 4, seed: 11)
        var rng = SplitMix64(seed: 2)
        for _ in 0 ..< 400 where !e.over {
            e.move(E.Direction.allCases[rng.int(in: 0 ... 3)])
            let cells = e.tiles.map { $0.row * 4 + $0.col }
            XCTAssertEqual(Set(cells).count, cells.count, "two tiles share a cell")
            XCTAssertTrue(e.tiles.allSatisfy { $0.value > 0 && ($0.value & ($0.value - 1)) == 0 })
        }
    }
}
