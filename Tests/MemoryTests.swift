import XCTest
@testable import Khel

final class MemoryTests: XCTestCase {
    typealias E = MemoryEngine

    func testDealIsDeterministicAndPaired() {
        let a = E.newGame(players: 2, seed: 7), b = E.newGame(players: 2, seed: 7), c = E.newGame(players: 2, seed: 8)
        XCTAssertEqual(a.cards, b.cards); XCTAssertNotEqual(a.cards, c.cards)
        XCTAssertEqual(a.cards.count, 16)
        for v in Set(a.cards) { XCTAssertEqual(a.cards.filter { $0 == v }.count, 2) }
        XCTAssertEqual(E.newGame(players: 4, seed: 1).cards.count, 24)
        XCTAssertEqual(E.newGame(players: 1, seed: 1).cards.count, 16)
    }

    private func pairIndices(_ s: E.State) -> (Int, Int) {
        let v = s.cards[0]
        return (0, s.cards.indices.first { $0 != 0 && s.cards[$0] == v }!)
    }

    func testMatchKeepsTheTurn() throws {
        var s = E.newGame(players: 2, seed: 3)
        let (a, b) = pairIndices(s)
        try E.apply(.flip(a), by: 0, to: &s); try E.apply(.flip(b), by: 0, to: &s)
        XCTAssertEqual(s.scores, [1, 0]); XCTAssertEqual(s.turn, 0); XCTAssertTrue(s.up.isEmpty); XCTAssertEqual(s.matchedBy[a], 0)
    }

    func testMismatchNeedsResolveThenPassesTurn() throws {
        var s = E.newGame(players: 2, seed: 3)
        let a = 0, b = s.cards.indices.first { s.cards[$0] != s.cards[0] }!
        try E.apply(.flip(a), by: 0, to: &s); try E.apply(.flip(b), by: 0, to: &s)
        XCTAssertTrue(s.pending)
        XCTAssertThrowsError(try E.apply(.flip(3), by: 0, to: &s))
        XCTAssertEqual(E.aiAction(for: s, seat: 0, level: .hard), .resolve)
        try E.apply(.resolve, by: 0, to: &s)
        XCTAssertEqual(s.turn, 1); XCTAssertFalse(s.pending)
        XCTAssertThrowsError(try E.apply(.resolve, by: 1, to: &s))
    }

    func testIllegalFlips() throws {
        var s = E.newGame(players: 2, seed: 3)
        try E.apply(.flip(0), by: 0, to: &s)
        XCTAssertThrowsError(try E.apply(.flip(0), by: 0, to: &s))
        XCTAssertThrowsError(try E.apply(.flip(1), by: 1, to: &s))
        XCTAssertThrowsError(try E.apply(.flip(99), by: 0, to: &s))
    }

    func testSoloFinishes() throws {
        var s = E.newGame(players: 1, seed: 5)
        var n = 0
        while E.activeSeat(s) != nil, n < 500 {
            try E.apply(try XCTUnwrap(E.aiAction(for: s, seat: 0, level: .hard)), by: 0, to: &s)
            n += 1
        }
        XCTAssertEqual(E.outcome(s)?.winners, [0])
        XCTAssertLessThanOrEqual(s.tries, 20, "a perfect-memory player needs few tries")
    }

    func testAIMemoryStrengthOrdering() throws {
        func average(_ level: AILevel) throws -> Double {
            var total = 0
            for seed in 0 ..< 12 {
                var s = E.newGame(players: 1, seed: UInt64(seed))
                var n = 0
                while E.activeSeat(s) != nil, n < 600 { try E.apply(try XCTUnwrap(E.aiAction(for: s, seat: 0, level: level)), by: 0, to: &s); n += 1 }
                total += s.tries
            }
            return Double(total) / 12
        }
        let easy = try average(.easy), hard = try average(.hard)
        XCTAssertLessThan(hard, easy)
    }

    func testMultiplayerOutcomeAndCodable() throws {
        for players in 2 ... 4 {
            var s = E.newGame(players: players, seed: 9)
            var n = 0
            while let seat = E.activeSeat(s), n < 800 {
                try E.apply(try XCTUnwrap(E.aiAction(for: s, seat: seat, level: .medium)), by: seat, to: &s)
                n += 1
            }
            let o = try XCTUnwrap(E.outcome(s))
            XCTAssertEqual(s.scores.reduce(0, +), s.cards.count / 2)
            XCTAssertEqual(Set(o.ranking), Set(0 ..< players))
            XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
        }
    }
}
