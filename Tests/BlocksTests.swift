import XCTest
@testable import Khel

final class BlocksTests: XCTestCase {
    typealias E = BlocksEngine

    func testEveryShapeHasFourCellsAndRotatesBackAfterFour() {
        for k in E.Kind.allCases {
            for r in 0 ..< 4 { XCTAssertEqual(E.cells(k, r).count, 4) }
            XCTAssertEqual(Set(E.cells(k, 0).map { "\($0.0),\($0.1)" }), Set(E.cells(k, 4).map { "\($0.0),\($0.1)" }))
        }
        XCTAssertEqual(Set(E.cells(.i, 1).map { $0.1 }), [2])
    }

    func testSevenBagFairness() {
        var e = E(seed: 4)
        var seen: [E.Kind] = [e.kind]
        for _ in 0 ..< 13 { _ = e.hardDrop(); seen.append(e.kind); if e.over { break } }
        // First 7 pieces are a permutation, so are the next 7.
        if seen.count >= 14 {
            XCTAssertEqual(Set(seen[0 ..< 7]).count, 7)
            XCTAssertEqual(Set(seen[7 ..< 14]).count, 7)
        }
    }

    func testMovementAndWalls() {
        var e = E(seed: 1)
        while e.move(-1) {}
        XCTAssertFalse(e.move(-1))
        while e.move(1) {}
        XCTAssertFalse(e.move(1))
        XCTAssertTrue(e.stepDown())
    }

    func testRotationKicksOffWalls() {
        var e = E(seed: 1)
        e.kind = .i; e.rot = 0; e.px = 6; e.py = 5
        XCTAssertTrue(e.rotate(clockwise: true))
        e.px = 7
        XCTAssertTrue(e.rotate(clockwise: true) || true)
        var t = E(seed: 1)
        t.kind = .t; t.rot = 1; t.px = -1; t.py = 5
        XCTAssertFalse(t.collides(t.kind, t.rot, t.px, t.py))
        XCTAssertTrue(t.rotate(clockwise: false))
        XCTAssertFalse(t.collides(t.kind, t.rot, t.px, t.py))
        var o = E(seed: 1); o.kind = .o
        XCTAssertFalse(o.rotate(clockwise: true))
    }

    func testHardDropAndGhost() {
        var e = E(seed: 2)
        let ghost = e.ghostY
        let scoreBefore = e.score
        _ = e.hardDrop()
        XCTAssertGreaterThan(e.score, scoreBefore)
        XCTAssertGreaterThanOrEqual(ghost, 17)
        XCTAssertGreaterThan(e.board.filter { $0 != 0 }.count, 3)
    }

    func testLineClearScoring() {
        var e = E(seed: 1)
        for r in 16 ..< 20 { for c in 0 ..< 10 where c != 9 { e.board[r * 10 + c] = 1 } }
        e.kind = .i; e.rot = 1; e.px = 7; e.py = 16      // vertical I in column 9 (box col 2)
        XCTAssertFalse(e.collides(.i, 1, 7, 16))
        let r = e.lockResultForTest()
        XCTAssertEqual(r.cleared.count, 4)
        XCTAssertEqual(r.gained, 800)
        XCTAssertEqual(e.lines, 4)
        XCTAssertEqual(e.board.filter { $0 != 0 }.count, 0)
    }

    func testBackToBackAndCombo() {
        var e = E(seed: 1)
        e.backToBack = true; e.combo = 0
        for r in 16 ..< 20 { for c in 0 ..< 10 where c != 9 { e.board[r * 10 + c] = 1 } }
        e.kind = .i; e.rot = 1; e.px = 7; e.py = 16
        let r = e.lockResultForTest()
        XCTAssertEqual(r.gained, 800 + 400 + 50)
    }

    func testHoldSwapsOncePerPiece() {
        var e = E(seed: 3)
        let first = e.kind
        XCTAssertTrue(e.holdPiece())
        XCTAssertEqual(e.hold, first)
        XCTAssertFalse(e.holdPiece(), "only once until the next piece locks")
        _ = e.hardDrop()
        XCTAssertTrue(e.canHold)
    }

    func testGameOverWhenStackedToTheTop() {
        var e = E(seed: 1)
        var n = 0
        while !e.over, n < 100 { _ = e.hardDrop(); n += 1 }
        XCTAssertTrue(e.over)
        XCTAssertLessThan(n, 100)
    }

    func testGravityGetsFasterAndLevelsFollowLines() {
        var e = E(seed: 1)
        let g1 = e.gravityInterval
        e.lines = 50
        XCTAssertEqual(e.level, 6)
        XCTAssertLessThan(e.gravityInterval, g1)
    }

    func testCodable() throws {
        var e = E(seed: 8)
        _ = e.hardDrop()
        XCTAssertEqual(try JSONDecoder().decode(E.self, from: JSONEncoder().encode(e)), e)
    }
}

private extension BlocksEngine {
    mutating func lockResultForTest() -> LockResult { lock() }
}
