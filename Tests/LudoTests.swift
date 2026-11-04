import XCTest
@testable import Khel

final class LudoTests: XCTestCase {
    typealias E = LudoEngine

    private func state(players: Int = 2, tokens: [[Int]]? = nil, roll: Int = 0) -> E.State {
        var s = E.newGame(players: players, seed: 1)
        if let tokens { s.tokens = tokens }
        s.roll = roll
        return s
    }

    func testRingGeometry() {
        XCTAssertEqual(E.ring.count, 52)
        XCTAssertEqual(Set(E.ring.map { "\($0.0),\($0.1)" }).count, 52)
        var diagonals = 0
        for i in 0 ..< 52 {      // consecutive cells touch; the four arm corners are diagonal steps, as on a real board
            let a = E.ring[i], b = E.ring[(i + 1) % 52]
            XCTAssertEqual(max(abs(a.0 - b.0), abs(a.1 - b.1)), 1, "gap after \(i)")
            if abs(a.0 - b.0) + abs(a.1 - b.1) == 2 { diagonals += 1 }
        }
        XCTAssertEqual(diagonals, 4)
        let starts = E.starts.map { E.ring[$0] }
        XCTAssertTrue(starts[0] == (1, 6) && starts[1] == (8, 1) && starts[2] == (13, 8) && starts[3] == (6, 13))
        // Each home column continues from the last ring cell a token of that colour uses.
        for slot in 0 ..< 4 {
            let last = E.ring[(E.starts[slot] + 50) % 52], first = E.homeColumns[slot][0]
            XCTAssertEqual(abs(last.0 - first.0) + abs(last.1 - first.1), 1)
        }
    }

    func testNeedsSixToLeaveYard() {
        XCTAssertTrue(E.legalMoves(state(tokens: [[-1, -1, -1, -1], [-1, -1, -1, -1]], roll: 5), seat: 0).isEmpty)
        XCTAssertEqual(E.legalMoves(state(tokens: [[-1, -1, -1, -1], [-1, -1, -1, -1]], roll: 6), seat: 0).count, 4)
        XCTAssertEqual(E.distinctMoves(state(tokens: [[-1, -1, 5, -1], [-1, -1, -1, -1]], roll: 6), seat: 0), [0, 2])
    }

    func testExactRollIntoHome() {
        let s = state(tokens: [[54, 56, -1, -1], [-1, -1, -1, -1]], roll: 3)
        XCTAssertEqual(E.legalMoves(s, seat: 0), [])
        XCTAssertEqual(E.legalMoves(state(tokens: [[54, 56, -1, -1], [-1, -1, -1, -1]], roll: 2), seat: 0), [0])
    }

    func testCaptureSendsTokenHomeAndGrantsExtraTurn() throws {
        // Seat 0 is slot 3 (start idx 39); seat 1 is slot 0 (start idx 0). Seat 0 at p=3 sits on idx 42, and so does seat 1 at p=42.
        var s = state(tokens: [[1, -1, -1, -1], [42, -1, -1, -1]], roll: 2)
        try E.apply(.move(0), by: 0, to: &s)
        XCTAssertEqual(s.tokens[0][0], 3)
        XCTAssertEqual(s.tokens[1][0], -1)
        XCTAssertEqual(s.captured, [[1, 0]])
        XCTAssertEqual(s.turn, 0, "capture gives another roll")
    }

    func testSafeCellsProtect() throws {
        // idx 47 is a star: seat 0 (start 39) at p=8 → idx 47.
        var s = state(tokens: [[6, -1, -1, -1], [47, -1, -1, -1]], roll: 2)   // seat 1 (start 0) at p=47 is on idx 47
        try E.apply(.move(0), by: 0, to: &s)
        XCTAssertEqual(s.tokens[1][0], 47)
        XCTAssertTrue(s.captured.isEmpty)
        XCTAssertEqual(s.turn, 1)
    }

    func testSixGivesAnotherRollAndThreeSixesForfeit() throws {
        var s = E.newGame(players: 2, seed: 3)
        s.tokens[0][0] = 10
        s.roll = 6
        s.sixes = 1
        try E.apply(.move(0), by: 0, to: &s)
        XCTAssertEqual(s.turn, 0)
        XCTAssertEqual(s.roll, 0)

        var t = E.newGame(players: 2, seed: 3)
        t.sixes = 2
        for i in 0 ..< 500 {
            var u = t; u.rng = SplitMix64(seed: UInt64(i))
            try E.apply(.roll, by: 0, to: &u)
            if u.lastRoll == 6 { XCTAssertEqual(u.note, 1); XCTAssertEqual(u.turn, 1); XCTAssertEqual(u.roll, 0); return }
        }
        XCTFail("never rolled a six")
    }

    func testRollWithNoMoveSkipsTurn() throws {
        for i in 0 ..< 200 {
            var s = E.newGame(players: 2, seed: UInt64(i))
            try E.apply(.roll, by: 0, to: &s)
            if s.lastRoll != 6 { XCTAssertEqual(s.turn, 1); XCTAssertEqual(s.note, 2); XCTAssertEqual(s.roll, 0); return }
        }
    }

    func testRejectsIllegalActions() throws {
        var s = E.newGame(players: 2, seed: 1)
        XCTAssertThrowsError(try E.apply(.move(0), by: 0, to: &s))
        XCTAssertThrowsError(try E.apply(.roll, by: 1, to: &s))
        s.roll = 6
        XCTAssertThrowsError(try E.apply(.roll, by: 0, to: &s))
    }

    func testFinishingAllTokensEndsTwoPlayerGame() throws {
        var s = state(tokens: [[56, 56, 56, 55], [-1, -1, -1, -1]], roll: 1)
        try E.apply(.move(3), by: 0, to: &s)
        XCTAssertEqual(E.outcome(s)?.ranking.first, 0)
        XCTAssertNil(E.activeSeat(s))
    }

    func testCodableRoundTrip() throws {
        var s = E.newGame(players: 4, seed: 11)
        try E.apply(.roll, by: 0, to: &s)
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
        XCTAssertEqual(try JSONDecoder().decode(E.Action.self, from: JSONEncoder().encode(E.Action.move(2))), .move(2))
    }

    func testSelfPlayAllSizesAndLevelsFinish() throws {
        for players in 2 ... 4 {
            for level in AILevel.allCases {
                var s = E.newGame(players: players, seed: UInt64(players * 10 + level.rawValue.count))
                var steps = 0
                while let seat = E.activeSeat(s) {
                    let a = try XCTUnwrap(E.aiAction(for: s, seat: seat, level: level))
                    try E.apply(a, by: seat, to: &s)
                    steps += 1
                    XCTAssertLessThan(steps, 60_000, "game does not converge")
                }
                XCTAssertEqual(Set(try XCTUnwrap(E.outcome(s)).ranking), Set(0 ..< players))
            }
        }
    }

    func testHardBeatsEasyMostOfTheTime() throws {
        var wins = 0
        let games = 30
        for g in 0 ..< games {
            var s = E.newGame(players: 2, seed: UInt64(100 + g))
            let hardSeat = g % 2
            while let seat = E.activeSeat(s) {
                try E.apply(E.aiAction(for: s, seat: seat, level: seat == hardSeat ? .hard : .easy)!, by: seat, to: &s)
            }
            if s.finished.first == hardSeat { wins += 1 }
        }
        XCTAssertGreaterThan(wins, games * 6 / 10, "hard AI won only \(wins)/\(games)")
    }
}
