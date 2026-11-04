import XCTest
@testable import Khel

final class ChessTests: XCTestCase {
    typealias E = ChessEngine

    private func pos(_ fen: String) -> ChessPosition { ChessPosition(fen: fen)! }

    // MARK: Perft

    func testPerftStartPosition() {
        let p = ChessPosition.start
        XCTAssertEqual(p.perft(1), 20); XCTAssertEqual(p.perft(2), 400); XCTAssertEqual(p.perft(3), 8902); XCTAssertEqual(p.perft(4), 197_281)
    }

    func testPerftKiwipete() {
        let p = pos("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        XCTAssertEqual(p.perft(1), 48); XCTAssertEqual(p.perft(2), 2039); XCTAssertEqual(p.perft(3), 97_862)
    }

    func testPerftEndgamePosition() {
        let p = pos("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
        XCTAssertEqual(p.perft(1), 14); XCTAssertEqual(p.perft(2), 191); XCTAssertEqual(p.perft(3), 2812); XCTAssertEqual(p.perft(4), 43_238)
    }

    func testPerftPromotionsAndCastlingPositions() {
        XCTAssertEqual(pos("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1").perft(3), 9467)
        XCTAssertEqual(pos("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8").perft(3), 62_379)
    }

    // MARK: Rules

    private func play(_ moves: [(Int, Int, Int)], from state: E.State = E.State()) throws -> E.State {
        var s = state
        for (f, t, p) in moves { try E.apply(ChessMove(from: f, to: t, promo: p), by: s.pos.side == 1 ? 0 : 1, to: &s) }
        return s
    }

    private func sq(_ name: String) -> Int { let u = Array(name.unicodeScalars); return (8 - Int(u[1].value - 48)) * 8 + Int(u[0].value - 97) }
    private func mv(_ a: String, _ b: String, _ promo: Int = 0) -> (Int, Int, Int) { (sq(a), sq(b), promo) }

    func testFoolsMate() throws {
        let s = try play([mv("f2", "f3"), mv("e7", "e5"), mv("g2", "g4"), mv("d8", "h4")])
        XCTAssertEqual(s.result, 1)
        XCTAssertEqual(E.outcome(s)?.winners, [1])
        XCTAssertNil(E.activeSeat(s))
    }

    func testIllegalAndOutOfTurnMoves() {
        var s = E.State()
        XCTAssertThrowsError(try E.apply(ChessMove(from: sq("e2"), to: sq("e5")), by: 0, to: &s))
        XCTAssertThrowsError(try E.apply(ChessMove(from: sq("e7"), to: sq("e5")), by: 1, to: &s))
        XCTAssertThrowsError(try E.apply(ChessMove(from: sq("e7"), to: sq("e5")), by: 0, to: &s))
        XCTAssertEqual(s, E.State())
    }

    func testCastlingRules() throws {
        var s = E.State(); s.pos = pos("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        let moves = s.pos.legalMoves()
        XCTAssertTrue(moves.contains(ChessMove(from: sq("e1"), to: sq("g1"))))
        XCTAssertTrue(moves.contains(ChessMove(from: sq("e1"), to: sq("c1"))))
        try E.apply(ChessMove(from: sq("e1"), to: sq("g1")), by: 0, to: &s)
        XCTAssertEqual(s.pos.b[sq("f1")], 4); XCTAssertEqual(s.pos.b[sq("g1")], 6); XCTAssertEqual(s.pos.b[sq("h1")], 0)

        // Not through an attacked square.
        let attacked = pos("r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1")
        XCTAssertFalse(attacked.legalMoves().contains(ChessMove(from: sq("e1"), to: sq("g1"))))
        XCTAssertTrue(attacked.legalMoves().contains(ChessMove(from: sq("e1"), to: sq("c1"))))
        // Not out of check.
        let check = pos("r3k2r/8/8/8/4r3/8/8/R3K2R w KQkq - 0 1")
        XCTAssertFalse(check.legalMoves().contains(where: { abs($0.to - $0.from) == 2 && $0.from == sq("e1") }))
    }

    func testEnPassant() throws {
        let s = try play([mv("e2", "e4"), mv("a7", "a6"), mv("e4", "e5"), mv("d7", "d5"), mv("e5", "d6")])
        XCTAssertEqual(s.pos.b[sq("d5")], 0)
        XCTAssertEqual(s.pos.b[sq("d6")], 1)
    }

    func testPromotionNeedsAPiece() throws {
        var s = E.State(); s.pos = pos("8/P6k/8/8/8/8/8/K7 w - - 0 1")
        XCTAssertThrowsError(try E.apply(ChessMove(from: sq("a7"), to: sq("a8")), by: 0, to: &s))
        try E.apply(ChessMove(from: sq("a7"), to: sq("a8"), promo: 5), by: 0, to: &s)
        XCTAssertEqual(s.pos.b[sq("a8")], 5)
    }

    func testStalemateAndInsufficientMaterial() throws {
        var s = E.State(); s.pos = pos("7k/5Q2/8/8/8/8/8/K7 w - - 0 1")
        try E.apply(ChessMove(from: sq("f7"), to: sq("g6")), by: 0, to: &s)
        XCTAssertEqual(s.result, 2)
        XCTAssertEqual(E.outcome(s)?.isDraw, true)
        XCTAssertTrue(pos("8/8/8/4k3/8/3K4/8/8 w - - 0 1").insufficientMaterial)
        XCTAssertTrue(pos("8/8/8/4k3/8/3KB3/8/8 w - - 0 1").insufficientMaterial)
        XCTAssertFalse(pos("8/8/8/4k3/8/3KR3/8/8 w - - 0 1").insufficientMaterial)
        XCTAssertFalse(pos("8/8/8/4k3/8/3KP3/8/8 w - - 0 1").insufficientMaterial)
    }

    func testThreefoldRepetitionAndFiftyMoveRule() throws {
        let shuffle = [mv("g1", "f3"), mv("g8", "f6"), mv("f3", "g1"), mv("f6", "g8")]
        let s = try play(shuffle + shuffle)
        XCTAssertEqual(s.result, 5)
        var f = E.State(); f.pos = pos("8/8/8/4k3/8/3K4/8/7R w - - 99 80")
        try E.apply(ChessMove(from: sq("h1"), to: sq("h2")), by: 0, to: &f)
        XCTAssertEqual(f.result, 4)
    }

    func testResign() throws {
        var s = E.State()
        try E.apply(E.resign, by: 0, to: &s)
        XCTAssertEqual(E.outcome(s)?.winners, [1])
    }

    func testCodableRoundTrip() throws {
        let s = try play([mv("e2", "e4"), mv("e7", "e5"), mv("g1", "f3")])
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
    }

    func testMakeUnmakeRestoresPosition() {
        var p = pos("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        let original = p
        for m in p.pseudoMoves() { let u = p.make(m); p.unmake(u); XCTAssertEqual(p, original) }
    }

    // MARK: AI

    func testAIFindsMateInOne() {
        var s = E.State(); s.pos = pos("6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1")
        for level in [AILevel.medium, .hard] {
            let a = E.aiAction(for: s, seat: 0, level: level)
            XCTAssertEqual(a, ChessMove(from: sq("a1"), to: sq("a8")), "\(level)")
        }
    }

    func testAIWinsFreeQueen() {
        var s = E.State(); s.pos = pos("4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1")
        XCTAssertEqual(E.aiAction(for: s, seat: 0, level: .medium), ChessMove(from: sq("d1"), to: sq("d5")))
    }

    func testAIPlaysOnlyLegalMovesInSelfPlay() throws {
        for (white, black) in [(AILevel.easy, AILevel.easy), (.medium, .easy), (.easy, .medium)] {
            var s = E.State()
            var plies = 0
            while let seat = E.activeSeat(s), plies < 50 {
                let m = try XCTUnwrap(E.aiAction(for: s, seat: seat, level: seat == 0 ? white : black))
                XCTAssertTrue(s.pos.legalMoves().contains(m))
                try E.apply(m, by: seat, to: &s)
                plies += 1
            }
        }
    }
}
