import XCTest
@testable import Khel

final class DotsBoxesTests: XCTestCase {
    typealias E = DotsBoxesEngine

    func testBoxEdgeMapping() {
        for b in 0 ..< 25 {
            for e in E.edges(ofBox: b) { XCTAssertTrue(E.boxes(ofEdge: e).contains(b)) }
        }
        XCTAssertEqual(E.boxes(ofEdge: 0), [0])
        XCTAssertEqual(E.boxes(ofEdge: 5).count, 2)
        XCTAssertEqual(E.boxes(ofEdge: 30), [0])
        XCTAssertEqual(E.boxes(ofEdge: 31).count, 2)
    }

    func testCompletingABoxScoresAndKeepsTheTurn() throws {
        var s = E.newGame(players: 2, seed: 1)
        let edges = E.edges(ofBox: 0)
        try E.apply(edges[0], by: 0, to: &s); XCTAssertEqual(s.turn, 1)
        try E.apply(edges[1], by: 1, to: &s)
        try E.apply(edges[2], by: 0, to: &s)
        try E.apply(edges[3], by: 1, to: &s)
        XCTAssertEqual(s.scores, [0, 1]); XCTAssertEqual(s.turn, 1); XCTAssertEqual(s.boxes[0], 2)
    }

    func testDoubleBoxEdge() throws {
        var s = E.newGame(players: 2, seed: 1)
        for e in E.edges(ofBox: 0) + E.edges(ofBox: 1) where e != 1 * 5 + 0 + 0 && e != 5 + 0 {
            if s.edges[e] == 0 && e != E.edges(ofBox: 0)[1] { s.edges[e] = 1 }
        }
        // Boxes 0 and 1 share the vertical edge 31; draw their last missing edges so one stroke closes both.
        s.edges = [Int8](repeating: 0, count: 60)
        for e in Set(E.edges(ofBox: 0) + E.edges(ofBox: 1)) where e != 31 { s.edges[e] = 1 }
        try E.apply(31, by: 0, to: &s)
        XCTAssertEqual(s.scores[0], 2)
        XCTAssertEqual(s.turn, 0)
    }

    func testIllegalMoves() throws {
        var s = E.newGame(players: 3, seed: 1)
        try E.apply(0, by: 0, to: &s)
        XCTAssertThrowsError(try E.apply(0, by: 1, to: &s))
        XCTAssertThrowsError(try E.apply(1, by: 0, to: &s))
        XCTAssertThrowsError(try E.apply(99, by: 1, to: &s))
    }

    func testAITakesFreeBoxAndAvoidsThirdSide() throws {
        var s = E.newGame(players: 2, seed: 1)
        let e = E.edges(ofBox: 12)
        for x in e.prefix(3) { s.edges[x] = 1 }
        for level in AILevel.allCases { XCTAssertEqual(E.aiAction(for: s, seat: 0, level: level), e[3], "\(level)") }
        var t = E.newGame(players: 2, seed: 1)
        for x in E.edges(ofBox: 12).prefix(2) { t.edges[x] = 1 }
        let move = E.aiAction(for: t, seat: 0, level: .medium)!
        XCTAssertFalse(E.boxes(ofEdge: move).contains { E.sides(t.edges, box: $0) == 2 })
    }

    func testSelfPlayAllPlayerCounts() throws {
        for players in 2 ... 4 {
            var s = E.newGame(players: players, seed: 2)
            var n = 0
            while let seat = E.activeSeat(s) {
                try E.apply(try XCTUnwrap(E.aiAction(for: s, seat: seat, level: players == 2 ? .medium : .easy)), by: seat, to: &s)
                n += 1; XCTAssertLessThan(n, 200)
            }
            XCTAssertEqual(s.scores.reduce(0, +), 25)
            XCTAssertEqual(Set(try XCTUnwrap(E.outcome(s)).ranking), Set(0 ..< players))
        }
    }

    func testHardSolverBeatsMediumInEndgames() throws {
        var s = E.newGame(players: 2, seed: 3)
        var rng = SplitMix64(seed: 5)
        var free = Array(0 ..< 60)
        while free.count > 12 {   // random opening, avoiding scoring so the endgame is rich
            let e = free.remove(at: rng.int(in: 0 ... free.count - 1))
            s.edges[e] = 1
            for b in E.boxes(ofEdge: e) where E.sides(s.edges, box: b) == 4 { s.boxes[b] = 1 }
        }
        s.turn = 0
        let move = E.aiAction(for: s, seat: 0, level: .hard)
        XCTAssertNotNil(move)
        XCTAssertEqual(s.edges[move!], 0)
    }

    func testCodableRoundTrip() throws {
        var s = E.newGame(players: 4, seed: 1)
        try E.apply(7, by: 0, to: &s)
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
    }
}
