import XCTest
@testable import Khel

final class SnakesLaddersTests: XCTestCase {
    typealias E = SnakesLaddersEngine

    func testBoardLayoutIsSane() {
        for (from, to) in E.ladders { XCTAssertLessThan(from, to); XCTAssertNil(E.snakes[from]); XCTAssertNil(E.snakes[to]); XCTAssertNil(E.ladders[to]) }
        for (from, to) in E.snakes { XCTAssertGreaterThan(from, to); XCTAssertNil(E.ladders[from]); XCTAssertNil(E.snakes[to]) }
        XCTAssertNil(E.ladders[100]); XCTAssertNil(E.snakes[100])
        XCTAssertEqual(E.cell(1).col, 0.5); XCTAssertEqual(E.cell(10).col, 9.5); XCTAssertEqual(E.cell(11).col, 9.5); XCTAssertEqual(E.cell(100).row, 0.5)
    }

    func testOnlyActiveSeatMovesAndRollIsDeterministic() throws {
        var a = E.newGame(players: 2, seed: 5), b = E.newGame(players: 2, seed: 5)
        XCTAssertThrowsError(try E.apply(.roll, by: 1, to: &a))
        try E.apply(.roll, by: 0, to: &a); try E.apply(.roll, by: 0, to: &b)
        XCTAssertEqual(a, b)
        XCTAssertTrue((1 ... 6).contains(a.lastRoll))
    }

    func testLadderSnakeAndExactFinish() throws {
        XCTAssertEqual(E.ladders[36], 44)
        var up = E.newGame(players: 2, seed: 3)
        up.positions[0] = 1
        var found = false
        for i in 0 ..< 200 {
            var t = up; t.rng = SplitMix64(seed: UInt64(i))
            try E.apply(.roll, by: 0, to: &t)
            if t.lastRoll == 1 && t.lastKind == 1 { XCTAssertEqual(t.positions[0], 38); XCTAssertEqual(t.lastPath, [2, 38]); found = true; break }
        }
        XCTAssertTrue(found)

        var snake = E.newGame(players: 2, seed: 3); snake.positions[0] = 13
        for i in 0 ..< 200 {
            var t = snake; t.rng = SplitMix64(seed: UInt64(i))
            try E.apply(.roll, by: 0, to: &t)
            if t.lastRoll == 3 { XCTAssertEqual(t.positions[0], 6); XCTAssertEqual(t.lastKind, 2); break }
        }

        var near = E.newGame(players: 2, seed: 3); near.positions[0] = 99
        for i in 0 ..< 200 {
            var t = near; t.rng = SplitMix64(seed: UInt64(i))
            try E.apply(.roll, by: 0, to: &t)
            if t.lastRoll == 1 { XCTAssertEqual(t.positions[0], 100); XCTAssertEqual(E.outcome(t)?.ranking.first, 0); }
            else { XCTAssertEqual(t.positions[0], 99); XCTAssertEqual(t.lastKind, 3) }
        }
    }

    func testSixGivesExtraTurnAndThreeSixesForfeit() throws {
        var s = E.newGame(players: 2, seed: 0)
        var sawExtra = false
        for i in 0 ..< 500 {
            var t = s; t.rng = SplitMix64(seed: UInt64(i))
            try E.apply(.roll, by: 0, to: &t)
            if t.lastRoll == 6 && t.positions[0] <= 100 { XCTAssertEqual(t.turn, 0); sawExtra = true; break }
        }
        XCTAssertTrue(sawExtra)
        s.sixes = 2
        for i in 0 ..< 500 {
            var t = s; t.rng = SplitMix64(seed: UInt64(i))
            try E.apply(.roll, by: 0, to: &t)
            if t.lastRoll == 6 { XCTAssertEqual(t.lastKind, 4); XCTAssertEqual(t.positions[0], 0); XCTAssertEqual(t.turn, 1); return }
        }
        XCTFail("no six found")
    }

    func testSelfPlayAllPlayerCountsFinish() throws {
        for players in 2 ... 4 {
            for seed in 0 ..< 20 {
                var s = E.newGame(players: players, seed: UInt64(seed))
                var n = 0
                while let seat = E.activeSeat(s) {
                    try E.apply(try XCTUnwrap(E.aiAction(for: s, seat: seat, level: .easy)), by: seat, to: &s)
                    n += 1; XCTAssertLessThan(n, 5000)
                }
                let o = try XCTUnwrap(E.outcome(s))
                XCTAssertEqual(Set(o.ranking), Set(0 ..< players))
            }
        }
    }

    func testCodableRoundTrip() throws {
        var s = E.newGame(players: 3, seed: 9); try E.apply(.roll, by: 0, to: &s)
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
    }
}
