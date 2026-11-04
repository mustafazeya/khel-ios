import XCTest
@testable import Khel

final class GoatsTigersTests: XCTestCase {
    typealias E = GoatsTigersEngine

    func testGraph() {
        XCTAssertEqual(Set(E.neighbours(0)), [1, 5, 6])
        XCTAssertEqual(Set(E.neighbours(1)), [0, 2, 6])
        XCTAssertEqual(E.neighbours(12).count, 8)
        XCTAssertEqual(E.neighbours(6).count, 8 - 0)
        for p in 0 ..< 25 { for n in E.neighbours(p) { XCTAssertTrue(E.neighbours(n).contains(p), "asymmetric \(p)-\(n)") } }
        // 40 orthogonal links and 16 diagonal links, each counted from both ends.
        XCTAssertEqual((0 ..< 25).reduce(0) { $0 + E.neighbours($1).count }, 112)
    }

    func testJumpsStayOnTheBoardAndAlongLines() {
        XCTAssertEqual(Set(E.jumps(0).map(\.to)), [2, 10, 12])
        XCTAssertEqual(Set(E.jumps(1).map(\.to)), [11, 3])
        for p in 0 ..< 25 { for j in E.jumps(p) { XCTAssertTrue(E.neighbours(p).contains(j.over)); XCTAssertTrue(E.neighbours(j.over).contains(j.to)) } }
    }

    func testPlacementThenMovement() throws {
        var s = E.State()
        XCTAssertEqual(E.moves(s).count, 21)
        try E.apply(E.Action(from: -1, to: 12), by: 0, to: &s)
        XCTAssertEqual(s.inHand, 19); XCTAssertEqual(s.b[12], 1)
        XCTAssertThrowsError(try E.apply(E.Action(from: -1, to: 13), by: 0, to: &s))
        XCTAssertThrowsError(try E.apply(E.Action(from: 0, to: 12), by: 1, to: &s))
        try E.apply(E.Action(from: 0, to: 1), by: 1, to: &s)
    }

    func testTigerCapturesByJumping() throws {
        var s = E.State()
        s.b = [Int8](repeating: 0, count: 25)
        s.b[0] = 2; s.b[1] = 1; s.b[24] = 2; s.b[20] = 2; s.b[4] = 2
        s.inHand = 0; s.turn = 1
        try E.apply(E.Action(from: 0, to: 2), by: 1, to: &s)
        XCTAssertEqual(s.b[1], 0); XCTAssertEqual(s.captured, 1); XCTAssertEqual(s.lastCaptured, 1)
    }

    func testFifthCaptureWinsForTigers() throws {
        var s = E.State()
        s.b = [Int8](repeating: 0, count: 25); s.b[0] = 2; s.b[1] = 1; s.b[24] = 2; s.b[20] = 2; s.b[4] = 2
        s.inHand = 0; s.turn = 1; s.captured = 4
        try E.apply(E.Action(from: 0, to: 2), by: 1, to: &s)
        XCTAssertEqual(E.outcome(s)?.winners, [1])
    }

    func testGoatsWinWhenTigersAreTrapped() throws {
        var s = E.State()
        s.b = [Int8](repeating: 0, count: 25)
        s.b[0] = 2; s.b[1] = 1; s.b[5] = 1; s.b[6] = 1; s.b[2] = 1; s.b[10] = 1; s.b[12] = 1
        s.b[24] = 0; s.b[20] = 0; s.b[4] = 0
        s.inHand = 5; s.turn = 0
        s.b[2] = 0
        try E.apply(E.Action(from: -1, to: 2), by: 0, to: &s)
        XCTAssertEqual(E.outcome(s)?.winners, [0], "single tiger fully boxed in")
    }

    func testCodableRoundTrip() throws {
        var s = E.State()
        try E.apply(E.Action(from: -1, to: 12), by: 0, to: &s)
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
    }

    func testSelfPlayAlwaysLegal() throws {
        for (g, t) in [(AILevel.easy, AILevel.easy), (.medium, .easy), (.easy, .medium)] {
            var s = E.State()
            var n = 0
            while let seat = E.activeSeat(s) {
                let m = try XCTUnwrap(E.aiAction(for: s, seat: seat, level: seat == 0 ? g : t))
                XCTAssertTrue(E.moves(s).contains(m))
                try E.apply(m, by: seat, to: &s)
                n += 1; XCTAssertLessThan(n, 300)
            }
            XCTAssertNotNil(E.outcome(s))
        }
    }

    func testTigerAIFindsCapture() {
        var s = E.State()
        s.b = [Int8](repeating: 0, count: 25)
        s.b[0] = 2; s.b[1] = 1; s.b[24] = 2; s.b[20] = 2; s.b[4] = 2
        s.inHand = 0; s.turn = 1
        XCTAssertEqual(E.aiAction(for: s, seat: 1, level: .hard), E.Action(from: 0, to: 2))
    }
}
