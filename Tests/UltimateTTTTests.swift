import XCTest
@testable import Khel

final class UltimateTTTTests: XCTestCase {
    typealias E = UltimateTTTEngine

    private func play(_ moves: [Int]) throws -> E.State {
        var s = E.State()
        for m in moves { try E.apply(m, by: s.side == 1 ? 0 : 1, to: &s) }
        return s
    }

    func testFirstMoveSendsOpponentToMatchingBoard() throws {
        let s = try play([4 * 9 + 2])
        XCTAssertEqual(s.next, 2)
        XCTAssertEqual(Set(E.legal(s).map { $0 / 9 }), [2])
        XCTAssertEqual(E.legal(E.State()).count, 81)
    }

    func testMustPlayInSentBoard() throws {
        var s = try play([0])      // board 0 square 0 → opponent must play in board 0
        XCTAssertThrowsError(try E.apply(9 * 5, by: 1, to: &s))
        try E.apply(1, by: 1, to: &s)
    }

    func testWinningASmallBoardAndFreeChoice() throws {
        var s = E.State()
        s.cells[0] = 1; s.cells[1] = 1; s.side = 1; s.next = 0
        try E.apply(2, by: 0, to: &s)
        XCTAssertEqual(s.won[0], 1)
        XCTAssertEqual(s.next, 2)
        // Sent to a decided board → free choice.
        var t = E.State()
        t.won[3] = 1; t.side = 1; t.next = 0
        try E.apply(3, by: 0, to: &t)
        XCTAssertEqual(t.next, -1)
    }

    func testWinningTheGame() throws {
        var s = E.State()
        s.won[0] = 1; s.won[1] = 1
        s.cells[18] = 1; s.cells[19] = 1; s.side = 1; s.next = 2
        try E.apply(20, by: 0, to: &s)
        XCTAssertEqual(s.winner, 0)
        XCTAssertEqual(E.outcome(s)?.winners, [0])
        XCTAssertNil(E.activeSeat(s))
    }

    func testFullBoardCountsAsDrawnBoard() throws {
        var s = E.State()
        // Board 0: fill without a line, leave one square for the last move.
        let layout: [Int8] = [1, -1, 1, 1, -1, -1, -1, 1, 0]
        for (i, v) in layout.enumerated() { s.cells[i] = v }
        s.side = 1; s.next = 0
        try E.apply(8, by: 0, to: &s)
        XCTAssertEqual(s.won[0], 2)
    }

    func testAIFindsBoardWin() {
        var s = E.State()
        s.cells[36] = 1; s.cells[37] = 1; s.side = 1; s.next = 4
        for level in AILevel.allCases { XCTAssertEqual(E.aiAction(for: s, seat: 0, level: level), level == .easy ? E.aiAction(for: s, seat: 0, level: level) : 38) }
    }

    func testSelfPlayAlwaysLegal() throws {
        for (a, b) in [(AILevel.easy, AILevel.easy), (.medium, .easy), (.easy, .medium)] {
            var s = E.State()
            var n = 0
            while let seat = E.activeSeat(s) {
                let m = try XCTUnwrap(E.aiAction(for: s, seat: seat, level: seat == 0 ? a : b))
                XCTAssertTrue(E.legal(s).contains(m))
                try E.apply(m, by: seat, to: &s)
                n += 1; XCTAssertLessThanOrEqual(n, 81)
            }
            XCTAssertNotNil(E.outcome(s))
        }
    }

    func testCodable() throws {
        let s = try play([40, 36, 4])
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
    }
}
