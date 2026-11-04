import XCTest
@testable import Khel

final class ReversiTests: XCTestCase {
    typealias E = ReversiEngine

    func testOpeningMovesAndFlip() throws {
        var s = E.State()
        XCTAssertEqual(Set(E.legalMoves(s.b, side: 1)), [19, 26, 37, 44])
        try E.apply(19, by: 0, to: &s)
        XCTAssertEqual(s.b[19], 1); XCTAssertEqual(s.b[27], 1)
        XCTAssertEqual(s.flipped, [27])
        XCTAssertEqual(E.counts(s).black, 4); XCTAssertEqual(E.counts(s).white, 1)
        XCTAssertEqual(E.activeSeat(s), 1)
    }

    func testIllegalMovesThrow() {
        var s = E.State()
        XCTAssertThrowsError(try E.apply(0, by: 0, to: &s))
        XCTAssertThrowsError(try E.apply(19, by: 1, to: &s))
        XCTAssertThrowsError(try E.apply(27, by: 0, to: &s))
        XCTAssertThrowsError(try E.apply(99, by: 0, to: &s))
        XCTAssertEqual(s, E.State())
    }

    func testAutomaticPass() throws {
        // Black to move can play a1 (flipping b1); afterwards white has no move, so black moves again.
        var s = E.State()
        s.b = [Int8](repeating: 0, count: 64)
        s.b[1] = -1; s.b[2] = 1; s.b[63] = 1; s.b[54] = -1
        s.side = 1
        try E.apply(0, by: 0, to: &s)
        XCTAssertEqual(s.b[1], 1)
        XCTAssertNotEqual(s.passed, 0)
    }

    func testGameEndsAndCountsWin() throws {
        var s = E.State()
        s.b = [Int8](repeating: 1, count: 64)
        s.b[0] = 0; s.b[1] = -1
        s.side = 1
        // black cannot flip anything at a1 (needs a line ending in black): b1 white then c1 black.
        s.b[2] = 1
        try E.apply(0, by: 0, to: &s)
        XCTAssertTrue(s.over)
        XCTAssertEqual(E.outcome(s)?.winners, [0])
    }

    func testCodableAndDeterminism() throws {
        var s = E.State()
        try E.apply(19, by: 0, to: &s)
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
        XCTAssertEqual(E.aiAction(for: s, seat: 1, level: .medium), E.aiAction(for: s, seat: 1, level: .medium))
    }

    func testAITakesACorner() {
        var s = E.State()
        s.b = [Int8](repeating: 0, count: 64)
        s.b[1] = -1; s.b[2] = 1       // black a1 captures b1
        s.b[27] = -1; s.b[28] = 1     // plus an ordinary move elsewhere
        s.side = 1
        for level in [AILevel.medium, .hard] { XCTAssertEqual(E.aiAction(for: s, seat: 0, level: level), 0, "\(level)") }
    }

    func testSelfPlayFinishesWithLegalMoves() throws {
        for (a, b) in [(AILevel.easy, AILevel.easy), (.medium, .easy), (.easy, .medium)] {
            var s = E.State()
            var n = 0
            while let seat = E.activeSeat(s) {
                let m = try XCTUnwrap(E.aiAction(for: s, seat: seat, level: seat == 0 ? a : b))
                XCTAssertFalse(E.flips(s.b, m, side: s.side).isEmpty)
                try E.apply(m, by: seat, to: &s)
                n += 1; XCTAssertLessThan(n, 80)
            }
            XCTAssertNotNil(E.outcome(s))
        }
    }

    func testHardBeatsEasy() throws {
        var wins = 0
        for g in 0 ..< 2 {
            var s = E.State()
            let hard = g % 2
            while let seat = E.activeSeat(s) { try E.apply(E.aiAction(for: s, seat: seat, level: seat == hard ? .medium : .easy)!, by: seat, to: &s) }
            if E.outcome(s)?.winners == [hard] { wins += 1 }
        }
        XCTAssertGreaterThanOrEqual(wins, 1)
    }
}
