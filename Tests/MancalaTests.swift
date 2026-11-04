import XCTest
@testable import Khel

final class MancalaTests: XCTestCase {
    typealias E = MancalaEngine

    func testBasicSowingAndExtraTurn() throws {
        var s = E.State()
        try E.apply(2, by: 0, to: &s)      // 4 seeds: 3,4,5 and the store
        XCTAssertEqual(s.pits[2], 0); XCTAssertEqual(s.pits[6], 1)
        XCTAssertEqual(s.lastPath, [3, 4, 5, 6])
        XCTAssertTrue(s.extraTurn); XCTAssertEqual(s.turn, 0)
    }

    func testSowingSkipsOpponentStore() throws {
        var s = E.State()
        s.pits = [0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0]
        s.pits[11] = 1   // keep the other side non-empty
        try E.apply(5, by: 0, to: &s)
        XCTAssertEqual(s.pits[13], 0, "seat 0 never sows into seat 1's store")
        XCTAssertGreaterThanOrEqual(s.pits[6], 1)
        XCTAssertEqual(s.lastPath.count, 10)
        XCTAssertFalse(s.lastPath.contains(13))
    }

    func testCaptureFromEmptyOwnPit() throws {
        var s = E.State()
        s.pits = [1, 0, 0, 0, 0, 3, 0, 2, 5, 0, 0, 0, 1, 0]   // seat 0 moves pit 0 → pit 1 (empty), opposite is pit 11
        s.pits[11] = 6
        try E.apply(0, by: 0, to: &s)
        XCTAssertEqual(s.pits[1], 0); XCTAssertEqual(s.pits[11], 0)
        XCTAssertEqual(s.pits[6], 7)
        XCTAssertEqual(s.captured, 7)
        XCTAssertEqual(s.turn, 1)
    }

    func testGameEndSweepsRemainingSeeds() throws {
        var s = E.State()
        s.pits = [0, 0, 0, 0, 0, 1, 10, 3, 0, 0, 0, 0, 0, 5]
        try E.apply(5, by: 0, to: &s)
        XCTAssertTrue(s.over)
        XCTAssertEqual(s.pits[6], 11); XCTAssertEqual(s.pits[13], 8)
        XCTAssertEqual(E.outcome(s)?.winners, [0])
        XCTAssertEqual(s.pits.reduce(0, +), 48 - 48 + 19)
    }

    func testIllegalMoves() {
        var s = E.State()
        XCTAssertThrowsError(try E.apply(7, by: 0, to: &s))
        XCTAssertThrowsError(try E.apply(6, by: 0, to: &s))
        XCTAssertThrowsError(try E.apply(0, by: 1, to: &s))
        s.pits[0] = 0
        XCTAssertThrowsError(try E.apply(0, by: 0, to: &s))
    }

    func testSeedsAreConserved() throws {
        var s = E.State()
        var n = 0
        while let seat = E.activeSeat(s), n < 400 {
            try E.apply(try XCTUnwrap(E.aiAction(for: s, seat: seat, level: .easy)), by: seat, to: &s)
            XCTAssertEqual(s.pits.reduce(0, +), 48)
            n += 1
        }
        XCTAssertTrue(s.over)
    }

    func testCodableAndAI() throws {
        var s = E.State()
        try E.apply(1, by: 0, to: &s)
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
        for level in AILevel.allCases { XCTAssertTrue(E.legal(s, seat: s.turn).contains(E.aiAction(for: s, seat: s.turn, level: level)!)) }
    }

    func testHardBeatsEasy() throws {
        var wins = 0
        for g in 0 ..< 2 {
            var s = E.State(); let hard = g % 2
            while let seat = E.activeSeat(s) { try E.apply(E.aiAction(for: s, seat: seat, level: seat == hard ? .medium : .easy)!, by: seat, to: &s) }
            if E.outcome(s)?.winners == [hard] { wins += 1 }
        }
        XCTAssertGreaterThanOrEqual(wins, 1)
    }
}
