import XCTest
@testable import Khel

final class ConnectFourTests: XCTestCase {
    typealias E = ConnectFourEngine

    private func play(_ cols: [Int]) throws -> E.State {
        var s = E.newGame(players: 2, seed: 1)
        for c in cols { try E.apply(c, by: s.turn, to: &s) }
        return s
    }

    func testVerticalWin() throws {
        let s = try play([0, 1, 0, 1, 0, 1, 0])
        XCTAssertEqual(s.winner, 0)
        XCTAssertEqual(s.winLine.count, 4)
        XCTAssertNil(E.activeSeat(s))
    }

    func testHorizontalAndDiagonalWin() throws {
        XCTAssertEqual(try play([0, 0, 1, 1, 2, 2, 3]).winner, 0)
        // Diagonal for seat 0: (0,5) (1,4) (2,3) (3,2)
        let s = try play([0, 1, 1, 2, 3, 2, 2, 3, 3, 6, 3])
        XCTAssertEqual(s.winner, 0)
    }

    func testIllegalMovesThrowAndLeaveStateUntouched() throws {
        var s = try play([0, 0, 0, 0, 0, 0])
        let before = s
        XCTAssertThrowsError(try E.apply(0, by: s.turn, to: &s))
        XCTAssertThrowsError(try E.apply(9, by: s.turn, to: &s))
        XCTAssertThrowsError(try E.apply(1, by: 1 - s.turn, to: &s))
        XCTAssertEqual(s, before)
    }

    func testDraw() throws {
        // A known full-board draw sequence.
        let seq = [0,1,0,1,0,1,1,0,1,0,1,0,2,3,2,3,2,3,3,2,3,2,3,2,4,5,4,5,4,5,5,4,5,4,5,4,6,6,6,6,6,6]
        let s = try play(seq)
        XCTAssertTrue(s.drawn)
        XCTAssertEqual(E.outcome(s)?.isDraw, true)
    }

    func testCodableRoundTrip() throws {
        let s = try play([3, 3, 4, 2])
        XCTAssertEqual(try JSONDecoder().decode(E.State.self, from: JSONEncoder().encode(s)), s)
    }

    func testAITakesWinAndBlocks() throws {
        var s = try play([0, 6, 1, 6, 2])           // seat 1 to move; seat 0 threatens column 3
        let block = try XCTUnwrap(E.aiAction(for: s, seat: 1, level: .medium))
        XCTAssertEqual(block, 3)
        s = try play([0, 6, 1, 6, 2, 5])            // seat 0 to move and can win at 3
        XCTAssertEqual(E.aiAction(for: s, seat: 0, level: .hard), 3)
    }

    func testAISelfPlayFinishesWithoutIllegalMoves() throws {
        for (a, b) in [(AILevel.easy, AILevel.medium), (.medium, .easy), (.easy, .easy)] {
            var s = E.newGame(players: 2, seed: 7)
            var plies = 0
            while let seat = E.activeSeat(s) {
                let level = seat == 0 ? a : b
                let move = try XCTUnwrap(E.aiAction(for: s, seat: seat, level: level))
                try E.apply(move, by: seat, to: &s)
                plies += 1
                XCTAssertLessThanOrEqual(plies, 42)
            }
            XCTAssertNotNil(E.outcome(s))
        }
    }

    func testHardBeatsEasy() throws {
        var hardWins = 0
        for game in 0 ..< 3 {
            var s = E.newGame(players: 2, seed: UInt64(game))
            let hardSeat = game % 2
            while let seat = E.activeSeat(s) {
                let move = E.aiAction(for: s, seat: seat, level: seat == hardSeat ? .medium : .easy)!
                try E.apply(move, by: seat, to: &s)
            }
            if s.winner == hardSeat { hardWins += 1 }
        }
        XCTAssertGreaterThanOrEqual(hardWins, 2)
    }
}
