import XCTest
@testable import Khel

final class CheckersTests: XCTestCase {
    typealias E = CheckersEngine

    private func sq(_ r: Int, _ c: Int) -> Int { r * 8 + c }

    private func state(_ pieces: [(Int, Int, Int8)], side: Int = 1) -> E.State {
        var b = [Int8](repeating: 0, count: 64)
        for (r, c, p) in pieces { b[r * 8 + c] = p }
        var s = E.State()
        s.pos = CheckersPosition(b: b, side: side)
        return s
    }

    func testInitialPosition() {
        let p = CheckersPosition.start
        XCTAssertEqual(p.b.filter { $0 > 0 }.count, 12)
        XCTAssertEqual(p.b.filter { $0 < 0 }.count, 12)
        XCTAssertEqual(p.options().count, 7)
    }

    func testForcedCaptureIsMandatory() throws {
        var s = state([(5, 2, 1), (4, 3, -1), (7, 6, 1)])
        XCTAssertThrowsError(try E.apply(CheckersMove(from: sq(7, 6), to: sq(6, 5)), by: 0, to: &s))
        try E.apply(CheckersMove(from: sq(5, 2), to: sq(3, 4)), by: 0, to: &s)
        XCTAssertEqual(s.pos.b[sq(4, 3)], 0)
    }

    func testMultiJumpKeepsTheTurn() throws {
        var s = state([(7, 0, 1), (6, 1, -1), (4, 3, -1), (2, 5, -1), (0, 7, -1)])
        try E.apply(CheckersMove(from: sq(7, 0), to: sq(5, 2)), by: 0, to: &s)
        XCTAssertEqual(s.pos.chain, sq(5, 2))
        XCTAssertEqual(E.activeSeat(s), 0)
        XCTAssertThrowsError(try E.apply(CheckersMove(from: sq(0, 7), to: sq(1, 6)), by: 0, to: &s))
        try E.apply(CheckersMove(from: sq(5, 2), to: sq(3, 4)), by: 0, to: &s)
        try E.apply(CheckersMove(from: sq(3, 4), to: sq(1, 6)), by: 0, to: &s)
        XCTAssertEqual(s.pos.chain, -1)
        XCTAssertEqual(s.pos.b.filter { $0 < 0 }.count, 1)
    }

    func testCrowningEndsTheJump() throws {
        var s = state([(2, 3, 1), (1, 2, -1), (1, 4, -1), (3, 0, -1)])
        try E.apply(CheckersMove(from: sq(2, 3), to: sq(0, 1)), by: 0, to: &s)
        XCTAssertEqual(s.pos.b[sq(0, 1)], 2)
        XCTAssertEqual(s.pos.chain, -1, "a man that is crowned stops")
        XCTAssertEqual(E.activeSeat(s), 1)
    }

    func testKingsMoveBackwards() {
        let s = state([(3, 3, 2), (0, 7, -1)])
        XCTAssertEqual(Set(s.pos.options().map(\.to)), Set([sq(2, 2), sq(2, 4), sq(4, 2), sq(4, 4)]))
    }

    func testNoMovesLoses() throws {
        var s = state([(2, 3, 1), (1, 2, -1)], side: 1)
        try E.apply(CheckersMove(from: sq(2, 3), to: sq(0, 1)), by: 0, to: &s)
        XCTAssertEqual(s.result, 1)
        XCTAssertEqual(E.outcome(s)?.winners, [0])
    }

    func testDrawAfterFortyMovesWithoutProgress() throws {
        var s = state([(7, 0, 2), (0, 7, -2)])
        s.half = 79
        try E.apply(CheckersMove(from: sq(7, 0), to: sq(6, 1)), by: 0, to: &s)
        XCTAssertEqual(s.result, 2)
        XCTAssertEqual(E.outcome(s)?.isDraw, true)
    }

    func testCodableRoundTrip() throws {
        var s = E.State()
        let o = s.pos.options()[0]
        try E.apply(CheckersMove(from: o.from, to: o.to), by: 0, to: &s)
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
    }

    func testAITakesTheWinningCapture() {
        let s = state([(5, 2, 1), (4, 3, -1), (3, 4, 0), (7, 0, 1), (0, 1, -1)])
        for level in AILevel.allCases { XCTAssertEqual(E.aiAction(for: s, seat: 0, level: level)?.to, sq(3, 4), "\(level)") }
    }

    func testSelfPlayAlwaysLegalAndFinishes() throws {
        for (a, b) in [(AILevel.easy, AILevel.easy), (.medium, .easy), (.easy, .medium)] {
            var s = E.State()
            var plies = 0
            while let seat = E.activeSeat(s), plies < 300 {
                let m = try XCTUnwrap(E.aiAction(for: s, seat: seat, level: seat == 0 ? a : b))
                XCTAssertTrue(s.pos.options().contains { $0.from == m.from && $0.to == m.to })
                try E.apply(m, by: seat, to: &s)
                plies += 1
            }
        }
    }

    func testMediumBeatsEasy() throws {
        var wins = 0
        for g in 0 ..< 2 {
            var s = E.State()
            var plies = 0
            let mediumSeat = g % 2
            while let seat = E.activeSeat(s), plies < 200 {
                try E.apply(E.aiAction(for: s, seat: seat, level: seat == mediumSeat ? .medium : .easy)!, by: seat, to: &s)
                plies += 1
            }
            if s.winner == mediumSeat { wins += 1 }
        }
        XCTAssertGreaterThanOrEqual(wins, 1)
    }
}
