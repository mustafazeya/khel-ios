import XCTest
@testable import Khel

final class GomokuTests: XCTestCase {
    typealias E = GomokuEngine
    private func idx(_ r: Int, _ c: Int) -> Int { r * 15 + c }

    private func play(_ moves: [Int]) throws -> E.State {
        var s = E.State()
        for m in moves { try E.apply(m, by: s.side == 1 ? 0 : 1, to: &s) }
        return s
    }

    func testHorizontalFiveWins() throws {
        let s = try play([idx(7, 3), idx(0, 0), idx(7, 4), idx(0, 2), idx(7, 5), idx(0, 4), idx(7, 6), idx(0, 6), idx(7, 7)])
        XCTAssertEqual(s.winner, 0)
        XCTAssertEqual(s.winLine.count, 5)
        XCTAssertEqual(E.outcome(s)?.winners, [0])
    }

    func testDiagonalAndOverlineWin() throws {
        var s = E.State()
        for i in 0 ..< 6 where i != 3 { s.cells[idx(i, i)] = 1 }
        s.side = 1
        try E.apply(idx(3, 3), by: 0, to: &s)
        XCTAssertEqual(s.winner, 0, "six in a row also wins (free-style)")
        XCTAssertEqual(s.winLine.count, 6)
    }

    func testFourDoesNotWinAndOccupiedThrows() throws {
        let s = try play([idx(7, 3), idx(0, 0), idx(7, 4), idx(0, 2), idx(7, 5), idx(0, 4), idx(7, 6)])
        XCTAssertNil(s.winner)
        var t = s
        XCTAssertThrowsError(try E.apply(idx(7, 3), by: 1, to: &t))
        XCTAssertThrowsError(try E.apply(idx(8, 8), by: 0, to: &t))
    }

    func testAIPlaysCentreFirstAndBlocksOpenFour() {
        XCTAssertEqual(E.aiAction(for: E.State(), seat: 0, level: .medium), idx(7, 7))
        var s = E.State()
        for c in 4 ... 7 { s.cells[idx(7, c)] = 1 }      // black has an open four; white must block an end
        s.side = -1; s.moves = 4
        for level in [AILevel.medium, .hard] { XCTAssertTrue([idx(7, 3), idx(7, 8)].contains(E.aiAction(for: s, seat: 1, level: level)!), "\(level)") }
    }

    func testAITakesImmediateWin() {
        var s = E.State()
        for c in 4 ... 7 { s.cells[idx(5, c)] = -1 }
        s.cells[idx(5, 3)] = 1
        s.cells[idx(9, 9)] = 1; s.cells[idx(9, 10)] = 1
        s.side = -1; s.moves = 7
        XCTAssertEqual(E.aiAction(for: s, seat: 1, level: .hard), idx(5, 8))
    }

    func testSelfPlayIsLegal() throws {
        var s = E.State()
        var n = 0
        while let seat = E.activeSeat(s), n < 60 {
            let m = try XCTUnwrap(E.aiAction(for: s, seat: seat, level: seat == 0 ? .medium : .easy))
            XCTAssertEqual(s.cells[m], 0)
            try E.apply(m, by: seat, to: &s)
            n += 1
        }
    }

    func testCodable() throws {
        let s = try play([112, 113, 127])
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
    }
}
